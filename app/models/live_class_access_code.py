import uuid
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, ForeignKey, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID
from app.core.database import Base


class LiveClassAccessCodeDelivery(Base):
    """Access code sent to a student for a specific live class (one code per class)."""
    __tablename__ = "live_class_access_codes"
    __table_args__ = (
        UniqueConstraint("student_id", "live_class_id", name="uq_access_code_student_class"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), index=True)
    live_class_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("live_classes.id"), index=True)
    join_code: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    subject: Mapped[str] = mapped_column(String(120), nullable=True)
    teacher_name: Mapped[str] = mapped_column(String(200), nullable=True)
    visibility: Mapped[str] = mapped_column(String(32), nullable=False, default="public")
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    is_used: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
