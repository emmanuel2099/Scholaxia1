import uuid
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, ForeignKey, Text, Float
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID
from app.core.database import Base


class TeacherMaterial(Base):
    """Notes, PDFs, and books shared by teachers with students."""
    __tablename__ = "teacher_materials"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    teacher_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), index=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    subject: Mapped[str] = mapped_column(String(100), nullable=False)
    material_type: Mapped[str] = mapped_column(String(30), default="pdf")  # pdf | doc | image | link | video | note
    file_url: Mapped[str] = mapped_column(String(500), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=True)
    is_free: Mapped[bool] = mapped_column(Boolean, default=True)
    price: Mapped[float] = mapped_column(Float, default=0.0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class MaterialPurchase(Base):
    """Student paid access to a teacher material."""
    __tablename__ = "material_purchases"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    student_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), index=True)
    material_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("teacher_materials.id"), index=True)
    payment_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("payments.id"), nullable=True)
    purchased_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
