from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import Optional
import uuid

from app.core.database import get_db
from app.core.deps import require_student
from app.core.config import settings
from app.models.payment import Payment, PaymentStatus
from app.models.live_class import LiveClass
from app.models.teacher_material import TeacherMaterial, MaterialPurchase
from app.models.user import User
from app.core.datetime_utils import naive_utc_now
from app.services.flutterwave_service import verify_transaction

router = APIRouter(prefix="/payments", tags=["Payments"])


class FlutterwaveVerifyRequest(BaseModel):
    transaction_id: str
    class_id: Optional[str] = None
    material_id: Optional[str] = None
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


async def _student_has_material_access(db: AsyncSession, student_id: str, material_id: str) -> bool:
    mat_res = await db.execute(select(TeacherMaterial).where(TeacherMaterial.id == material_id))
    material = mat_res.scalar_one_or_none()
    if not material or not material.is_active:
        return False
    if material.is_free:
        return True
    result = await db.execute(
        select(MaterialPurchase).where(
            MaterialPurchase.student_id == student_id,
            MaterialPurchase.material_id == material_id,
        )
    )
    return result.scalar_one_or_none() is not None


@router.get("/live-class/{class_id}/access")
async def live_class_access(
    class_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    paid = await _student_has_paid_for_class(db, current_user["sub"], class_id)
    return {
        "paid": paid,
        "amount": settings.LIVE_CLASS_JOIN_AMOUNT,
        "currency": "NGN",
        "public_key": settings.FLUTTERWAVE_PUBLIC_KEY,
    }


@router.get("/material/{material_id}/access")
async def material_access_payment(
    material_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(TeacherMaterial).where(TeacherMaterial.id == material_id))
    material = result.scalar_one_or_none()
    if not material or not material.is_active:
        raise HTTPException(status_code=404, detail="Material not found")
    has_access = await _student_has_material_access(db, current_user["sub"], material_id)
    return {
        "has_access": has_access,
        "is_free": material.is_free,
        "paid": has_access,
        "amount": material.price if not material.is_free else 0,
        "currency": "NGN",
        "public_key": settings.FLUTTERWAVE_PUBLIC_KEY,
        "title": material.title,
    }


@router.post("/flutterwave/live-class/{class_id}/init")
async def init_live_class_payment(
    class_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    if not settings.FLUTTERWAVE_PUBLIC_KEY or not settings.FLUTTERWAVE_SECRET_KEY:
        raise HTTPException(
            status_code=503,
            detail="Payment system is not configured. Contact Scholaxia support.",
        )

    result = await db.execute(select(LiveClass).where(LiveClass.id == class_id))
    live_class = result.scalar_one_or_none()
    now = naive_utc_now()
    in_window = (
        live_class
        and live_class.start_time
        and live_class.start_time <= now
        and (live_class.end_time is None or live_class.end_time > now)
    )
    if not live_class or (not live_class.is_live and not in_window):
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


@router.post("/flutterwave/material/{material_id}/init")
async def init_material_payment(
    material_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    if not settings.FLUTTERWAVE_PUBLIC_KEY or not settings.FLUTTERWAVE_SECRET_KEY:
        raise HTTPException(status_code=503, detail="Payment system is not configured.")

    result = await db.execute(select(TeacherMaterial).where(TeacherMaterial.id == material_id))
    material = result.scalar_one_or_none()
    if not material or not material.is_active:
        raise HTTPException(status_code=404, detail="Material not found")
    if material.is_free:
        return {"already_paid": True, "is_free": True, "has_access": True}

    if await _student_has_material_access(db, current_user["sub"], material_id):
        return {
            "already_paid": True,
            "amount": material.price,
            "currency": "NGN",
            "public_key": settings.FLUTTERWAVE_PUBLIC_KEY,
        }

    user_res = await db.execute(select(User).where(User.id == current_user["sub"]))
    user = user_res.scalar_one_or_none()
    email = user.email if user else f"{current_user['sub']}@scholaxia.local"
    name = user.full_name if user else "Student"

    tx_ref = f"scholaxia-mat-{material_id[:8]}-{uuid.uuid4().hex[:16]}"

    payment = Payment(
        student_id=current_user["sub"],
        amount=material.price,
        currency="NGN",
        status=PaymentStatus.pending,
        flutterwave_tx_ref=tx_ref,
        material_id=material.id,
        description=f"Material: {material.title}",
    )
    db.add(payment)
    await db.flush()

    return {
        "already_paid": False,
        "payment_id": str(payment.id),
        "tx_ref": tx_ref,
        "amount": material.price,
        "currency": "NGN",
        "public_key": settings.FLUTTERWAVE_PUBLIC_KEY,
        "material_title": material.title,
        "material_subject": material.subject,
        "customer": {"email": email, "name": name},
    }


@router.post("/flutterwave/verify")
async def verify_flutterwave_payment(
    payload: FlutterwaveVerifyRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    if not payload.class_id and not payload.material_id:
        raise HTTPException(status_code=400, detail="class_id or material_id required")

    if payload.class_id:
        if await _student_has_paid_for_class(db, current_user["sub"], payload.class_id):
            return {"paid": True, "class_id": payload.class_id}

    if payload.material_id:
        if await _student_has_material_access(db, current_user["sub"], payload.material_id):
            return {"paid": True, "material_id": payload.material_id, "has_access": True}

    try:
        data = await verify_transaction(payload.transaction_id)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Payment verification failed: {exc}")

    if (data.get("status") or "").lower() != "successful":
        raise HTTPException(status_code=400, detail="Payment was not successful")

    amount_paid = float(data.get("amount") or 0)
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

    if payload.class_id:
        if amount_paid < settings.LIVE_CLASS_JOIN_AMOUNT:
            raise HTTPException(status_code=400, detail="Incorrect payment amount")
        if payment and payment.live_class_id and str(payment.live_class_id) != payload.class_id:
            raise HTTPException(status_code=400, detail="Payment does not match this class")

        meta = data.get("meta") or {}
        if meta.get("class_id") and str(meta.get("class_id")) != payload.class_id:
            raise HTTPException(status_code=400, detail="Payment does not match this class")

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

    # Material purchase
    mat_res = await db.execute(select(TeacherMaterial).where(TeacherMaterial.id == payload.material_id))
    material = mat_res.scalar_one_or_none()
    if not material or not material.is_active:
        raise HTTPException(status_code=404, detail="Material not found")
    if material.is_free:
        return {"paid": True, "material_id": payload.material_id, "has_access": True}

    if amount_paid < material.price:
        raise HTTPException(status_code=400, detail="Incorrect payment amount")
    if payment and payment.material_id and str(payment.material_id) != payload.material_id:
        raise HTTPException(status_code=400, detail="Payment does not match this material")

    if not payment:
        payment = Payment(
            student_id=current_user["sub"],
            amount=amount_paid,
            currency=data.get("currency") or "NGN",
            material_id=material.id,
            description=f"Material: {material.title}",
        )
        db.add(payment)

    payment.status = PaymentStatus.success
    payment.flutterwave_transaction_id = str(data.get("id") or payload.transaction_id)
    if tx_ref:
        payment.flutterwave_tx_ref = tx_ref
    await db.flush()

    existing = await db.execute(
        select(MaterialPurchase).where(
            MaterialPurchase.student_id == current_user["sub"],
            MaterialPurchase.material_id == material.id,
        )
    )
    if not existing.scalar_one_or_none():
        db.add(MaterialPurchase(
            student_id=current_user["sub"],
            material_id=material.id,
            payment_id=payment.id,
        ))
        await db.flush()

    return {"paid": True, "material_id": payload.material_id, "has_access": True, "payment_id": str(payment.id)}
