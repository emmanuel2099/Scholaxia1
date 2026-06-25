import uuid
import json
from datetime import datetime
from sqlalchemy import String, DateTime, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID
from app.core.database import Base


class SchoolGroup(Base):
    """A teacher's class/group inside a school community (e.g. SS1 Science)."""
    __tablename__ = "school_groups"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    teacher_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    school_name: Mapped[str] = mapped_column(String(200), nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    student_ids: Mapped[str] = mapped_column(Text, nullable=False, default="[]")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    @staticmethod
    def parse_student_ids(raw: str | None) -> list[str]:
        if not raw:
            return []
        try:
            data = json.loads(raw)
            return [str(x) for x in data] if isinstance(data, list) else []
        except (json.JSONDecodeError, TypeError):
            return []

    def member_ids(self) -> list[str]:
        return self.parse_student_ids(self.student_ids)
