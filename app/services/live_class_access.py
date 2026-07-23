"""Shared live-class plan access checks."""
from __future__ import annotations

import uuid as uuid_lib
from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.datetime_utils import naive_utc_now
from app.core.live_class_plans import get_plan
from app.models.payment import Payment, PaymentStatus
from app.models.user import StudentProfile

PLATFORM_VISIBILITIES = frozenset({"public", "private", "school_group"})


def live_class_requires_subscription(visibility: str | None) -> bool:
    """Platform public/private/school classes join free; subject-matched 1-on-1 needs a plan."""
    vis = (visibility or "subject").lower()
    return vis not in PLATFORM_VISIBILITIES


def parse_uuid(value: str):
    import uuid as uuid_lib
    return uuid_lib.UUID(str(value))


async def _get_profile(db: AsyncSession, student_id: str) -> Optional[StudentProfile]:
    try:
        sid = parse_uuid(student_id)
    except ValueError:
        return None
    result = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == sid)
    )
    return result.scalar_one_or_none()


def _active_plan_from_profile(profile: Optional[StudentProfile], now: datetime) -> Optional[dict]:
    if not profile or not profile.live_plan_id or not profile.live_plan_expires_at:
        return None
    if profile.live_plan_expires_at <= now:
        return None
    plan = get_plan(profile.live_plan_id)
    if not plan:
        return None
    sessions_left = max(0, plan.sessions - (profile.live_plan_sessions_used or 0))
    return {
        "plan_id": plan.id,
        "plan_name": plan.name,
        "category": plan.category,
        "expires_at": profile.live_plan_expires_at,
        "sessions_total": plan.sessions,
        "sessions_used": profile.live_plan_sessions_used or 0,
        "sessions_left": sessions_left,
        "max_subjects": plan.max_subjects,
    }


async def _legacy_payment_plan(
    db: AsyncSession, student_id: uuid_lib.UUID, now: datetime
) -> Optional[dict]:
    """Honor older per-class / flat-fee payments until profile plan is set."""
    cutoff = now - timedelta(days=settings.LIVE_CLASS_MONTHLY_DAYS)
    result = await db.execute(
        select(Payment)
        .where(
            Payment.student_id == student_id,
            Payment.status == PaymentStatus.success,
            Payment.created_at >= cutoff,
            or_(Payment.live_plan_id.isnot(None), Payment.live_class_id.isnot(None)),
        )
        .order_by(Payment.created_at.desc())
        .limit(1)
    )
    payment = result.scalar_one_or_none()
    if not payment:
        return None

    plan = get_plan(payment.live_plan_id) if payment.live_plan_id else get_plan("secondary_standard")
    if not plan:
        return None

    sessions_used = 0
    if payment.live_class_id:
        used_res = await db.execute(
            select(Payment).where(
                Payment.student_id == student_id,
                Payment.status == PaymentStatus.success,
                Payment.live_class_id.isnot(None),
                Payment.created_at >= cutoff,
            )
        )
        sessions_used = len(used_res.scalars().all())

    expires_at = payment.created_at + timedelta(days=settings.LIVE_CLASS_MONTHLY_DAYS)
    if expires_at <= now:
        return None

    sessions_left = max(0, plan.sessions - sessions_used)
    return {
        "plan_id": plan.id,
        "plan_name": plan.name,
        "category": plan.category,
        "expires_at": expires_at,
        "sessions_total": plan.sessions,
        "sessions_used": sessions_used,
        "sessions_left": sessions_left,
        "max_subjects": plan.max_subjects,
        "legacy": True,
    }


async def _ensure_profile_plan_from_payment(
    db: AsyncSession, student_id: str, now: datetime
) -> None:
    """If Flutterwave payment succeeded but profile was not updated, sync from payments."""
    try:
        sid = parse_uuid(student_id)
    except ValueError:
        return

    profile = await _get_profile(db, student_id)
    if (
        profile
        and profile.live_plan_id
        and profile.live_plan_expires_at
        and profile.live_plan_expires_at > now
    ):
        return

    result = await db.execute(
        select(Payment)
        .where(
            Payment.student_id == sid,
            Payment.status == PaymentStatus.success,
            Payment.live_plan_id.isnot(None),
        )
        .order_by(Payment.created_at.desc())
        .limit(10)
    )
    payments = result.scalars().all()
    payment = None
    plan = None
    for row in payments:
        candidate = get_plan(row.live_plan_id)
        if candidate:
            payment = row
            plan = candidate
            break
    if not payment or not plan:
        return

    expires = payment.created_at + timedelta(days=settings.LIVE_CLASS_MONTHLY_DAYS)
    if expires <= now:
        return

    if not profile:
        profile = StudentProfile(user_id=sid, selected_subjects=[])
        db.add(profile)

    profile.live_plan_id = plan.id
    profile.live_plan_expires_at = expires
    profile.live_plan_sessions_used = profile.live_plan_sessions_used or 0
    profile.has_active_subscription = True
    await db.flush()


async def get_live_access_info(
    db: AsyncSession, student_id: str, class_id: Optional[str] = None
) -> dict:
    now = naive_utc_now()
    await _ensure_profile_plan_from_payment(db, student_id, now)
    profile = await _get_profile(db, student_id)
    active = _active_plan_from_profile(profile, now)

    if not active:
        try:
            sid = parse_uuid(student_id)
            active = await _legacy_payment_plan(db, sid, now)
        except ValueError:
            pass

    can_join = bool(active and active["sessions_left"] > 0)

    skill_access = False
    if not can_join:
        try:
            from app.services.skills_enrollment import student_has_active_skill_access

            skill_access = await student_has_active_skill_access(db, student_id)
            if skill_access:
                can_join = True
        except Exception:
            skill_access = False

    return {
        "can_join": can_join,
        "paid": can_join,
        "monthly_pass": can_join,
        "need_plan": not can_join,
        "active_plan": active,
        "valid_until": active["expires_at"] if active else None,
        "sessions_left": active["sessions_left"] if active else (99 if skill_access else 0),
        "skill_enrollment_access": skill_access,
    }


async def activate_live_plan(
    db: AsyncSession, student_id: str, plan_id: str
) -> dict:
    plan = get_plan(plan_id)
    if not plan:
        raise ValueError("Unknown plan")

    profile = await _get_profile(db, student_id)
    if not profile:
        profile = StudentProfile(user_id=parse_uuid(student_id), selected_subjects=[])
        db.add(profile)
        await db.flush()

    now = naive_utc_now()
    profile.live_plan_id = plan.id
    profile.live_plan_expires_at = now + timedelta(days=settings.LIVE_CLASS_MONTHLY_DAYS)
    profile.live_plan_sessions_used = 0
    profile.has_active_subscription = True

    return {
        "plan_id": plan.id,
        "plan_name": plan.name,
        "expires_at": profile.live_plan_expires_at,
        "sessions": plan.sessions,
    }


async def consume_live_session(db: AsyncSession, student_id: str) -> None:
    profile = await _get_profile(db, student_id)
    if not profile:
        return
    profile.live_plan_sessions_used = (profile.live_plan_sessions_used or 0) + 1
