"""Scholaxia Intellect League (SIL) models."""
import uuid
import enum
from datetime import datetime

from sqlalchemy import (
    String, Boolean, DateTime, ForeignKey, Integer, Float, Text, Enum, JSON,
)
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID

from app.core.database import Base


class SilMatchMode(str, enum.Enum):
    practice = "practice"
    ai_challenge = "ai_challenge"
    student_challenge = "student_challenge"
    class_challenge = "class_challenge"
    school_challenge = "school_challenge"
    friday_national = "friday_national"


class SilMatchStatus(str, enum.Enum):
    pending = "pending"
    live = "live"
    paused = "paused"
    completed = "completed"
    forfeited = "forfeited"
    cancelled = "cancelled"


class SilCoinTxType(str, enum.Enum):
    signup_bonus = "signup_bonus"
    purchase = "purchase"
    entry_fee = "entry_fee"
    reward = "reward"
    bet_win = "bet_win"
    bet_loss = "bet_loss"
    platform_fee = "platform_fee"
    refund = "refund"
    admin_adjust = "admin_adjust"


class SilLeagueProfile(Base):
    __tablename__ = "sil_league_profiles"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), unique=True, index=True)
    gamer_tag: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    country: Mapped[str] = mapped_column(String(80), default="Nigeria")
    state: Mapped[str] = mapped_column(String(80), nullable=False)
    school_name: Mapped[str] = mapped_column(String(255), nullable=False)
    academic_class: Mapped[str] = mapped_column(String(40), nullable=False)  # JSS1, SS2, etc.
    face_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    face_template: Mapped[str | None] = mapped_column(Text, nullable=True)  # opaque embedding/hash
    rules_accepted: Mapped[bool] = mapped_column(Boolean, default=False)
    coins: Mapped[int] = mapped_column(Integer, default=100)
    xp: Mapped[int] = mapped_column(Integer, default=0)
    level: Mapped[int] = mapped_column(Integer, default=1)
    wins: Mapped[int] = mapped_column(Integer, default=0)
    losses: Mapped[int] = mapped_column(Integer, default=0)
    current_streak: Mapped[int] = mapped_column(Integer, default=0)
    best_streak: Mapped[int] = mapped_column(Integer, default=0)
    national_rank: Mapped[int] = mapped_column(Integer, default=0)
    state_rank: Mapped[int] = mapped_column(Integer, default=0)
    school_rank: Mapped[int] = mapped_column(Integer, default=0)
    ai_level: Mapped[int] = mapped_column(Integer, default=1)  # 1–6 unlocked progress
    daily_ai_rewards: Mapped[int] = mapped_column(Integer, default=0)
    daily_ai_date: Mapped[str | None] = mapped_column(String(10), nullable=True)  # YYYY-MM-DD
    badges: Mapped[list | None] = mapped_column(JSON, default=list)
    is_school_captain: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class SilCoinTransaction(Base):
    __tablename__ = "sil_coin_transactions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), index=True)
    tx_type: Mapped[SilCoinTxType] = mapped_column(Enum(SilCoinTxType), nullable=False)
    amount: Mapped[int] = mapped_column(Integer, nullable=False)  # signed
    balance_after: Mapped[int] = mapped_column(Integer, nullable=False)
    description: Mapped[str] = mapped_column(String(500), nullable=True)
    match_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class SilQuestion(Base):
    __tablename__ = "sil_questions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    subject: Mapped[str] = mapped_column(String(80), index=True)
    academic_class: Mapped[str] = mapped_column(String(40), index=True)
    difficulty: Mapped[int] = mapped_column(Integer, default=1)  # 1–6
    question_text: Mapped[str] = mapped_column(Text, nullable=False)
    options: Mapped[list] = mapped_column(JSON, nullable=False)  # 4 strings
    correct_index: Mapped[int] = mapped_column(Integer, nullable=False)
    hint: Mapped[str | None] = mapped_column(String(500), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class SilMatch(Base):
    __tablename__ = "sil_matches"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    mode: Mapped[SilMatchMode] = mapped_column(Enum(SilMatchMode), nullable=False)
    status: Mapped[SilMatchStatus] = mapped_column(Enum(SilMatchStatus), default=SilMatchStatus.pending)
    academic_class: Mapped[str] = mapped_column(String(40), nullable=False)
    subject: Mapped[str] = mapped_column(String(80), default="General Knowledge")
    difficulty: Mapped[int] = mapped_column(Integer, default=1)
    question_count: Mapped[int] = mapped_column(Integer, default=5)
    seconds_per_question: Mapped[int] = mapped_column(Integer, default=20)
    entry_coins: Mapped[int] = mapped_column(Integer, default=0)
    pot_coins: Mapped[int] = mapped_column(Integer, default=0)
    player1_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), index=True)
    player2_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    winner_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    player1_score: Mapped[int] = mapped_column(Integer, default=0)
    player2_score: Mapped[int] = mapped_column(Integer, default=0)
    player1_correct: Mapped[int] = mapped_column(Integer, default=0)
    player2_correct: Mapped[int] = mapped_column(Integer, default=0)
    player1_streak: Mapped[int] = mapped_column(Integer, default=0)
    questions_payload: Mapped[list | None] = mapped_column(JSON, nullable=True)  # server questions w/ answers
    player1_answers: Mapped[list | None] = mapped_column(JSON, default=list)
    player2_answers: Mapped[list | None] = mapped_column(JSON, default=list)
    face_ok_p1: Mapped[bool] = mapped_column(Boolean, default=False)
    face_ok_p2: Mapped[bool] = mapped_column(Boolean, default=False)
    started_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class SilChallengeInvite(Base):
    __tablename__ = "sil_challenge_invites"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    mode: Mapped[SilMatchMode] = mapped_column(Enum(SilMatchMode), nullable=False)
    from_user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), index=True)
    to_user_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    to_school_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    academic_class: Mapped[str] = mapped_column(String(40), nullable=False)
    bet_coins: Mapped[int] = mapped_column(Integer, default=100)
    status: Mapped[str] = mapped_column(String(20), default="pending")  # pending|accepted|rejected|expired
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    match_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class SilSchoolProfile(Base):
    __tablename__ = "sil_school_profiles"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    state: Mapped[str] = mapped_column(String(80), nullable=False)
    logo_url: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    national_rank: Mapped[int] = mapped_column(Integer, default=0)
    trophies: Mapped[int] = mapped_column(Integer, default=0)
    captain_user_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class SilAntiCheatEvent(Base):
    __tablename__ = "sil_anticheat_events"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    match_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    event_type: Mapped[str] = mapped_column(String(60), nullable=False)
    detail: Mapped[str | None] = mapped_column(String(500), nullable=True)
    severity: Mapped[int] = mapped_column(Integer, default=1)  # 1 low … 5 critical
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class SilFlaggedMatch(Base):
    """Human-review queue for suspicious / anti-cheat matches (PRD §18)."""
    __tablename__ = "sil_flagged_matches"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    match_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), unique=True, index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    reasons: Mapped[list | None] = mapped_column(JSON, default=list)
    risk_score: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(20), default="pending")  # pending|cleared|confirmed_cheat
    reviewer_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    reviewed_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class SilDeviceReport(Base):
    __tablename__ = "sil_device_reports"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    match_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True, index=True)
    is_emulator: Mapped[bool] = mapped_column(Boolean, default=False)
    is_rooted: Mapped[bool] = mapped_column(Boolean, default=False)
    is_jailbroken: Mapped[bool] = mapped_column(Boolean, default=False)
    platform: Mapped[str | None] = mapped_column(String(40), nullable=True)
    model: Mapped[str | None] = mapped_column(String(120), nullable=True)
    raw: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
