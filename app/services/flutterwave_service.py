"""Flutterwave API helpers for live class payments."""
import httpx
from app.core.config import settings

FLW_BASE = "https://api.flutterwave.com/v3"


def _headers() -> dict:
    return {
        "Authorization": f"Bearer {settings.FLUTTERWAVE_SECRET_KEY}",
        "Content-Type": "application/json",
    }


async def verify_transaction(transaction_id: str) -> dict:
    """Verify a Flutterwave transaction by ID. Returns API JSON data object."""
    if not settings.FLUTTERWAVE_SECRET_KEY:
        raise RuntimeError("Flutterwave is not configured on the server")
    url = f"{FLW_BASE}/transactions/{transaction_id}/verify"
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.get(url, headers=_headers())
        resp.raise_for_status()
        body = resp.json()
    if body.get("status") != "success":
        raise ValueError(body.get("message") or "Flutterwave verification failed")
    return body.get("data") or {}
