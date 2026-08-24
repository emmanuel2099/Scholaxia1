"""CBT Settings admin + new practice attempt API (exam-type packages)."""
from __future__ import annotations

import uuid
from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm.attributes import flag_modified

from app.core.database import get_db
from app.core.datetime_utils import naive_utc_now
from app.core.deps import require_admin, require_student_or_kind
from app.models.cbt import CBTExam
from app.models.cbt_settings import CbtPracticeAttempt
from app.models.user import StudentProfile
from app.services.cbt_access import has_board_access, normalize_board
from app.services import cbt_engine

router = APIRouter(tags=["CBT settings & practice"])


class CbtSettingsUpdate(BaseModel):
    cbt_enabled: Optional[bool] = None
    jamb_questions_per_subject: Optional[int] = Field(None, ge=1, le=200)
    jamb_english_questions: Optional[int] = Field(None, ge=1, le=200)
    jamb_duration_minutes: Optional[int] = Field(None, ge=5, le=480)
    jamb_subjects_required: Optional[int] = Field(None, ge=1, le=6)
    waec_questions_per_subject: Optional[int] = Field(None, ge=1, le=200)
    waec_duration_minutes: Optional[int] = Field(None, ge=5, le=480)
    neco_questions_per_subject: Optional[int] = Field(None, ge=1, le=200)
    neco_duration_minutes: Optional[int] = Field(None, ge=5, le=480)
    randomize_questions: Optional[bool] = None
    randomize_options: Optional[bool] = None
    allow_resume: Optional[bool] = None
    auto_submit_on_timeout: Optional[bool] = None


class StartPracticeRequest(BaseModel):
    exam_type: str
    subjects: list[str] = Field(default_factory=list)


class SaveAnswersRequest(BaseModel):
    answers: dict[str, str] = Field(default_factory=dict)
    section_index: Optional[int] = None


class SubmitPracticeRequest(BaseModel):
    answers: Optional[dict[str, str]] = None


