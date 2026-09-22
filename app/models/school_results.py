"""School results (per student, per term) and scratch-card PINs.

Spec: schools enter CA + Exam scores; the system computes totals, grades,
positions; parents check results on the school's private link using a
scratch-card PIN.

Public helpers (importable without a DB):
- compute_grade(total): Nigerian WASSCE-style band.
- ordinal(n): 1 -> '1st' for class positions.
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, Numeric, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.datetime_utils import naive_utc_now


def compute_grade(total: float) -> str:
    """Nigerian WASSCE-style grade bands."""
    if total >= 75: return "A1"
    if total >= 70: return "B2"
    if total >= 65: return "B3"
    if total >= 60: return "C4"
    if total >= 55: return "C5"
    if total >= 50: return "C6"
    if total >= 45: return "D7"
    if total >= 40: return "E8"
    return "F9"


def ordinal(n: int) -> str:
    if 10 <= n % 100 <= 20:
        suffix = "th"
    else:
        suffix = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
    return f"{n}{suffix}"


def _grade(total: float) -> str:
    return compute_grade(total)


class SchoolResult(Base):
    """One subject result row for one student in one term."""

    __tablename__ = "school_results"
    __table_args__ = (
        UniqueConstraint("school_id", "student_id", "term_label", "subject", name="uq_school_result_row"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("school_campuses.id"), index=True)
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), index=True)
    term_label: Mapped[str] = mapped_column(String(80), index=True)  # "2025/2026 First Term"
    session_label: Mapped[str] = mapped_column(String(40), nullable=True)  # "2025/2026"
    class_name: Mapped[str] = mapped_column(String(60), nullable=True)     # "JSS 1A"
    subject: Mapped[str] = mapped_column(String(80))
    ca_score: Mapped[float] = mapped_column(Numeric(5, 2), default=0)      # out of 40 (configurable later)
    exam_score: Mapped[float] = mapped_column(Numeric(5, 2), default=0)    # out of 60
    total: Mapped[float] = mapped_column(Numeric(5, 2), default=0)
    grade: Mapped[str] = mapped_column(String(4), default="")
    remark: Mapped[str] = mapped_column(String(120), nullable=True)
    # Position in class for this subject ("3rd") — computed by a recompute call
    position: Mapped[str] = mapped_column(String(10), nullable=True)
    entered_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=naive_utc_now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=naive_utc_now, onupdate=naive_utc_now)


class ResultPublication(Base):
    """School flips this on when parents may view a term's results."""

    __tablename__ = "school_result_publications"
    __table_args__ = (
        UniqueConstraint("school_id", "term_label", name="uq_school_result_publication"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("school_campuses.id"), index=True)
    term_label: Mapped[str] = mapped_column(String(80))
    class_name: Mapped[str | None] = mapped_column(String(60), nullable=True)  # NULL = whole school
    is_published: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    published_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class SchoolScratchCard(Base):
    """A PIN a school generates and sells to parents; one result view per PIN."""

    __tablename__ = "school_scratch_cards"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("school_campuses.id"), index=True)
    pin: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    serial: Mapped[str] = mapped_column(String(30), nullable=True)
    # A card can be scoped to one student or usable for any student of the school
    student_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True, index=True)
    term_label: Mapped[str] = mapped_column(String(80), nullable=True)  # NULL = any term
    price_ngn: Mapped[float] = mapped_column(Numeric(10, 2), default=0)
    is_used: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    used_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    used_for_student: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    times_used: Mapped[int] = mapped_column(Integer, default=0)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=naive_utc_now)


class ScratchCardSale(Base):
    """Income record for cards sold — feeds the Super Admin income dashboard."""

    __tablename__ = "school_scratch_card_sales"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("school_campuses.id"), index=True)
    card_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("school_scratch_cards.id"), nullable=True)
    quantity: Mapped[int] = mapped_column(Integer, default=1)
    unit_price_ngn: Mapped[float] = mapped_column(Numeric(10, 2), default=0)
    total_ngn: Mapped[float] = mapped_column(Numeric(12, 2), default=0)
    sold_by: Mapped[str] = mapped_column(String(120), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=naive_utc_now)
