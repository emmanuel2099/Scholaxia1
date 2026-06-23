from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import Optional
import uuid

from app.core.database import get_db
from app.core.deps import require_student
from app.core.config import settings
from app.core.live_class_plans import (
    all_plans_dict,
    get_plan,
    suggest_plan_ids,
)
from app.models.payment import Payment, PaymentStatus
from app.models.live_class import LiveClass
from app.models.teacher_material import TeacherMaterial, MaterialPurchase
from app.models.user import User, StudentProfile
from app.core.datetime_utils import naive_utc_now
from app.services.flutterwave_service import verify_transaction, verify_transaction_by_reference
from app.services.live_class_access import (
    activate_live_plan,
    get_live_access_info,
    parse_uuid,
)

router = APIRouter(prefix="/payments", tags=["Payments"])


class FlutterwaveVerifyRequest(BaseModel):
    transaction_id: str
    class_id: Optional[str] = None
    material_id: Optional[str] = None
    plan_id: Optional[str] = None
    tx_ref: Optional[str] = None


class LivePlanInitRequest(BaseModel):
    plan_id: str
    class_id: Optional[str] = None


class ReconcilePlanRequest(BaseModel):
    tx_ref: Optional[str] = None


async def _student_has_live_access(db: AsyncSession, student_id: str, class_id: str = "") -> bool:
    access = await get_live_access_info(db, student_id, class_id or None)
    return access["can_join"]


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


@router.get("/live-class/plans")
async def list_live_class_plans(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    prof_res = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == current_user["sub"])
    )
    profile = prof_res.scalar_one_or_none()
    education_level = profile.education_level if profile else None
    exam_type = profile.exam_type.value if profile and profile.exam_type else None
    suggested = suggest_plan_ids(education_level, exam_type)
    access = await get_live_access_info(db, current_user["sub"])
    active = access.get("active_plan")
    return {
        "plans": all_plans_dict(),
        "suggested_plan_ids": suggested,
        "active_plan": {
            **active,
            "expires_at": active["expires_at"].isoformat() if active and active.get("expires_at") else None,
        } if active else None,
        "currency": "NGN",
        "public_key": settings.FLUTTERWAVE_PUBLIC_KEY,
    }


