import uuid
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, Integer, Text, ForeignKey, JSON
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID
from app.core.database import Base


# Keep in sync with Flutter kidGames catalog ids.
KID_GAME_CATALOG = [
    {"id": "spelling-bee", "title": "Spelling Bee"},
    {"id": "math-challenge", "title": "Math Challenge"},
    {"id": "counting-fun", "title": "Counting Fun"},
    {"id": "word-builder", "title": "Word Builder"},
    {"id": "abc-phonics", "title": "ABC Phonics"},
    {"id": "shapes-colors", "title": "Shapes & Colors"},
    {"id": "opposites", "title": "Opposites"},
    {"id": "rhyming-words", "title": "Rhyming Words"},
    {"id": "fun-quiz", "title": "Fun Quiz"},
    {"id": "science-facts", "title": "Science Facts"},
    {"id": "geography", "title": "Geography"},
    {"id": "animals", "title": "Animals & Sounds"},
    {"id": "time-calendar", "title": "Time & Calendar"},
    {"id": "good-manners", "title": "Good Manners"},
    {"id": "my-body", "title": "My Body"},
    {"id": "alphabet-adventure", "title": "Alphabet Adventure"},
    {"id": "number-kingdom", "title": "Number Kingdom"},
    {"id": "word-builder-adventure", "title": "Word Builder Lab"},
    {"id": "reading-adventure", "title": "Reading Adventure"},
    {"id": "science-explorer", "title": "Science Explorer"},
    {"id": "geography-explorer", "title": "Geography Explorer"},
    {"id": "coding-for-kids", "title": "Coding for Kids"},
    {"id": "art-studio", "title": "Art Studio"},
    {"id": "music-academy", "title": "Music Academy"},
    {"id": "memory-challenge", "title": "Memory Challenge"},
    {"id": "puzzle-world", "title": "Puzzle World"},
    {"id": "quiz-battle", "title": "Quiz Battle"},
    {"id": "treasure-hunt", "title": "Treasure Hunt"},
    {"id": "virtual-pet", "title": "Virtual Pet"},
    {"id": "school-city-builder", "title": "School City Builder"},
]


class KidGameQuestion(Base):
    """Admin-authored MCQ for a kids educational game."""

    __tablename__ = "kid_game_questions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    game_id: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    prompt: Mapped[str] = mapped_column(Text, nullable=False)
    # List of option strings, length 2–6
    options: Mapped[list] = mapped_column(JSON, nullable=False)
    correct_index: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    speak_word: Mapped[str] = mapped_column(String(255), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
