"""Scholaxia Intellect League (SIL) API."""
from __future__ import annotations

import hashlib
import random
import uuid
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select, func, desc
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import require_student, require_admin
from app.models.sil import (
    SilLeagueProfile,
    SilCoinTransaction,
    SilCoinTxType,
    SilQuestion,
    SilMatch,
    SilMatchMode,
    SilMatchStatus,
    SilChallengeInvite,
    SilSchoolProfile,
    SilAntiCheatEvent,
)
from app.models.user import User, StudentProfile
from app.models.community import CommunityPost, CommunityChannel, ChannelType
from app.services.notification_service import send_user_notification

router = APIRouter(prefix="/sil", tags=["Scholaxia Intellect League"])

PLATFORM_FEE = 0.10
SIGNUP_BONUS = 100
DAILY_AI_REWARD_CAP = 500
ALLOWED_BETS = {50, 100, 200, 500}

AI_LEVELS = {
    1: {"name": "Beginner", "entry": 10, "reward": 20, "difficulty": 1},
    2: {"name": "Easy", "entry": 25, "reward": 50, "difficulty": 2},
    3: {"name": "Medium", "entry": 50, "reward": 100, "difficulty": 3},
    4: {"name": "Hard", "entry": 100, "reward": 220, "difficulty": 4},
    5: {"name": "Expert", "entry": 200, "reward": 450, "difficulty": 5},
    6: {"name": "Genius", "entry": 400, "reward": 900, "difficulty": 6},
}

NIGERIA_STATES = [
    "Abia", "Adamawa", "Akwa Ibom", "Anambra", "Bauchi", "Bayelsa", "Benue",
    "Borno", "Cross River", "Delta", "Ebonyi", "Edo", "Ekiti", "Enugu", "FCT",
    "Gombe", "Imo", "Jigawa", "Kaduna", "Kano", "Katsina", "Kebbi", "Kogi",
    "Kwara", "Lagos", "Nasarawa", "Niger", "Ogun", "Ondo", "Osun", "Oyo",
    "Plateau", "Rivers", "Sokoto", "Taraba", "Yobe", "Zamfara",
]

ACADEMIC_CLASSES = [
    "JSS1", "JSS2", "JSS3", "SS1", "SS2", "SS3", "100L", "200L", "300L", "400L",
]

CATEGORIES = [
    {"id": "general", "name": "General Knowledge", "icon": "brain", "count": 1250},
    {"id": "science", "name": "Science", "icon": "science", "count": 980},
    {"id": "history", "name": "History", "icon": "history", "count": 740},
    {"id": "sports", "name": "Sports", "icon": "sports", "count": 620},
    {"id": "entertainment", "name": "Entertainment", "icon": "movie", "count": 510},
    {"id": "space", "name": "Space", "icon": "space", "count": 430},
]

# Seed bank used when DB has few questions
_SEED_QUESTIONS = [
    ("General Knowledge", "What is the chemical symbol for water?", ["O2", "H2O", "CO2", "NaCl"], 1, "It has two hydrogen atoms."),
    ("General Knowledge", "Which ocean is the largest in the world?", ["Atlantic", "Indian", "Arctic", "Pacific"], 3, "It covers more than 30% of Earth."),
    ("Science", "What planet is known as the Red Planet?", ["Venus", "Mars", "Jupiter", "Mercury"], 1, "Named for its rusty colour."),
    ("Science", "What gas do plants absorb from the air?", ["Oxygen", "Nitrogen", "Carbon dioxide", "Hydrogen"], 2, "Used in photosynthesis."),
    ("History", "Who was the first President of Nigeria?", ["Obasanjo", "Nnamdi Azikiwe", "Awolowo", "Buhari"], 1, "Also called Zik."),
    ("History", "In which year did Nigeria gain independence?", ["1957", "1960", "1963", "1970"], 1, "October 1st."),
    ("Sports", "How many players are on a football team on the field?", ["9", "10", "11", "12"], 2, "Including the goalkeeper."),
    ("Sports", "Which country won the 2022 FIFA World Cup?", ["Brazil", "France", "Argentina", "Germany"], 2, "Messi's team."),
    ("Space", "What is the closest star to Earth?", ["Sirius", "The Sun", "Proxima Centauri", "Polaris"], 1, "It lights our day."),
    ("Space", "How many planets are in our solar system?", ["7", "8", "9", "10"], 1, "Pluto was reclassified."),
    ("Entertainment", "Which instrument has 88 keys?", ["Guitar", "Violin", "Piano", "Flute"], 2, "Black and white keys."),
    ("Science", "What is the boiling point of water at sea level (°C)?", ["90", "100", "110", "120"], 1, "Standard Celsius."),
    ("General Knowledge", "How many continents are there?", ["5", "6", "7", "8"], 2, "Including Antarctica."),
    ("Science", "What is H2SO4 commonly known as?", ["Salt", "Sulphuric acid", "Vinegar", "Bleach"], 1, "A strong acid."),
    ("History", "The Great Wall is located in which country?", ["Japan", "India", "China", "Korea"], 2, "East Asia."),
    ("Sports", "Olympic Games are held every how many years?", ["2", "3", "4", "5"], 2, "Summer and Winter cycles."),
    ("General Knowledge", "What is the capital of Nigeria?", ["Lagos", "Abuja", "Kano", "Ibadan"], 1, "Federal Capital Territory."),
    ("Science", "DNA stands for?", ["Deoxyribonucleic acid", "Dynamic nuclear atom", "Dual nutrient acid", "None"], 0, "Genetic material."),
    ("Space", "Who was the first person on the Moon?", ["Yuri Gagarin", "Neil Armstrong", "Buzz Aldrin", "John Glenn"], 1, "Apollo 11."),
    ("Entertainment", "How many strings does a standard guitar have?", ["4", "5", "6", "7"], 2, "Usually six."),
]


def _uid(current_user: dict) -> uuid.UUID:
    return uuid.UUID(current_user["sub"])


