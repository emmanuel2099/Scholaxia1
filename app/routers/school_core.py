"""School commercial core: plan catalog, registration, gating, Super Admin.

Spec (scholaxia.com):
- Schools register on the main site and automatically get a private link
  slug (greensprings -> greensprings.scholaxia.com).
- 3 term plans: BASIC N20,000 / STANDARD N35,000 / PREMIUM N60,000.
- Super Admin (/super-admin) sees all schools, their plans, upgrades or
  downgrades instantly, and sees income from plans + scratch cards.
"""
from __future__ import annotations

import re
import uuid as uuid_mod
from datetime import datetime, timedelta
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import distinct, func, select, text, update as sql_update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import get_current_user, require_admin, require_school_staff
from app.core.security import hash_password
from app.core.datetime_utils import naive_utc_now
from app.models.school_campus import SchoolCampus
from app.models.school_plans import (
    ALL_FEATURES,
    ALL_PLANS,
    PLAN_PRICES_NGN,
    SchoolPlanAudit,
    SchoolSubscription,
    plan_has_feature,
    plan_price_ngn,
)
from app.models.user import User, UserRole

router = APIRouter(tags=["School plans"])

BASE_DOMAIN_DEFAULT = "scholaxia.com"


# ------------------------------------------------------------- helpers ----

