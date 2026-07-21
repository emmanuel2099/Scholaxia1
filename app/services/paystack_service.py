"""Paystack API helpers — transaction initialize/verify + webhook signature check.

All amounts are integer kobo (NGN * 100), computed server-side only.
"""
from __future__ import annotations

import hashlib
import hmac

import httpx

from app.core.config import settings

PAYSTACK_BASE = "https://api.paystack.co"
SUPPORTED_CURRENCY = "NGN"


class PaystackError(Exception):
    """Raised when the Paystack API rejects a request or returns failure."""


def is_configured() -> bool:
    return bool(settings.PAYSTACK_SECRET_KEY and settings.PAYSTACK_PUBLIC_KEY)


def _headers() -> dict:
    return {
        "Authorization": f"Bearer {settings.PAYSTACK_SECRET_KEY}",
        "Content-Type": "application/json",
    }


def naira_to_kobo(amount_naira: float) -> int:
    """Convert an NGN amount to integer kobo. Rejects non-positive amounts."""
    kobo = int(round(float(amount_naira) * 100))
    if kobo <= 0:
        raise PaystackError("Amount must be greater than zero")
    return kobo


async def initialize_transaction(
    *,
    email: str,
    amount_kobo: int,
    reference: str,
    metadata: dict | None = None,
    callback_url: str | None = None,
) -> dict:
    """Create a Paystack transaction. Returns {authorization_url, access_code, reference}."""
    if not settings.PAYSTACK_SECRET_KEY:
        raise PaystackError("Paystack is not configured on the server")
    if not isinstance(amount_kobo, int) or amount_kobo <= 0:
        raise PaystackError("Invalid amount")
    if not email or "@" not in email:
        raise PaystackError("A valid customer email is required")
    if not reference:
        raise PaystackError("A transaction reference is required")

    payload: dict = {
        "email": email,
        "amount": amount_kobo,
        "currency": SUPPORTED_CURRENCY,
        "reference": reference,
        "metadata": metadata or {},
    }
    redirect = callback_url or settings.PAYSTACK_CALLBACK_URL
    if redirect:
        payload["callback_url"] = redirect

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            f"{PAYSTACK_BASE}/transaction/initialize",
            headers=_headers(),
            json=payload,
        )
    body = resp.json()
    if resp.status_code >= 400 or not body.get("status"):
        raise PaystackError(body.get("message") or "Paystack initialization failed")
    return body.get("data") or {}


async def verify_transaction(reference: str) -> dict:
    """Verify a Paystack transaction by reference. Returns the API data object."""
    if not settings.PAYSTACK_SECRET_KEY:
        raise PaystackError("Paystack is not configured on the server")
    if not reference:
        raise PaystackError("A transaction reference is required")

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.get(
            f"{PAYSTACK_BASE}/transaction/verify/{reference}",
            headers=_headers(),
        )
    body = resp.json()
    if resp.status_code >= 400 or not body.get("status"):
        raise PaystackError(body.get("message") or "Paystack verification failed")
    return body.get("data") or {}


def validate_webhook_signature(raw_body: bytes, signature: str | None) -> bool:
    """Check the x-paystack-signature header (HMAC-SHA512 of the raw body)."""
    if not signature or not settings.PAYSTACK_SECRET_KEY:
        return False
    expected = hmac.new(
        settings.PAYSTACK_SECRET_KEY.encode("utf-8"),
        raw_body,
        hashlib.sha512,
    ).hexdigest()
    return hmac.compare_digest(expected, signature)
