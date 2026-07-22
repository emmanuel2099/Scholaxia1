"""Skills enrollment entitlements — once/half pay, balance deadline, live access."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Optional
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.datetime_utils import naive_utc_now
from app.core.skills_programs import (
    SKILL_ENTITLEMENT_TYPE,
    get_skill_program,
    payment_amount_for_mode,
    skill_midpoint_due,
    skill_program_end,
)
from app.models.payment import StudentEntitlement
from app.services.live_class_access import activate_live_plan, parse_uuid


def _as_dt(value: Any) -> Optional[datetime]:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    try:
        return datetime.fromisoformat(str(value).replace("Z", ""))
    except Exception:
        return None


async def get_skill_entitlement(
    db: AsyncSession, student_id: str, skill_id: str
) -> Optional[StudentEntitlement]:
    try:
        sid = parse_uuid(student_id)
    except ValueError:
        return None
    result = await db.execute(
        select(StudentEntitlement)
        .where(
            StudentEntitlement.student_id == sid,
            StudentEntitlement.entitlement_type == SKILL_ENTITLEMENT_TYPE,
            StudentEntitlement.entitlement_key == skill_id,
        )
        .order_by(StudentEntitlement.granted_at.desc())
        .limit(1)
    )
    return result.scalar_one_or_none()


async def list_skill_entitlements(
    db: AsyncSession, student_id: str
) -> list[StudentEntitlement]:
    try:
        sid = parse_uuid(student_id)
    except ValueError:
        return []
    result = await db.execute(
        select(StudentEntitlement)
        .where(
            StudentEntitlement.student_id == sid,
            StudentEntitlement.entitlement_type == SKILL_ENTITLEMENT_TYPE,
        )
        .order_by(StudentEntitlement.granted_at.desc())
    )
    return list(result.scalars().all())


async def refresh_skill_entitlement_status(
    db: AsyncSession, ent: StudentEntitlement
) -> StudentEntitlement:
    """Suspend half-pay enrollments when the balance deadline passes unpaid."""
    details = dict(ent.details or {})
    status = (details.get("status") or "active").lower()
    if status in ("completed", "suspended"):
        return ent

    mode = (details.get("payment_mode") or "half").lower()
    installments = int(details.get("installments_paid") or 0)
    due_at = _as_dt(details.get("balance_due_at"))
    now = naive_utc_now()

    if mode == "half" and installments < 2 and due_at and now >= due_at:
        details["status"] = "suspended"
        details["suspended_reason"] = "Balance installment not paid by due date"
        ent.details = details
        ent.expires_at = now
        await db.flush()
    return ent


def skill_entitlement_is_active(ent: Optional[StudentEntitlement], now: datetime | None = None) -> bool:
    if not ent:
        return False
    now = now or naive_utc_now()
    details = dict(ent.details or {})
    status = (details.get("status") or "active").lower()
    if status == "suspended":
        return False
    if status == "completed":
        if ent.expires_at and ent.expires_at <= now:
            return False
        return True
    # active half-pay or once (before complete)
    if ent.expires_at and ent.expires_at <= now:
        return False
    return status == "active"


async def student_has_active_skill_access(db: AsyncSession, student_id: str) -> bool:
    ents = await list_skill_entitlements(db, student_id)
    now = naive_utc_now()
    for ent in ents:
        await refresh_skill_entitlement_status(db, ent)
        if skill_entitlement_is_active(ent, now):
            return True
    return False


async def grant_or_update_skill_enrollment(
    db: AsyncSession,
    *,
    student_id: str,
    skill_id: str,
    payment_mode: str,
    installment: int,
    amount_paid: float,
    payment_id: UUID | None = None,
    contact: dict | None = None,
) -> StudentEntitlement:
    program = get_skill_program(skill_id)
    if not program:
        raise ValueError("Unknown skills program")

    mode = (payment_mode or "half").strip().lower()
    if mode not in ("once", "half"):
        mode = "half"
    installment = max(1, int(installment or 1))
    now = naive_utc_now()
    fee = float(program["fee"])

    ent = await get_skill_entitlement(db, student_id, skill_id)
    if not ent:
        ent = StudentEntitlement(
            student_id=parse_uuid(student_id),
            entitlement_type=SKILL_ENTITLEMENT_TYPE,
            entitlement_key=skill_id,
            payment_id=payment_id,
            granted_at=now,
            details={},
        )
        db.add(ent)

    details = dict(ent.details or {})
    prev_paid = float(details.get("amount_paid") or 0)
    prev_installments = int(details.get("installments_paid") or 0)

    if installment >= 2:
        details["installments_paid"] = max(prev_installments, 2)
        details["amount_paid"] = prev_paid + float(amount_paid)
        details["payment_mode"] = "half"
        details["status"] = "completed"
        details["balance_due"] = 0
        details.pop("suspended_reason", None)
        ent.expires_at = skill_program_end(ent.granted_at or now, program["duration"])
    elif mode == "once":
        details["payment_mode"] = "once"
        details["installments_paid"] = 1
        details["amount_paid"] = float(amount_paid)
        details["balance_due"] = 0
        details["status"] = "completed"
        details.pop("balance_due_at", None)
        details.pop("suspended_reason", None)
        ent.expires_at = skill_program_end(now, program["duration"])
        ent.granted_at = ent.granted_at or now
    else:
        due = skill_midpoint_due(now, program["duration"])
        details["payment_mode"] = "half"
        details["installments_paid"] = max(prev_installments, 1)
        details["amount_paid"] = float(amount_paid) if prev_installments < 1 else prev_paid
        details["balance_due"] = payment_amount_for_mode(fee, "half", 2)
        details["balance_due_at"] = due.isoformat()
        details["status"] = "active"
        details.pop("suspended_reason", None)
        ent.expires_at = due
        ent.granted_at = ent.granted_at or now

    details["total_fee"] = fee
    details["program_title"] = program["title"]
    details["program_duration"] = program["duration"]
    if contact:
        for key in ("full_name", "phone", "email", "location"):
            if contact.get(key):
                details[key] = contact[key]
    if payment_id:
        ent.payment_id = payment_id
    ent.details = details
    await db.flush()

    # Skill students may also join live classes for the enrollment window.
    try:
        await activate_live_plan(db, student_id, "secondary_standard")
    except Exception:
        pass

    return ent


def serialize_skill_enrollment(ent: StudentEntitlement) -> dict:
    details = dict(ent.details or {})
    return {
        "skill_id": ent.entitlement_key,
        "program_title": details.get("program_title") or ent.entitlement_key,
        "payment_mode": details.get("payment_mode") or "half",
        "status": details.get("status") or "active",
        "total_fee": details.get("total_fee"),
        "amount_paid": details.get("amount_paid") or 0,
        "balance_due": details.get("balance_due") or 0,
        "balance_due_at": details.get("balance_due_at"),
        "installments_paid": details.get("installments_paid") or 0,
        "expires_at": ent.expires_at.isoformat() if ent.expires_at else None,
        "granted_at": ent.granted_at.isoformat() if ent.granted_at else None,
        "suspended_reason": details.get("suspended_reason"),
        "active": skill_entitlement_is_active(ent),
    }
