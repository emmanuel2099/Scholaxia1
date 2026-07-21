"""
OTP Service — Brevo (formerly Sendinblue)
-----------------------------------------
Generates, stores, and verifies OTPs for:
  - Email verification on signup
  - Password reset

OTPs are stored in Redis with a TTL (default 10 minutes).
Brevo sends the email via their transactional email API.
"""

import json
import random
import string
from typing import Any, Optional

import httpx
from app.core.config import settings
from app.core.redis import get_redis

OTP_LENGTH = 6
OTP_TTL = settings.OTP_EXPIRE_MINUTES * 60   # seconds
PENDING_TTL = OTP_TTL

BREVO_SEND_URL = "https://api.brevo.com/v3/smtp/email"

# In-memory fallback when Redis is down (dev only)
_MEMORY_STORE: dict[str, str] = {}


def _generate_otp() -> str:
    return "".join(random.choices(string.digits, k=OTP_LENGTH))


def _redis_key(purpose: str, email: str) -> str:
    return f"otp:{purpose}:{email.lower()}"


def _pending_key(email: str) -> str:
    return f"signup_pending:{email.lower()}"


async def _store_set(key: str, value: str, ex: int) -> None:
    try:
        redis = await get_redis()
        await redis.set(key, value, ex=ex)
    except Exception:
        _MEMORY_STORE[key] = value
        print(f"[OTP] Redis unavailable — stored in memory for {key}")


async def _store_get(key: str) -> Optional[str]:
    try:
        redis = await get_redis()
        raw = await redis.get(key)
        if raw is None:
            return _MEMORY_STORE.get(key)
        return raw.decode() if isinstance(raw, bytes) else str(raw)
    except Exception:
        return _MEMORY_STORE.get(key)


async def _store_delete(key: str) -> None:
    try:
        redis = await get_redis()
        await redis.delete(key)
    except Exception:
        pass
    _MEMORY_STORE.pop(key, None)


async def send_otp(email: str, full_name: str, purpose: str) -> str:
    """
    Generate an OTP, store it in Redis, and send it via Brevo email.
    purpose: "signup" | "verify_email" | "reset_password" | "login"
    Returns the OTP (only expose to clients when DEBUG=True).
    """
    otp = _generate_otp()
    await _store_set(_redis_key(purpose, email), otp, OTP_TTL)
    print(f"[OTP] generated for {email} purpose={purpose}")

    subject, body = _build_email(purpose, full_name, otp)
    try:
        await _send_via_brevo(to_email=email, to_name=full_name, subject=subject, body=body)
    except Exception as e:
        # Keep OTP in store so DEBUG / retry still works even if Brevo/Gmail fails
        print(f"[OTP] Brevo send failed for {email}: {e}")
        if not settings.DEBUG:
            raise
    return otp


async def verify_otp(email: str, otp: str, purpose: str) -> bool:
    """
    Verify the OTP for a given email and purpose.
    Returns True if valid, False otherwise.
    Deletes the OTP on successful verification (one-time use).
    """
    key = _redis_key(purpose, email)
    stored = await _store_get(key)

    if not stored:
        return False   # expired or never sent

    if stored.strip() != (otp or "").strip():
        return False   # wrong code

    # Consume — delete so it can't be reused
    await _store_delete(key)
    return True


async def store_pending_signup(email: str, payload: dict[str, Any]) -> None:
    await _store_set(_pending_key(email), json.dumps(payload), PENDING_TTL)


async def load_pending_signup(email: str) -> Optional[dict[str, Any]]:
    raw = await _store_get(_pending_key(email))
    if not raw:
        return None
    try:
        return json.loads(raw)
    except Exception:
        return None


async def clear_pending_signup(email: str) -> None:
    await _store_delete(_pending_key(email))


def _build_email(purpose: str, full_name: str, otp: str) -> tuple[str, str]:
    if purpose in ("signup", "verify_email"):
        subject = "Verify your Scholaxia account"
        body = f"""
        <p>Hi {full_name},</p>
        <p>Your Scholaxia email verification code is:</p>
        <h2 style="letter-spacing:6px;">{otp}</h2>
        <p>This code expires in {settings.OTP_EXPIRE_MINUTES} minutes.</p>
        <p>If you did not create a Scholaxia account, ignore this email.</p>
        """
    elif purpose == "reset_password":
        subject = "Reset your Scholaxia password"
        body = f"""
        <p>Hi {full_name},</p>
        <p>Your password reset code is:</p>
        <h2 style="letter-spacing:6px;">{otp}</h2>
        <p>This code expires in {settings.OTP_EXPIRE_MINUTES} minutes.</p>
        <p>If you did not request a password reset, ignore this email.</p>
        """
    else:
        subject = "Your Scholaxia OTP"
        body = f"<p>Your OTP is: <strong>{otp}</strong>. Expires in {settings.OTP_EXPIRE_MINUTES} minutes.</p>"

    return subject, body


async def _send_via_brevo(to_email: str, to_name: str, subject: str, body: str) -> None:
    """Send a transactional email via Brevo API."""
    payload = {
        "sender": {
            "name": settings.BREVO_SENDER_NAME,
            "email": settings.BREVO_SENDER_EMAIL,
        },
        "to": [{"email": to_email, "name": to_name}],
        "subject": subject,
        "htmlContent": body,
    }

    async with httpx.AsyncClient() as client:
        response = await client.post(
            BREVO_SEND_URL,
            json=payload,
            headers={
                "api-key": settings.BREVO_API_KEY,
                "Content-Type": "application/json",
            },
            timeout=10.0,
        )
        response.raise_for_status()