@router.get("/admin/cbt-settings")
async def admin_get_cbt_settings(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    settings = await cbt_engine.get_cbt_settings(db)
    # Bank counts for admin visibility
    bank = await _bank_counts(db)
    return {"settings": settings, "question_bank": bank}


@router.put("/admin/cbt-settings")
async def admin_put_cbt_settings(
    payload: CbtSettingsUpdate,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    data = payload.model_dump(exclude_unset=True)
    settings = await cbt_engine.update_cbt_settings(db, data)
    return {"settings": settings, "message": "CBT settings saved."}


async def _bank_counts(db: AsyncSession) -> list[dict[str, Any]]:
    exams = (
        await db.execute(
            select(CBTExam).where(
                CBTExam.is_published.is_(True),
                CBTExam.is_school_exam.is_(False),
                CBTExam.paper_kind == "cbt_practice",
            )
        )
    ).scalars().all()
    from app.models.cbt import CBTQuestion

    counts: dict[tuple[str, str], int] = {}
    for ex in exams:
        board = normalize_board(ex.exam_type)
        if board not in {"JAMB", "WAEC", "NECO"}:
            continue
        n = (
            await db.execute(
                select(CBTQuestion.id).where(CBTQuestion.exam_id == ex.id)
            )
        ).scalars().all()
        key = (board, (ex.subject or "").strip())
        counts[key] = counts.get(key, 0) + len(n)
    return [
        {"exam_type": k[0], "subject": k[1], "total_questions": v}
        for k, v in sorted(counts.items())
    ]


@router.get("/cbt/practice/home")
async def practice_home(
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    """Exam-type first home: JAMB | WAEC | NECO with access + profile subjects."""
    sid = current_user["sub"]
    try:
        settings = await cbt_engine.get_cbt_settings(db)
    except Exception:
        settings = {
            "cbt_enabled": True,
            "jamb_subjects_required": 4,
            "jamb_duration_minutes": 180,
            "waec_duration_minutes": 60,
            "neco_duration_minutes": 60,
        }

    jamb_subjects: list = []
    ssce_subjects: list = []
    ssce_exam = "WAEC"
    try:
        profile = (
            await db.execute(select(StudentProfile).where(StudentProfile.user_id == sid))
        ).scalar_one_or_none()
        if profile:
            jamb_subjects = list(getattr(profile, "jamb_subjects", None) or [])
            ssce_subjects = list(
                getattr(profile, "ssce_subjects", None)
                or getattr(profile, "selected_subjects", None)
                or []
            )
            ssce_exam = getattr(profile, "ssce_exam_type", None) or "WAEC"
    except Exception:
        try:
            await db.rollback()
        except Exception:
            pass

    async def board_block(board: str) -> dict:
        has = False
        try:
            has = await has_board_access(db, sid, board)
        except Exception:
            has = False
        return {
            "exam_type": board,
            "has_access": has,
            "package_id": board.lower(),
        }

    return {
        "settings": {
            "cbt_enabled": bool(settings.get("cbt_enabled", True)),
            "jamb_subjects_required": int(settings.get("jamb_subjects_required") or 4),
            "jamb_duration_minutes": int(settings.get("jamb_duration_minutes") or 180),
            "waec_duration_minutes": int(settings.get("waec_duration_minutes") or 60),
            "neco_duration_minutes": int(settings.get("neco_duration_minutes") or 60),
        },
        "exam_types": [
            await board_block("JAMB"),
            await board_block("WAEC"),
            await board_block("NECO"),
        ],
        "profile": {
            "jamb_subjects": jamb_subjects,
            "ssce_subjects": ssce_subjects,
            "ssce_exam_type": ssce_exam,
        },
    }


@router.post("/cbt/practice/start")
async def start_practice(
    payload: StartPracticeRequest,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    try:
        attempt = await cbt_engine.start_practice_attempt(
            db,
            student_id=current_user["sub"],
            exam_type=payload.exam_type,
            subjects=payload.subjects,
        )
    except PermissionError:
        raise HTTPException(
            status_code=402,
            detail={
                "code": "cbt_package_required",
                "board": normalize_board(payload.exam_type),
                "message": "CBT package required. Redeem a coupon or pay to unlock this exam type.",
            },
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return cbt_engine.attempt_client_dict(attempt)


@router.get("/cbt/practice/attempts/{attempt_id}")
async def get_practice_attempt(
    attempt_id: str,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    attempt = await _load_own_attempt(db, attempt_id, current_user["sub"])
    return cbt_engine.attempt_client_dict(attempt)


@router.post("/cbt/practice/attempts/{attempt_id}/answers")
async def save_practice_answers(
    attempt_id: str,
    payload: SaveAnswersRequest,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    attempt = await _load_own_attempt(db, attempt_id, current_user["sub"])
    if attempt.status != "in_progress":
        raise HTTPException(status_code=400, detail="This attempt is already submitted")
    answers = dict(attempt.answers or {})
    answers.update({str(k): str(v).upper()[:1] for k, v in (payload.answers or {}).items()})
    attempt.answers = answers
    flag_modified(attempt, "answers")
    if payload.section_index is not None:
        attempt.section_index = max(0, int(payload.section_index))
    await db.flush()
    return {"ok": True, "answers": attempt.answers, "section_index": attempt.section_index}


@router.post("/cbt/practice/attempts/{attempt_id}/submit")
async def submit_practice(
    attempt_id: str,
    payload: SubmitPracticeRequest,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    attempt = await _load_own_attempt(db, attempt_id, current_user["sub"])
    if attempt.status == "completed":
        return {
            "attempt_id": str(attempt.id),
            "score": attempt.score,
            "max_score": attempt.max_score,
            "result_summary": attempt.result_summary,
        }

    answers = dict(attempt.answers or {})
    if payload.answers:
        answers.update({str(k): str(v).upper()[:1] for k, v in payload.answers.items()})
    attempt.answers = answers

    score = 0
    max_score = 0
    by_subject: dict[str, dict] = {}
    for sec in attempt.sections or []:
        sub = sec.get("subject") or "Subject"
        sub_score = 0
        sub_max = 0
        for q in sec.get("questions") or []:
            sub_max += 1
            max_score += 1
            qid = str(q.get("id"))
            if answers.get(qid) and answers.get(qid) == (q.get("correct_key") or "").upper():
                sub_score += 1
                score += 1
        by_subject[sub] = {"score": sub_score, "max": sub_max, "completed": True}
        sec["completed"] = True

    attempt.sections = attempt.sections
    flag_modified(attempt, "sections")
    attempt.answers = answers
    flag_modified(attempt, "answers")
    attempt.score = float(score)
    attempt.max_score = float(max_score)
    attempt.result_summary = {"by_subject": by_subject}
    attempt.status = "completed"
    attempt.submitted_at = naive_utc_now()
    await db.flush()
    return {
        "attempt_id": str(attempt.id),
        "score": attempt.score,
        "max_score": attempt.max_score,
        "percent": round((score / max_score) * 100, 1) if max_score else 0,
        "result_summary": attempt.result_summary,
    }


async def _load_own_attempt(db: AsyncSession, attempt_id: str, student_id: str) -> CbtPracticeAttempt:
    try:
        aid = uuid.UUID(str(attempt_id))
        sid = uuid.UUID(str(student_id))
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid attempt id") from exc
    attempt = (
        await db.execute(select(CbtPracticeAttempt).where(CbtPracticeAttempt.id == aid))
    ).scalar_one_or_none()
    if not attempt or attempt.student_id != sid:
        raise HTTPException(status_code=404, detail="Attempt not found")
    return attempt
