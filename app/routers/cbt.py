from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
import httpx
from app.core.database import get_db
from app.core.deps import require_student, require_admin, get_current_user, require_teacher
from app.models.cbt import CBTExam, CBTQuestion, CBTSession, ExamProctorLog
from app.models.user import StudentProfile
from app.core.subjects import subject_matches

router = APIRouter(prefix="/cbt", tags=["CBT"])

PRACTICE_BANK_BASE = "https://www.scholaxiacbtexam.blog/practice-exams"


@router.get("/practice-bank/{category}")
async def practice_bank(
    category: str,
    current_user: dict = Depends(require_student),
):
    """Proxy Scholaxia CBT question bank (avoids browser CORS blocks)."""
    cat = category.strip().upper()
    if cat not in {"JAMB", "WAEC", "NECO", "POST_UTME", "POST-UTME"}:
        raise HTTPException(status_code=400, detail="category must be JAMB, WAEC, NECO, or POST_UTME")
    cat_key = cat.replace("-", "_").upper()
    if cat_key == "POST_UTME":
        raise HTTPException(status_code=404, detail="POST-UTME practice bank uses ALOC API only")
    url = f"{PRACTICE_BANK_BASE}/{cat.lower()}.json"
    try:
        async with httpx.AsyncClient(timeout=90.0) as client:
            resp = await client.get(url)
            resp.raise_for_status()
            return resp.json()
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Could not load practice bank: {exc}") from exc


# ── ALOC Past Questions (questions.aloc.com.ng) ───────────────────────────────

def _profile_exam_type(profile) -> str:
    if not profile or not profile.exam_type:
        return "JAMB"
    return profile.exam_type.value if hasattr(profile.exam_type, "value") else str(profile.exam_type)


def _aloc_exam_response(exam: dict) -> dict:
    return {
        "session": {
            "session_id": f"aloc-{int(datetime.utcnow().timestamp())}",
            "is_portal": True,
            "is_aloc": True,
            "is_school_exam": False,
        },
        "exam": {
            "id": exam["id"],
            "title": exam["title"],
            "subject": exam["subject"],
            "exam_type": exam["exam_type"],
            "duration_minutes": exam["duration_minutes"],
            "total_questions": len(exam["questions"]),
            "questions": exam["questions"],
            "sections": exam["sections"],
            "is_combined": True,
            "is_aloc": True,
            "selected_year": exam.get("selected_year", ""),
        },
        "meta": exam["meta"],
        "selected_year": exam.get("selected_year", ""),
        "secondsLeft": exam["duration_minutes"] * 60,
    }


async def _get_student_profile(db, user_id: str) -> StudentProfile:
    profile_res = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == user_id)
    )
    profile = profile_res.scalar_one_or_none()
    if not profile or not profile.selected_subjects:
        raise HTTPException(status_code=400, detail="Complete exam setup in Profile first")
    return profile


@router.get("/aloc/status")
async def aloc_status(current_user: dict = Depends(require_student)):
    from app.services.aloc_service import aloc_configured

    return {"configured": aloc_configured(), "provider": "questions.aloc.com.ng"}


