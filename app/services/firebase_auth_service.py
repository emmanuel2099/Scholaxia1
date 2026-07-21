"""Verify Firebase Phone Auth ID tokens."""

from __future__ import annotations

import re
from typing import Any, Optional

from fastapi import HTTPException
from firebase_admin import auth as fb_auth

from app.services.notification_service import init_firebase


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
            pass
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


def verify_firebase_id_token(id_token: str) -> dict[str, Any]:
    """
    Verify a Firebase ID token from Phone Auth.
    Returns decoded claims (must include phone_number).
    """
    init_firebase()
    token = (id_token or "").strip()
    if not token:
        raise HTTPException(status_code=400, detail="Firebase ID token is required")

    try:
        decoded = fb_auth.verify_id_token(token)
    except Exception as e:
        print(f"[Firebase Auth] token verify failed: {e}")
        raise HTTPException(status_code=401, detail="Invalid or expired Firebase token")

    phone = decoded.get("phone_number")
    if not phone:
        raise HTTPException(
            status_code=400,
            detail="Firebase token has no phone number. Use Phone Auth.",
        )
    return decoded


def phone_from_firebase_token(id_token: str) -> str:
    decoded = verify_firebase_id_token(id_token)
    return normalize_phone(str(decoded["phone_number"]))
