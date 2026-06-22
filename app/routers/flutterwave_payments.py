from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import Optional
import uuid

from app.core.database import get_db
from app.core.deps import require_student, get_current_user
from app.core.config import settings
from app.models.payment import Payment, PaymentStatus
from app.models.live_class import LiveClass
from app.models.user import User
from app.services.flutterwave_service import verify_transaction

router = APIRouter(prefix="/payments", tags=["Payments"])


class FlutterwaveVerifyRequest(BaseModel):
    transaction_id: str
    class_id: str
    tx_ref: Optional[str] = None


async def _student_has_paid_for_class(db: AsyncSession, student_id: str, class_id: str) -> bool:
    result = await db.execute(
        select(Payment).where(
            Payment.student_id == student_id,
            Payment.live_class_id == class_id,
            Payment.status == PaymentStatus.success,
        )
    )
    return result.scalar_one_or_none() is not None


@router.get("/live-class/{class_id}/access")
async def live_class_access(
    class_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Check whether the student has already paid to join this live class."""
    paid = await _student_has_paid_for_class(db, current_user["sub"], class_id)
    return {
        "paid": paid,
        "amount": settings.LIVE_CLASS_JOIN_AMOUNT,
        "currency": "NGN",
        "public_key": settings.FLUTTERWAVE_PUBLIC_KEY,
    }


@router.post("/flutterwave/live-class/{class_id}/init")
async def init_live_class_payment(
    class_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Start a Flutterwave payment for joining a live class."""
    if not settings.FLUTTERWAVE_PUBLIC_KEY or not settings.FLUTTERWAVE_SECRET_KEY:
        raise HTTPException(
            status_code=503,
            detail="Payment system is not configured. Contact Scholaxia support.",
        )

    result = await db.execute(select(LiveClass).where(LiveClass.id == class_id))
    live_class = result.scalar_one_or_none()
    if not live_class or not live_class.is_live:
        raise HTTPException(status_code=404, detail="Class not live")

    if await _student_has_paid_for_class(db, current_user["sub"], class_id):
        return {
            "already_paid": True,
            "amount": settings.LIVE_CLASS_JOIN_AMOUNT,
            "currency": "NGN",
            "public_key": settings.FLUTTERWAVE_PUBLIC_KEY,
        }

    user_res = await db.execute(select(User).where(User.id == current_user["sub"]))
    user = user_res.scalar_one_or_none()
    email = user.email if user else f"{current_user['sub']}@scholaxia.local"
    name = user.full_name if user else "Student"

    tx_ref = f"scholaxia-live-{class_id[:8]}-{uuid.uuid4().hex[:16]}"

    payment = Payment(
        student_id=current_user["sub"],
        amount=settings.LIVE_CLASS_JOIN_AMOUNT,
        currency="NGN",
        status=PaymentStatus.pending,
        flutterwave_tx_ref=tx_ref,
        live_class_id=live_class.id,
        description=f"Live class: {live_class.title}",
    )
    db.add(payment)
    await db.flush()

    return {
        "already_paid": False,
        "payment_id": str(payment.id),
        "tx_ref": tx_ref,
        "amount": settings.LIVE_CLASS_JOIN_AMOUNT,
        "currency": "NGN",
        "public_key": settings.FLUTTERWAVE_PUBLIC_KEY,
        "class_title": live_class.title,
        "class_subject": live_class.subject,
        "customer": {"email": email, "name": name},
    }


@router.post("/flutterwave/verify")
async def verify_flutterwave_payment(
    payload: FlutterwaveVerifyRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Verify Flutterwave payment and grant access to the live class."""
    if await _student_has_paid_for_class(db, current_user["sub"], payload.class_id):
        return {"paid": True, "class_id": payload.class_id}

    try:
        data = await verify_transaction(payload.transaction_id)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Payment verification failed: {exc}")

    if (data.get("status") or "").lower() != "successful":
        raise HTTPException(status_code=400, detail="Payment was not successful")

    amount_paid = float(data.get("amount") or 0)
    if amount_paid < settings.LIVE_CLASS_JOIN_AMOUNT:
        raise HTTPException(status_code=400, detail="Incorrect payment amount")

    if payment and str(payment.live_class_id) != payload.class_id:
        raise HTTPException(status_code=400, detail="Payment does not match this class")

    meta = data.get("meta") or {}
    if meta.get("class_id") and str(meta.get("class_id")) != payload.class_id:
        raise HTTPException(status_code=400, detail="Payment does not match this class")

    tx_ref = data.get("tx_ref") or payload.tx_ref
    payment = None
    if tx_ref:
        pay_res = await db.execute(
            select(Payment).where(
                Payment.flutterwave_tx_ref == tx_ref,
                Payment.student_id == current_user["sub"],
            )
        )
        payment = pay_res.scalar_one_or_none()

    if not payment:
        payment = Payment(
            student_id=current_user["sub"],
            amount=amount_paid,
            currency=data.get("currency") or "NGN",
            live_class_id=payload.class_id,
            description="Live class access",
        )
        db.add(payment)

    payment.status = PaymentStatus.success
    payment.flutterwave_transaction_id = str(data.get("id") or payload.transaction_id)
    if tx_ref:
        payment.flutterwave_tx_ref = tx_ref
    await db.flush()

    return {"paid": True, "class_id": payload.class_id, "payment_id": str(payment.id)}
