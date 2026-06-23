import uuid
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, Enum, ForeignKey, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, ARRAY
from app.core.database import Base
import enum


class UserRole(str, enum.Enum):
    student = "student"
    teacher = "teacher"
    kind = "kind"           # young learners (kids / primary)
    admin = "admin"
    developer = "developer"   # external API developers


class ExamType(str, enum.Enum):
    JAMB = "JAMB"
    WAEC = "WAEC"
    NECO = "NECO"
    POST_UTME = "POST_UTME"
    ALL = "ALL"


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=True)  # null for OAuth
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[UserRole] = mapped_column(Enum(UserRole), default=UserRole.student)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    oauth_provider: Mapped[str] = mapped_column(String(50), nullable=True)  # google, apple
    oauth_id: Mapped[str] = mapped_column(String(255), nullable=True)
    profile_picture: Mapped[str] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    student_profile: Mapped["StudentProfile"] = relationship("StudentProfile", back_populates="user", uselist=False)
    teacher_profile: Mapped["TeacherProfile"] = relationship("TeacherProfile", back_populates="user", uselist=False)
    kind_profile: Mapped["KindProfile"] = relationship("KindProfile", back_populates="user", uselist=False)


class StudentProfile(Base):
    __tablename__ = "student_profiles"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), unique=True)
    exam_type: Mapped[ExamType] = mapped_column(Enum(ExamType), nullable=True)
    selected_subjects: Mapped[list] = mapped_column(ARRAY(String), default=[])
    education_level: Mapped[str] = mapped_column(String(50), nullable=True)  # JSS1, SS1, JAMB etc.
    has_active_subscription: Mapped[bool] = mapped_column(Boolean, default=False)
    live_plan_id: Mapped[str] = mapped_column(String(80), nullable=True)
    live_plan_expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    live_plan_sessions_used: Mapped[int] = mapped_column(Integer, default=0)
    community_channel_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("community_channels.id"), nullable=True)

    user: Mapped["User"] = relationship("User", back_populates="student_profile")


class TeacherProfile(Base):
    __tablename__ = "teacher_profiles"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), unique=True)
    subjects: Mapped[list] = mapped_column(ARRAY(String), default=[])
    bio: Mapped[str] = mapped_column(String(1000), nullable=True)
    is_approved: Mapped[bool] = mapped_column(Boolean, default=True)  # admin-created, always approved

    user: Mapped["User"] = relationship("User", back_populates="teacher_profile")


class KindProfile(Base):
    """Young learner profile (Kind / kids mode)."""
    __tablename__ = "kind_profiles"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), unique=True)
    age_group: Mapped[str] = mapped_column(String(20), nullable=False, default="6-8")  # 3-5 | 6-8 | 9-12
    grade_level: Mapped[str] = mapped_column(String(50), nullable=True)  # Nursery, Primary 1, JSS1
    parent_email: Mapped[str] = mapped_column(String(255), nullable=True)
    favorite_subjects: Mapped[list] = mapped_column(ARRAY(String), default=[])
    learning_goals: Mapped[str] = mapped_column(String(500), nullable=True)
    preferred_language: Mapped[str] = mapped_column(String(30), default="english")

    user: Mapped["User"] = relationship("User", back_populates="kind_profile")
