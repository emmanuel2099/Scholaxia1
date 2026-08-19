import uuid
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID, JSON, ARRAY
from app.core.database import Base


class SchoolExamCandidate(Base):
    """School-registered student for internal exams (slip: rec number + access code)."""
    __tablename__ = "school_exam_candidates"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    class_name: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    email: Mapped[str] = mapped_column(String(255), nullable=True, index=True)
    phone: Mapped[str] = mapped_column(String(40), nullable=True)
    rec_number: Mapped[str] = mapped_column(String(40), unique=True, index=True, nullable=False)
    candidate_id: Mapped[str] = mapped_column(String(40), unique=True, index=True, nullable=True)
    access_code: Mapped[str] = mapped_column(String(40), unique=True, index=True, nullable=False)
    subjects: Mapped[list] = mapped_column(ARRAY(String), default=[])
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    is_restricted: Mapped[bool] = mapped_column(Boolean, default=False)
    retake_exam_ids: Mapped[list | None] = mapped_column(JSON, nullable=True)
    note: Mapped[str] = mapped_column(Text, nullable=True)
    created_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("school_campuses.id"), nullable=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
