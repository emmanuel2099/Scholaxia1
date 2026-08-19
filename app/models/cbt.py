import uuid
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, ForeignKey, Text, Integer, Float, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.core.database import Base


def normalize_paper_kind(raw: str | None) -> str:
    value = (raw or "cbt_practice").strip().lower().replace("-", "_").replace(" ", "_")
    if value in ("past", "past_question", "past_questions", "pq"):
        return "past_questions"
    return "cbt_practice"


class CBTExam(Base):
    __tablename__ = "cbt_exams"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    subject: Mapped[str] = mapped_column(String(100), nullable=False)
    exam_type: Mapped[str] = mapped_column(String(30), nullable=False)  # JAMB, WAEC, NECO, SCHOOL, COMMON_ENTRANCE
    # cbt_practice = student CBT tab; past_questions = student Past Questions tab (same timed engine)
    paper_kind: Mapped[str] = mapped_column(String(32), default="cbt_practice", nullable=False)
    year: Mapped[int | None] = mapped_column(Integer, nullable=True)  # e.g. 2019 — used for student year filter
    duration_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    total_questions: Mapped[int] = mapped_column(Integer, nullable=False)
    created_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    is_published: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    # School exam security flags
    is_school_exam: Mapped[bool] = mapped_column(Boolean, default=False)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("school_campuses.id"), nullable=True, index=True
    )
    # When True: AI is locked, camera required, minimize/screenshot blocked
    ai_locked: Mapped[bool] = mapped_column(Boolean, default=False)
    camera_required: Mapped[bool] = mapped_column(Boolean, default=False)
    block_minimize: Mapped[bool] = mapped_column(Boolean, default=False)

    # School exam schedule (teacher sets window when students can take the exam)
    scheduled_start: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    scheduled_end: Mapped[datetime] = mapped_column(DateTime, nullable=True)

    # Internal exam targeting (admin assigns teacher + optional students)
    assigned_student_ids: Mapped[list | None] = mapped_column(JSON, nullable=True)
    notes_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    notes_title: Mapped[str | None] = mapped_column(String(255), nullable=True)

    questions: Mapped[list["CBTQuestion"]] = relationship("CBTQuestion", back_populates="exam")
    sessions: Mapped[list["CBTSession"]] = relationship("CBTSession", back_populates="exam")


class CBTQuestion(Base):
    __tablename__ = "cbt_questions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    exam_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("cbt_exams.id"))
    question_text: Mapped[str] = mapped_column(Text, nullable=False)
    option_a: Mapped[str] = mapped_column(Text, nullable=False)
    option_b: Mapped[str] = mapped_column(Text, nullable=False)
    option_c: Mapped[str] = mapped_column(Text, nullable=False)
    option_d: Mapped[str] = mapped_column(Text, nullable=False)
    correct_option: Mapped[str] = mapped_column(String(1), nullable=False)  # A, B, C, D
    explanation: Mapped[str] = mapped_column(Text, nullable=True)
    topic: Mapped[str] = mapped_column(String(255), nullable=True)
    image_url: Mapped[str] = mapped_column(String(500), nullable=True)

    exam: Mapped["CBTExam"] = relationship("CBTExam", back_populates="questions")


class CBTSession(Base):
    __tablename__ = "cbt_sessions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))
    exam_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("cbt_exams.id"))
    started_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    submitted_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    score: Mapped[float] = mapped_column(Float, nullable=True)
    percentage: Mapped[float] = mapped_column(Float, nullable=True)
    total_correct: Mapped[int] = mapped_column(Integer, nullable=True)
    total_wrong: Mapped[int] = mapped_column(Integer, nullable=True)
    answers: Mapped[dict] = mapped_column(JSON, default={})       # {question_id: chosen_option}
    weak_topics: Mapped[list] = mapped_column(JSON, default=[])   # computed after submission
    is_auto_submitted: Mapped[bool] = mapped_column(Boolean, default=False)

    exam: Mapped["CBTExam"] = relationship("CBTExam", back_populates="sessions")


class ExamProctorLog(Base):
    """
    Records camera snapshots and violation events during a school exam.
    Admin can view all active students' camera feeds and violation logs.
    """
    __tablename__ = "exam_proctor_logs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    session_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("cbt_sessions.id"))
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))
    event_type: Mapped[str] = mapped_column(String(50), nullable=False)
    # event_type values:
    #   "camera_snapshot"   — periodic face capture
    #   "minimize_attempt"  — student tried to minimize/switch app
    #   "screenshot_attempt"— screenshot key detected (frontend signals this)
    #   "tab_switch"        — browser tab changed
    #   "camera_lost"       — camera feed dropped
    snapshot_url: Mapped[str] = mapped_column(String(500), nullable=True)  # S3 URL of face snapshot
    extra_data: Mapped[dict] = mapped_column(JSON, default={})
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
