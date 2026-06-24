import uuid
from datetime import datetime
import enum
from sqlalchemy import String, Boolean, DateTime, ForeignKey, Text, Enum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.core.database import Base


class LiveSessionRequestStatus(str, enum.Enum):
    pending = "pending"
    approved = "approved"
    scheduled = "scheduled"
    dismissed = "dismissed"


class LiveClass(Base):
    __tablename__ = "live_classes"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    teacher_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    subject: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=True)
    start_time: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    end_time: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    is_live: Mapped[bool] = mapped_column(Boolean, default=False)
    is_recording_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    recording_url: Mapped[str] = mapped_column(String(500), nullable=True)
    room_id: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)  # WebRTC room
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    attendances: Mapped[list["ClassAttendance"]] = relationship("ClassAttendance", back_populates="live_class")


class ClassAttendance(Base):
    __tablename__ = "class_attendances"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    live_class_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("live_classes.id"))
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))
    joined_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    left_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    is_muted: Mapped[bool] = mapped_column(Boolean, default=True)  # muted by default
    is_removed: Mapped[bool] = mapped_column(Boolean, default=False)

    live_class: Mapped["LiveClass"] = relationship("LiveClass", back_populates="attendances")


class LiveSessionRequest(Base):
    """Student requests a live class on a subject — teachers/admins can review."""
    __tablename__ = "live_session_requests"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    subject: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    topic: Mapped[str] = mapped_column(String(255), nullable=True)
    message: Mapped[str] = mapped_column(Text, nullable=True)
    preferred_time: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    status: Mapped[LiveSessionRequestStatus] = mapped_column(
        Enum(LiveSessionRequestStatus), default=LiveSessionRequestStatus.pending
    )
    reviewed_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    reviewed_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    assigned_teacher_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    linked_class_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("live_classes.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
