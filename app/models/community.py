import uuid
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, ForeignKey, Text, Enum, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.core.database import Base
import enum


class PostVisibility(str, enum.Enum):
    everyone = "everyone"
    class_only = "class_only"
    teachers_only = "teachers_only"


class ChannelType(str, enum.Enum):
    general = "general"               # Art + Science + Commercial merged into one
    teacher_announcement = "teacher_announcement"  # teachers/admins only


class AssignmentStatus(str, enum.Enum):
    pending = "pending"
    reviewed = "reviewed"
    graded = "graded"


class AssignmentFileType(str, enum.Enum):
    pdf = "pdf"
    image = "image"


class CommunityChannel(Base):
    __tablename__ = "community_channels"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    channel_type: Mapped[ChannelType] = mapped_column(Enum(ChannelType), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=True)
    is_readonly_for_students: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    messages: Mapped[list["CommunityMessage"]] = relationship("CommunityMessage", back_populates="channel")
    assignments: Mapped[list["AssignmentSubmission"]] = relationship("AssignmentSubmission", back_populates="channel")


class CommunityMessage(Base):
    __tablename__ = "community_messages"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    channel_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("community_channels.id"))
    sender_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))
    content: Mapped[str] = mapped_column(Text, nullable=False)
    media_url: Mapped[str] = mapped_column(String(500), nullable=True)
    media_type: Mapped[str] = mapped_column(String(50), nullable=True)  # image | pdf
    is_flagged: Mapped[bool] = mapped_column(Boolean, default=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    flagged_reason: Mapped[str] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    channel: Mapped["CommunityChannel"] = relationship("CommunityChannel", back_populates="messages")


class MessageReport(Base):
    __tablename__ = "message_reports"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    message_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("community_messages.id"))
    reported_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))
    reason: Mapped[str] = mapped_column(String(255), nullable=False)
    resolved: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


# ── Assignment Board ──────────────────────────────────────────────────────────

class AssignmentSubmission(Base):
    """
    Student submits assignment by tagging a teacher.
    File must be PDF or image. Result is private — only visible to that student.
    """
    __tablename__ = "assignment_submissions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    channel_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("community_channels.id"))
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))
    tagged_teacher_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))

    # File submitted by student
    file_url: Mapped[str] = mapped_column(String(500), nullable=False)
    file_type: Mapped[AssignmentFileType] = mapped_column(Enum(AssignmentFileType), nullable=False)
    caption: Mapped[str] = mapped_column(Text, nullable=True)

    status: Mapped[AssignmentStatus] = mapped_column(
        Enum(AssignmentStatus), default=AssignmentStatus.pending
    )

    # Result posted by teacher — PRIVATE to student only
    result_text: Mapped[str] = mapped_column(Text, nullable=True)
    result_score: Mapped[str] = mapped_column(String(50), nullable=True)  # e.g. "85/100" or "A"
    result_feedback: Mapped[str] = mapped_column(Text, nullable=True)
    result_posted_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)

    submitted_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    channel: Mapped["CommunityChannel"] = relationship("CommunityChannel", back_populates="assignments")


# ── Community Posts (Feed) ────────────────────────────────────────────────────

class CommunityPost(Base):
    """
    Rich posts in a channel — can have text, media, and likes.
    Unlike messages (chat), posts are more structured feed items.
    """
    __tablename__ = "community_posts"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    channel_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("community_channels.id"))
    author_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))
    content: Mapped[str] = mapped_column(Text, nullable=False)
    media_url: Mapped[str] = mapped_column(String(500), nullable=True)
    media_type: Mapped[str] = mapped_column(String(50), nullable=True)  # image | pdf | video | doc
    is_anonymous: Mapped[bool] = mapped_column(Boolean, default=False)
    visibility: Mapped[PostVisibility] = mapped_column(
        Enum(PostVisibility), default=PostVisibility.everyone, nullable=False
    )
    cbt_exam_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=True)
    group_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("student_groups.id"), nullable=True)
    is_pinned: Mapped[bool] = mapped_column(Boolean, default=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    like_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    likes: Mapped[list["PostLike"]] = relationship("PostLike", back_populates="post")


class PostLike(Base):
    """One like per user per post."""
    __tablename__ = "post_likes"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    post_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("community_posts.id"))
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    post: Mapped["CommunityPost"] = relationship("CommunityPost", back_populates="likes")


class PostReaction(Base):
    """One emoji reaction per user per post (general channel)."""
    __tablename__ = "post_reactions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    post_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("community_posts.id"), index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), index=True)
    emoji: Mapped[str] = mapped_column(String(16), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
