"""CBT practice engine: global settings + random selection from question bank."""
from __future__ import annotations

import random
import re
import uuid
from datetime import timedelta
from typing import Any

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm.attributes import flag_modified

from app.core.database import engine
from app.core.datetime_utils import naive_utc_now
from app.models.cbt import CBTExam, CBTQuestion
from app.models.cbt_settings import CbtGlobalSettings, CbtPracticeAttempt
from app.services.cbt_access import has_board_access, normalize_board

import logging

logger = logging.getLogger(__name__)

DEFAULT_SETTINGS = {
    "cbt_enabled": True,
    "jamb_questions_per_subject": 40,
    "jamb_english_questions": 60,
    "jamb_duration_minutes": 180,
    "jamb_subjects_required": 4,
    "waec_questions_per_subject": 50,
    "waec_duration_minutes": 60,
    "neco_questions_per_subject": 50,
    "neco_duration_minutes": 60,
    "randomize_questions": True,
    "randomize_options": True,
    "allow_resume": True,
    "auto_submit_on_timeout": True,
}

ENGLISH_ALIASES = {
    "english",
    "english language",
    "use of english",
    "english language (use of english)",
}


async def ensure_cbt_settings_schema() -> None:
    stmts = (
        """
        CREATE TABLE IF NOT EXISTS cbt_global_settings (
            id INTEGER PRIMARY KEY DEFAULT 1,
            cbt_enabled BOOLEAN DEFAULT TRUE,
            jamb_questions_per_subject INTEGER DEFAULT 40,
            jamb_english_questions INTEGER DEFAULT 60,
            jamb_duration_minutes INTEGER DEFAULT 180,
            jamb_subjects_required INTEGER DEFAULT 4,
            waec_questions_per_subject INTEGER DEFAULT 50,
            waec_duration_minutes INTEGER DEFAULT 60,
            neco_questions_per_subject INTEGER DEFAULT 50,
            neco_duration_minutes INTEGER DEFAULT 60,
            randomize_questions BOOLEAN DEFAULT TRUE,
            randomize_options BOOLEAN DEFAULT TRUE,
            allow_resume BOOLEAN DEFAULT TRUE,
            auto_submit_on_timeout BOOLEAN DEFAULT TRUE,
            updated_at TIMESTAMP DEFAULT NOW()
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS cbt_practice_attempts (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            student_id UUID NOT NULL,
            exam_type VARCHAR(30) NOT NULL,
            subjects JSON NOT NULL DEFAULT '[]',
            sections JSON NOT NULL DEFAULT '[]',
            answers JSON NULL,
            status VARCHAR(30) DEFAULT 'in_progress',
            section_index INTEGER DEFAULT 0,
            duration_minutes INTEGER NOT NULL,
            started_at TIMESTAMP DEFAULT NOW(),
            ends_at TIMESTAMP NULL,
            submitted_at TIMESTAMP NULL,
            score DOUBLE PRECISION NULL,
            max_score DOUBLE PRECISION NULL,
            result_summary JSON NULL,
            notes TEXT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS ix_cbt_practice_attempts_student_id ON cbt_practice_attempts (student_id)",
        "CREATE INDEX IF NOT EXISTS ix_cbt_practice_attempts_exam_type ON cbt_practice_attempts (exam_type)",
        "CREATE INDEX IF NOT EXISTS ix_cbt_practice_attempts_status ON cbt_practice_attempts (status)",
    )
    try:
        async with engine.begin() as conn:
            for stmt in stmts:
                try:
                    await conn.execute(text(stmt))
                except Exception as exc:
                    logger.warning("cbt settings schema stmt skipped: %s", exc)
            # Seed singleton settings row
            try:
                await conn.execute(
                    text(
                        """
                        INSERT INTO cbt_global_settings (id) VALUES (1)
                        ON CONFLICT (id) DO NOTHING
                        """
                    )
                )
            except Exception as exc:
                logger.warning("cbt settings seed skipped: %s", exc)
    except Exception as exc:
        logger.warning("ensure_cbt_settings_schema failed: %s", exc)


def settings_to_dict(row: CbtGlobalSettings | None) -> dict[str, Any]:
    if not row:
        return dict(DEFAULT_SETTINGS)
    return {
        "cbt_enabled": bool(row.cbt_enabled),
        "jamb_questions_per_subject": int(row.jamb_questions_per_subject or 40),
        "jamb_english_questions": int(row.jamb_english_questions or 60),
        "jamb_duration_minutes": int(row.jamb_duration_minutes or 180),
        "jamb_subjects_required": int(row.jamb_subjects_required or 4),
        "waec_questions_per_subject": int(row.waec_questions_per_subject or 50),
        "waec_duration_minutes": int(row.waec_duration_minutes or 60),
        "neco_questions_per_subject": int(row.neco_questions_per_subject or 50),
        "neco_duration_minutes": int(row.neco_duration_minutes or 60),
        "randomize_questions": bool(row.randomize_questions if row.randomize_questions is not None else True),
        "randomize_options": bool(row.randomize_options if row.randomize_options is not None else True),
        "allow_resume": bool(row.allow_resume if row.allow_resume is not None else True),
        "auto_submit_on_timeout": bool(
            row.auto_submit_on_timeout if row.auto_submit_on_timeout is not None else True
        ),
    }


async def get_cbt_settings(db: AsyncSession) -> dict[str, Any]:
    await ensure_cbt_settings_schema()
    row = (await db.execute(select(CbtGlobalSettings).where(CbtGlobalSettings.id == 1))).scalar_one_or_none()
    if not row:
        row = CbtGlobalSettings(id=1, **DEFAULT_SETTINGS)
        db.add(row)
        await db.flush()
    return settings_to_dict(row)


async def update_cbt_settings(db: AsyncSession, payload: dict[str, Any]) -> dict[str, Any]:
    await ensure_cbt_settings_schema()
    row = (await db.execute(select(CbtGlobalSettings).where(CbtGlobalSettings.id == 1))).scalar_one_or_none()
    if not row:
        row = CbtGlobalSettings(id=1)
        db.add(row)
    for key in DEFAULT_SETTINGS:
        if key in payload and payload[key] is not None:
            setattr(row, key, payload[key])
    row.updated_at = naive_utc_now()
    await db.flush()
    return settings_to_dict(row)


def _norm_subject(value: str | None) -> str:
    return re.sub(r"\s+", " ", (value or "").strip().lower())


def _subject_keys(subject: str) -> set[str]:
    """Loose matching so Maths ↔ Mathematics, CRS aliases, etc."""
    n = _norm_subject(subject)
    keys = {n} if n else set()
    if not n:
        return keys
    if n in {"math", "maths", "mathematics", "further mathematics", "addmath"} or "math" in n:
        keys |= {"math", "maths", "mathematics"}
    if n in ENGLISH_ALIASES or "english" in n:
        keys |= set(ENGLISH_ALIASES) | {n}
    if n in {"crs", "crk", "christian religious studies", "christian religious knowledge"} or (
        "christian" in n and "relig" in n
    ):
        keys |= {"crs", "crk", "christian religious studies", "christian religious knowledge"}
    if n in {"irs", "irk", "islamic religious studies", "islamic studies"} or (
        "islam" in n and "relig" in n
    ):
        keys |= {"irs", "irk", "islamic religious studies", "islamic studies"}
    if n in {"government", "govt"}:
        keys |= {"government", "govt"}
    if n in {"biology", "agric", "agricultural science"} and "agric" in n:
        keys |= {"agricultural science", "agric", "agriculture"}
    return keys


def subjects_match(a: str | None, b: str | None) -> bool:
    return bool(_subject_keys(a or "") & _subject_keys(b or ""))


def is_english_subject(subject: str) -> bool:
    return _norm_subject(subject) in ENGLISH_ALIASES or "english" in _norm_subject(subject)


def _shuffle_options(
    q: CBTQuestion,
    *,
    randomize: bool,
) -> tuple[list[dict[str, str]], str]:
    raw = [
        ("A", q.option_a or ""),
        ("B", q.option_b or ""),
        ("C", q.option_c or ""),
        ("D", q.option_d or ""),
    ]
    correct_text = dict(raw).get((q.correct_option or "A").upper(), q.option_a or "")
    if randomize:
        random.shuffle(raw)
    letters = ["A", "B", "C", "D"]
    options = []
    correct_key = "A"
    for i, (_old, text) in enumerate(raw[:4]):
        key = letters[i]
        options.append({"key": key, "text": text})
        if text == correct_text:
            correct_key = key
    return options, correct_key


async def _published_practice_exams(db: AsyncSession, exam_type: str) -> list[CBTExam]:
    from app.models.cbt import normalize_paper_kind

    board = normalize_board(exam_type)
    exams = (
        await db.execute(
            select(CBTExam).where(
                CBTExam.is_published.is_(True),
                CBTExam.is_school_exam.is_(False),
            )
        )
    ).scalars().all()
    out = []
    for ex in exams:
        if normalize_board(ex.exam_type) != board:
            continue
        # Practice bank = anything that is not past_questions
        if normalize_paper_kind(getattr(ex, "paper_kind", None)) == "past_questions":
            continue
        out.append(ex)
    return out


async def _bank_questions_for(
    db: AsyncSession,
    exam_type: str,
    subject: str,
    practice_exams: list[CBTExam] | None = None,
    limit: int | None = None,
) -> list[CBTQuestion]:
    """Load a capped set of questions. Never use ORDER BY random() — it times out on Render."""
    exams = practice_exams if practice_exams is not None else await _published_practice_exams(db, exam_type)
    exam_ids = [ex.id for ex in exams if subjects_match(ex.subject, subject)]
    if not exam_ids:
        return []

    # Fast path: ids only, then sample in Python, then fetch rows
    id_cap = 600
    if limit and limit > 0:
        id_cap = min(max(int(limit) * 8, 120), 600)
    id_rows = (
        await db.execute(
            select(CBTQuestion.id).where(CBTQuestion.exam_id.in_(exam_ids)).limit(id_cap)
        )
    ).scalars().all()
    ids = list(id_rows)
    if not ids:
        return []
    if limit and len(ids) > limit:
        ids = random.sample(ids, int(limit))
    rows = (
        await db.execute(select(CBTQuestion).where(CBTQuestion.id.in_(ids)))
    ).scalars().all()
    return list(rows)


async def build_section(
    db: AsyncSession,
    *,
    exam_type: str,
    subject: str,
    count: int,
    randomize_questions: bool,
    randomize_options: bool,
    practice_exams: list[CBTExam] | None = None,
) -> dict[str, Any]:
    need = max(int(count or 1), 1)
    bank = await _bank_questions_for(
        db,
        exam_type,
        subject,
        practice_exams=practice_exams,
        limit=need,
    )
    if not bank:
        raise ValueError(
            f"No questions in bank for {exam_type} / {subject}. "
            "In Admin → CBT, upload/publish practice questions for this subject."
        )
    pick_n = min(need, len(bank))
    chosen = random.sample(bank, pick_n) if randomize_questions else bank[:pick_n]
    questions_out = []
    for q in chosen:
        options, correct_key = _shuffle_options(q, randomize=randomize_options)
        questions_out.append(
            {
                "id": str(q.id),
                "question_text": q.question_text or "",
                "options": options,
                "correct_key": correct_key,
                "topic": q.topic,
                "image_url": q.image_url,
            }
        )
    return {
        "subject": subject,
        "total": len(questions_out),
        "completed": False,
        "questions": questions_out,
    }


def client_sections(sections: list[dict]) -> list[dict]:
    """Strip correct answers for the student client."""
    out = []
    for sec in sections:
        qs = []
        for q in sec.get("questions") or []:
            qs.append(
                {
                    "id": q["id"],
                    "question_text": q.get("question_text"),
                    "options": q.get("options") or [],
                    "topic": q.get("topic"),
                    "image_url": q.get("image_url"),
                }
            )
        out.append(
            {
                "subject": sec.get("subject"),
                "total": sec.get("total") or len(qs),
                "completed": bool(sec.get("completed")),
                "questions": qs,
            }
        )
    return out


def light_sections(sections: list[dict]) -> list[dict]:
    """Subject stubs only — full questions load per section on demand."""
    out = []
    for sec in sections or []:
        qs = sec.get("questions") or []
        out.append(
            {
                "subject": sec.get("subject"),
                "total": int(sec.get("total") or len(qs) or 0),
                "completed": bool(sec.get("completed")),
                "questions": [],
            }
        )
    return out


def client_section_at(sections: list[dict], index: int) -> dict[str, Any]:
    secs = list(sections or [])
    if index < 0 or index >= len(secs):
        raise IndexError("section index out of range")
    return client_sections([secs[index]])[0]


def section_stub(subject: str, count: int) -> dict[str, Any]:
    """Placeholder section — questions are filled on first open."""
    n = max(int(count or 1), 1)
    return {
        "subject": subject,
        "total": n,
        "completed": False,
        "questions": [],
    }


async def ensure_section_built(
    db: AsyncSession,
    attempt: CbtPracticeAttempt,
    section_index: int,
) -> dict[str, Any]:
    """Build one subject paper the first time the student opens it."""
    sections = list(attempt.sections or [])
    if section_index < 0 or section_index >= len(sections):
        raise IndexError("section index out of range")
    sec = dict(sections[section_index] or {})
    if sec.get("questions"):
        return sec

    settings = await get_cbt_settings(db)
    board = normalize_board(attempt.exam_type)
    subject = str(sec.get("subject") or "").strip()
    if not subject:
        raise ValueError("Section has no subject")

    if board == "JAMB":
        count = (
            int(settings["jamb_english_questions"] or 60)
            if is_english_subject(subject)
            else int(settings["jamb_questions_per_subject"] or 40)
        )
    elif board == "WAEC":
        count = int(settings["waec_questions_per_subject"] or 50)
    else:
        count = int(settings["neco_questions_per_subject"] or 50)
    # Prefer stub total if admin already set it at start
    if int(sec.get("total") or 0) > 0:
        count = int(sec["total"])

    built = await build_section(
        db,
        exam_type=board,
        subject=subject,
        count=count,
        randomize_questions=bool(settings["randomize_questions"]),
        randomize_options=bool(settings["randomize_options"]),
    )
    sections[section_index] = built
    attempt.sections = sections
    flag_modified(attempt, "sections")
    await db.flush()
    return built


async def ensure_all_sections_built(db: AsyncSession, attempt: CbtPracticeAttempt) -> None:
    for i, sec in enumerate(list(attempt.sections or [])):
        if not (sec or {}).get("questions"):
            await ensure_section_built(db, attempt, i)


async def start_practice_attempt(
    db: AsyncSession,
    *,
    student_id: str,
    exam_type: str,
    subjects: list[str],
) -> CbtPracticeAttempt:
    from app.models.user import StudentProfile

    settings = await get_cbt_settings(db)
    if not settings.get("cbt_enabled", True):
        raise ValueError("CBT practice is currently disabled by admin.")

    board = normalize_board(exam_type)
    if board not in {"JAMB", "WAEC", "NECO"}:
        raise ValueError("Exam type must be JAMB, WAEC, or NECO")

    sid = uuid.UUID(str(student_id))
    # Access check must never poison the DB transaction used to build the paper
    try:
        allowed = await has_board_access(db, str(sid), board)
    except Exception:
        logger.exception("has_board_access failed during practice start")
        try:
            await db.rollback()
        except Exception:
            pass
        allowed = False
    if not allowed:
        raise PermissionError(f"{board}_PACKAGE_REQUIRED")

    await ensure_cbt_settings_schema()

    # Resume in-progress attempt only if time remains; otherwise close it and start fresh
    if settings.get("allow_resume"):
        existing = (
            await db.execute(
                select(CbtPracticeAttempt)
                .where(
                    CbtPracticeAttempt.student_id == sid,
                    CbtPracticeAttempt.exam_type == board,
                    CbtPracticeAttempt.status == "in_progress",
                )
                .order_by(CbtPracticeAttempt.started_at.desc())
                .limit(1)
            )
        ).scalar_one_or_none()
        if existing:
            now_check = naive_utc_now()
            ends = existing.ends_at
            still_valid = True
            if ends is not None:
                # Treat already-expired attempts as abandoned so coupon/start opens a real exam
                if ends <= now_check:
                    existing.status = "abandoned"
                    existing.submitted_at = now_check
                    await db.flush()
                    still_valid = False
            if still_valid:
                secs = existing.sections or []
                has_answers = bool(existing.answers)
                # Heavy unanswered papers block instant Start — replace with a fresh stub session
                heavy = any(len((s or {}).get("questions") or []) > 0 for s in secs)
                if heavy and not has_answers:
                    existing.status = "abandoned"
                    existing.submitted_at = now_check
                    await db.flush()
                    still_valid = False
                else:
                    return existing

    subjects_clean = [s.strip() for s in subjects if (s or "").strip()]

    # Prefer student profile subjects (exam package), not a per-start selection form
    try:
        profile = (
            await db.execute(select(StudentProfile).where(StudentProfile.user_id == sid))
        ).scalar_one_or_none()
    except Exception:
        profile = None

    if board == "JAMB":
        need = int(settings["jamb_subjects_required"] or 4)
        profile_jamb = list((profile.jamb_subjects if profile else None) or [])
        if len(subjects_clean) != need and len(profile_jamb) == need:
            subjects_clean = [str(s).strip() for s in profile_jamb if str(s).strip()]
        if len(subjects_clean) != need:
            raise ValueError(
                f"Your profile must have exactly {need} JAMB subjects before starting CBT. "
                "Update Profile → Exam subjects, then try again."
            )
        duration = int(settings["jamb_duration_minutes"] or 60)
        # Fast open: create subject stubs now; build questions when student picks a subject
        sections = []
        for sub in subjects_clean:
            n = (
                int(settings["jamb_english_questions"] or 60)
                if is_english_subject(sub)
                else int(settings["jamb_questions_per_subject"] or 40)
            )
            sections.append(section_stub(sub, n))
    else:
        profile_ssce = list(
            (profile.ssce_subjects if profile else None)
            or (profile.selected_subjects if profile else None)
            or []
        )
        if not subjects_clean and len(profile_ssce) == 1:
            subjects_clean = [str(profile_ssce[0]).strip()]
        if len(subjects_clean) != 1:
            raise ValueError(f"Select one {board} subject to practice.")
        # Soft-check: subject should be one the student registered
        if profile_ssce:
            want = subjects_clean[0].strip().lower()
            allowed = {str(s).strip().lower() for s in profile_ssce}
            if want not in allowed:
                raise ValueError(
                    f"{subjects_clean[0]} is not in your registered {board} subjects. Update your profile."
                )
        duration = int(
            settings["waec_duration_minutes"] if board == "WAEC" else settings["neco_duration_minutes"]
        )
        count = int(
            settings["waec_questions_per_subject"]
            if board == "WAEC"
            else settings["neco_questions_per_subject"]
        )
        sections = [section_stub(subjects_clean[0], count)]

    now = naive_utc_now()
    attempt = CbtPracticeAttempt(
        student_id=sid,
        exam_type=board,
        subjects=subjects_clean,
        sections=sections,
        answers={},
        status="in_progress",
        section_index=0,
        duration_minutes=duration,
        started_at=now,
        ends_at=now + timedelta(minutes=duration),
    )
    db.add(attempt)
    await db.flush()
    return attempt


def attempt_client_dict(
    attempt: CbtPracticeAttempt,
    *,
    include_questions: bool = True,
) -> dict[str, Any]:
    now = naive_utc_now()
    ends = attempt.ends_at
    seconds_left = None
    if ends:
        seconds_left = max(0, int((ends - now).total_seconds()))
    raw_sections = attempt.sections or []
    sections = (
        client_sections(raw_sections) if include_questions else light_sections(raw_sections)
    )
    return {
        "attempt_id": str(attempt.id),
        "exam_type": attempt.exam_type,
        "subjects": attempt.subjects or [],
        "sections": sections,
        "section_index": int(attempt.section_index or 0),
        "status": attempt.status,
        "duration_minutes": attempt.duration_minutes,
        "started_at": attempt.started_at.isoformat() if attempt.started_at else None,
        "ends_at": attempt.ends_at.isoformat() if attempt.ends_at else None,
        "seconds_left": seconds_left,
        "answers": attempt.answers or {},
        "questions_deferred": not include_questions,
    }
