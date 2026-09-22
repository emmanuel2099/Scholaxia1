"""School plans (Basic / Standard / Premium) and the commercial core.

Spec (scholaxia.com):
- 3 term-based plans a school picks at registration: BASIC N20,000,
  STANDARD N35,000, PREMIUM N60,000 per term.
- A plan unlocks features (gating): results, scratch cards, CBT,
  attendance, assignments, timetable, fees, communication, staff mgmt.
- Super Admin can upgrade/downgrade a school instantly.
"""
from __future__ import annotations

import uuid
from datetime import datetime
from typing import Union

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, Numeric, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.datetime_utils import naive_utc_now

# ---------------------------------------------------------------- plans ----

PLAN_BASIC = "basic"
PLAN_STANDARD = "standard"
PLAN_PREMIUM = "premium"
ALL_PLANS = (PLAN_BASIC, PLAN_STANDARD, PLAN_PREMIUM)

PLAN_PRICES_NGN = {PLAN_BASIC: 20000.0, PLAN_STANDARD: 35000.0, PLAN_PREMIUM: 60000.0}

# plan -> feature flags. Gating is plan-inclusive: PREMIUM includes everything.
PLAN_FEATURES: dict[str, set[str]] = {
    PLAN_BASIC: {"students", "subjects", "results", "scratch_cards"},
    PLAN_STANDARD: {"students", "subjects", "results", "scratch_cards", "cbt",
                    "attendance", "assignments", "timetable"},
    PLAN_PREMIUM: {"students", "subjects", "results", "scratch_cards", "cbt",
                   "attendance", "assignments", "timetable", "fees",
                   "communication", "staff_management"},
}


def plan_has_feature(plan: str | None, feature: str) -> bool:
    if not plan:
        return False
    return feature in PLAN_FEATURES.get(plan.lower(), set())


def plan_price_ngn(plan: str) -> float:
    return PLAN_PRICES_NGN.get(plan.lower(), 0.0)


# The features a school portal may show, in a stable order for the UI.
ALL_FEATURES = (
    "students", "subjects", "results", "scratch_cards", "cbt",
    "attendance", "assignments", "timetable", "fees",
    "communication", "staff_management",
)


class SchoolSubscription(Base):
    """A school's current plan, renewed per term.

    One active row per campus. History is preserved by starting a new row
    on each renewal/upgrade so income reports can sum them.
    """

    __tablename__ = "school_subscriptions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("school_campuses.id"), index=True)
    plan: Mapped[str] = mapped_column(String(20), nullable=False)  # basic | standard | premium
    price_ngn: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    # Terms are free-form strings: "2025/2026 First Term" etc.
    term_label: Mapped[str] = mapped_column(String(80), nullable=False, default="")
    starts_at: Mapped[datetime] = mapped_column(DateTime, default=naive_utc_now)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)  # None = open-ended
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    # Who flipped it: super admin email or "system"
    changed_by: Mapped[str] = mapped_column(String(120), nullable=True)
    notes: Mapped[str] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=naive_utc_now)


class SchoolPlanAudit(Base):
    """One row per plan change (upgrade/downgrade/renewal) for the income dashboard."""

    __tablename__ = "school_plan_audit"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("school_campuses.id"), index=True)
    old_plan: Mapped[str | None] = mapped_column(String(20), nullable=True)
    new_plan: Mapped[str] = mapped_column(String(20), nullable=False)
    amount_ngn: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    term_label: Mapped[str] = mapped_column(String(80), nullable=False, default="")
    changed_by: Mapped[str] = mapped_column(String(120), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=naive_utc_now)
