"""Paystack payments — library books, CBT packages, and live class packages.

Security model:
- Amounts are always computed server-side (kobo) from the catalog/DB price.
- The client only ever sends a product identifier and receives a reference.
- Verification re-checks status, currency (NGN), and amount against the
  pending Payment row before fulfilling.
- The webhook validates the x-paystack-signature header (HMAC-SHA512 of the
  raw body with the secret key) and fulfillment is idempotent.
"""
from __future__ import annotations

import json
import logging
import uuid
from datetime import timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.cbt_packages import all_cbt_packages_dict, get_cbt_package
from app.core.config import settings
from app.core.database import get_db
from app.core.datetime_utils import naive_utc_now
from app.core.deps import require_student_or_kind
from app.core.live_class_plans import get_plan
from app.core.skills_programs import (
    get_skill_program,
    payment_amount_for_mode,
    skill_plan_key,
)
from app.models.content import Book, BookPurchase
from app.models.payment import Payment, PaymentStatus, StudentEntitlement
from app.models.marketplace import MarketplaceBooking, MarketplaceProduct
from app.models.user import StudentProfile, User
from app.services.cbt_access import active_cbt_access, subject_snapshot
from app.services import paystack_service
from app.services.live_class_access import (
    activate_live_plan,
    parse_uuid,
)
from app.services.paystack_service import PaystackError
from app.services.skills_enrollment import (
    get_skill_entitlement,
    grant_or_update_skill_enrollment,
    refresh_skill_entitlement_status,
    serialize_skill_enrollment,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/payments/paystack", tags=["Paystack Payments"])

PROVIDER = "paystack"

PRODUCT_LIBRARY_BOOK = "library_book"
PRODUCT_CBT_PACKAGE = "cbt_package"
PRODUCT_CLASS_PACKAGE = "class_package"
PRODUCT_MARKETPLACE_BOOKING = "marketplace_booking"
PRODUCT_SKILL_ENROLLMENT = "skill_enrollment"
PRODUCT_TYPES = {
    PRODUCT_LIBRARY_BOOK,
    PRODUCT_CBT_PACKAGE,
    PRODUCT_CLASS_PACKAGE,
    PRODUCT_MARKETPLACE_BOOKING,
    PRODUCT_SKILL_ENROLLMENT,
}

ENTITLEMENT_CBT_PACKAGE = "cbt_package"


class InitializeRequest(BaseModel):
    product_type: str
    product_id: str
    payment_mode: Optional[str] = None
    installment: Optional[int] = None
    full_name: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    location: Optional[str] = None
    preferred_start: Optional[str] = None
    notes: Optional[str] = None


class VerifyRequest(BaseModel):
    reference: str


def _require_configured() -> None:
    if not paystack_service.is_configured():
        raise HTTPException(status_code=503, detail="Paystack is not configured on the server.")


def _new_reference(product_type: str) -> str:
    short = {
        "library_book": "book",
        "cbt_package": "cbt",
        "class_package": "class",
        "marketplace_booking": "market",
        "skill_enrollment": "skill",
    }[product_type]
    return f"pstk-{short}-{uuid.uuid4().hex}"


async def _get_user(db: AsyncSession, user_id: str) -> Optional[User]:
    result = await db.execute(select(User).where(User.id == user_id))
    return result.scalar_one_or_none()


# ── Product resolution (server-side prices) ──────────────────────────────────

async def _resolve_product(
    db: AsyncSession, student_id: str, product_type: str, product_id: str
) -> dict:
    """Return {price_naira, title, already_owned, extra} for a purchasable product."""
    if product_type == PRODUCT_LIBRARY_BOOK:
        try:
            book_uuid = parse_uuid(product_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid book id")
        result = await db.execute(select(Book).where(Book.id == book_uuid))
        book = result.scalar_one_or_none()
        if not book or not book.is_active:
            raise HTTPException(status_code=404, detail="Book not found")
        if book.is_free:
            return {"price_naira": 0.0, "title": book.title, "already_owned": True, "extra": {"is_free": True}}
        if not book.price or book.price <= 0:
            raise HTTPException(status_code=400, detail="Book has no valid price")
        owned_res = await db.execute(
            select(BookPurchase).where(
                BookPurchase.student_id == parse_uuid(student_id),
                BookPurchase.book_id == book_uuid,
            )
        )
        owned = owned_res.scalar_one_or_none() is not None
        return {"price_naira": float(book.price), "title": book.title, "already_owned": owned, "extra": {}}

    if product_type == PRODUCT_CBT_PACKAGE:
        package = get_cbt_package(product_id)
        if not package:
            raise HTTPException(status_code=404, detail="CBT package not found")
        # Renewals/extensions are allowed — never report as already owned.
        return {"price_naira": float(package.price), "title": package.name, "already_owned": False, "extra": {"duration_days": package.duration_days}}

    if product_type == PRODUCT_CLASS_PACKAGE:
        plan = get_plan(product_id)
        if not plan:
            raise HTTPException(status_code=404, detail="Class package not found")
        return {
            "price_naira": float(plan.price),
            "title": plan.name,
            # Class bundles can be purchased again after their sessions are used.
            "already_owned": False,
            "extra": {"sessions": plan.sessions},
        }

    if product_type == PRODUCT_MARKETPLACE_BOOKING:
        try:
            booking_uuid = parse_uuid(product_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid marketplace booking id")
        result = await db.execute(
            select(MarketplaceBooking, MarketplaceProduct)
            .join(
                MarketplaceProduct,
                MarketplaceProduct.id == MarketplaceBooking.product_id,
            )
            .where(
                MarketplaceBooking.id == booking_uuid,
                MarketplaceBooking.user_id == parse_uuid(student_id),
            )
        )
        row = result.first()
        if not row:
            raise HTTPException(status_code=404, detail="Marketplace booking not found")
        booking, product = row
        if not product.price or product.price <= 0:
            raise HTTPException(status_code=400, detail="This product has no online price")
        return {
            "price_naira": float(product.price),
            "title": product.title,
            "already_owned": booking.status == "paid",
            "extra": {"booking_id": str(booking.id)},
        }

    if product_type == PRODUCT_SKILL_ENROLLMENT:
        raise HTTPException(
            status_code=400,
            detail="skill_enrollment requires payment_mode via initialize payload",
        )

    raise HTTPException(status_code=400, detail=f"Unknown product_type. Use one of: {sorted(PRODUCT_TYPES)}")


async def _resolve_skill_product(
    db: AsyncSession,
    student_id: str,
    skill_id: str,
    *,
    payment_mode: str = "half",
    installment: int = 1,
) -> dict:
    program = get_skill_program(skill_id)
    if not program:
        raise HTTPException(status_code=404, detail="Training program not found")

    mode = (payment_mode or "half").strip().lower()
    if mode not in ("once", "half"):
        raise HTTPException(status_code=400, detail="payment_mode must be once or half")
    installment = int(installment or 1)
    if installment not in (1, 2):
        raise HTTPException(status_code=400, detail="installment must be 1 or 2")
    if mode == "once" and installment != 1:
        raise HTTPException(status_code=400, detail="Full payment uses installment 1 only")

    existing_ent = await get_skill_entitlement(db, student_id, skill_id)
    if existing_ent:
        await refresh_skill_entitlement_status(db, existing_ent)
        details = dict(existing_ent.details or {})
        status = (details.get("status") or "").lower()
        paid_n = int(details.get("installments_paid") or 0)
        if status == "completed" or (details.get("payment_mode") == "once" and paid_n >= 1):
            return {
                "price_naira": 0.0,
                "title": program["title"],
                "already_owned": True,
                "extra": {
                    "enrollment": serialize_skill_enrollment(existing_ent),
                    "payment_mode": mode,
                    "installment": installment,
                },
            }
        if installment == 2:
            if status == "suspended":
                raise HTTPException(
                    status_code=403,
                    detail="Enrollment was shut down because the balance was not paid on time. Contact support.",
                )
            if paid_n < 1:
                raise HTTPException(status_code=400, detail="Pay the first installment before the balance.")
            if paid_n >= 2:
                return {
                    "price_naira": 0.0,
                    "title": program["title"],
                    "already_owned": True,
                    "extra": {"enrollment": serialize_skill_enrollment(existing_ent)},
                }
            mode = "half"
        elif installment == 1 and paid_n >= 1 and status == "active":
            raise HTTPException(
                status_code=400,
                detail="First installment already paid. Pay the balance installment when due.",
            )

    amount = payment_amount_for_mode(program["fee"], mode, installment)
    return {
        "price_naira": float(amount),
        "title": program["title"],
        "already_owned": False,
        "extra": {"payment_mode": mode, "installment": installment, "fee": program["fee"]},
    }


# ── Idempotent fulfillment ────────────────────────────────────────────────────

async def _grant_book(db: AsyncSession, payment: Payment) -> None:
    book_uuid = parse_uuid(payment.product_id)
    existing = await db.execute(
        select(BookPurchase).where(
            BookPurchase.student_id == payment.student_id,
            BookPurchase.book_id == book_uuid,
        )
    )
    if existing.scalar_one_or_none() is None:
        db.add(BookPurchase(student_id=payment.student_id, book_id=book_uuid, payment_id=payment.id))


async def _grant_cbt_package(db: AsyncSession, payment: Payment) -> None:
    existing = await db.execute(
        select(StudentEntitlement).where(StudentEntitlement.payment_id == payment.id)
    )
    if existing.scalar_one_or_none() is not None:
        return
    package = get_cbt_package(payment.product_id or "")
    duration = package.duration_days if package else 30
    now = naive_utc_now()
    # Extend from the current active entitlement's expiry when renewing.
    active_res = await db.execute(
        select(StudentEntitlement)
        .where(
            StudentEntitlement.student_id == payment.student_id,
            StudentEntitlement.entitlement_type == ENTITLEMENT_CBT_PACKAGE,
            StudentEntitlement.entitlement_key == (payment.product_id or ""),
            StudentEntitlement.expires_at > now,
        )
        .order_by(StudentEntitlement.expires_at.desc())
        .limit(1)
    )
    active = active_res.scalar_one_or_none()
    start = active.expires_at if active else now
    profile = (
        await db.execute(
            select(StudentProfile).where(StudentProfile.user_id == payment.student_id)
        )
    ).scalar_one_or_none()
    db.add(StudentEntitlement(
        student_id=payment.student_id,
        entitlement_type=ENTITLEMENT_CBT_PACKAGE,
        entitlement_key=payment.product_id or "",
        payment_id=payment.id,
        granted_at=now,
        expires_at=start + timedelta(days=duration),
        details=subject_snapshot(profile),
    ))


async def _grant_class_package(db: AsyncSession, payment: Payment) -> None:
    await activate_live_plan(db, str(payment.student_id), payment.product_id or "")


async def _grant_marketplace_booking(db: AsyncSession, payment: Payment) -> None:
    result = await db.execute(
        select(MarketplaceBooking).where(
            MarketplaceBooking.id == parse_uuid(payment.product_id or "")
        )
    )
    booking = result.scalar_one_or_none()
    if booking and booking.status == "pending":
        booking.status = "paid"


async def _fulfill(db: AsyncSession, payment: Payment, tx_data: dict) -> None:
    """Mark the payment successful and grant the product. Safe to call repeatedly."""
    already_fulfilled = payment.status == PaymentStatus.success

    if not already_fulfilled:
        payment.status = PaymentStatus.success
        payment.provider_transaction_id = str(tx_data.get("id") or "")

    if payment.product_type == PRODUCT_LIBRARY_BOOK:
        await _grant_book(db, payment)
    elif payment.product_type == PRODUCT_CBT_PACKAGE:
        await _grant_cbt_package(db, payment)
    elif payment.product_type == PRODUCT_CLASS_PACKAGE:
        # Grant on first success; on verify/webhook replay, re-apply only if
        # the student has no active plan row (missed grant), not when sessions
        # are exhausted (that would unfairly reset the counter).
        if not already_fulfilled:
            await _grant_class_package(db, payment)
        else:
            from app.services.live_class_access import get_live_access_info

            access = await get_live_access_info(db, str(payment.student_id))
            if not access.get("active_plan"):
                await _grant_class_package(db, payment)
    elif payment.product_type == PRODUCT_MARKETPLACE_BOOKING:
        await _grant_marketplace_booking(db, payment)
    elif payment.product_type == PRODUCT_SKILL_ENROLLMENT and not already_fulfilled:
        desc = payment.description or ""
        mode = "half"
        installment = 1
        if "mode=once" in desc:
            mode = "once"
        if "installment=2" in desc:
            installment = 2
            mode = "half"
        contact = {}
        if "contact=" in desc:
            # contact is stored in payment metadata via description prefix only; details in entitlement
            pass
        await grant_or_update_skill_enrollment(
            db,
            student_id=str(payment.student_id),
            skill_id=payment.product_id or "",
            payment_mode=mode,
            installment=installment,
            amount_paid=float(payment.amount or 0),
            payment_id=payment.id,
            contact=contact or None,
        )

    await db.flush()


def _validate_success(payment: Payment, tx_data: dict) -> None:
    """Reject fulfillment when status/currency/amount don't match the server record."""
    if (tx_data.get("status") or "").lower() != "success":
        raise HTTPException(status_code=400, detail="Payment was not successful")
    currency = (tx_data.get("currency") or "").upper()
    if currency != paystack_service.SUPPORTED_CURRENCY:
        raise HTTPException(status_code=400, detail="Unsupported payment currency")
    paid_kobo = int(tx_data.get("amount") or 0)
    expected_kobo = paystack_service.naira_to_kobo(payment.amount)
    if paid_kobo < expected_kobo:
        raise HTTPException(status_code=400, detail="Incorrect payment amount")


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("/cbt-packages")
async def list_cbt_packages(current_user: dict = Depends(require_student_or_kind)):
    return {
        "packages": all_cbt_packages_dict(),
        "currency": "NGN",
        "public_key": settings.PAYSTACK_PUBLIC_KEY,
    }


@router.get("/cbt-access")
async def get_cbt_access(
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    """Current annual package access, including paid-subject snapshot checks."""
    return await active_cbt_access(db, current_user["sub"])


@router.post("/initialize")
async def initialize_payment(
    payload: InitializeRequest,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    _require_configured()
    product_type = (payload.product_type or "").strip().lower()
    product_id = (payload.product_id or "").strip()
    if product_type not in PRODUCT_TYPES:
        raise HTTPException(status_code=400, detail=f"Unknown product_type. Use one of: {sorted(PRODUCT_TYPES)}")
    if not product_id:
        raise HTTPException(status_code=400, detail="product_id is required")

    student_id = current_user["sub"]
    if product_type == PRODUCT_SKILL_ENROLLMENT:
        product = await _resolve_skill_product(
            db,
            student_id,
            product_id,
            payment_mode=payload.payment_mode or "half",
            installment=int(payload.installment or 1),
        )
        if int(payload.installment or 1) == 1:
            if not (payload.full_name or "").strip() or not (payload.phone or "").strip():
                raise HTTPException(status_code=400, detail="Full name and phone are required")
    else:
        product = await _resolve_product(db, student_id, product_type, product_id)

    if product["already_owned"]:
        return {
            "already_owned": True,
            "product_type": product_type,
            "product_id": product_id,
            "title": product["title"],
            **product["extra"],
        }

    user = await _get_user(db, student_id)
    email = (payload.email or "").strip() if product_type == PRODUCT_SKILL_ENROLLMENT else ""
    email = email or (user.email if user else "")
    if not email:
        raise HTTPException(status_code=400, detail="Your account has no email for payment receipts")

    amount_kobo = paystack_service.naira_to_kobo(product["price_naira"])
    reference = _new_reference(product_type)

    mode = (product.get("extra") or {}).get("payment_mode") or payload.payment_mode or "half"
    installment = (product.get("extra") or {}).get("installment") or payload.installment or 1
    desc = f"{product_type}: {product['title']}"
    if product_type == PRODUCT_SKILL_ENROLLMENT:
        desc = (
            f"Skills enroll: {product['title']} | mode={mode} | installment={installment}"
        )[:255]

    payment = Payment(
        student_id=parse_uuid(student_id),
        amount=product["price_naira"],
        currency="NGN",
        status=PaymentStatus.pending,
        provider=PROVIDER,
        provider_reference=reference,
        product_type=product_type,
        product_id=product_id,
        # Keep legacy columns populated so existing access checks keep working.
        book_id=parse_uuid(product_id) if product_type == PRODUCT_LIBRARY_BOOK else None,
        live_plan_id=(
            skill_plan_key(product_id)
            if product_type == PRODUCT_SKILL_ENROLLMENT
            else (product_id if product_type == PRODUCT_CLASS_PACKAGE else None)
        ),
        description=desc[:255],
    )
    db.add(payment)
    await db.flush()

    try:
        data = await paystack_service.initialize_transaction(
            email=email,
            amount_kobo=amount_kobo,
            reference=reference,
            callback_url="https://scholaxia.app/paystack/callback",
            metadata={
                "student_id": str(student_id),
                "product_type": product_type,
                "product_id": product_id,
                "payment_id": str(payment.id),
                "payment_mode": str(mode),
                "installment": str(installment),
                "full_name": (payload.full_name or "")[:120],
                "phone": (payload.phone or "")[:40],
            },
        )
    except PaystackError as exc:
        raise HTTPException(status_code=502, detail=f"Paystack error: {exc}")

    return {
        "already_owned": False,
        "payment_id": str(payment.id),
        "reference": reference,
        "authorization_url": data.get("authorization_url"),
        "access_code": data.get("access_code"),
        "amount": product["price_naira"],
        "amount_kobo": amount_kobo,
        "currency": "NGN",
        "public_key": settings.PAYSTACK_PUBLIC_KEY,
        "product_type": product_type,
        "product_id": product_id,
        "title": product["title"],
        "payment_mode": mode,
        "installment": installment,
        "customer": {"email": email, "name": user.full_name if user else payload.full_name},
    }


@router.post("/verify")
async def verify_payment(
    payload: VerifyRequest,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    _require_configured()
    reference = (payload.reference or "").strip()
    if not reference:
        raise HTTPException(status_code=400, detail="reference is required")

    pay_res = await db.execute(
        select(Payment).where(
            Payment.provider == PROVIDER,
            Payment.provider_reference == reference,
            Payment.student_id == parse_uuid(current_user["sub"]),
        )
    )
    payment = pay_res.scalar_one_or_none()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment reference not found")

    if payment.status == PaymentStatus.success:
        # Already fulfilled (e.g. by the webhook) — re-run grants idempotently.
        await _fulfill(db, payment, {})
        return _fulfillment_response(payment)

    try:
        tx_data = await paystack_service.verify_transaction(reference)
    except PaystackError as exc:
        raise HTTPException(status_code=400, detail=f"Payment verification failed: {exc}")

    _validate_success(payment, tx_data)
    await _fulfill(db, payment, tx_data)
    return _fulfillment_response(payment)


def _fulfillment_response(payment: Payment) -> dict:
    return {
        "paid": True,
        "payment_id": str(payment.id),
        "reference": payment.provider_reference,
        "product_type": payment.product_type,
        "product_id": payment.product_id,
        "has_access": True,
    }


@router.post("/webhook")
async def paystack_webhook(request: Request, db: AsyncSession = Depends(get_db)):
    raw_body = await request.body()
    signature = request.headers.get("x-paystack-signature")
    if not paystack_service.validate_webhook_signature(raw_body, signature):
        raise HTTPException(status_code=401, detail="Invalid webhook signature")

    try:
        event = json.loads(raw_body)
    except (ValueError, UnicodeDecodeError):
        raise HTTPException(status_code=400, detail="Invalid webhook payload")

    if event.get("event") != "charge.success":
        return {"status": "ignored"}

    tx_data = event.get("data") or {}
    reference = tx_data.get("reference") or ""

    pay_res = await db.execute(
        select(Payment).where(
            Payment.provider == PROVIDER,
            Payment.provider_reference == reference,
        )
    )
    payment = pay_res.scalar_one_or_none()
    if not payment:
        logger.warning("Paystack webhook: unknown reference %r", reference)
        return {"status": "ignored"}

    if payment.status == PaymentStatus.success:
        return {"status": "ok"}

    try:
        _validate_success(payment, tx_data)
    except HTTPException as exc:
        # Signed event that doesn't match our record — do not fulfill, don't retry.
        logger.error("Paystack webhook rejected for %r: %s", reference, exc.detail)
        return {"status": "rejected", "detail": exc.detail}

    await _fulfill(db, payment, tx_data)
    return {"status": "ok"}
