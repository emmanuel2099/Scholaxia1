"""Global CBT practice settings and generated attempts (exam-type packages)."""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Float, Integer, String, Text
from sqlalchemy.dialects.postgresql import JSON, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class CbtGlobalSettings(Base):
    """Singleton-style row (id=1) controlling practice CBT behaviour."""

    __tablename__ = "cbt_global_settings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, default=1)
    cbt_enabled: Mapped[bool] = mapped_column(Boolean, default=True)

    # Per board: questions per subject (JAMB English can differ)
    jamb_questions_per_subject: Mapped[int] = mapped_column(Integer, default=40)
    jamb_english_questions: Mapped[int] = mapped_column(Integer, default=60)
    jamb_duration_minutes: Mapped[int] = mapped_column(Integer, default=180)
    jamb_subjects_required: Mapped[int] = mapped_column(Integer, default=4)

    waec_questions_per_subject: Mapped[int] = mapped_column(Integer, default=50)
    waec_duration_minutes: Mapped[int] = mapped_column(Integer, default=60)

    neco_questions_per_subject: Mapped[int] = mapped_column(Integer, default=50)
    neco_duration_minutes: Mapped[int] = mapped_column(Integer, default=60)

    # Common Entrance — independent from JAMB
    ce_questions_per_subject: Mapped[int] = mapped_column(Integer, default=40)
    ce_duration_minutes: Mapped[int] = mapped_column(Integer, default=60)
    # Combined-exam subject list (like JAMB subjects, but admin-configured)
    ce_subjects: Mapped[list | None] = mapped_column(JSON, nullable=True)

    randomize_questions: Mapped[bool] = mapped_column(Boolean, default=True)
    randomize_options: Mapped[bool] = mapped_column(Boolean, default=True)
    allow_resume: Mapped[bool] = mapped_column(Boolean, default=True)
    auto_submit_on_timeout: Mapped[bool] = mapped_column(Boolean, default=True)

    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class CbtPracticeAttempt(Base):
    """One generated practice run (unique question set per attempt)."""

    __tablename__ = "cbt_practice_attempts"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True, nullable=False)
    exam_type: Mapped[str] = mapped_column(String(30), index=True, nullable=False)  # JAMB | WAEC | NECO
    # Subjects in order (JAMB sections). For WAEC/NECO usually one subject.
    subjects: Mapped[list] = mapped_column(JSON, nullable=False, default=list)
    # [{subject, questions:[{id, text, options:[{key,text}], correct_key, explanation, topic}]}]
    # correct_key stored server-side only for grading; client pack strips it on download if needed
    sections: Mapped[list] = mapped_column(JSON, nullable=False, default=list)
    answers: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    status: Mapped[str] = mapped_column(String(30), default="in_progress", index=True)
    section_index: Mapped[int] = mapped_column(Integer, default=0)
    duration_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    started_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    ends_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    submitted_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    score: Mapped[float | None] = mapped_column(Float, nullable=True)
    max_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    result_summary: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