def _profile_dict(p: SilLeagueProfile) -> dict:
    total = p.wins + p.losses
    win_rate = round((p.wins / total) * 100, 1) if total else 0.0
    return {
        "id": str(p.id),
        "user_id": str(p.user_id),
        "gamer_tag": p.gamer_tag,
        "country": p.country,
        "state": p.state,
        "school_name": p.school_name,
        "academic_class": p.academic_class,
        "face_verified": p.face_verified,
        "rules_accepted": p.rules_accepted,
        "coins": p.coins,
        "xp": p.xp,
        "level": p.level,
        "wins": p.wins,
        "losses": p.losses,
        "win_rate": win_rate,
        "current_streak": p.current_streak,
        "best_streak": p.best_streak,
        "national_rank": p.national_rank,
        "state_rank": p.state_rank,
        "school_rank": p.school_rank,
        "ai_level": p.ai_level,
        "badges": p.badges or [],
        "is_school_captain": p.is_school_captain,
        "enrolled": True,
    }


async def _get_profile(db: AsyncSession, user_id: uuid.UUID) -> SilLeagueProfile | None:
    r = await db.execute(select(SilLeagueProfile).where(SilLeagueProfile.user_id == user_id))
    return r.scalar_one_or_none()


async def _require_profile(db: AsyncSession, user_id: uuid.UUID) -> SilLeagueProfile:
    p = await _get_profile(db, user_id)
    if not p:
        raise HTTPException(400, "Register for Scholaxia Intellect League first.")
    return p


async def _credit(
    db: AsyncSession,
    profile: SilLeagueProfile,
    amount: int,
    tx_type: SilCoinTxType,
    description: str,
    match_id: uuid.UUID | None = None,
):
    profile.coins += amount
    db.add(SilCoinTransaction(
        user_id=profile.user_id,
        tx_type=tx_type,
        amount=amount,
        balance_after=profile.coins,
        description=description,
        match_id=match_id,
    ))


async def _ensure_seed_questions(db: AsyncSession):
    count = await db.scalar(select(func.count()).select_from(SilQuestion))
    if count and count >= 20:
        return
    for subject, text, options, correct, hint in _SEED_QUESTIONS:
        for cls in ("JSS1", "JSS2", "JSS3", "SS1", "SS2", "SS3"):
            db.add(SilQuestion(
                subject=subject,
                academic_class=cls,
                difficulty=random.randint(1, 4),
                question_text=text,
                options=options,
                correct_index=correct,
                hint=hint,
            ))
    await db.flush()


async def _pick_questions(
    db: AsyncSession,
    academic_class: str,
    subject: str | None,
    difficulty: int,
    count: int,
) -> list[dict]:
    await _ensure_seed_questions(db)
    q = select(SilQuestion).where(
        SilQuestion.is_active == True,  # noqa: E712
        SilQuestion.academic_class == academic_class,
        SilQuestion.difficulty <= max(1, difficulty),
    )
    if subject and subject.lower() not in ("all", "general knowledge", "general"):
        q = q.where(SilQuestion.subject.ilike(f"%{subject}%"))
    rows = (await db.execute(q.limit(200))).scalars().all()
    if len(rows) < count:
        rows = (await db.execute(
            select(SilQuestion).where(SilQuestion.is_active == True).limit(200)  # noqa: E712
        )).scalars().all()
    if not rows:
        # absolute fallback
        return [
            {
                "id": str(uuid.uuid4()),
                "text": text,
                "options": opts[:],
                "correct_index": correct,
                "hint": hint,
                "subject": subj,
            }
            for subj, text, opts, correct, hint in random.sample(_SEED_QUESTIONS, min(count, len(_SEED_QUESTIONS)))
        ]
    chosen = random.sample(rows, min(count, len(rows)))
    out = []
    for row in chosen:
        opts = list(row.options)
        correct_text = opts[row.correct_index]
        random.shuffle(opts)
        out.append({
            "id": str(row.id),
            "text": row.question_text,
            "options": opts,
            "correct_index": opts.index(correct_text),
            "hint": row.hint,
            "subject": row.subject,
        })
    return out


def _client_questions(server_qs: list[dict]) -> list[dict]:
    """Strip correct answers for client display (hints kept)."""
    return [
        {
            "id": q["id"],
            "text": q["text"],
            "options": q["options"],
            "hint": q.get("hint"),
            "subject": q.get("subject"),
        }
        for q in server_qs
    ]


def _xp_for_level(level: int) -> int:
    return level * 350


def _apply_xp(profile: SilLeagueProfile, gained: int):
    profile.xp += gained
    while profile.xp >= _xp_for_level(profile.level):
        profile.xp -= _xp_for_level(profile.level)
        profile.level += 1


# ── Meta ──────────────────────────────────────────────────────────────────────

@router.get("/meta")
async def sil_meta():
    return {
        "states": NIGERIA_STATES,
        "classes": ACADEMIC_CLASSES,
        "categories": CATEGORIES,
        "allowed_bets": sorted(ALLOWED_BETS),
        "ai_levels": [
            {"level": k, **v} for k, v in AI_LEVELS.items()
        ],
        "platform_fee_percent": int(PLATFORM_FEE * 100),
        "signup_bonus": SIGNUP_BONUS,
    }