@router.get("/aloc/exam-preview")
async def aloc_exam_preview(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    from app.services.aloc_service import aloc_configured, build_combined_exam, normalize_exam_type

    if not aloc_configured():
        raise HTTPException(status_code=404, detail="ALOC is not configured on the server")

    profile = await _get_student_profile(db, current_user["sub"])
    exam_type = normalize_exam_type(_profile_exam_type(profile))
    preview = await build_combined_exam(exam_type, profile.selected_subjects, fetch=False)
    preview.pop("questions", None)
    preview.pop("sections", None)
    return preview


@router.get("/aloc/exam")
async def aloc_exam(
    year: Optional[str] = Query(None),
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    from app.core.config import settings
    from app.services.aloc_service import aloc_configured, build_combined_exam, normalize_exam_type

    if not aloc_configured():
        raise HTTPException(status_code=503, detail="ALOC access token is not configured on the server")

    profile = await _get_student_profile(db, current_user["sub"])
    exam_type = normalize_exam_type(_profile_exam_type(profile))

    if year is not None:
        use_year = str(year).strip() or None
    else:
        use_year = (settings.ALOC_DEFAULT_YEAR or "").strip() or None

    exam = await build_combined_exam(
        exam_type, profile.selected_subjects, year=use_year, fetch=True
    )
    if not exam["questions"]:
        raise HTTPException(status_code=502, detail="ALOC returned no questions for your subjects")

    return _aloc_exam_response(exam)


@router.get("/aloc/jamb-preview")
async def aloc_jamb_preview(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    from app.services.aloc_service import aloc_configured, build_combined_exam

    if not aloc_configured():
        raise HTTPException(status_code=404, detail="ALOC is not configured on the server")

    profile = await _get_student_profile(db, current_user["sub"])
    if _profile_exam_type(profile).upper() != "JAMB" or len(profile.selected_subjects) != 4:
        raise HTTPException(status_code=400, detail="ALOC full JAMB CBT requires exactly 4 JAMB subjects")

    preview = await build_combined_exam("JAMB", profile.selected_subjects, fetch=False)
    preview.pop("questions", None)
    preview.pop("sections", None)
    return preview


@router.get("/aloc/jamb-exam")
async def aloc_jamb_exam(
    year: Optional[str] = Query(None),
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    from app.core.config import settings
    from app.services.aloc_service import aloc_configured, build_combined_exam

    if not aloc_configured():
        raise HTTPException(status_code=503, detail="ALOC access token is not configured on the server")

    profile = await _get_student_profile(db, current_user["sub"])

    if year is not None:
        use_year = str(year).strip() or None
    else:
        use_year = (settings.ALOC_DEFAULT_YEAR or "").strip() or None

    exam = await build_combined_exam("JAMB", profile.selected_subjects, year=use_year, fetch=True)
    if not exam["questions"]:
        raise HTTPException(status_code=502, detail="ALOC returned no questions for your subjects")

    return _aloc_exam_response(exam)


# ── Schemas ───────────────────────────────────────────────────────────────────

class SubmitAnswersRequest(BaseModel):
    session_id: str
    answers: dict  # {question_id: "A"|"B"|"C"|"D"}
    is_auto_submit: bool = False


class SessionResponse(BaseModel):
    session_id: str
    exam_id: str
    started_at: datetime
    duration_minutes: int
    total_questions: int
    is_school_exam: bool = False
    ai_locked: bool = False
    camera_required: bool = False
    block_minimize: bool = False


class ResultResponse(BaseModel):
    score: float
    percentage: float
    total_correct: int
    total_wrong: int
    weak_topics: list


class ExamSummary(BaseModel):
    id: str
    title: str
    subject: str
    exam_type: str
    duration_minutes: int
    total_questions: int
    is_published: bool
    is_school_exam: bool = False
    camera_required: bool = False
    scheduled_start: Optional[datetime] = None
    scheduled_end: Optional[datetime] = None


def _exam_summary(e: CBTExam) -> ExamSummary:
    return ExamSummary(
        id=str(e.id), title=e.title, subject=e.subject,
        exam_type=e.exam_type, duration_minutes=e.duration_minutes,
        total_questions=e.total_questions, is_published=e.is_published,
        is_school_exam=e.is_school_exam,
        camera_required=e.camera_required,
        scheduled_start=e.scheduled_start,
        scheduled_end=e.scheduled_end,
    )


def _school_exam_is_open(exam: CBTExam, now: datetime) -> bool:
    if not exam.is_school_exam:
        return True
    if exam.scheduled_start and now < exam.scheduled_start:
        return False
    if exam.scheduled_end and now > exam.scheduled_end:
        return False
    return True


class SchoolExamQuestionCreate(BaseModel):
    question_text: str
    option_a: str
    option_b: str
    option_c: str
    option_d: str
    correct_option: str
    explanation: Optional[str] = None
    topic: Optional[str] = None


class CreateSchoolExamRequest(BaseModel):
    title: str
    subject: str
    duration_minutes: int
    scheduled_start: datetime
    scheduled_end: datetime
    questions: List[SchoolExamQuestionCreate]


class QuestionOut(BaseModel):
    id: str
    question_text: str
    option_a: str
    option_b: str
    option_c: str
    option_d: str
    topic: Optional[str]
    image_url: Optional[str]


class ExamDownload(BaseModel):
    id: str
    title: str
    subject: str
    exam_type: str
    duration_minutes: int
    total_questions: int
    questions: List[QuestionOut]


# ── List Exams (public) ───────────────────────────────────────────────────────

@router.get("/exams", response_model=List[ExamSummary])
async def list_exams(
    exam_type: Optional[str] = Query(None),
    subject: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
):
    """List all published exams. No auth required. Filterable by exam_type and subject."""
    q = select(CBTExam).where(CBTExam.is_published == True)  # noqa: E712
    if exam_type:
        q = q.where(CBTExam.exam_type == exam_type.upper())
    if subject:
        q = q.where(CBTExam.subject.ilike(f"%{subject}%"))
    result = await db.execute(q.order_by(CBTExam.exam_type, CBTExam.subject))
    exams = result.scalars().all()
    return [_exam_summary(e) for e in exams]


@router.get("/exams/for-me")
async def exams_for_student(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    Practice + school exams filtered by the student's exam type and selected subjects.
    Practice exams can be downloaded for offline use; school exams cannot.
    """
    profile_res = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == current_user["sub"])
    )
    profile = profile_res.scalar_one_or_none()
    if not profile or not profile.exam_type or not profile.selected_subjects:
        raise HTTPException(
            status_code=400,
            detail="Complete exam setup first at /students/setup-exam",
        )

    exam_type = profile.exam_type.value
    subjects = profile.selected_subjects
    now = datetime.utcnow()

    result = await db.execute(
        select(CBTExam).where(CBTExam.is_published == True)  # noqa: E712
    )
    all_exams = result.scalars().all()

    practice = []
    school = []
    for e in all_exams:
        if not subject_matches(e.subject, subjects):
            continue
        if e.is_school_exam:
            if _school_exam_is_open(e, now) or (e.scheduled_start and e.scheduled_start > now):
                school.append(_exam_summary(e))
        elif e.exam_type.upper() == exam_type.upper():
            practice.append(_exam_summary(e))

    return {
        "exam_type": exam_type,
        "selected_subjects": subjects,
        "practice_exams": practice,
        "school_exams": school,
    }


# ── Get Single Exam Info (public) ─────────────────────────────────────────────

@router.get("/exams/{exam_id}", response_model=ExamSummary)
async def get_exam(exam_id: str, db: AsyncSession = Depends(get_db)):
    """Get exam metadata. No auth required."""
    result = await db.execute(
        select(CBTExam).where(CBTExam.id == exam_id, CBTExam.is_published == True)  # noqa: E712
    )
    exam = result.scalar_one_or_none()
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")
    return _exam_summary(exam)


# ── Download Exam for Offline Use (auth required) ─────────────────────────────

@router.get("/exams/{exam_id}/download")
async def download_exam(
    exam_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Returns the full exam with questions (NO correct answers).
    Used by the web/mobile client to cache exam for offline CBT.
    """
    result = await db.execute(
        select(CBTExam).where(CBTExam.id == exam_id, CBTExam.is_published == True)  # noqa: E712
    )
    exam = result.scalar_one_or_none()
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")

    if exam.is_school_exam:
        raise HTTPException(
            status_code=403,
            detail="School exams cannot be downloaded. They must be taken online during the scheduled window.",
        )

    q_result = await db.execute(
        select(CBTQuestion).where(CBTQuestion.exam_id == exam.id)
    )
    questions = q_result.scalars().all()

    question_list = []
    for q in questions:
        item = {
            "id": str(q.id),
            "question_text": q.question_text,
            "option_a": q.option_a,
            "option_b": q.option_b,
            "option_c": q.option_c,
            "option_d": q.option_d,
            "topic": q.topic,
            "image_url": q.image_url,
        }
        # Practice exams include answers in offline pack for local scoring
        if not exam.is_school_exam:
            item["correct_option"] = q.correct_option
            item["explanation"] = q.explanation
        question_list.append(item)

    return {
        "id": str(exam.id),
        "title": exam.title,
        "subject": exam.subject,
        "exam_type": exam.exam_type,
        "duration_minutes": exam.duration_minutes,
        "total_questions": exam.total_questions,
        "is_school_exam": exam.is_school_exam,
        "questions": question_list,
    }


# ── Start Session ─────────────────────────────────────────────────────────────

@router.post("/sessions/{exam_id}/start", response_model=SessionResponse)
async def start_session(
    exam_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(CBTExam).where(CBTExam.id == exam_id, CBTExam.is_published == True)  # noqa: E712
    )
    exam = result.scalar_one_or_none()
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")

    now = datetime.utcnow()
    if exam.is_school_exam:
        if not _school_exam_is_open(exam, now):
            raise HTTPException(status_code=403, detail="This school exam is not open right now")
        # School exams always require online session — enforce security flags
        if not exam.camera_required:
            exam.camera_required = True
        if not exam.ai_locked:
            exam.ai_locked = True
        if not exam.block_minimize:
            exam.block_minimize = True

    session = CBTSession(student_id=current_user["sub"], exam_id=exam.id)
    db.add(session)
    await db.flush()

    return SessionResponse(
        session_id=str(session.id),
        exam_id=str(exam.id),
        started_at=session.started_at,
        duration_minutes=exam.duration_minutes,
        total_questions=exam.total_questions,
        is_school_exam=exam.is_school_exam,
        ai_locked=exam.ai_locked,
        camera_required=exam.camera_required,
        block_minimize=exam.block_minimize,
    )


# ── Submit Session ────────────────────────────────────────────────────────────

@router.post("/sessions/submit", response_model=ResultResponse)
async def submit_session(
    payload: SubmitAnswersRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(CBTSession).where(
            CBTSession.id == payload.session_id,
            CBTSession.student_id == current_user["sub"],
        )
    )
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    if session.submitted_at:
        raise HTTPException(status_code=400, detail="Already submitted")

    q_result = await db.execute(
        select(CBTQuestion).where(CBTQuestion.exam_id == session.exam_id)
    )
    questions = q_result.scalars().all()

    correct = 0
    wrong = 0
    weak_topics: set = set()

    for q in questions:
        chosen = payload.answers.get(str(q.id))
        if chosen and chosen.upper() == q.correct_option.upper():
            correct += 1
        else:
            wrong += 1
            if q.topic:
                weak_topics.add(q.topic)

    total = correct + wrong
    percentage = round((correct / total) * 100, 2) if total > 0 else 0.0

    session.answers = payload.answers
    session.score = correct
    session.percentage = percentage
    session.total_correct = correct
    session.total_wrong = wrong
    session.weak_topics = list(weak_topics)
    session.submitted_at = datetime.utcnow()
    session.is_auto_submitted = payload.is_auto_submit
    await db.flush()

    return ResultResponse(
        score=correct,
        percentage=percentage,
        total_correct=correct,
        total_wrong=wrong,
        weak_topics=list(weak_topics),
    )


# ── Get Session Result ────────────────────────────────────────────────────────

@router.get("/sessions/{session_id}/result", response_model=ResultResponse)
async def get_session_result(
    session_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(CBTSession).where(
            CBTSession.id == session_id,
            CBTSession.student_id == current_user["sub"],
        )
    )
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    if not session.submitted_at:
        raise HTTPException(status_code=400, detail="Session not yet submitted")

    return ResultResponse(
        score=session.score or 0,
        percentage=session.percentage or 0.0,
        total_correct=session.total_correct or 0,
        total_wrong=session.total_wrong or 0,
        weak_topics=session.weak_topics or [],
    )


# ── Get Session Review (with correct answers + explanations) ──────────────────

@router.get("/sessions/{session_id}/review")
async def get_session_review(
    session_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Returns all questions with correct answers, student answers, and explanations."""
    res = await db.execute(
        select(CBTSession).where(
            CBTSession.id == session_id,
            CBTSession.student_id == current_user["sub"],
        )
    )
    session = res.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    if not session.submitted_at:
        raise HTTPException(status_code=400, detail="Session not yet submitted")

    q_result = await db.execute(
        select(CBTQuestion).where(CBTQuestion.exam_id == session.exam_id)
    )
    questions = q_result.scalars().all()
    submitted_answers = session.answers or {}

    return {
        "session_id": session_id,
        "percentage": session.percentage,
        "total_correct": session.total_correct,
        "total_wrong": session.total_wrong,
        "questions": [
            {
                "id": str(q.id),
                "question_text": q.question_text,
                "option_a": q.option_a,
                "option_b": q.option_b,
                "option_c": q.option_c,
                "option_d": q.option_d,
                "correct_option": q.correct_option,
                "explanation": q.explanation,
                "topic": q.topic,
                "student_answer": submitted_answers.get(str(q.id)),
                "is_correct": (submitted_answers.get(str(q.id)) or "").upper() == q.correct_option.upper(),
            }
            for q in questions
        ],
    }


# ── My Sessions ───────────────────────────────────────────────────────────────

@router.get("/my-sessions")
async def my_sessions(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Student's own submitted exam sessions."""
    result = await db.execute(
        select(CBTSession, CBTExam)
        .join(CBTExam, CBTExam.id == CBTSession.exam_id)
        .where(
            CBTSession.student_id == current_user["sub"],
            CBTSession.submitted_at.isnot(None),
        )
        .order_by(CBTSession.submitted_at.desc())
    )
    rows = result.all()
    return [
        {
            "session_id": str(s.id),
            "exam_id": str(e.id),
            "exam_title": e.title,
            "subject": e.subject,
            "exam_type": e.exam_type,
            "percentage": s.percentage,
            "total_correct": s.total_correct,
            "total_wrong": s.total_wrong,
            "submitted_at": s.submitted_at,
            "weak_topics": s.weak_topics or [],
        }
        for s, e in rows
    ]


# ── AI Lock Check ─────────────────────────────────────────────────────────────

@router.get("/sessions/{session_id}/ai-status")
async def check_ai_lock(
    session_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(CBTSession, CBTExam)
        .join(CBTExam, CBTExam.id == CBTSession.exam_id)
        .where(
            CBTSession.id == session_id,
            CBTSession.student_id == current_user["sub"],
        )
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Session not found")
    session, exam = row
    return {
        "session_id": session_id,
        "ai_locked": exam.ai_locked,
        "message": "AI is disabled during this exam." if exam.ai_locked else "AI is available.",
    }


# ── Proctoring ────────────────────────────────────────────────────────────────

class ProctorEventRequest(BaseModel):
    session_id: str
    event_type: str
    snapshot_url: Optional[str] = None
    metadata: Optional[dict] = None


@router.post("/proctor/event")
async def log_proctor_event(
    payload: ProctorEventRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    VALID_EVENTS = {"minimize_attempt", "screenshot_attempt", "tab_switch", "camera_lost", "camera_snapshot"}
    if payload.event_type not in VALID_EVENTS:
        raise HTTPException(status_code=400, detail=f"Invalid event_type. Use: {VALID_EVENTS}")
    log = ExamProctorLog(
        session_id=payload.session_id,
        student_id=current_user["sub"],
        event_type=payload.event_type,
        snapshot_url=payload.snapshot_url,
        extra_data=payload.metadata or {},
    )
    db.add(log)
    await db.flush()
    return {"logged": True, "event": payload.event_type}


@router.get("/proctor/sessions/{session_id}/logs")
async def get_proctor_logs(
    session_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(ExamProctorLog)
        .where(ExamProctorLog.session_id == session_id)
        .order_by(ExamProctorLog.created_at.asc())
    )
    logs = result.scalars().all()
    return [
        {"id": str(l.id), "student_id": str(l.student_id), "event_type": l.event_type,
         "snapshot_url": l.snapshot_url, "extra_data": l.extra_data, "at": l.created_at}
        for l in logs
    ]


@router.get("/proctor/exam/{exam_id}/active-students")
async def get_active_students(
    exam_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(CBTSession).where(
            CBTSession.exam_id == exam_id,
            CBTSession.submitted_at == None,  # noqa: E711
        )
    )
    sessions = result.scalars().all()
    return [{"session_id": str(s.id), "student_id": str(s.student_id), "started_at": s.started_at} for s in sessions]


# ── Teacher: Schedule School Exam ─────────────────────────────────────────────

@router.post("/school-exams", status_code=201)
async def teacher_create_school_exam(
    payload: CreateSchoolExamRequest,
    current_user: dict = Depends(require_teacher),
    db: AsyncSession = Depends(get_db),
):
    """Teacher schedules a proctored school exam with camera monitoring."""
    if not payload.questions:
        raise HTTPException(status_code=400, detail="At least one question required")
    if payload.scheduled_end <= payload.scheduled_start:
        raise HTTPException(status_code=400, detail="scheduled_end must be after scheduled_start")

    exam = CBTExam(
        title=payload.title,
        subject=payload.subject,
        exam_type="SCHOOL",
        duration_minutes=payload.duration_minutes,
        total_questions=len(payload.questions),
        created_by=current_user["sub"],
        is_published=True,
        is_school_exam=True,
        ai_locked=True,
        camera_required=True,
        block_minimize=True,
        scheduled_start=payload.scheduled_start,
        scheduled_end=payload.scheduled_end,
    )
    db.add(exam)
    await db.flush()

    for q in payload.questions:
        if q.correct_option.upper() not in ("A", "B", "C", "D"):
            raise HTTPException(status_code=400, detail="correct_option must be A/B/C/D")
        db.add(CBTQuestion(
            exam_id=exam.id,
            question_text=q.question_text,
            option_a=q.option_a, option_b=q.option_b,
            option_c=q.option_c, option_d=q.option_d,
            correct_option=q.correct_option.upper(),
            explanation=q.explanation,
            topic=q.topic,
        ))

    await db.flush()
    return _exam_summary(exam)
