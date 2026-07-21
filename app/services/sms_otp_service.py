"""
SMS OTP via Bird (MessageBird) platform API.
Sends OTP using the bird_otp_verification SMS template.
"""

from __future__ import annotations

import json
import random
import re
import string
from typing import Any, Optional

import httpx
from fastapi import HTTPException

from app.core.config import settings
from app.core.redis import get_redis

OTP_LENGTH = 6
OTP_TTL = settings.OTP_EXPIRE_MINUTES * 60
PENDING_TTL = OTP_TTL

# In-memory fallback when Redis is down (dev only)
_MEMORY_OTP: dict[str, str] = {}
_MEMORY_PENDING: dict[str, str] = {}


def normalize_phone(raw: str, default_region: str = "NG") -> str:
    """Normalize to E.164. Default country Nigeria (+234)."""
    s = re.sub(r"[^\d+]", "", (raw or "").strip())
    if not s:
        raise HTTPException(status_code=400, detail="Phone number is required")

    if s.startswith("00"):
        s = "+" + s[2:]

    digits = s[1:] if s.startswith("+") else s

    if default_region == "NG":
        if digits.startswith("234") and len(digits) >= 13:
            digits = digits
        elif digits.startswith("0") and len(digits) == 11:
            digits = "234" + digits[1:]
        elif len(digits) == 10:
            digits = "234" + digits

    if not digits.isdigit() or len(digits) < 10 or len(digits) > 15:
        raise HTTPException(
            status_code=400,
            detail="Enter a valid phone number (e.g. 08012345678 or +2348012345678)",
        )
    return "+" + digits


def phone_to_email(phone_e164: str) -> str:
    digits = phone_e164.lstrip("+")
    return f"{digits}@phone.scholaxia.local"


def _generate_otp() -> str:
    return "".join(random.choices(string.digits, k=OTP_LENGTH))


def _otp_key(purpose: str, phone: str) -> str:
    return f"sms_otp:{purpose}:{phone}"


def _pending_key(phone: str) -> str:
    return f"sms_signup_pending:{phone}"


async def _redis_set(key: str, value: str, ex: int) -> None:
    try:
        redis = await get_redis()
        await redis.set(key, value, ex=ex)
    except Exception:
        if key.startswith("sms_otp:"):
            _MEMORY_OTP[key] = value
        else:
            _MEMORY_PENDING[key] = value
        print(f"[SMS OTP] Redis unavailable — stored in memory for {key}")


async def _redis_get(key: str) -> Optional[str]:
    try:
        redis = await get_redis()
        raw = await redis.get(key)
        if raw is None:
            return None
        return raw.decode() if isinstance(raw, bytes) else str(raw)
    except Exception:
        return _MEMORY_OTP.get(key) or _MEMORY_PENDING.get(key)


async def _redis_delete(key: str) -> None:
    try:
        redis = await get_redis()
        await redis.delete(key)
    except Exception:
        _MEMORY_OTP.pop(key, None)
        _MEMORY_PENDING.pop(key, None)


async def send_sms_otp(phone_e164: str, purpose: str = "signup") -> str:
    """
    Generate OTP, store in Redis, send via Bird SMS template.
    Returns the OTP only in DEBUG mode (never in production responses).
    """
    otp = _generate_otp()
    await _redis_set(_otp_key(purpose, phone_e164), otp, OTP_TTL)

    if not settings.BIRD_API_KEY:
        print(f"[SMS OTP] BIRD_API_KEY missing — code for {phone_e164}: {otp}")
        if settings.DEBUG:
            return otp
        raise HTTPException(
            status_code=503,
            detail="SMS service is not configured. Please try again later.",
        )

    await _send_bird_otp(phone_e164, otp)
    return otp if settings.DEBUG else ""


async def verify_sms_otp(phone_e164: str, otp: str, purpose: str = "signup") -> bool:
    key = _otp_key(purpose, phone_e164)
    stored = await _redis_get(key)
    if not stored:
        return False
    if stored.strip() != (otp or "").strip():
        return False
    await _redis_delete(key)
    return True


async def store_pending_signup(phone_e164: str, payload: dict[str, Any]) -> None:
    await _redis_set(_pending_key(phone_e164), json.dumps(payload), PENDING_TTL)


async def load_pending_signup(phone_e164: str) -> Optional[dict[str, Any]]:
    raw = await _redis_get(_pending_key(phone_e164))
    if not raw:
        return None
    try:
        return json.loads(raw)
    except Exception:
        return None


async def clear_pending_signup(phone_e164: str) -> None:
    await _redis_delete(_pending_key(phone_e164))


async def _send_bird_otp(to_e164: str, code: str) -> None:
    """
    Bird SMS API (us1):
      POST https://us1.platform.bird.com/v1/sms/messages
      Authorization: Bearer <api_key>
      { "to": "+234...", "template": { "name": "bird_otp_verification", "parameters": {"code": "123456"} } }
    """
    base = (settings.BIRD_BASE_URL or "https://us1.platform.bird.com").rstrip("/")
    url = f"{base}/v1/sms/messages"
    template_name = settings.BIRD_OTP_TEMPLATE or "bird_otp_verification"

    payload = {
        "to": to_e164,
        "template": {
            "name": template_name,
            "language": "en",
            "parameters": {
                "code": code,
                "ttl": str(settings.OTP_EXPIRE_MINUTES),
            },
        },
    }

    # Some Bird templates only accept `code` (no ttl) — retry without ttl on 422
    headers = {
        "Authorization": f"Bearer {settings.BIRD_API_KEY}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }

    async with httpx.AsyncClient(timeout=20.0) as client:
        res = await client.post(url, json=payload, headers=headers)
        if res.status_code == 422:
            payload["template"]["parameters"] = {"code": code}
            res = await client.post(url, json=payload, headers=headers)

        if res.status_code >= 400:
            detail = res.text[:300]
            print(f"[SMS OTP] Bird error {res.status_code}: {detail}")
            raise HTTPException(
                status_code=502,
                detail="Could not send SMS OTP. Check the phone number and try again.",
            )