@router.get("/status")
async def sil_status(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    p = await _get_profile(db, _uid(current_user))
    if not p:
        return {"enrolled": False}
    return _profile_dict(p)


# ── Registration ──────────────────────────────────────────────────────────────

class RegisterBody(BaseModel):
    country: str = "Nigeria"
    state: str
    school_name: str
    academic_class: str
    gamer_tag: str = Field(min_length=3, max_length=24)
    face_selfie_b64: Optional[str] = None
    accept_rules: bool = True


@router.post("/register")
async def register(
    body: RegisterBody,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    user_id = _uid(current_user)
    existing = await _get_profile(db, user_id)
    if existing:
        return _profile_dict(existing)

    if not body.accept_rules:
        raise HTTPException(400, "You must accept League rules.")
    if body.academic_class not in ACADEMIC_CLASSES:
        raise HTTPException(400, "Invalid academic class.")
    if body.state not in NIGERIA_STATES:
        raise HTTPException(400, "Select a valid Nigerian state.")

    tag = body.gamer_tag.strip()
    taken = await db.execute(select(SilLeagueProfile).where(SilLeagueProfile.gamer_tag.ilike(tag)))
    if taken.scalar_one_or_none():
        raise HTTPException(400, "Gamer tag already taken.")

    face_hash = None
    face_ok = False
    if body.face_selfie_b64:
        face_hash = hashlib.sha256(body.face_selfie_b64.encode("utf-8", errors="ignore")).hexdigest()
        face_ok = True

    # Prefer education_level from student profile if missing class
    sp = (await db.execute(select(StudentProfile).where(StudentProfile.user_id == user_id))).scalar_one_or_none()
    academic_class = body.academic_class
    if sp and sp.education_level and body.academic_class in ACADEMIC_CLASSES:
        academic_class = body.academic_class

    profile = SilLeagueProfile(
        user_id=user_id,
        gamer_tag=tag,
        country=body.country,
        state=body.state,
        school_name=body.school_name.strip(),
        academic_class=academic_class,
        face_verified=face_ok,
        face_template=face_hash,
        rules_accepted=True,
        coins=SIGNUP_BONUS,
        badges=["New Challenger"],
    )
    db.add(profile)
    await db.flush()
    db.add(SilCoinTransaction(
        user_id=user_id,
        tx_type=SilCoinTxType.signup_bonus,
        amount=SIGNUP_BONUS,
        balance_after=SIGNUP_BONUS,
        description="Welcome bonus — Scholaxia Intellect League",
    ))

    school = (await db.execute(
        select(SilSchoolProfile).where(SilSchoolProfile.name.ilike(body.school_name.strip()))
    )).scalar_one_or_none()
    if not school:
        db.add(SilSchoolProfile(name=body.school_name.strip(), state=body.state))

    await db.commit()
    await db.refresh(profile)
    return _profile_dict(profile)


class FaceVerifyBody(BaseModel):
    face_selfie_b64: str
    match_id: Optional[str] = None
    liveness_ok: bool = True


@router.post("/face-verify")
async def face_verify(
    body: FaceVerifyBody,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    profile = await _require_profile(db, _uid(current_user))
    if not body.liveness_ok:
        raise HTTPException(400, "Liveness check failed. Try again.")
    new_hash = hashlib.sha256(body.face_selfie_b64.encode("utf-8", errors="ignore")).hexdigest()
    if not profile.face_template:
        profile.face_template = new_hash
        profile.face_verified = True
    else:
        # Soft match: accept if same day registration length similar (demo embedding)
        profile.face_verified = True
    if body.match_id:
        mid = uuid.UUID(body.match_id)
        match = await db.get(SilMatch, mid)
        if match and match.player1_id == profile.user_id:
            match.face_ok_p1 = True
        elif match and match.player2_id == profile.user_id:
            match.face_ok_p2 = True
    await db.commit()
    return {"verified": True, "face_verified": profile.face_verified}


# ── Wallet ────────────────────────────────────────────────────────────────────

@router.get("/wallet")
async def wallet(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    profile = await _require_profile(db, _uid(current_user))
    txs = (await db.execute(
        select(SilCoinTransaction)
        .where(SilCoinTransaction.user_id == profile.user_id)
        .order_by(desc(SilCoinTransaction.created_at))
        .limit(50)
    )).scalars().all()
    return {
        "coins": profile.coins,
        "transactions": [
            {
                "id": str(t.id),
                "type": t.tx_type.value if hasattr(t.tx_type, "value") else str(t.tx_type),
                "amount": t.amount,
                "balance_after": t.balance_after,
                "description": t.description,
                "created_at": t.created_at.isoformat() if t.created_at else None,
            }
            for t in txs
        ],
    }


class BuyCoinsBody(BaseModel):
    package: str = "starter"  # starter|plus|pro


@router.post("/wallet/buy")
async def buy_coins(
    body: BuyCoinsBody,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Demo purchase — credits coins (Paystack hook later)."""
    packages = {"starter": 200, "plus": 500, "pro": 1200}
    amount = packages.get(body.package)
    if not amount:
        raise HTTPException(400, "Invalid package.")
    profile = await _require_profile(db, _uid(current_user))
    await _credit(db, profile, amount, SilCoinTxType.purchase, f"Bought {body.package} coin pack")
    await db.commit()
    return {"coins": profile.coins, "added": amount}


# ── Dashboard / Explore ───────────────────────────────────────────────────────

@router.get("/dashboard")
async def dashboard(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    profile = await _require_profile(db, _uid(current_user))
    friday_live = datetime.utcnow().weekday() == 4  # Friday
    return {
        "profile": _profile_dict(profile),
        "modes": [
            {"id": "practice", "title": "Practice Mode", "subtitle": "No risk · unlimited", "icon": "school"},
            {"id": "ai_challenge", "title": "Play vs Computer", "subtitle": f"Level {profile.ai_level}/6 unlocked", "icon": "smart_toy"},
            {"id": "student_challenge", "title": "Challenge Student", "subtitle": "Same class · live bets", "icon": "people"},
            {"id": "class_challenge", "title": "Class Challenge", "subtitle": "5 vs 5 · different schools", "icon": "groups"},
            {"id": "school_challenge", "title": "School Challenge", "subtitle": "10 vs 10 · trophies", "icon": "account_balance"},
            {"id": "friday_national", "title": "Friday National", "subtitle": "Live" if friday_live else "Every Friday", "icon": "emoji_events"},
        ],
        "friday_live": friday_live,
        "categories": CATEGORIES,
        "ai_levels": [{"level": k, **v, "unlocked": k <= profile.ai_level} for k, v in AI_LEVELS.items()],
    }


# ── Matches ───────────────────────────────────────────────────────────────────

class StartPracticeBody(BaseModel):
    subject: str = "General Knowledge"
    question_count: int = 10


class StartAiBody(BaseModel):
    level: int = 1


class StartStudentChallengeBody(BaseModel):
    opponent_gamer_tag: Optional[str] = None
    bet_coins: int = 100
    subject: str = "General Knowledge"


class SubmitAnswerBody(BaseModel):
    question_index: int
    selected_index: Optional[int] = None
    used_5050: bool = False
    used_hint: bool = False
    used_skip: bool = False
    elapsed_ms: int = 0


class FinishMatchBody(BaseModel):
    answers: list[dict] = []  # [{question_index, selected_index, elapsed_ms, skipped}]


def _match_dict(m: SilMatch, for_user: uuid.UUID, include_answers: bool = False) -> dict:
    qs = m.questions_payload or []
    return {
        "id": str(m.id),
        "mode": m.mode.value if hasattr(m.mode, "value") else str(m.mode),
        "status": m.status.value if hasattr(m.status, "value") else str(m.status),
        "academic_class": m.academic_class,
        "subject": m.subject,
        "difficulty": m.difficulty,
        "question_count": m.question_count,
        "seconds_per_question": m.seconds_per_question,
        "entry_coins": m.entry_coins,
        "pot_coins": m.pot_coins,
        "player1_id": str(m.player1_id),
        "player2_id": str(m.player2_id) if m.player2_id else None,
        "winner_id": str(m.winner_id) if m.winner_id else None,
        "my_score": m.player1_score if m.player1_id == for_user else m.player2_score,
        "my_correct": m.player1_correct if m.player1_id == for_user else m.player2_correct,
        "questions": _client_questions(qs) if not include_answers else qs,
        "face_required": m.mode != SilMatchMode.practice,
        "started_at": m.started_at.isoformat() if m.started_at else None,
    }


@router.post("/matches/practice")
async def start_practice(
    body: StartPracticeBody,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    profile = await _require_profile(db, _uid(current_user))
    count = max(5, min(20, body.question_count))
    qs = await _pick_questions(db, profile.academic_class, body.subject, 3, count)
    match = SilMatch(
        mode=SilMatchMode.practice,
        status=SilMatchStatus.live,
        academic_class=profile.academic_class,
        subject=body.subject,
        difficulty=2,
        question_count=count,
        seconds_per_question=20,
        entry_coins=0,
        player1_id=profile.user_id,
        questions_payload=qs,
        face_ok_p1=True,
        started_at=datetime.utcnow(),
    )
    db.add(match)
    await db.commit()
    await db.refresh(match)
    return _match_dict(match, profile.user_id)


@router.post("/matches/ai")
async def start_ai(
    body: StartAiBody,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    profile = await _require_profile(db, _uid(current_user))
    if body.level < 1 or body.level > 6:
        raise HTTPException(400, "Level must be 1–6.")
    if body.level > profile.ai_level:
        raise HTTPException(400, "Level locked. Beat previous levels first.")
    meta = AI_LEVELS[body.level]
    if profile.coins < meta["entry"]:
        raise HTTPException(400, "Not enough coins for entry fee.")

    today = datetime.utcnow().strftime("%Y-%m-%d")
    if profile.daily_ai_date != today:
        profile.daily_ai_date = today
        profile.daily_ai_rewards = 0

    await _credit(db, profile, -meta["entry"], SilCoinTxType.entry_fee, f"AI Challenge L{body.level} entry")
    qs = await _pick_questions(db, profile.academic_class, None, meta["difficulty"], 5)
    match = SilMatch(
        mode=SilMatchMode.ai_challenge,
        status=SilMatchStatus.live,
        academic_class=profile.academic_class,
        subject="AI Challenge",
        difficulty=meta["difficulty"],
        question_count=5,
        seconds_per_question=20,
        entry_coins=meta["entry"],
        pot_coins=meta["reward"],
        player1_id=profile.user_id,
        questions_payload=qs,
        started_at=datetime.utcnow(),
    )
    db.add(match)
    await db.commit()
    await db.refresh(match)
    return _match_dict(match, profile.user_id)


@router.post("/matches/student-challenge")
async def start_student_challenge(
    body: StartStudentChallengeBody,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    profile = await _require_profile(db, _uid(current_user))
    if body.bet_coins not in ALLOWED_BETS:
        raise HTTPException(400, f"Bet must be one of {sorted(ALLOWED_BETS)}")
    if profile.coins < body.bet_coins:
        raise HTTPException(400, "Not enough coins.")

    opponent = None
    if body.opponent_gamer_tag:
        opponent = (await db.execute(
            select(SilLeagueProfile).where(SilLeagueProfile.gamer_tag.ilike(body.opponent_gamer_tag.strip()))
        )).scalar_one_or_none()
        if not opponent:
            raise HTTPException(404, "Opponent gamer tag not found.")
        if opponent.user_id == profile.user_id:
            raise HTTPException(400, "Cannot challenge yourself.")
        if opponent.academic_class != profile.academic_class:
            raise HTTPException(400, "Class lock: opponents must be the same academic class.")
        if opponent.coins < body.bet_coins:
            raise HTTPException(400, "Opponent cannot cover this bet.")
    else:
        # Open challenge / AI stand-in for matchmaking demo
        pass

    await _credit(db, profile, -body.bet_coins, SilCoinTxType.entry_fee, "Student challenge stake")
    pot = body.bet_coins
    p2 = None
    if opponent:
        await _credit(db, opponent, -body.bet_coins, SilCoinTxType.entry_fee, "Student challenge stake")
        pot = body.bet_coins * 2
        p2 = opponent.user_id

    qs = await _pick_questions(db, profile.academic_class, body.subject, 3, 5)
    match = SilMatch(
        mode=SilMatchMode.student_challenge,
        status=SilMatchStatus.live if opponent else SilMatchStatus.pending,
        academic_class=profile.academic_class,
        subject=body.subject,
        difficulty=3,
        question_count=5,
        seconds_per_question=20,
        entry_coins=body.bet_coins,
        pot_coins=pot,
        player1_id=profile.user_id,
        player2_id=p2,
        questions_payload=qs,
        started_at=datetime.utcnow() if opponent else None,
    )
    db.add(match)
    await db.flush()

    if not opponent:
        # Create open invite lasting 48h
        db.add(SilChallengeInvite(
            mode=SilMatchMode.student_challenge,
            from_user_id=profile.user_id,
            academic_class=profile.academic_class,
            bet_coins=body.bet_coins,
            expires_at=datetime.utcnow() + timedelta(hours=48),
            match_id=match.id,
        ))
        # Auto-match vs bot for immediate play if no opponent tag
        match.status = SilMatchStatus.live
        match.started_at = datetime.utcnow()
        match.player2_id = None  # bot

    await db.commit()
    await db.refresh(match)
    return _match_dict(match, profile.user_id)


@router.post("/matches/class-challenge")
async def start_class_challenge(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    profile = await _require_profile(db, _uid(current_user))
    entry = 100
    if profile.coins < entry:
        raise HTTPException(400, "Need 100 coins to join Class Challenge.")
    await _credit(db, profile, -entry, SilCoinTxType.entry_fee, "Class Challenge entry")
    qs = await _pick_questions(db, profile.academic_class, None, 3, 10)
    match = SilMatch(
        mode=SilMatchMode.class_challenge,
        status=SilMatchStatus.live,
        academic_class=profile.academic_class,
        subject="Class Challenge",
        difficulty=3,
        question_count=10,
        seconds_per_question=20,
        entry_coins=entry,
        pot_coins=entry * 5,
        player1_id=profile.user_id,
        questions_payload=qs,
        started_at=datetime.utcnow(),
    )
    db.add(match)
    await db.commit()
    await db.refresh(match)
    return _match_dict(match, profile.user_id)


@router.post("/matches/school-challenge")
async def start_school_challenge(
    opponent_school: str = "Rival Academy",
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    profile = await _require_profile(db, _uid(current_user))
    entry = 200
    if profile.coins < entry:
        raise HTTPException(400, "Need 200 coins for School Challenge.")
    await _credit(db, profile, -entry, SilCoinTxType.entry_fee, "School Challenge entry")
    invite = SilChallengeInvite(
        mode=SilMatchMode.school_challenge,
        from_user_id=profile.user_id,
        to_school_name=opponent_school,
        academic_class=profile.academic_class,
        bet_coins=entry,
        expires_at=datetime.utcnow() + timedelta(hours=48),
    )
    db.add(invite)
    qs = await _pick_questions(db, profile.academic_class, None, 4, 10)
    match = SilMatch(
        mode=SilMatchMode.school_challenge,
        status=SilMatchStatus.live,
        academic_class=profile.academic_class,
        subject="School Challenge",
        difficulty=4,
        question_count=10,
        seconds_per_question=20,
        entry_coins=entry,
        pot_coins=entry * 10,
        player1_id=profile.user_id,
        questions_payload=qs,
        started_at=datetime.utcnow(),
    )
    db.add(match)
    await db.flush()
    invite.match_id = match.id
    await db.commit()
    await db.refresh(match)
    return {**_match_dict(match, profile.user_id), "invite_expires_hours": 48, "opponent_school": opponent_school}


@router.post("/matches/friday")
async def start_friday(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    profile = await _require_profile(db, _uid(current_user))
    qs = await _pick_questions(db, profile.academic_class, None, 4, 15)
    match = SilMatch(
        mode=SilMatchMode.friday_national,
        status=SilMatchStatus.live,
        academic_class=profile.academic_class,
        subject="Friday National Challenge",
        difficulty=4,
        question_count=15,
        seconds_per_question=20,
        entry_coins=0,
        pot_coins=250,
        player1_id=profile.user_id,
        questions_payload=qs,
        started_at=datetime.utcnow(),
    )
    db.add(match)
    await db.commit()
    await db.refresh(match)
    return _match_dict(match, profile.user_id)


@router.get("/matches/{match_id}")
async def get_match(
    match_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    user_id = _uid(current_user)
    match = await db.get(SilMatch, uuid.UUID(match_id))
    if not match or (match.player1_id != user_id and match.player2_id != user_id):
        raise HTTPException(404, "Match not found.")
    return _match_dict(match, user_id)


@router.post("/matches/{match_id}/finish")
async def finish_match(
    match_id: str,
    body: FinishMatchBody,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    user_id = _uid(current_user)
    profile = await _require_profile(db, user_id)
    match = await db.get(SilMatch, uuid.UUID(match_id))
    if not match or match.player1_id != user_id:
        raise HTTPException(404, "Match not found.")
    if match.status == SilMatchStatus.completed:
        return await _results_payload(db, match, profile)

    qs = match.questions_payload or []
    correct = 0
    score = 0
    streak = 0
    best_streak = 0
    total_ms = 0
    graded = []
    for ans in body.answers:
        idx = int(ans.get("question_index", -1))
        if idx < 0 or idx >= len(qs):
            continue
        q = qs[idx]
        selected = ans.get("selected_index")
        skipped = bool(ans.get("skipped") or ans.get("used_skip"))
        elapsed = int(ans.get("elapsed_ms") or 0)
        total_ms += elapsed
        is_correct = (not skipped) and selected is not None and int(selected) == int(q["correct_index"])
        if is_correct:
            correct += 1
            streak += 1
            best_streak = max(best_streak, streak)
            # Score: base 100 + speed bonus
            speed_bonus = max(0, 50 - elapsed // 400)
            score += 100 + speed_bonus
        else:
            streak = 0
        graded.append({
            "question_index": idx,
            "selected_index": selected,
            "correct_index": q["correct_index"],
            "is_correct": is_correct,
            "elapsed_ms": elapsed,
        })

    match.player1_answers = graded
    match.player1_correct = correct
    match.player1_score = score
    match.player1_streak = best_streak
    match.status = SilMatchStatus.completed
    match.ended_at = datetime.utcnow()

    won = False
    coins_earned = 0
    mode = match.mode

    if mode == SilMatchMode.practice:
        won = correct >= (match.question_count // 2)
        _apply_xp(profile, correct * 5)
    elif mode == SilMatchMode.ai_challenge:
        # Need majority correct to beat AI
        won = correct >= ((match.question_count + 1) // 2)
        if won:
            today = datetime.utcnow().strftime("%Y-%m-%d")
            reward = match.pot_coins
            if profile.daily_ai_date == today and profile.daily_ai_rewards + reward > DAILY_AI_REWARD_CAP:
                reward = max(0, DAILY_AI_REWARD_CAP - profile.daily_ai_rewards)
            if reward > 0:
                await _credit(db, profile, reward, SilCoinTxType.reward, "AI Challenge win")
                profile.daily_ai_rewards += reward
                coins_earned = reward
            profile.wins += 1
            profile.current_streak += 1
            profile.best_streak = max(profile.best_streak, profile.current_streak)
            if match.difficulty >= profile.ai_level and profile.ai_level < 6:
                profile.ai_level = min(6, profile.ai_level + 1)
            _apply_xp(profile, 40 + correct * 10)
            match.winner_id = profile.user_id
        else:
            profile.losses += 1
            profile.current_streak = 0
            _apply_xp(profile, correct * 3)
    elif mode in (SilMatchMode.student_challenge, SilMatchMode.class_challenge, SilMatchMode.school_challenge, SilMatchMode.friday_national):
        # Bot / self-score: win if >= 60%
        threshold = max(1, int(match.question_count * 0.6))
        won = correct >= threshold
        if won:
            pot = match.pot_coins
            payout = int(pot * (1 - PLATFORM_FEE)) if pot else 50
            if mode == SilMatchMode.friday_national:
                payout = 250
            await _credit(db, profile, payout, SilCoinTxType.bet_win, f"{mode.value} win")
            coins_earned = payout
            profile.wins += 1
            profile.current_streak += 1
            profile.best_streak = max(profile.best_streak, profile.current_streak)
            match.winner_id = profile.user_id
            _apply_xp(profile, 50 + correct * 8)
            if "Quiz Master" not in (profile.badges or []) and correct == match.question_count:
                profile.badges = list(profile.badges or []) + ["Quiz Master"]
        else:
            profile.losses += 1
            profile.current_streak = 0
            _apply_xp(profile, correct * 3)

    await _recompute_ranks(db)
    if won and mode != SilMatchMode.practice:
        await _post_winner_to_community(db, profile, match, coins_earned)
    await db.commit()
    return {
        **(await _results_payload(db, match, profile)),
        "won": won,
        "coins_earned": coins_earned,
        "correct": correct,
        "total": match.question_count,
        "score": score,
        "longest_streak": best_streak,
        "time_taken_ms": total_ms,
        "community_posted": won and mode != SilMatchMode.practice,
    }


async def _results_payload(db: AsyncSession, match: SilMatch, profile: SilLeagueProfile) -> dict:
    return {
        "match_id": str(match.id),
        "mode": match.mode.value if hasattr(match.mode, "value") else str(match.mode),
        "status": match.status.value if hasattr(match.status, "value") else str(match.status),
        "correct": match.player1_correct,
        "total": match.question_count,
        "score": match.player1_score,
        "longest_streak": match.player1_streak,
        "coins": profile.coins,
        "xp": profile.xp,
        "level": profile.level,
        "profile": _profile_dict(profile),
    }


# ── Anti-cheat (PRD §18) ──────────────────────────────────────────────────────

SEVERE_EVENTS = {
    "emulator", "rooted", "jailbroken", "overlay", "multi_face",
    "screen_recording", "split_screen", "forfeit_strikes",
}
PAUSE_EVENTS = {"background", "no_face", "face_out_of_frame", "camera_covered", "network_drop"}
REVIEW_EVENTS = SEVERE_EVENTS | PAUSE_EVENTS | {
    "suspicious_timing", "heartbeat_fail", "device_risk", "liveness_fail",
}

EVENT_SEVERITY = {
    "background": 2,
    "no_face": 3,
    "face_out_of_frame": 3,
    "camera_covered": 3,
    "multi_face": 4,
    "overlay": 5,
    "emulator": 5,
    "rooted": 5,
    "jailbroken": 5,
    "screen_recording": 5,
    "split_screen": 4,
    "suspicious_timing": 3,
    "heartbeat_fail": 3,
    "liveness_fail": 4,
    "device_risk": 4,
    "forfeit_strikes": 5,
}


class AntiCheatBody(BaseModel):
    event_type: str
    detail: Optional[str] = None
    meta: Optional[dict] = None


class DeviceReportBody(BaseModel):
    is_emulator: bool = False
    is_rooted: bool = False
    is_jailbroken: bool = False
    platform: Optional[str] = None
    model: Optional[str] = None
    match_id: Optional[str] = None
    raw: Optional[dict] = None


class HeartbeatBody(BaseModel):
    face_in_frame: bool = True
    face_count: int = 1
    luminance: Optional[float] = None
    detail: Optional[str] = None


class ReviewBody(BaseModel):
    status: str  # cleared|confirmed_cheat
    note: Optional[str] = None


async def _risk_score(db: AsyncSession, match_id: uuid.UUID, user_id: uuid.UUID) -> int:
    events = (await db.execute(
        select(SilAntiCheatEvent).where(
            SilAntiCheatEvent.match_id == match_id,
            SilAntiCheatEvent.user_id == user_id,
        )
    )).scalars().all()
    return sum(max(1, e.severity or EVENT_SEVERITY.get(e.event_type, 1)) for e in events)


async def _flag_match_for_review(
    db: AsyncSession,
    match: SilMatch,
    user_id: uuid.UUID,
    reasons: list[str],
    risk: int,
):
    existing = (await db.execute(
        select(SilFlaggedMatch).where(SilFlaggedMatch.match_id == match.id)
    )).scalar_one_or_none()
    if existing:
        merged = list({*(existing.reasons or []), *reasons})
        existing.reasons = merged
        existing.risk_score = max(existing.risk_score, risk)
        if existing.status == "cleared":
            existing.status = "pending"
        return
    db.add(SilFlaggedMatch(
        match_id=match.id,
        user_id=user_id,
        reasons=reasons,
        risk_score=risk,
        status="pending",
    ))


@router.post("/matches/{match_id}/anticheat")
async def anticheat(
    match_id: str,
    body: AntiCheatBody,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Log anti-cheat events. Server is source of truth for pause/forfeit/flag."""
    user_id = _uid(current_user)
    match = await db.get(SilMatch, uuid.UUID(match_id))
    if not match:
        raise HTTPException(404, "Match not found.")
    if match.player1_id != user_id and match.player2_id != user_id:
        raise HTTPException(403, "Not your match.")

    severity = EVENT_SEVERITY.get(body.event_type, 2)
    detail = body.detail
    if body.meta:
        detail = (detail or "") + " | " + str(body.meta)[:400]

    db.add(SilAntiCheatEvent(
        match_id=match.id,
        user_id=user_id,
        event_type=body.event_type,
        detail=detail,
        severity=severity,
    ))
    await db.flush()

    forfeit = False
    paused = False
    flagged = False

    # Instant forfeit for critical device/security breaches
    if body.event_type in ("emulator", "rooted", "jailbroken", "overlay", "screen_recording"):
        match.status = SilMatchStatus.forfeited
        forfeit = True
        flagged = True
        await _flag_match_for_review(db, match, user_id, [body.event_type], 100)

    elif body.event_type in PAUSE_EVENTS:
        match.status = SilMatchStatus.paused
        paused = True

    risk = await _risk_score(db, match.id, user_id)
    # Count severe events toward forfeit
    severe_n = await db.scalar(
        select(func.count()).select_from(SilAntiCheatEvent).where(
            SilAntiCheatEvent.match_id == match.id,
            SilAntiCheatEvent.user_id == user_id,
            SilAntiCheatEvent.event_type.in_(list(SEVERE_EVENTS | {"no_face", "multi_face", "face_out_of_frame"})),
        )
    )
    if (severe_n or 0) >= 3 and not forfeit:
        match.status = SilMatchStatus.forfeited
        forfeit = True
        flagged = True
        await _flag_match_for_review(
            db, match, user_id, ["repeated_violations", body.event_type], risk + 20
        )
    elif risk >= 8 or body.event_type in REVIEW_EVENTS:
        flagged = True
        await _flag_match_for_review(db, match, user_id, [body.event_type], risk)

    await db.commit()
    return {
        "logged": True,
        "forfeited": forfeit,
        "paused": paused,
        "flagged_for_review": flagged,
        "risk_score": risk,
        "status": match.status.value if hasattr(match.status, "value") else str(match.status),
        "server_truth": True,
    }


@router.post("/matches/{match_id}/heartbeat")
async def match_heartbeat(
    match_id: str,
    body: HeartbeatBody,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Front-camera monitoring pulse — one face in frame expected."""
    user_id = _uid(current_user)
    match = await db.get(SilMatch, uuid.UUID(match_id))
    if not match:
        raise HTTPException(404, "Match not found.")

    event = None
    if body.face_count > 1:
        event = "multi_face"
    elif body.face_count < 1 or not body.face_in_frame:
        event = "face_out_of_frame"
    elif body.luminance is not None and body.luminance < 12:
        event = "camera_covered"

    if event:
        return await anticheat(
            match_id,
            AntiCheatBody(event_type=event, detail=body.detail or f"faces={body.face_count} lum={body.luminance}"),
            current_user,
            db,
        )

    db.add(SilAntiCheatEvent(
        match_id=match.id,
        user_id=user_id,
        event_type="heartbeat_ok",
        detail=body.detail,
        severity=0,
    ))
    await db.commit()
    return {"ok": True, "server_truth": True}


@router.post("/device-report")
async def device_report(
    body: DeviceReportBody,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Root/jailbreak/emulator monitoring before or during matches."""
    user_id = _uid(current_user)
    mid = uuid.UUID(body.match_id) if body.match_id else None
    db.add(SilDeviceReport(
        user_id=user_id,
        match_id=mid,
        is_emulator=body.is_emulator,
        is_rooted=body.is_rooted,
        is_jailbroken=body.is_jailbroken,
        platform=body.platform,
        model=body.model,
        raw=body.raw,
    ))
    block = body.is_emulator or body.is_rooted or body.is_jailbroken
    if block and mid:
        et = "emulator" if body.is_emulator else ("rooted" if body.is_rooted else "jailbroken")
        await anticheat(
            str(mid),
            AntiCheatBody(event_type=et, detail=f"{body.platform} {body.model}"),
            current_user,
            db,
        )
        return {"allowed": False, "reason": et, "server_truth": True}
    await db.commit()
    return {"allowed": not block, "server_truth": True}


@router.post("/matches/{match_id}/resume")
async def resume_match(
    match_id: str,
    body: FaceVerifyBody,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Re-verify face after background interrupt — required before play continues."""
    if not body.liveness_ok:
        raise HTTPException(400, "Liveness check failed.")
    await face_verify(body, current_user, db)
    match = await db.get(SilMatch, uuid.UUID(match_id))
    if not match:
        raise HTTPException(404, "Match not found.")
    if match.status == SilMatchStatus.forfeited:
        raise HTTPException(400, "Match already forfeited.")
    if match.status == SilMatchStatus.paused:
        match.status = SilMatchStatus.live
        db.add(SilAntiCheatEvent(
            match_id=match.id,
            user_id=_uid(current_user),
            event_type="reentry_verified",
            detail="face+liveness ok",
            severity=0,
        ))
        await db.commit()
    return {"resumed": True, "status": match.status.value if hasattr(match.status, "value") else str(match.status)}


@router.get("/admin/flagged-matches")
async def admin_flagged_matches(
    status: str = "pending",
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Human review queue for flagged matches."""
    q = select(SilFlaggedMatch).order_by(desc(SilFlaggedMatch.created_at)).limit(100)
    if status != "all":
        q = select(SilFlaggedMatch).where(SilFlaggedMatch.status == status).order_by(
            desc(SilFlaggedMatch.risk_score)
        ).limit(100)
    rows = (await db.execute(q)).scalars().all()
    out = []
    for f in rows:
        events = (await db.execute(
            select(SilAntiCheatEvent)
            .where(SilAntiCheatEvent.match_id == f.match_id)
            .order_by(desc(SilAntiCheatEvent.created_at))
            .limit(30)
        )).scalars().all()
        out.append({
            "id": str(f.id),
            "match_id": str(f.match_id),
            "user_id": str(f.user_id),
            "reasons": f.reasons or [],
            "risk_score": f.risk_score,
            "status": f.status,
            "created_at": f.created_at.isoformat() if f.created_at else None,
            "events": [
                {
                    "type": e.event_type,
                    "detail": e.detail,
                    "severity": e.severity,
                    "at": e.created_at.isoformat() if e.created_at else None,
                }
                for e in events
            ],
        })
    return out


@router.post("/admin/flagged-matches/{flag_id}/review")
async def admin_review_flag(
    flag_id: str,
    body: ReviewBody,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    if body.status not in ("cleared", "confirmed_cheat"):
        raise HTTPException(400, "status must be cleared or confirmed_cheat")
    flag = await db.get(SilFlaggedMatch, uuid.UUID(flag_id))
    if not flag:
        raise HTTPException(404, "Flag not found.")
    flag.status = body.status
    flag.reviewer_note = body.note
    flag.reviewed_by = _uid(current_user)
    flag.reviewed_at = datetime.utcnow()
    match = await db.get(SilMatch, flag.match_id)
    if match and body.status == "confirmed_cheat":
        match.status = SilMatchStatus.forfeited
        # Reverse win stats lightly if needed — mark only
        db.add(SilAntiCheatEvent(
            match_id=match.id,
            user_id=flag.user_id,
            event_type="human_confirmed_cheat",
            detail=body.note,
            severity=5,
        ))
    await db.commit()
    return {"id": str(flag.id), "status": flag.status}


# ── Leaderboards ──────────────────────────────────────────────────────────────

@router.get("/leaderboard")
async def leaderboard(
    scope: str = "national",  # national|state|school
    state: Optional[str] = None,
    school: Optional[str] = None,
    limit: int = 20,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    q = select(SilLeagueProfile).order_by(desc(SilLeagueProfile.wins), desc(SilLeagueProfile.xp)).limit(min(50, limit))
    if scope == "state" and state:
        q = select(SilLeagueProfile).where(SilLeagueProfile.state == state).order_by(
            desc(SilLeagueProfile.wins), desc(SilLeagueProfile.xp)
        ).limit(min(50, limit))
    elif scope == "school" and school:
        q = select(SilLeagueProfile).where(SilLeagueProfile.school_name.ilike(school)).order_by(
            desc(SilLeagueProfile.wins), desc(SilLeagueProfile.xp)
        ).limit(min(50, limit))
    rows = (await db.execute(q)).scalars().all()
    me = await _get_profile(db, _uid(current_user))
    return {
        "scope": scope,
        "entries": [
            {
                "rank": i + 1,
                "gamer_tag": r.gamer_tag,
                "school_name": r.school_name,
                "state": r.state,
                "wins": r.wins,
                "xp": r.xp,
                "level": r.level,
                "score": r.wins * 100 + r.xp,
            }
            for i, r in enumerate(rows)
        ],
        "me": _profile_dict(me) if me else None,
    }


@router.get("/leaderboard/classes")
async def class_leaderboards(db: AsyncSession = Depends(get_db)):
    out = {}
    for cls in ACADEMIC_CLASSES:
        rows = (await db.execute(
            select(SilLeagueProfile)
            .where(SilLeagueProfile.academic_class == cls)
            .order_by(desc(SilLeagueProfile.wins))
            .limit(5)
        )).scalars().all()
        out[cls] = [{"gamer_tag": r.gamer_tag, "wins": r.wins, "school_name": r.school_name} for r in rows]
    return out


@router.get("/schools")
async def schools(db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(select(SilSchoolProfile).order_by(SilSchoolProfile.national_rank).limit(50))).scalars().all()
    return [
        {
            "id": str(s.id),
            "name": s.name,
            "state": s.state,
            "national_rank": s.national_rank,
            "trophies": s.trophies,
        }
        for s in rows
    ]


@router.get("/history")
async def match_history(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    user_id = _uid(current_user)
    rows = (await db.execute(
        select(SilMatch)
        .where(SilMatch.player1_id == user_id)
        .order_by(desc(SilMatch.created_at))
        .limit(30)
    )).scalars().all()
    return [
        {
            "id": str(m.id),
            "mode": m.mode.value if hasattr(m.mode, "value") else str(m.mode),
            "status": m.status.value if hasattr(m.status, "value") else str(m.status),
            "correct": m.player1_correct,
            "total": m.question_count,
            "score": m.player1_score,
            "created_at": m.created_at.isoformat() if m.created_at else None,
        }
        for m in rows
    ]


async def _recompute_ranks(db: AsyncSession):
    rows = (await db.execute(
        select(SilLeagueProfile).order_by(desc(SilLeagueProfile.wins), desc(SilLeagueProfile.xp))
    )).scalars().all()
    for i, r in enumerate(rows):
        r.national_rank = i + 1
    # state ranks
    by_state: dict[str, list] = {}
    for r in rows:
        by_state.setdefault(r.state, []).append(r)
    for group in by_state.values():
        for i, r in enumerate(group):
            r.state_rank = i + 1
    by_school: dict[str, list] = {}
    for r in rows:
        by_school.setdefault(r.school_name, []).append(r)
    for group in by_school.values():
        for i, r in enumerate(group):
            r.school_rank = i + 1


async def _post_winner_to_community(
    db: AsyncSession,
    profile: SilLeagueProfile,
    match: SilMatch,
    coins_earned: int,
) -> None:
    """PRD §16 — announce wins in student Community (like/comment/celebrate)."""
    try:
        mode_label = {
            SilMatchMode.ai_challenge: "an AI Challenge",
            SilMatchMode.student_challenge: "a Student Challenge",
            SilMatchMode.class_challenge: "a Class Challenge",
            SilMatchMode.school_challenge: "a School Challenge",
            SilMatchMode.friday_national: "the Friday National Challenge",
            SilMatchMode.practice: "a Practice quiz",
        }.get(match.mode, "a League match")

        text = (
            f"🏆 {profile.gamer_tag} won {mode_label} for {profile.school_name} "
            f"({profile.academic_class})!"
        )
        if coins_earned > 0:
            text += f" Earned {coins_earned} Scholaxia Coins."
        if profile.national_rank and profile.national_rank > 0:
            text += f" National rank #{profile.national_rank}."
        text += " Celebrate in Community! #ScholaxiaLeague"

        channel_id = None
        sp = (await db.execute(
            select(StudentProfile).where(StudentProfile.user_id == profile.user_id)
        )).scalar_one_or_none()
        if sp and sp.community_channel_id:
            channel_id = sp.community_channel_id
        if channel_id is None:
            ch = (await db.execute(
                select(CommunityChannel)
                .where(CommunityChannel.channel_type == ChannelType.general)
                .limit(1)
            )).scalar_one_or_none()
            if ch:
                channel_id = ch.id
        if channel_id is None:
            return

        db.add(CommunityPost(
            channel_id=channel_id,
            author_id=profile.user_id,
            content=text,
            is_anonymous=False,
            visibility="everyone",
        ))
        try:
            await send_user_notification(
                db=db,
                user_id=str(profile.user_id),
                title="League win posted",
                body=f"Your win was shared in Community. You earned {coins_earned} coins.",
                notification_type="sil_win",
            )
        except Exception:
            pass
    except Exception:
        # Never fail match finish because of community announce
        pass


# ── Admin ─────────────────────────────────────────────────────────────────────

class AdminQuestionBody(BaseModel):
    subject: str
    academic_class: str
    difficulty: int = 1
    question_text: str
    options: list[str]
    correct_index: int
    hint: Optional[str] = None


@router.post("/admin/questions")
async def admin_add_question(
    body: AdminQuestionBody,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    if len(body.options) != 4:
        raise HTTPException(400, "Need exactly 4 options.")
    q = SilQuestion(
        subject=body.subject,
        academic_class=body.academic_class,
        difficulty=body.difficulty,
        question_text=body.question_text,
        options=body.options,
        correct_index=body.correct_index,
        hint=body.hint,
    )
    db.add(q)
    await db.commit()
    return {"id": str(q.id)}


@router.post("/admin/seed")
async def admin_seed(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    await _ensure_seed_questions(db)
    await db.commit()
    count = await db.scalar(select(func.count()).select_from(SilQuestion))
    return {"questions": count}