def slugify(name: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", (name or "").lower()).strip("-")
    return re.sub(r"-{2,}", "-", s)


async def _unique_slug(db: AsyncSession, base: str) -> str:
    base = slugify(base)[:60] or "school"
    slug, n = base, 2
    while (await db.execute(select(SchoolCampus.id).where(SchoolCampus.slug == slug))).scalar_one_or_none():
        slug = f"{base}-{n}"
        n += 1
    return slug


async def _active_subscription(db: AsyncSession, school_id) -> SchoolSubscription | None:
    row = (
        await db.execute(
            select(SchoolSubscription)
            .where(
                SchoolSubscription.school_id == school_id,
                SchoolSubscription.is_active.is_(True),
            )
            .order_by(SchoolSubscription.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if row and row.expires_at and row.expires_at < naive_utc_now():
        return None
    return row


def _features_response(plan: str | None) -> dict:
    plan = (plan or "").lower()
    return {
        "plan": plan or None,
        "features": [f for f in ALL_FEATURES if plan_has_feature(plan, f)],
    }


async def _require_super_admin(current_user: dict = Depends(require_admin)) -> dict:
    """Main platform admin (role=admin). Sub-admins are rejected."""
    if current_user.get("sub_admin_permissions") is not None:
        raise HTTPException(status_code=403, detail="Super admin only")
    return current_user


# -------------------------------------------------- plan catalog (public) ----

class PlanOut(BaseModel):
    id: str
    price_ngn: float
    features: list[str]


@router.get("/public/school-plans")
async def list_plans() -> dict:
    """Public plan catalog for the registration page."""
    return {
        "plans": [
            {
                "id": p,
                "price_ngn": PLAN_PRICES_NGN[p],
                "features": sorted(ALL_FEATURES and [f for f in ALL_FEATURES if plan_has_feature(p, f)]),
            }
            for p in ALL_PLANS
        ]
    }


@router.get("/public/schools/check-email")
async def check_email(email: str, db: AsyncSession = Depends(get_db)) -> dict:
    """Registration-page helper: does this email already exist on the platform?

    Registration itself never requires the old password (any email may register
    a school); this endpoint remains available for UX hints.
    """
    email = (email or "").lower().strip()
    exists = False
    if email:
        exists = (
            await db.execute(select(User.id).where(User.email == email))
        ).scalar_one_or_none() is not None
    return {"exists": exists}


# ------------------------------------------------------- registration ----

class SchoolRegisterIn(BaseModel):
    school_name: str = Field(min_length=2, max_length=255)
    city: str | None = None
    state: str | None = None
    admin_full_name: str = Field(min_length=2, max_length=255)
    admin_email: EmailStr
    admin_phone: str | None = None
    admin_password: str = Field(min_length=8, max_length=128)
    plan: str = "basic"


@router.post("/public/schools/register", status_code=201)
async def register_school(payload: SchoolRegisterIn, db: AsyncSession = Depends(get_db)) -> dict:
    """Public school signup: creates campus + slug + admin account + plan.

    Returns the school's private link slug so the site can show
    'your link: greensprings.scholaxia.com' immediately.
    """
    plan = (payload.plan or "basic").lower().strip()
    if plan not in ALL_PLANS:
        raise HTTPException(status_code=422, detail=f"plan must be one of {list(ALL_PLANS)}")

    email = payload.admin_email.lower().strip()
    existing_user = (
        await db.execute(select(User).where(User.email == email))
    ).scalar_one_or_none()
    if existing_user is not None:
        # Any email may register a school. If the email matches an existing
        # platform account, that account is promoted to this school's admin and
        # the password entered here becomes the account password — no proof of
        # the old password is required.
        if existing_user.role == UserRole.school_admin and existing_user.school_id is not None:
            raise HTTPException(status_code=409, detail="This account already manages a school on Scholaxia")
    phone = (payload.admin_phone or "").strip() or None
    if phone:
        phone_query = select(User.id).where(User.phone == phone)
        if existing_user is not None:
            phone_query = phone_query.where(User.id != existing_user.id)
        if (await db.execute(phone_query)).scalar_one_or_none():
            raise HTTPException(status_code=409, detail="An account with this phone number already exists")

    campus = SchoolCampus(
        name=payload.school_name.strip(),
        slug=await _unique_slug(db, payload.school_name),
        city=payload.city,
        state=payload.state,
        is_active=True,
        subscription_active=False,  # flipped on when super admin confirms payment
        subscription_plan=plan,
    )
    db.add(campus)
    await db.flush()

    if existing_user is not None:
        # The existing account becomes the school's admin; the password chosen
        # in this form is now the account's password.
        admin = existing_user
        admin.role = UserRole.school_admin
        admin.school_id = campus.id
        admin.hashed_password = hash_password(payload.admin_password)
        if phone:
            admin.phone = phone
        linked_account = True
    else:
        admin = User(
            email=email,
            hashed_password=hash_password(payload.admin_password),
            full_name=payload.admin_full_name.strip(),
            phone=phone,
            role=UserRole.school_admin,
            school_id=campus.id,
            is_active=True,
        )
        db.add(admin)
        linked_account = False
    await db.flush()

    sub = SchoolSubscription(
        school_id=campus.id,
        plan=plan,
        price_ngn=plan_price_ngn(plan),
        term_label="pending payment",
        is_active=False,  # pending until super admin confirms payment
        changed_by="self-registration",
    )
    audit = SchoolPlanAudit(
        school_id=campus.id,
        old_plan=None,
        new_plan=plan,
        amount_ngn=0,  # only counted when confirmed
        term_label="pending payment",
        changed_by="self-registration",
    )
    db.add_all([sub, audit])
    await db.commit()

    return {
        "school_id": str(campus.id),
        "slug": campus.slug,
        "private_link": f"https://{campus.slug}.{BASE_DOMAIN_DEFAULT}",
        "plan": plan,
        "price_ngn": plan_price_ngn(plan),
        "status": "pending_payment",
        "account_linked": linked_account,
        "message": (
            "Registration received. This email is now your school's admin account — "
            "sign in with the password you just created. Your plan activates as soon "
            "as payment is confirmed."
            if linked_account
            else "Registration received. Your school's plan activates as soon as payment is confirmed."
        ),
    }


# ------------------------------------------------- subdomain resolution ----

class SchoolPublicOut(BaseModel):
    slug: str
    name: str
    city: str | None = None
    state: str | None = None
    plan: str | None = None
    logo_url: str | None = None


@router.get("/public/schools/by-slug/{slug}")
async def school_by_slug(slug: str, db: AsyncSession = Depends(get_db)) -> dict:
    """Resolve a school's private link (greensprings.scholaxia.com)."""
    row = (
        await db.execute(
            select(SchoolCampus).where(SchoolCampus.slug == slug.lower().strip(), SchoolCampus.is_active.is_(True))
        )
    ).scalar_one_or_none()
    if not row:
        raise HTTPException(status_code=404, detail="School not found")
    sub = await _active_subscription(db, row.id)
    return {
        "school_id": str(row.id),
        "slug": row.slug,
        "name": row.name,
        "city": row.city,
        "state": row.state,
        "plan": sub.plan if sub else None,
        "logo_url": getattr(row, "logo_url", None),
    }


@router.get("/public/schools/resolve-host")
async def resolve_host(host: str = Query(..., description="e.g. greensprings.scholaxia.com"),
                       db: AsyncSession = Depends(get_db)) -> dict:
    """Given a hostname, return the school (or null for the main site)."""
    host = (host or "").lower().strip().split(":")[0]
    base = BASE_DOMAIN_DEFAULT
    if host == base or host == f"www.{base}" or not host.endswith(f".{base}"):
        return {"school": None}
    slug = host[: -len(base) - 1]
    if not slug or "." in slug:
        return {"school": None}
    try:
        return {"school": await school_by_slug(slug, db)}
    except HTTPException:
        return {"school": None}


# ------------------------------------------------------ plan management ----

class PlanChangeIn(BaseModel):
    plan: str
    term_label: str = Field(default="", max_length=80)
    months: int = Field(default=0, ge=0, le=36, description="Sets expiry; 0 = open-ended")
    amount_paid_ngn: float = Field(default=0, ge=0)
    notes: str | None = None


@router.get("/school/me/plan")
async def my_plan(current_user: dict = Depends(require_school_staff), db: AsyncSession = Depends(get_db)) -> dict:
    """What the school portal uses to decide which buttons to show."""
    sid = current_user.get("school_id")
    if not sid:
        raise HTTPException(status_code=400, detail="No school linked to this account")
    campus = (
        await db.execute(select(SchoolCampus).where(SchoolCampus.id == UUID(sid)))
    ).scalar_one_or_none()
    if not campus:
        raise HTTPException(status_code=404, detail="School not found")
    sub = await _active_subscription(db, campus.id)
    plan = sub.plan if sub else campus.subscription_plan
    features = _features_response(plan)
    return {
        "school_id": sid,
        "school_name": campus.name,
        "slug": campus.slug,
        "plan": plan,
        "features": features["features"],
        "subscription_active": bool(sub),
        "expires_at": sub.expires_at.isoformat() if sub and sub.expires_at else None,
        "term_label": sub.term_label if sub else None,
        "price_ngn": plan_price_ngn(plan) if plan else 0,
    }


def require_school_feature(feature: str):
    """Dependency factory: gate any endpoint behind a plan feature.

    Usage:  deps = [Depends(require_school_feature("cbt"))]
    """

    async def _inner(current_user: dict = Depends(require_school_staff), db: AsyncSession = Depends(get_db)) -> dict:
        sid = current_user.get("school_id")
        if not sid:
            raise HTTPException(status_code=400, detail="No school linked to this account")
        sub = await _active_subscription(db, UUID(sid))
        plan = sub.plan if sub else None
        if not plan or not plan_has_feature(plan, feature):
            pretty = feature.replace("_", " ")
            raise HTTPException(
                status_code=402,
                detail=f"This feature is not in your plan. Please upgrade to use {pretty}.",
            )
        return current_user

    return _inner


# -------------------------------------------------------- super admin ----

@router.get("/super-admin/schools")
async def list_schools(
    q: str | None = None,
    plan: str | None = None,
    current_user: dict = Depends(_require_super_admin),
    db: AsyncSession = Depends(get_db),
) -> dict:
    stmt = select(SchoolCampus).order_by(SchoolCampus.created_at.desc()).limit(500)
    rows = (await db.execute(stmt)).scalars().all()
    out = []
    for r in rows:
        sub = await _active_subscription(db, r.id)
        plan_now = sub.plan if sub else None
        if plan and plan_now != plan.lower():
            continue
        if q and q.lower() not in (r.name or "").lower() and q.lower() not in (r.slug or ""):
            continue
        admin = (
            await db.execute(
                select(User.email, User.full_name).where(
                    User.school_id == r.id, User.role == UserRole.school_admin
                )
            )
        ).first()
        out.append(
            {
                "school_id": str(r.id),
                "name": r.name,
                "slug": r.slug,
                "city": r.city,
                "state": r.state,
                "plan": plan_now,
                "subscription_active": bool(sub),
                "expires_at": sub.expires_at.isoformat() if sub and sub.expires_at else None,
                "term_label": sub.term_label if sub else None,
                "price_ngn": plan_price_ngn(plan_now) if plan_now else 0,
                "admin_email": admin[0] if admin else None,
                "admin_name": admin[1] if admin else None,
                "is_active": r.is_active,
            }
        )
    return {"schools": out, "count": len(out)}


@router.post("/super-admin/schools/{school_id}/plan", status_code=201)
async def change_school_plan(
    school_id: UUID,
    payload: PlanChangeIn,
    current_user: dict = Depends(_require_super_admin),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """The one-button upgrade/downgrade. Deactivates old subs, writes a new
    active sub + an income audit row (only when money was actually paid)."""
    plan = (payload.plan or "").lower().strip()
    if plan not in ALL_PLANS:
        raise HTTPException(status_code=422, detail=f"plan must be one of {list(ALL_PLANS)}")

    campus = (
        await db.execute(select(SchoolCampus).where(SchoolCampus.id == school_id))
    ).scalar_one_or_none()
    if not campus:
        raise HTTPException(status_code=404, detail="School not found")

    current = await _active_subscription(db, school_id)
    old_plan = current.plan if current else None

    if current:
        current.is_active = False

    expires = naive_utc_now() + timedelta(days=30 * payload.months) if payload.months else None
    amount = float(payload.amount_paid_ngn or plan_price_ngn(plan))
    sub = SchoolSubscription(
        school_id=school_id,
        plan=plan,
        price_ngn=amount,
        term_label=payload.term_label,
        starts_at=naive_utc_now(),
        expires_at=expires,
        is_active=True,
        changed_by=current_user.get("email") or "super-admin",
        notes=payload.notes,
    )
    audit = SchoolPlanAudit(
        school_id=school_id,
        old_plan=old_plan,
        new_plan=plan,
        amount_ngn=amount,
        term_label=payload.term_label,
        changed_by=current_user.get("email") or "super-admin",
    )
    campus.subscription_plan = plan
    campus.subscription_active = True
    db.add_all([sub, audit])
    await db.commit()

    return {
        "school_id": str(school_id),
        "old_plan": old_plan,
        "new_plan": plan,
        "subscription_active": True,
        "expires_at": expires.isoformat() if expires else None,
    }


@router.get("/super-admin/income")
async def income(
    current_user: dict = Depends(_require_super_admin),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """All income from subscriptions + scratch cards, for the dashboard."""
    sub_total = (
        await db.execute(select(func.coalesce(func.sum(SchoolPlanAudit.amount_ngn), 0)))
    ).scalar() or 0
    by_school = (
        await db.execute(
            select(
                SchoolPlanAudit.school_id,
                func.coalesce(func.sum(SchoolPlanAudit.amount_ngn), 0).label("total"),
            )
            .group_by(SchoolPlanAudit.school_id)
            .order_by(func.coalesce(func.sum(SchoolPlanAudit.amount_ngn), 0).desc())
        )
    ).all()
    from app.models.school_results import ScratchCardSale

    card_total = (
        await db.execute(select(func.coalesce(func.sum(ScratchCardSale.total_ngn), 0)))
    ).scalar() or 0
    school_names = {
        str(r.id): r.name
        for r in (await db.execute(select(SchoolCampus.id, SchoolCampus.name))).all()
    }
    return {
        "subscriptions_total_ngn": float(sub_total),
        "scratch_cards_total_ngn": float(card_total),
        "grand_total_ngn": float(sub_total) + float(card_total),
        "by_school": [
            {
                "school_id": str(school_id),
                "school_name": school_names.get(str(school_id), "?"),
                "subscriptions_ngn": float(total),
            }
            for school_id, total in by_school
        ],
    }