@router.get("/live-class/{class_id}/access")
async def live_class_access(
    class_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    access = await get_live_access_info(db, current_user["sub"], class_id)
    valid_until = access.get("valid_until")
    active = access.get("active_plan")
    return {
        "paid": access["can_join"],
        "need_plan": access.get("need_plan", True),
        "monthly_pass": access.get("monthly_pass", False),
        "sessions_left": access.get("sessions_left", 0),
        "active_plan": active,
        "valid_until": valid_until.isoformat() if valid_until else None,
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


@router.post("/flutterwave/live-plan/init")
async def init_live_plan_payment(
    payload: LivePlanInitRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    if not settings.FLUTTERWAVE_PUBLIC_KEY or not settings.FLUTTERWAVE_SECRET_KEY:
        raise HTTPException(
            status_code=503,
            detail="Payment system is not configured. Contact Scholaxia support.",
        )

    plan = get_plan(payload.plan_id)
    if not plan:
        raise HTTPException(status_code=404, detail="Plan not found")

    if await _student_has_live_access(db, current_user["sub"], payload.class_id or ""):
        return {
            "already_paid": True,
            "plan_id": plan.id,
            "amount": plan.price,
            "currency": "NGN",
            "public_key": settings.FLUTTERWAVE_PUBLIC_KEY,
        }

    if payload.class_id:
        result = await db.execute(select(LiveClass).where(LiveClass.id == payload.class_id))
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

    user_res = await db.execute(select(User).where(User.id == current_user["sub"]))
    user = user_res.scalar_one_or_none()
    email = user.email if user else f"{current_user['sub']}@scholaxia.local"
    name = user.full_name if user else "Student"

    tx_ref = f"scholaxia-plan-{plan.id[:12]}-{uuid.uuid4().hex[:12]}"

    payment = Payment(
        student_id=parse_uuid(current_user["sub"]),
        amount=plan.price,
        currency="NGN",
        status=PaymentStatus.pending,
        flutterwave_tx_ref=tx_ref,
        live_plan_id=plan.id,
        live_class_id=parse_uuid(payload.class_id) if payload.class_id else None,
        description=f"Live plan: {plan.name}",
    )
    db.add(payment)
    await db.flush()

    return {
        "already_paid": False,
        "payment_id": str(payment.id),
        "plan_id": plan.id,
        "plan_name": plan.name,
        "tx_ref": tx_ref,
        "amount": plan.price,
        "currency": "NGN",
        "public_key": settings.FLUTTERWAVE_PUBLIC_KEY,
        "class_id": payload.class_id,
        "customer": {"email": email, "name": name},
    }


@router.post("/flutterwave/live-class/{class_id}/init")
async def init_live_class_payment(
    class_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Legacy endpoint — redirects clients to choose a monthly plan."""
    if await _student_has_live_access(db, current_user["sub"], class_id):
        return {"already_paid": True, "need_plan": False}
    raise HTTPException(
        status_code=402,
        detail="Choose a Scholaxia One-on-One Live Class plan before joining.",
    )


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
        student_id=parse_uuid(current_user["sub"]),
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


@router.post("/flutterwave/reconcile-plan")
async def reconcile_plan_payment(
    payload: ReconcilePlanRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Activate a plan when payment succeeded but the return page was missed."""
    sid = parse_uuid(current_user["sub"])
    payment = None

    if payload.tx_ref:
        pay_res = await db.execute(
            select(Payment).where(
                Payment.flutterwave_tx_ref == payload.tx_ref,
                Payment.student_id == sid,
            )
        )
        payment = pay_res.scalar_one_or_none()

    if not payment:
        pending_res = await db.execute(
            select(Payment)
            .where(
                Payment.student_id == sid,
                Payment.live_plan_id.isnot(None),
                Payment.status == PaymentStatus.pending,
            )
            .order_by(Payment.created_at.desc())
            .limit(1)
        )
        payment = pending_res.scalar_one_or_none()

    if not payment or not payment.live_plan_id:
        access = await get_live_access_info(db, current_user["sub"])
        return {
            "reconciled": False,
            "paid": access["paid"],
            "active_plan": access.get("active_plan"),
        }

    plan = get_plan(payment.live_plan_id)
    if not plan:
        raise HTTPException(status_code=400, detail="Unknown plan")

    if payment.status == PaymentStatus.success:
        access = await get_live_access_info(db, current_user["sub"])
        if access["paid"]:
            active = access.get("active_plan") or {}
            expires = active.get("expires_at")
            return {
                "reconciled": True,
                "paid": True,
                "plan_id": plan.id,
                "active_plan": {
                    **active,
                    "expires_at": expires.isoformat() if hasattr(expires, "isoformat") else expires,
                },
            }
        activated = await activate_live_plan(db, current_user["sub"], plan.id)
        await db.flush()
        access = await get_live_access_info(db, current_user["sub"])
        return {
            "reconciled": True,
            "paid": access["paid"],
            "plan_id": plan.id,
            "active_plan": {
                **activated,
                "expires_at": activated["expires_at"].isoformat(),
            },
        }

    tx_ref = payment.flutterwave_tx_ref
    if not tx_ref:
        raise HTTPException(status_code=400, detail="Payment reference missing")

    try:
        data = await verify_transaction_by_reference(tx_ref)
    except Exception as exc:
        access = await get_live_access_info(db, current_user["sub"])
        return {
            "reconciled": False,
            "paid": access["paid"],
            "message": str(exc),
        }

    if (data.get("status") or "").lower() != "successful":
        access = await get_live_access_info(db, current_user["sub"])
        return {
            "reconciled": False,
            "paid": access["paid"],
            "message": "Payment not completed yet",
        }

    amount_paid = float(data.get("amount") or data.get("charged_amount") or 0)
    expected_amount = float(payment.amount) if payment.amount else plan.price
    if amount_paid + 1 < expected_amount and amount_paid + 1 < plan.price:
        raise HTTPException(status_code=400, detail="Incorrect payment amount")

    payment.status = PaymentStatus.success
    payment.live_plan_id = plan.id
    payment.flutterwave_transaction_id = str(data.get("id") or "")
    payment.flutterwave_tx_ref = data.get("tx_ref") or tx_ref

    activated = await activate_live_plan(db, current_user["sub"], plan.id)
    await db.flush()
    access = await get_live_access_info(db, current_user["sub"])
    return {
        "reconciled": True,
        "paid": access["paid"],
        "plan_id": plan.id,
        "payment_id": str(payment.id),
        "active_plan": {
            **activated,
            "expires_at": activated["expires_at"].isoformat(),
        },
    }


@router.post("/flutterwave/verify")
async def verify_flutterwave_payment(
    payload: FlutterwaveVerifyRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    plan_id = payload.plan_id
    if not payload.class_id and not payload.material_id and not plan_id:
        if payload.tx_ref:
            pay_lookup = await db.execute(
                select(Payment).where(
                    Payment.flutterwave_tx_ref == payload.tx_ref,
                    Payment.student_id == parse_uuid(current_user["sub"]),
                )
            )
            existing = pay_lookup.scalar_one_or_none()
            if existing and existing.live_plan_id:
                plan_id = existing.live_plan_id
        if not plan_id and not payload.material_id and not payload.class_id:
            raise HTTPException(status_code=400, detail="class_id, plan_id, or material_id required")

    if payload.class_id and await _student_has_live_access(db, current_user["sub"], payload.class_id):
        return {"paid": True, "class_id": payload.class_id}

    if payload.material_id and await _student_has_material_access(db, current_user["sub"], payload.material_id):
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
                Payment.student_id == parse_uuid(current_user["sub"]),
            )
        )
        payment = pay_res.scalar_one_or_none()

    plan_id = plan_id or (payment.live_plan_id if payment else None)
    if not plan_id and payment and payment.live_plan_id:
        plan_id = payment.live_plan_id

    if plan_id or (payment and payment.live_plan_id):
        plan_id = plan_id or payment.live_plan_id
        plan = get_plan(plan_id)
        if not plan:
            raise HTTPException(status_code=400, detail="Unknown plan")

        expected_amount = float(payment.amount) if payment and payment.amount else plan.price
        if amount_paid + 1 < expected_amount and amount_paid + 1 < plan.price:
            raise HTTPException(status_code=400, detail="Incorrect payment amount")

        if payment and payment.status == PaymentStatus.success and payment.live_plan_id:
            activated = await activate_live_plan(db, current_user["sub"], payment.live_plan_id)
            await db.flush()
            return {
                "paid": True,
                "plan_id": payment.live_plan_id,
                "class_id": payload.class_id,
                "payment_id": str(payment.id),
                "active_plan": {
                    **activated,
                    "expires_at": activated["expires_at"].isoformat(),
                },
            }

        if not payment:
            payment = Payment(
                student_id=parse_uuid(current_user["sub"]),
                amount=amount_paid,
                currency=data.get("currency") or "NGN",
                live_plan_id=plan.id,
                description=f"Live plan: {plan.name}",
            )
            db.add(payment)

        payment.status = PaymentStatus.success
        payment.live_plan_id = plan.id
        payment.flutterwave_transaction_id = str(data.get("id") or payload.transaction_id)
        if tx_ref:
            payment.flutterwave_tx_ref = tx_ref
        activated = await activate_live_plan(db, current_user["sub"], plan.id)
        await db.flush()
        return {
            "paid": True,
            "plan_id": plan.id,
            "class_id": payload.class_id,
            "payment_id": str(payment.id),
            "active_plan": {
                **activated,
                "expires_at": activated["expires_at"].isoformat(),
            },
        }

    if payload.material_id:
        mat_res = await db.execute(select(TeacherMaterial).where(TeacherMaterial.id == payload.material_id))
        material = mat_res.scalar_one_or_none()
        if not material or not material.is_active:
            raise HTTPException(status_code=404, detail="Material not found")
        if material.is_free:
            return {"paid": True, "material_id": payload.material_id, "has_access": True}

        if amount_paid < material.price:
            raise HTTPException(status_code=400, detail="Incorrect payment amount")

        if not payment:
            payment = Payment(
                student_id=parse_uuid(current_user["sub"]),
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

    raise HTTPException(status_code=400, detail="Could not verify payment")
