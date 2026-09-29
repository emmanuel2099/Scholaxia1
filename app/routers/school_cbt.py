"""SCHOLAXIA — School CBT / Examination engine API (owner spec §1–§32).

Two connected parts, both server-authoritative (§30):

  /school-cbt/...          — School Management System (staff, tenant-scoped)
  /school-cbt/student/...  — Student CBT portal (reg number + access code)

Security rules enforced on EVERY request (deny-by-default):
  valid student → belongs to school → assigned to exam → exam belongs to
  school → exam available → attempt valid → not already submitted.

The backend is the ONLY authority for exam rules: it stores the question
order and option order per attempt (randomization mapping, §10), computes
the deadline server-side (§7), marks submissions server-side (§29), and
keeps scores hidden until the school publishes them (§22).
"""
import hashlib
import json
import secrets
import string
from datetime import datetime, timedelta
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import select, delete, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import require_school_staff
from app.core.datetime_utils import naive_utc_now
from app.core.security import decode_token, hash_password
from app.models.school_cbt import (
    EXAM_MODES,
    SchoolExQuestionBank,
    SchoolExQuestion,
    SchoolExam,
    SchoolExamQuestion,
    SchoolExamAssignment,
    SchoolExamAccessCode,
    SchoolExamAttempt,
    SchoolExamAnswer,
    SchoolExamDownload,
    SchoolExamSyncLog,
    SchoolExamResult,
    grade_from_percentage,
)
from app.models.user import User, UserRole, StudentProfile
from app.models.school_campus import SchoolCampus

router = APIRouter(prefix="/school-cbt", tags=["School CBT"])

STUDENT_TOKEN_TTL_HOURS = 18

# ── Brute-force protection (§13/§14): server-side counters per code ──────
LOGIN_MAX_FAILURES = 5
LOGIN_LOCK_MINUTES = 15


def _code_secret(code: str) -> str:
    """Constant-looking storage for access codes (staff can view them, but we
    never store the raw code as the only copy — hash enables lookup)."""
    return code.strip().upper()


# ═════════════════════════════════════════════════════════════════════════
# HELPERS — tenant scoping + authorization
# ═════════════════════════════════════════════════════════════════════════

def _staff_school_id(current_user: dict, school_id: Optional[str] = None) -> UUID:
    """Staff caller's tenant. Main admin must pass school_id explicitly."""
    sid = current_user.get("school_id") if current_user.get("role") == "school_admin" else school_id
    if not sid:
        raise HTTPException(status_code=400, detail="Select a school first")
    try:
        return UUID(str(sid))
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid school id")


async def _get_school_exam(db: AsyncSession, exam_id: str, school_id: UUID) -> SchoolExam:
    """Exam must exist AND belong to this school (spec §30 — server-side
    check on every request; never trust a client-supplied exam id alone)."""
    try:
        eid = UUID(str(exam_id))
    except ValueError:
        raise HTTPException(status_code=404, detail="Exam not found")
    exam = (await db.execute(select(SchoolExam).where(SchoolExam.id == eid))).scalar_one_or_none()
    if not exam or exam.school_id != school_id:
        raise HTTPException(status_code=404, detail="Exam not found")
    return exam


def _exam_row(exam: SchoolExam, question_count: int = 0, submission_count: int = 0) -> dict:
    return {
        "id": str(exam.id),
        "title": exam.title,
        "subject": exam.subject,
        "class_name": exam.class_name,
        "exam_type": exam.exam_type,
        "session": exam.session,
        "term": exam.term,
        "instructions": exam.instructions,
        "exam_mode": exam.exam_mode,
        "total_mark": exam.total_mark,
        "duration_minutes": exam.duration_minutes,
        "questions_to_display": exam.questions_to_display or question_count,
        "questions_to_answer": exam.questions_to_answer or question_count,
        "randomize_questions": bool(exam.randomize_questions),
        "randomize_options": bool(exam.randomize_options),
        "allow_review": bool(exam.allow_review),
        "allow_previous": bool(exam.allow_previous),
        "allow_flagging": bool(exam.allow_flagging),
        "exam_date": exam.exam_date.isoformat() if exam.exam_date else None,
        "scheduled_start": exam.scheduled_start.isoformat() if exam.scheduled_start else None,
        "scheduled_end": exam.scheduled_end.isoformat() if exam.scheduled_end else None,
        "max_attempts": exam.max_attempts or 1,
        "retake_student_ids": list(exam.retake_student_ids or []),
        "results_published": bool(exam.results_published),
        "status": exam.status,
        "is_published": bool(exam.is_published),
        "question_count": question_count,
        "submission_count": submission_count,
        "created_at": exam.created_at.isoformat() if exam.created_at else None,
    }


def _exam_window_open(exam: SchoolExam, now: datetime) -> bool:
    if exam.scheduled_start and now < exam.scheduled_start:
        return False
    if exam.scheduled_end and now > exam.scheduled_end:
        return False
    return True


async def _student_for_exam(db: AsyncSession, exam: SchoolExam, student_id: UUID) -> None:
    """Verify the student is actually assigned to this exam (spec §12/§30).

    Assignment = explicit assignment row OR class-list membership OR the
    exam has no restriction at all (whole school). Everything else → 403.
    """
    row = (
        await db.execute(
            select(SchoolExamAssignment.id).where(
                SchoolExamAssignment.exam_id == exam.id,
                SchoolExamAssignment.student_id == student_id,
            )
        )
    ).scalar_one_or_none()
    if row:
        return
    if exam.assigned_student_ids:
        listed = {str(x) for x in exam.assigned_student_ids}
        if str(student_id) in listed:
            return
        raise HTTPException(status_code=403, detail="You are not assigned to this examination")
    if exam.assigned_class_names:
        profile = (
            await db.execute(select(StudentProfile).where(StudentProfile.user_id == student_id))
        ).scalar_one_or_none()
        cls = (getattr(profile, "education_level", None) or "").upper() if profile else ""
        if cls and cls in {str(c).upper() for c in exam.assigned_class_names}:
            return
        raise HTTPException(status_code=403, detail="You are not assigned to this examination")
    # No restriction configured → whole school may take it.


def _exam_questions_available(exam: SchoolExam, questions: list[SchoolExamQuestion]) -> list[SchoolExamQuestion]:
    """§9 — questions to display vs to answer. Display ≤ bank available."""
    qs = list(questions)
    if exam.questions_to_display and exam.questions_to_display > 0:
        qs = qs[: exam.questions_to_display]
    return qs


async def _attempt_of(db: AsyncSession, attempt_id: str, student_id: str, exam_id: str) -> SchoolExamAttempt:
    """Attempt must belong to THIS student and THIS exam (spec §30 — blocks
    another student's attempt id even if guessed)."""
    try:
        aid = UUID(str(attempt_id))
    except ValueError:
        raise HTTPException(status_code=404, detail="Attempt not found")
    att = (await db.execute(select(SchoolExamAttempt).where(SchoolExamAttempt.id == aid))).scalar_one_or_none()
    if not att or str(att.student_id) != str(student_id) or str(att.exam_id) != str(exam_id):
        raise HTTPException(status_code=404, detail="Attempt not found")
    return att


async def _sync_log(
    db: AsyncSession,
    exam: SchoolExam,
    student_id,
    event: str,
    attempt_id=None,
    channel: str = "online",
    detail: dict | None = None,
) -> None:
    db.add(
        SchoolExamSyncLog(
            school_id=exam.school_id,
            exam_id=exam.id,
            attempt_id=attempt_id,
            student_id=student_id,
            event=event,
            channel=channel,
            detail=detail or {},
        )
    )


def _option_map_for(question: SchoolExamQuestion, option_order: dict | None) -> dict:
    """§10 — options randomized per attempt; mapping kept server-side.

    Display labels are ALWAYS positional A–D top-to-bottom (JAMB style, see
    the CBT mockup); randomization shuffles which CONTENT sits under each
    label. Marking maps the chosen label back through attempt.option_order.
    """
    base = [
        question.option_a,
        question.option_b,
        question.option_c,
        question.option_d,
    ]
    order = (option_order or {}).get(str(question.id))
    seq = base
    if order:
        try:
            seq = [base[i] for i in order]
        except Exception:
            seq = base
    return {"options": [{"label": "ABCD"[i], "text": txt} for i, txt in enumerate(seq)]}


def _map_answer_back(q: SchoolExamQuestion, chosen_label: str, option_order: dict | None) -> str:
    """Convert the label the student saw back to the CONTENT position letter
    that `correct_option` refers to. Without randomization, identity."""
    order = (option_order or {}).get(str(q.id))
    if not order:
        return (chosen_label or "").upper()
    try:
        # base index i holds the content letter chr(65+i); order[i] is which
        # base entry the student saw at display position i.
        base_pos = order["ABCD".index((chosen_label or "").upper())]
        return chr(65 + int(base_pos))
    except Exception:
        return (chosen_label or "").upper()


def _make_option_order(questions: list[SchoolExamQuestion], randomize: bool) -> dict:
    if not randomize:
        return {}
    order = {}
    for q in questions:
        perm = list(range(4))
        for i in range(3, 0, -1):
            j = secrets.randbelow(i + 1)
            perm[i], perm[j] = perm[j], perm[i]
        order[str(q.id)] = perm
    return order


# ═════════════════════════════════════════════════════════════════════════
# STAFF — Exam Bank / Question Bank (§2/§3)
# ═════════════════════════════════════════════════════════════════════════

class BankIn(BaseModel):
    school_id: Optional[str] = None
    name: str
    subject: str
    class_name: str
    description: Optional[str] = None


class BankQuestionIn(BaseModel):
    question_text: str
    option_a: str = ""
    option_b: str = ""
    option_c: str = ""
    option_d: str = ""
    correct_option: str = "A"
    question_type: str = "mcq"
    topic: Optional[str] = None
    sub_topic: Optional[str] = None
    marks: int = 1
    difficulty: str = "medium"
    explanation: Optional[str] = None
    year: Optional[str] = None
    tags: list[str] = []
    image_url: Optional[str] = None
    status: str = "active"


@router.get("/banks")
async def list_banks(
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    sid = _staff_school_id(current_user, school_id)
    rows = (
        await db.execute(
            select(SchoolExQuestionBank)
            .where(SchoolExQuestionBank.school_id == sid)
            .order_by(SchoolExQuestionBank.created_at.desc())
        )
    ).scalars().all()
    counts = (
        await db.execute(
            select(SchoolExQuestion.bank_id, func.count(SchoolExQuestion.id))
            .where(SchoolExQuestion.school_id == sid)
            .group_by(SchoolExQuestion.bank_id)
        )
    ).all()
    cmap = {str(b): int(c) for b, c in counts}
    return {
        "banks": [
            {
                "id": str(b.id),
                "name": b.name,
                "subject": b.subject,
                "class_name": b.class_name,
                "description": b.description,
                "status": b.status,
                "question_count": cmap.get(str(b.id), 0),
                "created_at": b.created_at.isoformat() if b.created_at else None,
            }
            for b in rows
        ]
    }


@router.post("/banks", status_code=201)
async def create_bank(
    payload: BankIn,
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    sid = _staff_school_id(current_user, payload.school_id)
    bank = SchoolExQuestionBank(
        school_id=sid,
        name=payload.name.strip(),
        subject=payload.subject.strip(),
        class_name=payload.class_name.strip().upper(),
        description=(payload.description or "").strip() or None,
        created_by=current_user["sub"],
    )
    db.add(bank)
    await db.flush()
    return {"id": str(bank.id), "name": bank.name, "question_count": 0}


class BankImportIn(BaseModel):
    """Reference pattern — questions are UPLOADED per class. Defaults applied
    to every question in the file; class/subject feed the bank's identity."""
    class_name: str
    subject: str
    name: Optional[str] = None      # bank name; defaults to "<Subject> <Class> Bank"
    topic: Optional[str] = None
    marks: int = 1


@router.post("/banks/import", status_code=201)
async def import_bank_questions(
    file: UploadFile = File(...),
    class_name: str = Form(...),
    subject: str = Form(...),
    name: Optional[str] = Form(None),
    topic: Optional[str] = Form(None),
    marks: int = Form(1),
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """Upload a question file (.csv / .json / .pdf) into the school's question
    bank for ONE class + subject — exactly like the reference dashboard's
    "Upload New Questions" flow (bank per class, e.g. JS1/JS2/.../SS3).

    Creates the bank if the school has none for that class+subject; appends to
    the existing one otherwise. Returns per-question parse issues, if any."""
    from app.services.cbt_import import parse_cbt_file

    sid = _staff_school_id(current_user, school_id)
    cls = (class_name or "").strip().upper()
    subj = (subject or "").strip()
    if not cls or not subj:
        raise HTTPException(status_code=400, detail="class_name and subject are required")

    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="The uploaded file is empty")
    stem = (file.filename or "questions").rsplit(".", 1)[0].replace("_", " ").replace("-", " ").strip() or subj
    defaults = {
        "title": (name or "").strip() or f"{subj} {cls}",
        "subject": subj,
        "duration_minutes": 60,
        "exam_type": "SCHOOL",
        "is_published": True,
    }
    name_lower = (file.filename or "").lower()
    flagged = 0
    try:
        parsed = parse_cbt_file(file.filename or "", content, defaults)
    except ValueError as exc:
        # Notes-style PDFs usually fail the strict parser (no marked answers,
        # low confidence). The question bank is a DRAFT store — accept the
        # extraction and flag incomplete answers instead of rejecting the
        # whole upload; the school fixes the answer key in the bank.
        if not (name_lower.endswith(".pdf") or content[:5] == b"%PDF-"):
            raise HTTPException(status_code=400, detail=str(exc))
        from app.services.cbt_pdf_parser import parse_pdf_questions

        result = parse_pdf_questions(content)
        extracted = result["questions"]
        if not extracted:
            raise HTTPException(status_code=400, detail=str(exc))
        flagged = sum(1 for q in extracted if not str(q.get("correct_option") or "").strip())
        parsed = [
            {
                "title": defaults["title"],
                "subject": subj,
                "duration_minutes": 60,
                "questions": [
                    {
                        "question_text": q.get("question_text"),
                        "option_a": q.get("option_a"),
                        "option_b": q.get("option_b"),
                        "option_c": q.get("option_c"),
                        "option_d": q.get("option_d"),
                        "correct_option": q.get("correct_option") or "A",
                    }
                    for q in extracted
                ],
            }
        ]

    qs = []
    for item in parsed:
        for q in item.get("questions") or []:
            if not str(q.get("question_text") or "").strip():
                continue
            opt = str(q.get("correct_option") or "A").upper()[:1]
            qs.append(
                {
                    "question_text": str(q.get("question_text"))[:4000],
                    "option_a": str(q.get("option_a") or "")[:1000],
                    "option_b": str(q.get("option_b") or "")[:1000],
                    "option_c": str(q.get("option_c") or "")[:1000],
                    "option_d": str(q.get("option_d") or "")[:1000],
                    "correct_option": opt if opt in ("A", "B", "C", "D") else "A",
                    "topic": (str(q.get("topic") or topic or "").strip() or None),
                    "marks": int(q.get("marks") or marks or 1),
                }
            )
    if not qs:
        raise HTTPException(status_code=400, detail="No usable questions found in the file")

    # One bank per class+subject — reuse it, or create it on first upload.
    bank = (
        await db.execute(
            select(SchoolExQuestionBank).where(
                SchoolExQuestionBank.school_id == sid,
                func.upper(SchoolExQuestionBank.class_name) == cls,
                func.lower(SchoolExQuestionBank.subject) == subj.lower(),
            )
        )
    ).scalars().first()
    if not bank:
        bank = SchoolExQuestionBank(
            school_id=sid,
            name=(name or "").strip() or f"{subj} {cls} Bank",
            subject=subj,
            class_name=cls,
            created_by=current_user["sub"],
        )
        db.add(bank)
        await db.flush()

    for q in qs:
        db.add(
            SchoolExQuestion(
                school_id=sid,
                bank_id=bank.id,
                question_text=q["question_text"],
                option_a=q["option_a"],
                option_b=q["option_b"],
                option_c=q["option_c"],
                option_d=q["option_d"],
                correct_option=q["correct_option"],
                question_type="mcq",
                topic=q["topic"],
                marks=max(1, min(int(q["marks"]), 100)),
            )
        )
    await db.flush()
    bank_total = (
        await db.execute(
            select(func.count(SchoolExQuestion.id)).where(SchoolExQuestion.bank_id == bank.id)
        )
    ).scalar_one()
    return {
        "ok": True,
        "bank_id": str(bank.id),
        "bank_name": bank.name,
        "class_name": bank.class_name,
        "added": len(qs),
        "flagged": flagged,
        "bank_total": int(bank_total or 0),
    }


@router.delete("/banks/{bank_id}")
async def delete_bank(
    bank_id: str,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    sid = _staff_school_id(current_user, school_id)
    bank = (await db.execute(select(SchoolExQuestionBank).where(SchoolExQuestionBank.id == bank_id))).scalar_one_or_none()
    if not bank or bank.school_id != sid:
        raise HTTPException(status_code=404, detail="Question bank not found")
    await db.execute(delete(SchoolExQuestion).where(SchoolExQuestion.bank_id == bank.id))
    await db.delete(bank)
    await db.flush()
    return {"ok": True}


@router.get("/banks/{bank_id}/questions")
async def list_bank_questions(
    bank_id: str,
    topic: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    bank = (await db.execute(select(SchoolExQuestionBank).where(SchoolExQuestionBank.id == bank_id))).scalar_one_or_none()
    if not bank or bank.school_id != _staff_school_id(current_user):
        raise HTTPException(status_code=404, detail="Question bank not found")
    q = select(SchoolExQuestion).where(SchoolExQuestion.bank_id == bank.id).order_by(SchoolExQuestion.created_at.desc() if hasattr(SchoolExQuestion, "created_at") else SchoolExQuestion.question_text)
    if topic:
        q = q.where(SchoolExQuestion.topic == topic)
    rows = (await db.execute(q)).scalars().all()
    return {
        "bank": {"id": str(bank.id), "name": bank.name, "subject": bank.subject, "class_name": bank.class_name},
        "questions": [
            {
                "id": str(r.id),
                "question_text": r.question_text,
                "option_a": r.option_a,
                "option_b": r.option_b,
                "option_c": r.option_c,
                "option_d": r.option_d,
                "correct_option": r.correct_option,
                "question_type": r.question_type,
                "topic": r.topic,
                "sub_topic": r.sub_topic,
                "marks": r.marks,
                "difficulty": r.difficulty,
                "explanation": r.explanation,
                "year": r.year,
                "tags": list(r.tags or []),
                "status": r.status,
            }
            for r in rows
        ],
    }


@router.post("/banks/{bank_id}/questions", status_code=201)
async def add_bank_questions(
    bank_id: str,
    payload: list[BankQuestionIn],
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    bank = (await db.execute(select(SchoolExQuestionBank).where(SchoolExQuestionBank.id == bank_id))).scalar_one_or_none()
    if not bank or bank.school_id != _staff_school_id(current_user):
        raise HTTPException(status_code=404, detail="Question bank not found")
    if not payload:
        raise HTTPException(status_code=400, detail="Add at least one question")
    made = []
    for q in payload[:500]:
        copt = (q.correct_option or "A").upper().replace(" ", "")
        if q.question_type == "mcq" and any(ch not in "ABCD" for ch in copt):
            raise HTTPException(status_code=400, detail="correct_option must be letters A–D (e.g. A or AC)")
        row = SchoolExQuestion(
            bank_id=bank.id,
            school_id=bank.school_id,
            question_text=q.question_text.strip(),
            option_a=(q.option_a or "").strip(),
            option_b=(q.option_b or "").strip(),
            option_c=(q.option_c or "").strip(),
            option_d=(q.option_d or "").strip(),
            correct_option=copt,
            question_type=q.question_type if q.question_type in ("mcq", "true_false", "multi_select", "theory") else "mcq",
            topic=(q.topic or "").strip() or None,
            sub_topic=(q.sub_topic or "").strip() or None,
            marks=max(1, min(int(q.marks or 1), 100)),
            difficulty=q.difficulty if q.difficulty in ("easy", "medium", "hard") else "medium",
            explanation=(q.explanation or "").strip() or None,
            year=(q.year or "").strip() or None,
            tags=[t.strip() for t in (q.tags or []) if str(t).strip()],
            image_url=(q.image_url or "").strip() or None,
            status=q.status if q.status in ("draft", "active", "archived") else "active",
        )
        db.add(row)
        made.append(row)
    await db.flush()
    return {"added": len(made), "ids": [str(r.id) for r in made]}


@router.delete("/banks/{bank_id}/questions/{question_id}")
async def delete_bank_question(
    bank_id: str,
    question_id: str,
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    bank = (await db.execute(select(SchoolExQuestionBank).where(SchoolExQuestionBank.id == bank_id))).scalar_one_or_none()
    if not bank or bank.school_id != _staff_school_id(current_user):
        raise HTTPException(status_code=404, detail="Question bank not found")
    row = (await db.execute(select(SchoolExQuestion).where(SchoolExQuestion.id == question_id))).scalar_one_or_none()
    if not row or row.bank_id != bank.id:
        raise HTTPException(status_code=404, detail="Question not found")
    await db.delete(row)
    await db.flush()
    return {"ok": True}


# ═════════════════════════════════════════════════════════════════════════
# STAFF — Create / manage examinations (§4–§12, §25–§28)
# ═════════════════════════════════════════════════════════════════════════

class ExamQuestionIn(BankQuestionIn):
    """A question written directly into the exam (bank-optional)."""


class ExamCreateIn(BaseModel):
    school_id: Optional[str] = None
    title: str
    subject: str
    class_name: str
    exam_type: str = "SCHOOL"
    session: Optional[str] = None
    term: Optional[str] = None
    instructions: Optional[str] = None
    exam_mode: str = "ONLINE"          # ONLINE / OFFLINE / HYBRID (§5)
    total_mark: int = 100              # §6 — school decides, never assumed
    duration_minutes: int = 60         # §7
    questions_to_display: int = 0      # §8/§9
    questions_to_answer: int = 0
    randomize_questions: bool = False  # §10
    randomize_options: bool = False
    allow_review: bool = True
    allow_previous: bool = True
    allow_flagging: bool = True
    bank_ids: list[str] = []           # §11 — source banks
    selected_question_ids: list[str] = []  # §11 Option A — manual
    topic_picks: list[dict] = []       # §11 Option B — [{topic, count}]
    auto_pick_count: int = 0           # §11 Option C — random N
    questions: list[ExamQuestionIn] = []   # hand-typed questions
    exam_date: Optional[datetime] = None   # §26 item 5
    scheduled_start: Optional[datetime] = None
    scheduled_end: Optional[datetime] = None
    assigned_student_ids: list[str] = []   # §26 item 6
    assigned_class_names: list[str] = []
    generate_codes: bool = True            # §26 item 7
    access_code_expires_at: Optional[datetime] = None
    max_attempts: int = 1
    publish: bool = False                  # §26 item 8 — Save Draft vs Publish


def _pick_bank_questions(
    bank_qs: list[SchoolExQuestion],
    selected_ids: list[str],
    topic_picks: list[dict],
    auto_pick: int,
) -> list[SchoolExQuestion]:
    """§11 — manual / by-topic / random selection from the Exam Bank."""
    picked: list[SchoolExQuestion] = []
    seen: set = set()

    def add(items: list[SchoolExQuestion]):
        for it in items:
            if it.id not in seen:
                seen.add(it.id)
                picked.append(it)

    if selected_ids:
        sel = {str(s) for s in selected_ids}
        add([q for q in bank_qs if str(q.id) in sel])
    for tp in topic_picks or []:
        topic = str(tp.get("topic") or "").strip()
        count = int(tp.get("count") or 0)
        pool = [q for q in bank_qs if (q.topic or "").strip().lower() == topic.lower() and q.id not in seen]
        if count and len(pool) > count:
            idx = secrets.SystemRandom().sample(range(len(pool)), count)
            pool = [pool[i] for i in idx]
        add(pool)
    remaining = [q for q in bank_qs if q.id not in seen]
    if auto_pick and len(remaining) > auto_pick:
        idx = secrets.SystemRandom().sample(range(len(remaining)), auto_pick)
        remaining = [remaining[i] for i in idx]
    add(remaining[:auto_pick] if auto_pick else remaining)
    return picked


@router.post("/exams", status_code=201)
async def create_exam(
    payload: ExamCreateIn,
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    sid = _staff_school_id(current_user, payload.school_id)
    mode = (payload.exam_mode or "ONLINE").upper()
    if mode not in EXAM_MODES:
        raise HTTPException(status_code=400, detail="exam_mode must be ONLINE, OFFLINE or HYBRID")

    exam = SchoolExam(
        school_id=sid,
        title=payload.title.strip(),
        subject=payload.subject.strip(),
        class_name=payload.class_name.strip().upper(),
        exam_type=(payload.exam_type or "SCHOOL").strip().upper(),
        session=(payload.session or "").strip() or None,
        term=(payload.term or "").strip() or None,
        instructions=(payload.instructions or "").strip() or None,
        exam_mode=mode,
        total_mark=max(1, min(int(payload.total_mark or 100), 1000)),
        duration_minutes=max(5, min(int(payload.duration_minutes or 60), 600)),
        questions_to_display=max(0, int(payload.questions_to_display or 0)),
        questions_to_answer=max(0, int(payload.questions_to_answer or 0)),
        randomize_questions=bool(payload.randomize_questions),
        randomize_options=bool(payload.randomize_options),
        allow_review=bool(payload.allow_review),
        allow_previous=bool(payload.allow_previous),
        allow_flagging=bool(payload.allow_flagging),
        bank_ids=[str(b) for b in payload.bank_ids if str(b).strip()],
        selected_question_ids=[str(q) for q in payload.selected_question_ids if str(q).strip()],
        auto_pick_count=max(0, int(payload.auto_pick_count or 0)),
        exam_date=payload.exam_date,
        scheduled_start=payload.scheduled_start,
        scheduled_end=payload.scheduled_end,
        assigned_student_ids=[str(s) for s in payload.assigned_student_ids if str(s).strip()] or None,
        assigned_class_names=[str(c).strip().upper() for c in payload.assigned_class_names if str(c).strip()] or None,
        access_code_expires_at=payload.access_code_expires_at,
        max_attempts=max(1, min(int(payload.max_attempts or 1), 10)),
        status="draft" if not payload.publish else "published",
        is_published=bool(payload.publish),
        created_by=current_user["sub"],
    )
    db.add(exam)
    await db.flush()

    # Source questions: hand-typed + bank selection (§11)
    rows: list[tuple] = []  # (text, a,b,c,d, correct, type, topic, marks, bank_q_id)
    for q in payload.questions:
        if not q.question_text.strip():
            continue
        copt = (q.correct_option or "A").upper().replace(" ", "")
        rows.append((
            q.question_text.strip(), (q.option_a or "").strip(), (q.option_b or "").strip(),
            (q.option_c or "").strip(), (q.option_d or "").strip(), copt,
            q.question_type or "mcq", (q.topic or "").strip() or None,
            max(1, min(int(q.marks or 1), 100)), None,
        ))
    if payload.bank_ids:
        bq = (
            await db.execute(
                select(SchoolExQuestion).where(
                    SchoolExQuestion.bank_id.in_([UUID(b) for b in payload.bank_ids if b]),
                    SchoolExQuestion.school_id == sid,
                    SchoolExQuestion.status == "active",
                )
            )
        ).scalars().all()
        for q in _pick_bank_questions(list(bq), payload.selected_question_ids, payload.topic_picks, payload.auto_pick_count):
            rows.append((
                q.question_text, q.option_a, q.option_b, q.option_c, q.option_d, q.correct_option,
                q.question_type, q.topic, q.marks, q.id,
            ))
    if not rows:
        raise HTTPException(status_code=400, detail="Add questions — type them or pick from the Exam Bank")

    for i, (txt, a, b, c, d, copt, qtype, topic, marks, bank_qid) in enumerate(rows):
        db.add(
            SchoolExamQuestion(
                exam_id=exam.id,
                school_id=sid,
                bank_question_id=bank_qid,
                question_text=txt[:4000],
                option_a=a[:1000],
                option_b=b[:1000],
                option_c=c[:1000],
                option_d=d[:1000],
                correct_option=copt or "A",
                question_type=qtype if qtype in ("mcq", "true_false", "multi_select", "theory") else "mcq",
                topic=topic,
                marks=marks,
                position=i,
            )
        )
    await db.flush()

    # §12 — materialize assignments; §13 — access codes.
    assigned = await _materialize_assignments(db, exam, sid)
    codes_made = 0
    if payload.generate_codes:
        codes_made = await _ensure_access_codes(db, exam)

    await db.flush()
    return {
        "id": str(exam.id),
        "title": exam.title,
        "status": exam.status,
        "question_count": len(rows),
        "students_assigned": assigned,
        "access_codes_created": codes_made,
    }


async def _materialize_assignments(db: AsyncSession, exam: SchoolExam, sid: UUID) -> int:
    """§12 — explicit student rows; class lists resolve at login time but we
    also create rows for students already in those classes."""
    count = 0
    existing = {
        str(r) for r in (
            await db.execute(
                select(SchoolExamAssignment.student_id).where(SchoolExamAssignment.exam_id == exam.id)
            )
        ).scalars().all()
    }
    for s in exam.assigned_student_ids or []:
        try:
            suid = UUID(str(s))
        except ValueError:
            continue
        if str(suid) in existing:
            continue
        db.add(SchoolExamAssignment(school_id=sid, exam_id=exam.id, student_id=suid, subject=exam.subject))
        existing.add(str(suid))
        count += 1
    for cls in exam.assigned_class_names or []:
        students = (
            await db.execute(
                select(User.id)
                .join(StudentProfile, StudentProfile.user_id == User.id)
                .where(
                    User.school_id == sid,
                    User.role == UserRole.student,
                    func.upper(StudentProfile.education_level) == str(cls).upper(),
                )
            )
        ).scalars().all()
        for suid in students:
            if str(suid) in existing:
                continue
            db.add(
                SchoolExamAssignment(
                    school_id=sid, exam_id=exam.id, student_id=suid,
                    class_name=str(cls).upper(), subject=exam.subject,
                )
            )
            existing.add(str(suid))
            count += 1
    return count


async def _ensure_access_codes(db: AsyncSession, exam: SchoolExam) -> int:
    """§13 — one REG NUMBER + access code per assigned student."""
    students = (
        await db.execute(select(SchoolExamAssignment.student_id).where(SchoolExamAssignment.exam_id == exam.id))
    ).scalars().all()
    have = {
        str(r) for r in (
            await db.execute(select(SchoolExamAccessCode.student_id).where(SchoolExamAccessCode.exam_id == exam.id))
        ).scalars().all()
    }
    made = 0
    for suid in students:
        if str(suid) in have:
            continue
        reg = await _reg_number_for(db, exam.school_id, suid)
        db.add(
            SchoolExamAccessCode(
                school_id=exam.school_id,
                exam_id=exam.id,
                student_id=suid,
                reg_number=reg,
                access_code=_new_access_code(),
                expires_at=exam.access_code_expires_at,
            )
        )
        made += 1
    return made


async def _reg_number_for(db: AsyncSession, school_id: UUID, student_id) -> str:
    """Prefer the school's own student id; otherwise mint SCHX/26/544560."""
    profile = (
        await db.execute(select(StudentProfile).where(StudentProfile.user_id == student_id))
    ).scalar_one_or_none()
    if profile and getattr(profile, "school_student_id", None):
        return profile.school_student_id
    year = datetime.utcnow().strftime("%y")
    while True:
        cand = f"SCHX/{year}/{secrets.randbelow(900000) + 100000}"
        clash = (
            await db.execute(
                select(SchoolExamAccessCode.id).where(
                    SchoolExamAccessCode.reg_number == cand,
                    SchoolExamAccessCode.school_id == school_id,
                )
            )
        ).scalar_one_or_none()
        if not clash:
            return cand


def _new_access_code() -> str:
    alphabet = string.ascii_uppercase + string.digits
    p1 = "".join(secrets.choice(alphabet) for _ in range(4))
    p2 = "".join(secrets.choice(alphabet) for _ in range(4))
    return f"SCH-{p1}-{p2}"


class ExamPatchIn(BaseModel):
    """§28 — publishing locks the critical config; schedule/status stay editable."""
    scheduled_start: Optional[datetime] = None
    scheduled_end: Optional[datetime] = None
    exam_date: Optional[datetime] = None
    is_published: Optional[bool] = None
    status: Optional[str] = None
    results_published: Optional[bool] = None


class ScheduleIn(BaseModel):
    """Reference pattern — scheduling is a SEPARATE step from question upload.
    Pick the class, set the date/time + duration, save."""
    exam_date: Optional[datetime] = None
    scheduled_start: Optional[datetime] = None
    scheduled_end: Optional[datetime] = None
    duration_minutes: Optional[int] = Field(default=None, ge=5, le=300)
    venue: Optional[str] = Field(default=None, max_length=120)


@router.get("/roster/{class_name}")
async def class_roster(
    class_name: str,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """Registered Students in Selected Class (reference Schedule tab):
    every student in the class, which of the class's exams they are assigned
    to, their reg number + code status, and their submission counts."""
    sid = _staff_school_id(current_user, school_id)
    cls = (class_name or "").strip().upper()
    students = (
        await db.execute(
            select(User)
            .join(StudentProfile, StudentProfile.user_id == User.id)
            .where(
                User.school_id == sid,
                User.role == UserRole.student,
                func.upper(StudentProfile.education_level) == cls,
            )
            .order_by(User.full_name)
        )
    ).scalars().all()
    class_exams = (
        await db.execute(
            select(SchoolExam)
            .where(
                SchoolExam.school_id == sid,
                func.upper(SchoolExam.class_name) == cls,
            )
            .order_by(SchoolExam.created_at.desc())
        )
    ).scalars().all()
    exam_ids = [e.id for e in class_exams]
    assigns: dict[str, set[str]] = {str(su.id): set() for su in students}
    codes: dict[str, SchoolExamAccessCode] = {}
    subs: dict[str, int] = {}
    if exam_ids:
        for a in (
            await db.execute(
                select(SchoolExamAssignment).where(
                    SchoolExamAssignment.exam_id.in_(exam_ids)
                )
            )
        ).scalars().all():
            key = str(a.student_id)
            if key in assigns:
                assigns[key].add(str(a.exam_id))
        for c in (
            await db.execute(
                select(SchoolExamAccessCode).where(SchoolExamAccessCode.exam_id.in_(exam_ids))
            )
        ).scalars().all():
            codes.setdefault(str(c.student_id), c)  # first code wins (per exam)
        for exam_id, cnt in (
            await db.execute(
                select(SchoolExamAttempt.student_id, func.count(SchoolExamAttempt.id))
                .where(
                    SchoolExamAttempt.exam_id.in_(exam_ids),
                    SchoolExamAttempt.submitted_at != None,  # noqa: E711
                )
                .group_by(SchoolExamAttempt.student_id)
            )
        ).all():
            subs[str(exam_id)] = int(cnt)
    subjects_by_student: dict[str, list[str]] = {}
    for su in students:
        subjects_by_student[str(su.id)] = sorted(
            {e.subject for e in class_exams if str(e.id) in assigns[str(su.id)]}
        )
    return {
        "class_name": cls,
        "exams": [
            {"id": str(e.id), "subject": e.subject, "title": e.title, "is_published": bool(e.is_published)}
            for e in class_exams
        ],
        "students": [
            {
                "student_id": str(su.id),
                "full_name": su.full_name,
                "class_name": cls,
                "subjects_registered": subjects_by_student[str(su.id)],
                "exam_count": len(assigns[str(su.id)]),
                "exams_taken": int(subs.get(str(su.id), 0)),
                "reg_number": (codes.get(str(su.id)).reg_number if codes.get(str(su.id)) else None),
                "has_code": bool(codes.get(str(su.id))),
            }
            for su in students
        ],
    }


@router.get("/students/register")
async def register_form_options(
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """Dropdown data for the Register Student form: class categories
    (Junior/Senior), classes and the subjects prepared per class."""
    sid = _staff_school_id(current_user, school_id)
    exams = (
        await db.execute(select(SchoolExam).where(SchoolExam.school_id == sid))
    ).scalars().all()
    classes: dict[str, set[str]] = {}
    for e in exams:
        cls = (e.class_name or "").strip().upper()
        if cls:
            classes.setdefault(cls, set()).add(e.subject)
    # Merge the school's own registries (Classes tab / Subjects tab) so the
    # dropdowns are NEVER empty just because no exam exists yet.
    campus = (
        await db.execute(select(SchoolCampus).where(SchoolCampus.id == sid))
    ).scalar_one_or_none()
    reg_classes = [
        str((c.get("name") if isinstance(c, dict) else c) or "").strip().upper()
        for c in (getattr(campus, "portal_classes", None) or [])
    ]
    reg_subjects = [
        str((s.get("name") if isinstance(s, dict) else s) or "").strip()
        for s in (getattr(campus, "portal_subjects", None) or [])
    ]
    for cls in filter(None, reg_classes):
        classes.setdefault(cls, set()).update(x for x in reg_subjects if x)
    # Fallback 2 — classes that actually have students; subjects already in
    # the question bank. Guarantees usable dropdowns for a fresh school.
    for (cls,) in (
        await db.execute(
            select(func.upper(StudentProfile.education_level))
            .join(User, User.id == StudentProfile.user_id)
            .where(User.school_id == sid, User.role == UserRole.student)
            .distinct()
        )
    ).all():
        if cls:
            classes.setdefault(cls, set())
    for b in (
        await db.execute(
            select(SchoolExQuestionBank).where(SchoolExQuestionBank.school_id == sid)
        )
    ).scalars().all():
        if b.class_name:
            classes.setdefault(b.class_name.upper(), set()).add(b.subject)
    cats: dict[str, list[str]] = {"junior": [], "senior": [], "other": []}
    for cls in sorted(classes):
        if cls.startswith("JS"):
            cats["junior"].append(cls)
        elif cls.startswith("SS"):
            cats["senior"].append(cls)
        else:
            cats["other"].append(cls)
    return {
        "categories": [
            {"id": "junior", "name": "Junior Secondary", "classes": cats["junior"]},
            {"id": "senior", "name": "Senior Secondary", "classes": cats["senior"]},
            {"id": "other", "name": "Other Classes", "classes": cats["other"]},
        ],
        "class_subjects": {cls: sorted(subs) for cls, subs in classes.items()},
    }


class RegisterStudentIn(BaseModel):
    """Reference 'Register Student for Exam' form — names, class, subject.
    Registration Number + Access Code are ALWAYS generated server-side."""
    first_name: str = Field(min_length=1, max_length=80)
    middle_name: Optional[str] = Field(default=None, max_length=80)
    surname: str = Field(min_length=1, max_length=80)
    class_name: str = Field(min_length=1, max_length=40)
    subject: str = Field(min_length=1, max_length=120)  # subject name or "ALL"


@router.post("/students/register", status_code=201)
async def register_exam_student(
    payload: RegisterStudentIn,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """Register a student for exams (reference flow): creates the student,
    assigns them to the class+subject exam(s) and issues their Registration
    Number + Access Code immediately."""
    sid = _staff_school_id(current_user, school_id)
    full = " ".join(
        x for x in [payload.first_name.strip(), (payload.middle_name or "").strip(), payload.surname.strip()] if x
    )
    cls = payload.class_name.strip().upper()
    # Exam-scoped students never log into the main app; email is a unique
    # placeholder (they sign in with REG NUMBER + ACCESS CODE, §14).
    while True:
        email = f"exam.{secrets.token_hex(6).lower()}@students.scholaxia.local"
        if (await db.execute(select(User.id).where(User.email == email))).scalar_one_or_none() is None:
            break
    user = User(
        email=email,
        hashed_password=hash_password(secrets.token_urlsafe(12)),
        full_name=full[:120],
        role=UserRole.student,
        is_verified=True,
        is_active=True,
        school_id=sid,
    )
    db.add(user)
    await db.flush()
    db.add(StudentProfile(user_id=user.id, education_level=cls))
    await db.flush()

    q = select(SchoolExam).where(
        SchoolExam.school_id == sid,
        func.upper(SchoolExam.class_name) == cls,
    )
    if payload.subject.strip().upper() != "ALL":
        q = q.where(func.lower(SchoolExam.subject) == payload.subject.strip().lower())
    exams = (await db.execute(q)).scalars().all()
    if not exams:
        raise HTTPException(
            status_code=400,
            detail=f"No examination found for {cls} / {payload.subject} — prepare it under Exam Settings first",
        )
    have = {
        str(r)
        for r in (
            await db.execute(
                select(SchoolExamAssignment.exam_id).where(
                    SchoolExamAssignment.student_id == user.id,
                    SchoolExamAssignment.exam_id.in_([e.id for e in exams]),
                )
            )
        ).scalars().all()
    }
    for e in exams:
        if str(e.id) in have:
            continue
        db.add(
            SchoolExamAssignment(
                school_id=sid, exam_id=e.id, student_id=user.id,
                class_name=cls, subject=e.subject,
            )
        )
        await _ensure_access_codes(db, e)
    await db.flush()
    code = (
        await db.execute(
            select(SchoolExamAccessCode)
            .where(SchoolExamAccessCode.student_id == user.id)
            .order_by(SchoolExamAccessCode.created_at.desc())
        )
    ).scalars().first()
    return {
        "student_id": str(user.id),
        "full_name": user.full_name,
        "class_name": cls,
        "exams_assigned": len(exams),
        "subjects": sorted({e.subject for e in exams}),
        "reg_number": code.reg_number if code else None,
        "access_code": code.access_code if code else None,
    }


@router.get("/exam-students")
async def exam_students_aggregate(
    class_name: Optional[str] = None,
    subject: Optional[str] = None,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """Reference 'Manage Exam Students' table across ALL exams: Reg Number,
    Full Name, Class, Subject, Access Code, Status — filterable."""
    sid = _staff_school_id(current_user, school_id)
    q = (
        select(SchoolExamAccessCode, SchoolExam, User)
        .join(SchoolExam, SchoolExam.id == SchoolExamAccessCode.exam_id)
        .join(User, User.id == SchoolExamAccessCode.student_id)
        .where(SchoolExam.school_id == sid)
        .order_by(SchoolExamAccessCode.reg_number)
    )
    if class_name and str(class_name).strip().upper() != "ALL":
        q = q.where(func.upper(SchoolExam.class_name) == str(class_name).strip().upper())
    if subject and str(subject).strip().upper() != "ALL":
        q = q.where(func.lower(SchoolExam.subject) == str(subject).strip().lower())
    rows = (await db.execute(q)).all()
    now = naive_utc_now()
    out = []
    for code, exam, user in rows:
        out.append(
            {
                "student_id": str(user.id),
                "exam_id": str(exam.id),
                "full_name": user.full_name,
                "class_name": (exam.class_name or "").upper(),
                "subject": exam.subject,
                "reg_number": code.reg_number,
                "access_code": code.access_code,
                "exam_taken": bool(code.is_used),
                "locked": bool(code.locked_until and code.locked_until > now),
                "status": "used" if code.is_used else ("locked" if code.locked_until and code.locked_until > now else "pending"),
            }
        )
    return {"students": out}


@router.get("/retake-lookup/{reg_number}")
async def retake_lookup(
    reg_number: str,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """Reference 'Grant Exam Retake': type a registration number → fetch the
    student's exams + scores → grant the retake on any of them."""
    sid = _staff_school_id(current_user, school_id)
    reg = (reg_number or "").strip().upper()
    rows = (
        await db.execute(
            select(SchoolExamAccessCode, SchoolExam, User)
            .join(SchoolExam, SchoolExam.id == SchoolExamAccessCode.exam_id)
            .join(User, User.id == SchoolExamAccessCode.student_id)
            .where(
                SchoolExam.school_id == sid,
                func.upper(func.trim(SchoolExamAccessCode.reg_number)) == reg,
            )
            .order_by(SchoolExam.created_at.desc())
        )
    ).all()
    out = []
    for code, exam, user in rows:
        res = (
            await db.execute(
                select(SchoolExamResult).where(
                    SchoolExamResult.exam_id == exam.id,
                    SchoolExamResult.student_id == user.id,
                )
            )
        ).scalar_one_or_none()
        out.append(
            {
                "student_id": str(user.id),
                "exam_id": str(exam.id),
                "student_name": user.full_name,
                "class_name": (exam.class_name or "").upper(),
                "subject": exam.subject,
                "submitted": bool(code.is_used),
                "score": (res.final_score if res else None),
                "total_mark": (res.total_mark if res else None),
                "percentage": (res.percentage if res else None),
                "grade": (res.grade if res else None),
            }
        )
    return {"matches": out}


class ScheduleSaveIn(BaseModel):
    """Reference 'Exam Schedule Management' — the schedule IS the exam setup.
    One slot per class+subject: subjects, question count, duration, start."""
    class_category: Optional[str] = None
    class_name: str = Field(min_length=1, max_length=40)
    subjects: list[str] = Field(min_length=1)
    question_count: int = Field(ge=1, le=200)
    duration_minutes: int = Field(ge=1, le=300)
    starts_at: datetime
    total_mark: int = Field(default=100, ge=1)


@router.post("/schedule/save")
async def save_schedule(
    payload: ScheduleSaveIn,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """Save the exam schedule for a class (reference semantics).

    Creates (or updates) one published exam PER SUBJECT with the given
    question count / duration / start time. Subjects that were scheduled
    before but left out now are removed (like the reference's clear+rewrite
    of the class schedule document). Students of the class see the exams
    from their window; questions must exist in the per-class bank.
    """
    sid = _staff_school_id(current_user, school_id)
    cls = payload.class_name.strip().upper()
    want = {s.strip() for s in payload.subjects if s.strip()}
    if not want:
        raise HTTPException(status_code=400, detail="Select at least one subject")
    start = payload.starts_at
    now = naive_utc_now()

    exams = (
        await db.execute(
            select(SchoolExam).where(
                SchoolExam.school_id == sid,
                func.upper(SchoolExam.class_name) == cls,
            )
        )
    ).scalars().all()
    by_subject: dict[str, SchoolExam] = {}
    for e in exams:
        by_subject.setdefault((e.subject or "").strip().lower(), e)

    async def bank_count(subject: str) -> int:
        rows = (
            await db.execute(
                select(func.count(SchoolExQuestion.id))
                .join(SchoolExQuestionBank, SchoolExQuestionBank.id == SchoolExQuestion.bank_id)
                .where(
                    SchoolExQuestionBank.school_id == sid,
                    func.upper(SchoolExQuestionBank.class_name) == cls,
                    func.lower(SchoolExQuestionBank.subject) == subject.strip().lower(),
                )
            )
        ).scalar_one()
        return int(rows or 0)

    made, updated, missing = 0, 0, []
    for subject in sorted(want, key=str.lower):
        avail = await bank_count(subject)
        if avail == 0:
            missing.append(subject)
            continue
        exam = by_subject.get(subject.strip().lower())
        if exam:
            exam.duration_minutes = int(payload.duration_minutes)
            exam.questions_to_display = min(int(payload.question_count), avail)
            exam.total_mark = int(payload.total_mark)
            exam.exam_date = start
            exam.scheduled_start = start
            exam.scheduled_end = start + timedelta(minutes=int(payload.duration_minutes))
            exam.is_published = start <= now or exam.is_published
            exam.status = "published" if (start <= now or exam.is_published) else "draft"
            updated += 1
        else:
            exam = SchoolExam(
                school_id=sid,
                title=f"{subject} — {cls}",
                subject=subject.strip(),
                class_name=cls,
                exam_type="SCHOOL",
                exam_mode="ONLINE",
                total_mark=int(payload.total_mark),
                duration_minutes=int(payload.duration_minutes),
                questions_to_display=min(int(payload.question_count), avail),
                assigned_class_names=[cls],
                exam_date=start,
                scheduled_start=start,
                scheduled_end=start + timedelta(minutes=int(payload.duration_minutes)),
                is_published=start <= now,
                status="published" if start <= now else "draft",
            )
            db.add(exam)
            await db.flush()
            # §8 — fill exam questions from the class bank (all of them; the
            # engine shows questions_to_display of them per attempt).
            bank_qs = (
                await db.execute(
                    select(SchoolExQuestion)
                    .join(SchoolExQuestionBank, SchoolExQuestionBank.id == SchoolExQuestion.bank_id)
                    .where(
                        SchoolExQuestionBank.school_id == sid,
                        func.upper(SchoolExQuestionBank.class_name) == cls,
                        func.lower(SchoolExQuestionBank.subject) == subject.strip().lower(),
                        SchoolExQuestion.status == "active",
                    )
                )
            ).scalars().all()
            for i, q in enumerate(bank_qs):
                db.add(
                    SchoolExamQuestion(
                        exam_id=exam.id,
                        school_id=sid,
                        bank_question_id=q.id,
                        question_text=q.question_text,
                        option_a=q.option_a,
                        option_b=q.option_b,
                        option_c=q.option_c,
                        option_d=q.option_d,
                        correct_option=q.correct_option,
                        question_type=q.question_type if q.question_type in ("mcq", "true_false", "multi_select", "theory") else "mcq",
                        topic=q.topic,
                        marks=q.marks,
                        position=i,
                    )
                )
            made += 1
    # Subjects no longer scheduled → their exams are removed (class schedule
    # is rewritten, exactly like the reference overwrites its doc).
    removed = 0
    for subject, exam in list(by_subject.items()):
        if subject in {w.strip().lower() for w in want}:
            continue
        if any(str(a) for a in (
            await db.execute(
                select(SchoolExamAttempt.id).where(SchoolExamAttempt.exam_id == exam.id)
            )
        ).scalars().all()[:1]):
            continue  # keep exams with submissions
        for rel in (SchoolExamQuestion, SchoolExamAssignment, SchoolExamAccessCode, SchoolExamResult):
            await db.execute(delete(rel).where(rel.exam_id == exam.id))
        await db.delete(exam)
        removed += 1
    await db.flush()
    return {
        "ok": True,
        "class_name": cls,
        "created": made,
        "updated": updated,
        "removed": removed,
        "missing_questions": missing,
    }


@router.delete("/schedule/{class_name}")
async def clear_schedule(
    class_name: str,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """Clear the class's schedule (reference 'Clear'): removes scheduled
    exams that have no submissions yet."""
    sid = _staff_school_id(current_user, school_id)
    cls = (class_name or "").strip().upper()
    exams = (
        await db.execute(
            select(SchoolExam).where(
                SchoolExam.school_id == sid,
                func.upper(SchoolExam.class_name) == cls,
            )
        )
    ).scalars().all()
    removed = 0
    for exam in exams:
        attempts = (
            await db.execute(select(SchoolExamAttempt.id).where(SchoolExamAttempt.exam_id == exam.id))
        ).scalars().all()
        if attempts:
            continue
        for rel in (SchoolExamQuestion, SchoolExamAssignment, SchoolExamAccessCode, SchoolExamResult):
            await db.execute(delete(rel).where(rel.exam_id == exam.id))
        await db.delete(exam)
        removed += 1
    await db.flush()
    return {"ok": True, "removed": removed}


@router.get("/schedule")
async def schedule_overview(
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """Exam Schedule Management (reference layout): per class — Subjects,
    Date & Time, Duration, Venue/Class — plus the exams sitting in that class.
    Scheduling is fully decoupled from question upload."""
    sid = _staff_school_id(current_user, school_id)
    exams = (
        await db.execute(select(SchoolExam).where(SchoolExam.school_id == sid).order_by(SchoolExam.created_at.desc()))
    ).scalars().all()
    qcounts: dict[str, int] = {}
    if exams:
        qcounts = dict(
            (str(exam_id), int(c))
            for exam_id, c in (
                await db.execute(
                    select(SchoolExamQuestion.exam_id, func.count(SchoolExamQuestion.id))
                    .where(SchoolExamQuestion.exam_id.in_([e.id for e in exams]))
                    .group_by(SchoolExamQuestion.exam_id)
                )
            ).all()
        )
    now = naive_utc_now()
    out = []
    for e in exams:
        cls = (e.class_name or "—").upper()
        out.append(
            {
                "exam_id": str(e.id),
                "class_name": cls,
                "subjects": e.subject,
                "exam_date": e.exam_date.isoformat() if e.exam_date else None,
                "scheduled_start": e.scheduled_start.isoformat() if e.scheduled_start else (e.exam_date.isoformat() if e.exam_date else None),
                "scheduled_end": e.scheduled_end.isoformat() if e.scheduled_end else None,
                "duration_minutes": e.duration_minutes,
                "venue": cls,
                "questions": qcounts.get(str(e.id), 0),
                "questions_to_display": e.questions_to_display or qcounts.get(str(e.id), 0),
                "status": e.status,
                "is_published": bool(e.is_published),
                "window_open": bool(
                    e.is_published
                    and (not e.scheduled_start or e.scheduled_start <= now)
                    and (not e.scheduled_end or e.scheduled_end >= now)
                ),
            }
        )
    return {"schedule": out}


@router.patch("/exams/{exam_id}/schedule")
async def reschedule_exam(
    exam_id: str,
    payload: ScheduleIn,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """Reschedule ONE exam (reference: pick class → set date/time + duration →
    save). Once the window opens, students of that class see the exam on login
    and can write it. Duration edits apply to future attempts only."""
    sid = _staff_school_id(current_user, school_id)
    exam = await _get_school_exam(db, exam_id, sid)
    if payload.exam_date is not None:
        exam.exam_date = payload.exam_date
    if payload.scheduled_start is not None:
        start = payload.scheduled_start
        exam.scheduled_start = start
        if payload.scheduled_end is None:
            dur = payload.duration_minutes or exam.duration_minutes
            exam.scheduled_end = start + timedelta(minutes=int(dur))
    if payload.scheduled_end is not None:
        exam.scheduled_end = payload.scheduled_end
    if payload.duration_minutes is not None:
        exam.duration_minutes = int(payload.duration_minutes)
    await db.flush()
    return {"ok": True, "status": exam.status, "duration_minutes": exam.duration_minutes}


@router.patch("/exams/{exam_id}")
async def patch_exam(
    exam_id: str,
    payload: ExamPatchIn,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    sid = _staff_school_id(current_user, school_id)
    exam = await _get_school_exam(db, exam_id, sid)
    if payload.is_published is not None:
        exam.is_published = bool(payload.is_published)
        exam.status = "published" if payload.is_published else "draft"
    if payload.status in ("draft", "published", "completed", "archived"):
        exam.status = payload.status
    if payload.results_published is not None:
        exam.results_published = bool(payload.results_published)
    if payload.exam_date is not None:
        exam.exam_date = payload.exam_date
    if payload.scheduled_start is not None:
        exam.scheduled_start = payload.scheduled_start
    if payload.scheduled_end is not None:
        exam.scheduled_end = payload.scheduled_end
    await db.flush()
    return {"ok": True, "status": exam.status, "is_published": exam.is_published}


@router.delete("/exams/{exam_id}")
async def delete_exam(
    exam_id: str,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    sid = _staff_school_id(current_user, school_id)
    exam = await _get_school_exam(db, exam_id, sid)
    subs = (
        await db.execute(select(func.count(SchoolExamAttempt.id)).where(SchoolExamAttempt.exam_id == exam.id))
    ).scalar_one()
    if int(subs or 0) > 0:
        raise HTTPException(status_code=400, detail="This exam already has submissions — archive it instead")
    for rel in (SchoolExamQuestion, SchoolExamAssignment, SchoolExamAccessCode, SchoolExamResult):
        await db.execute(delete(rel).where(rel.exam_id == exam.id))
    await db.delete(exam)
    await db.flush()
    return {"ok": True}


@router.get("/exams")
async def list_exams(
    school_id: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """§25 — Exam list with the reference dashboard's columns."""
    sid = _staff_school_id(current_user, school_id)
    q = select(SchoolExam).where(SchoolExam.school_id == sid).order_by(SchoolExam.created_at.desc())
    if status:
        q = q.where(SchoolExam.status == status)
    exams = (await db.execute(q)).scalars().all()
    if not exams:
        return {"exams": []}
    ids = [e.id for e in exams]
    qcounts = dict(
        (str(exam_id), int(c))
        for exam_id, c in (
            await db.execute(
                select(SchoolExamQuestion.exam_id, func.count(SchoolExamQuestion.id))
                .where(SchoolExamQuestion.exam_id.in_(ids))
                .group_by(SchoolExamQuestion.exam_id)
            )
        ).all()
    )
    scounts = dict(
        (str(exam_id), int(c))
        for exam_id, c in (
            await db.execute(
                select(SchoolExamAttempt.exam_id, func.count(SchoolExamAttempt.id))
                .where(SchoolExamAttempt.exam_id.in_(ids), SchoolExamAttempt.submitted_at != None)  # noqa: E711
                .group_by(SchoolExamAttempt.exam_id)
            )
        ).all()
    )
    return {"exams": [_exam_row(e, qcounts.get(str(e.id), 0), scounts.get(str(e.id), 0)) for e in exams]}


@router.get("/exams/{exam_id}")
async def exam_detail(
    exam_id: str,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """§27 — preview: full config + assigned students (no answers leaked)."""
    sid = _staff_school_id(current_user, school_id)
    exam = await _get_school_exam(db, exam_id, sid)
    qs = (
        await db.execute(
            select(SchoolExamQuestion).where(SchoolExamQuestion.exam_id == exam.id).order_by(SchoolExamQuestion.position)
        )
    ).scalars().all()
    assignments = (
        await db.execute(
            select(SchoolExamAssignment, User)
            .join(User, User.id == SchoolExamAssignment.student_id)
            .where(SchoolExamAssignment.exam_id == exam.id)
            .order_by(User.full_name)
        )
    ).all()
    codes = {
        str(c.student_id): c
        for c in (
            await db.execute(select(SchoolExamAccessCode).where(SchoolExamAccessCode.exam_id == exam.id))
        ).scalars().all()
    }
    students = []
    for assign, user in assignments:
        code = codes.get(str(user.id))
        students.append(
            {
                "student_id": str(user.id),
                "full_name": user.full_name,
                "email": user.email if not str(user.email or "").endswith(".scholaxia.local") else None,
                "class_name": assign.class_name or exam.class_name,
                "reg_number": code.reg_number if code else None,
                "access_code": code.access_code if code else None,
                "code_used": bool(code and code.is_used),
            }
        )
    row = _exam_row(exam, len(qs), len(students))
    row["assigned"] = students
    return row


@router.post("/exams/{exam_id}/questions", status_code=201)
async def add_exam_questions(
    exam_id: str,
    payload: list[ExamQuestionIn],
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    sid = _staff_school_id(current_user, school_id)
    exam = await _get_school_exam(db, exam_id, sid)
    if exam.status == "completed":
        raise HTTPException(status_code=400, detail="Exam is completed — questions can no longer change")
    pos = (
        await db.execute(select(func.max(SchoolExamQuestion.position)).where(SchoolExamQuestion.exam_id == exam.id))
    ).scalar_one() or 0
    added = 0
    for q in payload[:300]:
        if not q.question_text.strip():
            continue
        pos += 1
        db.add(
            SchoolExamQuestion(
                exam_id=exam.id,
                school_id=sid,
                question_text=q.question_text.strip()[:4000],
                option_a=(q.option_a or "").strip()[:1000],
                option_b=(q.option_b or "").strip()[:1000],
                option_c=(q.option_c or "").strip()[:1000],
                option_d=(q.option_d or "").strip()[:1000],
                correct_option=(q.correct_option or "A").upper(),
                topic=(q.topic or "").strip() or None,
                marks=max(1, min(int(q.marks or 1), 100)),
                position=pos,
            )
        )
        added += 1
    await db.flush()
    return {"added": added}


@router.post("/exams/{exam_id}/schedule")
async def schedule_exam(
    exam_id: str,
    payload: ExamPatchIn,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    return await patch_exam(exam_id, payload, school_id, current_user, db)


# ── Access codes (§13): dedicated generation tab ─────────────────────────
# The portal keeps Reg Number + Access Code generation on its OWN tab,
# separate from exam-student assignment. These endpoints power it.

class CodesIn(BaseModel):
    """Generate credentials on demand. None of the fields are required —
    an empty payload generates codes for every student already assigned to
    the exam (missing ones only, never rotates existing codes)."""
    student_ids: list[str] = []   # explicit students (joined to the exam if needed)
    class_names: list[str] = []   # or whole classes, resolved through the school
    regenerate: bool = False      # True → also issue NEW codes to students who have one


async def _codes_for(db: AsyncSession, exam: SchoolExam, payload: CodesIn, sid: UUID) -> int:
    """Ensure every wanted student has an assignment row + access code.
    Returns how many NEW codes were minted."""
    # Resolve wanted students (explicit ids ∪ class members), school-scoped.
    wanted: list[UUID] = []
    for s in payload.student_ids or []:
        try:
            wanted.append(UUID(str(s)))
        except ValueError:
            continue
    for cls in payload.class_names or []:
        c = str(cls).strip().upper()
        if not c:
            continue
        wanted.extend(
            (
                await db.execute(
                    select(User.id)
                    .join(StudentProfile, StudentProfile.user_id == User.id)
                    .where(
                        User.school_id == sid,
                        User.role == UserRole.student,
                        func.upper(StudentProfile.education_level) == c,
                    )
                )
            ).scalars().all()
        )
    # Tenant guard (§30) — explicit ids must belong to THIS school.
    if wanted:
        allowed = {
            str(r)
            for r in (
                await db.execute(
                    select(User.id).where(
                        User.id.in_(wanted),
                        User.school_id == sid,
                        User.role == UserRole.student,
                    )
                )
            ).scalars().all()
        }
        if len(allowed) != len({str(w) for w in wanted}):
            raise HTTPException(status_code=400, detail="Some students were not found in your school")
        wanted = [UUID(v) for v in allowed]

    have_assignment = {
        str(r) for r in (
            await db.execute(
                select(SchoolExamAssignment.student_id).where(SchoolExamAssignment.exam_id == exam.id)
            )
        ).scalars().all()
    }
    for suid in wanted:
        if str(suid) not in have_assignment:
            db.add(
                SchoolExamAssignment(
                    school_id=sid, exam_id=exam.id, student_id=suid, subject=exam.subject,
                )
            )
            have_assignment.add(str(suid))
    await db.flush()

    codes = {
        str(c.student_id): c
        for c in (
            await db.execute(select(SchoolExamAccessCode).where(SchoolExamAccessCode.exam_id == exam.id))
        ).scalars().all()
    }
    made = 0
    for suid in {str(u) for u in wanted}:
        row = codes.get(suid)
        if row and not payload.regenerate:
            continue
        if row:
            row.access_code = _new_access_code()
            row.failed_attempts = 0
            row.locked_until = None
        else:
            db.add(
                SchoolExamAccessCode(
                    school_id=exam.school_id,
                    exam_id=exam.id,
                    student_id=UUID(suid),
                    reg_number=await _reg_number_for(db, exam.school_id, UUID(suid)),
                    access_code=_new_access_code(),
                    expires_at=exam.access_code_expires_at,
                )
            )
        made += 1
    # Codes for assigned students who have none yet (e.g. class-bulk assigns).
    made += await _ensure_access_codes(db, exam)
    return made


@router.post("/exams/{exam_id}/access-codes")
async def generate_codes(
    exam_id: str,
    payload: CodesIn | None = None,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """§13 — generate Registration Numbers + Access Codes on demand.
    Empty body = fill in codes for students already assigned; pass
    student_ids / class_names to admit more students; regenerate=True
    re-issues codes (old ones stop working immediately)."""
    sid = _staff_school_id(current_user, school_id)
    exam = await _get_school_exam(db, exam_id, sid)
    made = await _codes_for(db, exam, payload or CodesIn(), sid)
    await db.flush()
    return {"ok": True, "new_codes": made}


@router.get("/exams/{exam_id}/codes")
async def list_codes(
    exam_id: str,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """Credential slips for printing: one row per assigned student."""
    sid = _staff_school_id(current_user, school_id)
    exam = await _get_school_exam(db, exam_id, sid)
    assignments = {
        str(a.student_id): a
        for a in (
            await db.execute(select(SchoolExamAssignment).where(SchoolExamAssignment.exam_id == exam.id))
        ).scalars().all()
    }
    rows = (
        await db.execute(
            select(SchoolExamAccessCode, User)
            .join(User, User.id == SchoolExamAccessCode.student_id)
            .where(SchoolExamAccessCode.exam_id == exam.id)
            .order_by(SchoolExamAccessCode.reg_number)
        )
    ).all()
    now = naive_utc_now()
    out = []
    for code, user in rows:
        assign = assignments.get(str(user.id))
        out.append(
            {
                "student_id": str(user.id),
                "full_name": user.full_name,
                "class_name": (assign.class_name if assign else None) or exam.class_name,
                "reg_number": code.reg_number,
                "access_code": code.access_code,
                "is_used": bool(code.is_used),
                "locked": bool(code.locked_until and code.locked_until > now),
                "expires_at": code.expires_at.isoformat() if code.expires_at else None,
            }
        )
    return {"codes": out}


@router.post("/exams/{exam_id}/codes/{student_id}/reset")
async def reset_code(
    exam_id: str,
    student_id: str,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """Issue a FRESH access code for one student (old code invalid; lock and
    failure counters cleared). Use when a student forgets theirs or gets locked."""
    sid = _staff_school_id(current_user, school_id)
    exam = await _get_school_exam(db, exam_id, sid)
    row = (
        await db.execute(
            select(SchoolExamAccessCode).where(
                SchoolExamAccessCode.exam_id == exam.id,
                SchoolExamAccessCode.student_id == UUID(student_id),
            )
        )
    ).scalar_one_or_none()
    if not row:
        raise HTTPException(status_code=404, detail="No access code found for this student on this exam")
    row.access_code = _new_access_code()
    row.failed_attempts = 0
    row.locked_until = None
    row.expires_at = exam.access_code_expires_at
    await db.flush()
    return {"ok": True, "reg_number": row.reg_number, "access_code": row.access_code}


@router.delete("/exams/{exam_id}/codes/{student_id}")
async def revoke_code(
    exam_id: str,
    student_id: str,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """Stop a student from logging into THIS exam (e.g. wrong assignment).
    Their login immediately returns 'Registration number or access code is
    incorrect' because the code row is gone."""
    sid = _staff_school_id(current_user, school_id)
    exam = await _get_school_exam(db, exam_id, sid)
    res = await db.execute(
        delete(SchoolExamAccessCode).where(
            SchoolExamAccessCode.exam_id == exam.id,
            SchoolExamAccessCode.student_id == UUID(student_id),
        )
    )
    await db.execute(
        delete(SchoolExamAssignment).where(
            SchoolExamAssignment.exam_id == exam.id,
            SchoolExamAssignment.student_id == UUID(student_id),
        )
    )
    await db.flush()
    return {"ok": True, "revoked": int(res.rowcount or 0)}


@router.get("/codes/students")
async def codes_student_directory(
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """Compact student directory for the codes tab's assign form."""
    sid = _staff_school_id(current_user, school_id)
    rows = (
        await db.execute(
            select(User, StudentProfile)
            .join(StudentProfile, StudentProfile.user_id == User.id)
            .where(User.school_id == sid, User.role == UserRole.student, User.is_active == True)  # noqa: E712
            .order_by(User.full_name)
        )
    ).all()
    return {
        "students": [
            {
                "id": str(u.id),
                "full_name": u.full_name,
                "class_name": (p.education_level or "").upper() if p else None,
                "school_student_id": getattr(p, "school_student_id", None) if p else None,
            }
            for u, p in rows
        ]
    }


# ═════════════════════════════════════════════════════════════════════════
# STAFF — Results (§29), publish (§22), Grant Exam Retake
# ═════════════════════════════════════════════════════════════════════════

@router.get("/exams/{exam_id}/results")
async def exam_results(
    exam_id: str,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """Reference-dashboard results table: student, reg number, correct, score,
    percentage, grade, date — per exam."""
    sid = _staff_school_id(current_user, school_id)
    exam = await _get_school_exam(db, exam_id, sid)
    rows = (
        await db.execute(
            select(SchoolExamResult, User)
            .join(User, User.id == SchoolExamResult.student_id)
            .where(SchoolExamResult.exam_id == exam.id)
            .order_by(SchoolExamResult.final_score.desc())
        )
    ).all()
    out = []
    for res, user in rows:
        out.append(
            {
                "student_id": str(user.id),
                "student_name": user.full_name,
                "total_questions": res.total_questions,
                "questions_answered": res.questions_answered,
                "correct_answers": res.correct_count,
                "wrong_answers": res.wrong_count,
                "raw_score": res.raw_score,
                "total_mark": res.total_mark,
                "final_score": res.final_score,
                "percentage": res.percentage,
                "grade": res.grade,
                "is_published": bool(res.is_published),
                "submitted_at": res.created_at.isoformat() if res.created_at else None,
            }
        )
    return {"exam": _exam_row(exam), "results": out}


class RetakeIn(BaseModel):
    student_ids: list[str] = Field(..., min_length=1)


@router.post("/exams/{exam_id}/retake")
async def grant_retake(
    exam_id: str,
    payload: RetakeIn,
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """Reference dashboard's \"Grant Exam Retake\": listed students may sit the
    exam again — we clear their last attempt (keeping the audit log) so the
    portal shows START EXAM once more."""
    sid = _staff_school_id(current_user, school_id)
    exam = await _get_school_exam(db, exam_id, sid)
    granted = []
    for s in payload.student_ids:
        try:
            suid = UUID(str(s))
        except ValueError:
            continue
        attempts = (
            await db.execute(
                select(SchoolExamAttempt).where(
                    SchoolExamAttempt.exam_id == exam.id, SchoolExamAttempt.student_id == suid
                )
            )
        ).scalars().all()
        if not attempts:
            continue
        for att in attempts:
            await _sync_log(
                db, exam, suid, "retake_granted",
                attempt_id=att.id,
                detail={"granted_by": str(current_user.get("sub") or "")},
            )
            await db.execute(delete(SchoolExamAnswer).where(SchoolExamAnswer.attempt_id == att.id))
            await db.delete(att)
        await db.execute(delete(SchoolExamResult).where(SchoolExamResult.exam_id == exam.id, SchoolExamResult.student_id == suid))
        retakes = list(exam.retake_student_ids or [])
        if str(suid) not in retakes:
            retakes.append(str(suid))
        exam.retake_student_ids = retakes
        granted.append(str(suid))
    await db.flush()
    return {"ok": True, "retake_granted": granted}


@router.post("/exams/{exam_id}/publish-results")
async def publish_results(
    exam_id: str,
    publish: bool = Query(True),
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    """§22 — students see their scores only after the school publishes."""
    sid = _staff_school_id(current_user, school_id)
    exam = await _get_school_exam(db, exam_id, sid)
    exam.results_published = bool(publish)
    await db.execute(
        SchoolExamResult.__table__.update()
        .where(SchoolExamResult.exam_id == exam.id)
        .values(is_published=bool(publish), published_at=naive_utc_now() if publish else None)
    )
    await db.flush()
    return {"ok": True, "results_published": exam.results_published}


# ═════════════════════════════════════════════════════════════════════════
# STUDENT CBT PORTAL (§14–§23) — reg number + access code, server-side auth
# ═════════════════════════════════════════════════════════════════════════

class StudentLoginIn(BaseModel):
    school_slug: Optional[str] = None
    reg_number: str = Field(min_length=2, max_length=60)
    access_code: str = Field(min_length=4, max_length=60)


@router.post("/student/login")
async def student_exam_login(
    payload: StudentLoginIn,
    db: AsyncSession = Depends(get_db),
):
    """§14 — student logs in with Registration Number + Access Code.

    Returns a short-lived exam-scoped token. Brute-force protected
    server-side: 5 failures locks that code for 15 minutes.
    """
    reg = payload.reg_number.strip().upper()
    code = payload.access_code.strip().upper()
    now = naive_utc_now()

    # Same reg number can legitimately hold one code per exam — match BOTH.
    rows = (
        await db.execute(
            select(SchoolExamAccessCode).where(
                func.upper(func.trim(SchoolExamAccessCode.reg_number)) == reg,
            )
        )
    ).scalars().all()
    row = next((r for r in rows if (r.access_code or "").strip().upper() == code), None)
    if not row:
        # §13/§14 brute-force protection: a matching REG NUMBER with a wrong
        # code increments a server-side counter; 5 failures locks the code.
        for r in rows:
            _mark_login_failure(r)
        if rows:
            await db.flush()
        raise HTTPException(status_code=401, detail="Registration number or access code is incorrect")

    if row.locked_until and row.locked_until > now:
        mins = int((row.locked_until - now).total_seconds() // 60) + 1
        raise HTTPException(status_code=429, detail=f"Too many attempts — try again in {mins} minute(s)")
    if row.expires_at and row.expires_at < now:
        raise HTTPException(status_code=403, detail="This access code has expired")

    exam = (await db.execute(select(SchoolExam).where(SchoolExam.id == row.exam_id))).scalar_one_or_none()
    if not exam or not exam.is_published:
        raise HTTPException(status_code=403, detail="This examination is not available yet")

    student = (await db.execute(select(User).where(User.id == row.student_id))).scalar_one_or_none()
    if not student or not student.is_active:
        raise HTTPException(status_code=403, detail="This student account is not active")

    # Success — reset the failure counter.
    row.failed_attempts = 0
    await db.flush()
    # Exam-scoped token (independent of the main app's token_version so a
    # school-student logout never invalidates a downloaded offline exam).
    from jose import jwt as _jwt
    from app.core.config import settings as _settings

    token = _jwt.encode(
        {
            "sub": str(student.id),
            "role": "student",
            "exp": datetime.utcnow() + timedelta(hours=STUDENT_TOKEN_TTL_HOURS),
            "type": "access",
            "sv": -1,
            "scope": "school_exam",
        },
        _settings.SECRET_KEY,
        algorithm=_settings.ALGORITHM,
    )
    return {
        "access_token": token,
        "token_type": "bearer",
        "student": {"full_name": student.full_name, "reg_number": row.reg_number},
        "school_id": str(exam.school_id),
        "exam_id": str(exam.id),
    }


async def _exam_student(db: AsyncSession, credentials) -> tuple[User, SchoolExamAccessCode | None]:
    """Resolve the exam-scoped student token → user. Deny by default (§30).

    ONLY tokens minted by the CBT portal login (scope="school_exam") are
    accepted here — the main Scholaxia app cannot drive the exam engine."""
    if credentials is None or not getattr(credentials, "credentials", None):
        raise HTTPException(status_code=401, detail="Not authenticated")
    payload = decode_token(credentials.credentials)
    if not payload or payload.get("type") != "access" or not payload.get("sub"):
        raise HTTPException(status_code=401, detail="Session expired — log in again")
    if payload.get("scope") != "school_exam":
        raise HTTPException(status_code=403, detail="Log in with your examination access code")
    user = (await db.execute(select(User).where(User.id == UUID(payload["sub"])))).scalar_one_or_none()
    if not user or not user.is_active or user.role != UserRole.student:
        raise HTTPException(status_code=401, detail="Not authorized")
    code = (
        await db.execute(
            select(SchoolExamAccessCode).where(
                SchoolExamAccessCode.student_id == user.id,
                SchoolExamAccessCode.is_used == False,  # noqa: E712
            )
        )
    ).scalars().first()
    return user, code


from fastapi import Security  # noqa: E402
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials  # noqa: E402

exam_bearer = HTTPBearer(auto_error=False)


def _exam_credentials(credentials: HTTPAuthorizationCredentials | None = Security(exam_bearer)):
    return credentials


def _mark_login_failure(row: SchoolExamAccessCode) -> None:
    row.failed_attempts = int(row.failed_attempts or 0) + 1
    if row.failed_attempts >= LOGIN_MAX_FAILURES:
        row.locked_until = naive_utc_now() + timedelta(minutes=LOGIN_LOCK_MINUTES)
        row.failed_attempts = 0


@router.get("/student/my-exams")
async def student_my_exams(
    credentials: HTTPAuthorizationCredentials | None = Depends(_exam_credentials),
    db: AsyncSession = Depends(get_db),
):
    """§15 — ONLY the exams this student is assigned to. Never the school
    dashboard; never another student's exam."""
    user, _code = await _exam_student(db, credentials)
    uid = str(user.id)
    now = naive_utc_now()

    assignments = (
        await db.execute(select(SchoolExamAssignment).where(SchoolExamAssignment.student_id == user.id))
    ).scalars().all()
    exam_ids = {a.exam_id for a in assignments}
    out = []
    if exam_ids:
        exams = (
            await db.execute(
                select(SchoolExam)
                .where(SchoolExam.id.in_(list(exam_ids)), SchoolExam.is_published == True)  # noqa: E712
                .order_by(SchoolExam.exam_date.desc().nullslast(), SchoolExam.created_at.desc())
            )
        ).scalars().all()
        attempts = {
            a.exam_id: a
            for a in (
                await db.execute(
                    select(SchoolExamAttempt).where(
                        SchoolExamAttempt.student_id == user.id, SchoolExamAttempt.status == "submitted"
                    )
                )
            ).scalars().all()
        }
        downloads = {
            d.exam_id for d in (
                await db.execute(select(SchoolExamDownload).where(SchoolExamDownload.student_id == user.id))
            ).scalars().all()
        }
        qcounts = dict(
            (str(eid), int(c))
            for eid, c in (
                await db.execute(
                    select(SchoolExamQuestion.exam_id, func.count(SchoolExamQuestion.id))
                    .where(SchoolExamQuestion.exam_id.in_(list(exam_ids)))
                    .group_by(SchoolExamQuestion.exam_id)
                )
            ).all()
        )
        for e in exams:
            qc = qcounts.get(str(e.id), 0)
            if qc == 0:
                continue
            att = attempts.get(e.id)
            res = (
                await db.execute(
                    select(SchoolExamResult).where(
                        SchoolExamResult.exam_id == e.id, SchoolExamResult.student_id == user.id
                    )
                )
            ).scalar_one_or_none()
            out.append(
                {
                    "id": str(e.id),
                    "title": e.title,
                    "subject": e.subject,
                    "class_name": e.class_name,
                    "session": e.session,
                    "term": e.term,
                    "questions": qc,
                    "questions_to_answer": e.questions_to_answer or qc,
                    "duration_minutes": e.duration_minutes,
                    "total_mark": e.total_mark,
                    "exam_mode": e.exam_mode,
                    "status": "Completed" if att else ("Open" if _exam_window_open(e, now) else "Closed"),
                    "window_open": _exam_window_open(e, now),
                    "scheduled_start": e.scheduled_start.isoformat() if e.scheduled_start else None,
                    "scheduled_end": e.scheduled_end.isoformat() if e.scheduled_end else None,
                    "exam_date": e.exam_date.isoformat() if e.exam_date else None,
                    "downloaded": str(e.id) in downloads or e.exam_mode == "ONLINE",
                    "needs_download": e.exam_mode in ("OFFLINE", "HYBRID") and str(e.id) not in downloads,
                    "attempt_status": "submitted" if att else "not_started",
                    "results_published": bool(e.results_published),
                    "result": (
                        {
                            "final_score": res.final_score,
                            "total_mark": res.total_mark,
                            "percentage": res.percentage,
                            "grade": res.grade,
                            "correct": res.correct_count,
                            "total_questions": res.total_questions,
                        }
                        if res and e.results_published
                        else None
                    ),
                }
            )
    return {"student": user.full_name, "exams": out}


@router.post("/student/exams/{exam_id}/download")
async def download_exam(
    exam_id: str,
    credentials: HTTPAuthorizationCredentials | None = Depends(_exam_credentials),
    db: AsyncSession = Depends(get_db),
):
    """§16/§17 — download ONLY for OFFLINE/HYBRID exams, ONLY when assigned."""
    user, _code = await _exam_student(db, credentials)
    exam = await _get_school_exam(db, exam_id, user.school_id)
    if exam.exam_mode not in ("OFFLINE", "HYBRID"):
        raise HTTPException(status_code=400, detail="This examination is online — no download needed")
    await _student_for_exam(db, exam, user.id)
    qs = (
        await db.execute(
            select(SchoolExamQuestion).where(SchoolExamQuestion.exam_id == exam.id).order_by(SchoolExamQuestion.position)
        )
    ).scalars().all()
    shown = _exam_questions_available(exam, list(qs))
    # §10 — the student's randomization is decided HERE, at download time, and
    # stored server-side; start_attempt reuses the exact same mapping so the
    # offline copy and the marking key always agree.
    dl_order = [str(q.id) for q in shown]
    if exam.randomize_questions:
        secrets.SystemRandom().shuffle(dl_order)
    dl_options = _make_option_order(shown, exam.randomize_options)
    checksum = hashlib.sha256(json.dumps(dl_order, sort_keys=True).encode()).hexdigest()[:32]
    # Correct answers NEVER leave the server (§30).
    package = {
        "exam": {
            "id": str(exam.id),
            "title": exam.title,
            "subject": exam.subject,
            "class_name": exam.class_name,
            "instructions": exam.instructions,
            "exam_mode": exam.exam_mode,
            "duration_minutes": exam.duration_minutes,
            "total_mark": exam.total_mark,
            "questions_to_answer": exam.questions_to_answer or len(shown),
            "allow_review": bool(exam.allow_review),
            "allow_previous": bool(exam.allow_previous),
            "allow_flagging": bool(exam.allow_flagging),
        },
        "questions": [
            {
                "id": str(q.id),
                "question_text": q.question_text,
                "topic": q.topic,
                "image_url": None,
                "question_type": q.question_type,
                "options": [
                    {"label": lbl, "text": txt}
                    for lbl, txt in (("A", q.option_a), ("B", q.option_b), ("C", q.option_c), ("D", q.option_d))
                ],
            }
            for q in shown
        ],
    }
    exists = (
        await db.execute(
            select(SchoolExamDownload).where(
                SchoolExamDownload.exam_id == exam.id, SchoolExamDownload.student_id == user.id
            )
        )
    ).scalar_one_or_none()
    if not exists:
        db.add(
            SchoolExamDownload(
                school_id=exam.school_id,
                exam_id=exam.id,
                student_id=user.id,
                checksum=checksum,
                verified=True,
                question_order=dl_order,
                option_order=dl_options,
            )
        )
        await _sync_log(db, exam, user.id, "exam_downloaded", detail={"checksum": checksum})
        await db.flush()
    else:
        # Re-download returns the SAME mapping as the first download.
        dl_order = exists.question_order or dl_order
        dl_options = exists.option_order or dl_options
    # Emit the package in the student's stored order with positional labels.
    by_id = {str(q.id): q for q in shown}
    ordered = [by_id[i] for i in dl_order if i in by_id]
    package["questions"] = [
        {
            "id": str(q.id),
            "question_text": q.question_text,
            "topic": q.topic,
            "image_url": None,
            "question_type": q.question_type,
            **_option_map_for(q, dl_options),
        }
        for q in ordered
    ]
    body = json.dumps(package, sort_keys=True).encode()
    package["checksum"] = hashlib.sha256(body).hexdigest()[:32]
    return package


@router.post("/student/exams/{exam_id}/verify-download")
async def verify_download(
    exam_id: str,
    credentials: HTTPAuthorizationCredentials | None = Depends(_exam_credentials),
    db: AsyncSession = Depends(get_db),
):
    """§18 — revalidate with the server when connectivity allows."""
    user, _code = await _exam_student(db, credentials)
    exam = await _get_school_exam(db, exam_id, user.school_id)
    rec = (
        await db.execute(
            select(SchoolExamDownload).where(
                SchoolExamDownload.exam_id == exam.id, SchoolExamDownload.student_id == user.id
            )
        )
    ).scalar_one_or_none()
    return {
        "verified": bool(rec and rec.verified),
        "checksum": rec.checksum if rec else None,
        "exam_mode": exam.exam_mode,
    }


@router.get("/student/exams/{exam_id}")
async def exam_details(
    exam_id: str,
    credentials: HTTPAuthorizationCredentials | None = Depends(_exam_credentials),
    db: AsyncSession = Depends(get_db),
):
    """§19 — exam details before start."""
    user, _code = await _exam_student(db, credentials)
    exam = await _get_school_exam(db, exam_id, user.school_id)
    await _student_for_exam(db, exam, user.id)
    qc = (
        await db.execute(select(func.count(SchoolExamQuestion.id)).where(SchoolExamQuestion.exam_id == exam.id))
    ).scalar_one()
    dl = (
        await db.execute(
            select(SchoolExamDownload).where(
                SchoolExamDownload.exam_id == exam.id, SchoolExamDownload.student_id == user.id
            )
        )
    ).scalar_one_or_none()
    return {
        "id": str(exam.id),
        "title": exam.title,
        "subject": exam.subject,
        "class_name": exam.class_name,
        "session": exam.session,
        "term": exam.term,
        "instructions": exam.instructions,
        "questions": int(qc or 0),
        "questions_to_answer": exam.questions_to_answer or int(qc or 0),
        "total_mark": exam.total_mark,
        "duration_minutes": exam.duration_minutes,
        "exam_mode": exam.exam_mode,
        "allow_review": bool(exam.allow_review),
        "allow_previous": bool(exam.allow_previous),
        "allow_flagging": bool(exam.allow_flagging),
        "downloaded": bool(dl),
        "window_open": _exam_window_open(exam, naive_utc_now()),
    }


@router.post("/student/exams/{exam_id}/start")
async def start_attempt(
    exam_id: str,
    credentials: HTTPAuthorizationCredentials | None = Depends(_exam_credentials),
    db: AsyncSession = Depends(get_db),
):
    """§19/§20 — officially start. The server keeps the authoritative
    started_at/deadline (§7). One attempt at a time; resumable."""
    user, code = await _exam_student(db, credentials)
    exam = await _get_school_exam(db, exam_id, user.school_id)
    if not exam.is_published:
        raise HTTPException(status_code=403, detail="This examination is not available")
    if not _exam_window_open(exam, naive_utc_now()):
        raise HTTPException(status_code=403, detail="This examination window is closed")
    await _student_for_exam(db, exam, user.id)

    # OFFLINE exams must be downloaded first (§16).
    if exam.exam_mode == "OFFLINE":
        dl = (
            await db.execute(
                select(SchoolExamDownload).where(
                    SchoolExamDownload.exam_id == exam.id, SchoolExamDownload.student_id == user.id
                )
            )
        ).scalar_one_or_none()
        if not dl:
            raise HTTPException(status_code=400, detail="Download the examination first")

    existing = (
        await db.execute(
            select(SchoolExamAttempt).where(
                SchoolExamAttempt.exam_id == exam.id,
                SchoolExamAttempt.student_id == user.id,
                SchoolExamAttempt.status == "in_progress",
            )
        )
    ).scalar_one_or_none()
    if existing:
        attempt = existing
    else:
        past = (
            await db.execute(
                select(func.count(SchoolExamAttempt.id)).where(
                    SchoolExamAttempt.exam_id == exam.id, SchoolExamAttempt.student_id == user.id
                )
            )
        ).scalar_one()
        allowed = int(exam.max_attempts or 1) + (1 if str(user.id) in {str(x) for x in (exam.retake_student_ids or [])} else 0)
        if int(past or 0) >= allowed:
            raise HTTPException(status_code=403, detail="You have already taken this examination")
        started = naive_utc_now()
        attempt = SchoolExamAttempt(
            school_id=exam.school_id,
            exam_id=exam.id,
            student_id=user.id,
            started_at=started,
            deadline_at=started + timedelta(minutes=int(exam.duration_minutes or 60)),
        )
        db.add(attempt)
        await db.flush()
        if code and not code.is_used:
            code.is_used = True
            code.used_at = started
        await _sync_log(db, exam, user.id, "attempt_started", attempt_id=attempt.id)

    qs = (
        await db.execute(
            select(SchoolExamQuestion).where(SchoolExamQuestion.exam_id == exam.id).order_by(SchoolExamQuestion.position)
        )
    ).scalars().all()
    shown = _exam_questions_available(exam, list(qs))
    # §18 — a student who already DOWNLOADED the package answers against that
    # fixed copy, so the attempt reuses the downloaded (natural) order; only
    # never-downloaded (online) attempts get fresh randomization.
    dl_rec = (
        await db.execute(
            select(SchoolExamDownload).where(
                SchoolExamDownload.exam_id == exam.id, SchoolExamDownload.student_id == user.id
            )
        )
    ).scalar_one_or_none()
    # §10 — per-attempt mapping: reuse the DOWNLOADED mapping when one exists
    # (offline copy ≡ marking key); otherwise randomize fresh.
    if not attempt.question_order:
        if dl_rec and dl_rec.question_order:
            attempt.question_order = list(dl_rec.question_order)
            attempt.option_order = dict(dl_rec.option_order or {})
        else:
            order = [str(q.id) for q in shown]
            if exam.randomize_questions:
                secrets.SystemRandom().shuffle(order)
            attempt.question_order = order
            attempt.option_order = _make_option_order(shown, exam.randomize_options)
        await db.flush()

    by_id = {str(q.id): q for q in shown}
    ordered = [by_id[i] for i in attempt.question_order if i in by_id]
    answers = {
        str(a.exam_question_id): {"answer": a.answer, "is_flagged": bool(a.is_flagged)}
        for a in (
            await db.execute(select(SchoolExamAnswer).where(SchoolExamAnswer.attempt_id == attempt.id))
        ).scalars().all()
    }
    remaining = max(0, int((attempt.deadline_at - naive_utc_now()).total_seconds())) if attempt.deadline_at else int(exam.duration_minutes or 60) * 60
    return {
        "attempt_id": str(attempt.id),
        "exam": {
            "id": str(exam.id),
            "title": exam.title,
            "subject": exam.subject,
            "exam_mode": exam.exam_mode,
            "total_mark": exam.total_mark,
            "duration_minutes": exam.duration_minutes,
            "questions_to_answer": exam.questions_to_answer or len(ordered),
            "allow_review": bool(exam.allow_review),
            "allow_previous": bool(exam.allow_previous),
            "allow_flagging": bool(exam.allow_flagging),
            "instructions": exam.instructions,
        },
        "seconds_remaining": remaining,
        "questions": [
            {
                "id": str(q.id),
                "question_text": q.question_text,
                "topic": q.topic,
                "question_type": q.question_type,
                "image_url": None,
                **_option_map_for(q, attempt.option_order),
                "saved_answer": answers.get(str(q.id), {}).get("answer"),
                "is_flagged": answers.get(str(q.id), {}).get("is_flagged", False),
            }
            for q in ordered
        ],
    }


class AnswerIn(BaseModel):
    attempt_id: str
    question_id: str
    answer: Optional[str] = None   # "A"…/"A,C" — label the student SAW
    is_flagged: Optional[bool] = None
    offline_sync: bool = False


@router.post("/student/answers")
async def save_answer(
    payload: AnswerIn,
    credentials: HTTPAuthorizationCredentials | None = Depends(_exam_credentials),
    db: AsyncSession = Depends(get_db),
):
    """§21 — auto-save every answer. Attempt ownership re-verified; deadline
    enforced server-side."""
    user, _code = await _exam_student(db, credentials)
    try:
        aid = UUID(payload.attempt_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Attempt not found")
    attempt = (await db.execute(select(SchoolExamAttempt).where(SchoolExamAttempt.id == aid))).scalar_one_or_none()
    if not attempt or str(attempt.student_id) != str(user.id):
        raise HTTPException(status_code=404, detail="Attempt not found")
    if attempt.status == "submitted":
        raise HTTPException(status_code=409, detail="This attempt was already submitted")
    exam = (await db.execute(select(SchoolExam).where(SchoolExam.id == attempt.exam_id))).scalar_one_or_none()
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")
    if attempt.deadline_at and naive_utc_now() > attempt.deadline_at and not payload.offline_sync:
        raise HTTPException(status_code=409, detail="Time is up — submit your examination")

    qid = payload.question_id
    qrow = None
    if qid:
        try:
            quuid = UUID(qid)
        except ValueError:
            raise HTTPException(status_code=404, detail="Question not found in this exam")
        qrow = (
            await db.execute(
                select(SchoolExamQuestion).where(
                    SchoolExamQuestion.id == quuid, SchoolExamQuestion.exam_id == attempt.exam_id
                )
            )
        ).scalar_one_or_none()
    if not qrow:
        raise HTTPException(status_code=404, detail="Question not found in this exam")

    row = (
        await db.execute(
            select(SchoolExamAnswer).where(
                SchoolExamAnswer.attempt_id == attempt.id, SchoolExamAnswer.exam_question_id == qrow.id
            )
        )
    ).scalar_one_or_none()
    if not row:
        row = SchoolExamAnswer(
            school_id=attempt.school_id,
            attempt_id=attempt.id,
            exam_question_id=qrow.id,
            student_id=user.id,
        )
        db.add(row)
    if payload.answer is not None:
        row.answer = (payload.answer or "").strip().upper()[:50] or None
    if payload.is_flagged is not None:
        row.is_flagged = bool(payload.is_flagged)
    row.synced_offline = bool(payload.offline_sync)
    await db.flush()
    if payload.offline_sync:
        await _sync_log(db, exam, user.id, "answer_synced", attempt_id=attempt.id, channel="offline_sync")
    return {"ok": True}


class SubmitIn(BaseModel):
    attempt_id: str
    is_auto_submit: bool = False
    offline_sync: bool = False
    started_at: Optional[datetime] = None
    submitted_at: Optional[datetime] = None
    client: Optional[str] = None


@router.post("/student/exams/{exam_id}/submit")
async def submit_attempt(
    exam_id: str,
    payload: SubmitIn,
    credentials: HTTPAuthorizationCredentials | None = Depends(_exam_credentials),
    db: AsyncSession = Depends(get_db),
):
    """§22/§23 — final submission. Idempotent; marked server-side (§29);
    scores hidden until the school publishes them."""
    user, _code = await _exam_student(db, credentials)
    attempt = await _attempt_of(db, payload.attempt_id, str(user.id), exam_id)
    exam = await _get_school_exam(db, exam_id, user.school_id)

    if attempt.status == "submitted":
        # Duplicate/replayed submission — idempotent success (offline queues).
        await _sync_log(
            db, exam, user.id, "duplicate_ignored", attempt_id=attempt.id,
            channel="offline_sync" if payload.offline_sync else "online",
        )
        await db.flush()
        return {
            "ok": True,
            "already_submitted": True,
            "sync_status": "synced",
            "message": "Your examination was already submitted successfully.",
        }

    now = naive_utc_now()
    if attempt.deadline_at and now > attempt.deadline_at:
        payload.is_auto_submit = True  # server knows it was late → auto

    qs = (
        await db.execute(select(SchoolExamQuestion).where(SchoolExamQuestion.exam_id == exam.id))
    ).scalars().all()
    ans_rows = (
        await db.execute(select(SchoolExamAnswer).where(SchoolExamAnswer.attempt_id == attempt.id))
    ).scalars().all()
    answers = {str(a.exam_question_id): (a.answer or "") for a in ans_rows}

    # §29 — AUTO MARKING: raw score → configured total mark.
    total_q = len(qs)
    answered = 0
    correct = 0
    wrong = 0
    raw_score = 0.0
    raw_total = 0.0
    for q in qs:
        raw_total += float(q.marks or 1)
        given = answers.get(str(q.id), "")
        if given:
            answered += 1
            mapped = _map_answer_back(q, given.split(",")[0], attempt.option_order) if "," not in given else None
            if "," in given:
                # multi-select: exact set match
                chosen = set(given.split(","))
                truth = set((q.correct_option or "").split(","))
                if chosen == truth and truth:
                    correct += 1
                    raw_score += float(q.marks or 1)
                else:
                    wrong += 1
            elif mapped and mapped == (q.correct_option or "").strip().upper():
                correct += 1
                raw_score += float(q.marks or 1)
            else:
                wrong += 1

    raw_total = raw_total or float(total_q or 1)
    pct_raw = (raw_score / raw_total) * 100 if raw_total else 0.0
    total_mark = int(exam.total_mark or 100)
    final_score = round(pct_raw / 100 * total_mark, 2)
    percentage = round(pct_raw, 2)
    grade = grade_from_percentage(percentage)

    attempt.status = "submitted"
    attempt.submitted_at = now
    attempt.is_auto_submitted = bool(payload.is_auto_submit)
    attempt.sync_status = "synced"

    res = (
        await db.execute(
            select(SchoolExamResult).where(
                SchoolExamResult.exam_id == exam.id, SchoolExamResult.student_id == user.id
            )
        )
    ).scalar_one_or_none()
    if not res:
        res = SchoolExamResult(school_id=exam.school_id, exam_id=exam.id, student_id=user.id, attempt_id=attempt.id)
        db.add(res)
    res.attempt_id = attempt.id
    res.total_questions = total_q
    res.questions_answered = answered
    res.correct_count = correct
    res.wrong_count = wrong
    res.raw_score = raw_score
    res.raw_total = raw_total
    res.total_mark = total_mark
    res.final_score = final_score
    res.percentage = percentage
    res.grade = grade
    res.is_published = bool(exam.results_published)

    await _sync_log(
        db, exam, user.id, "submitted", attempt_id=attempt.id,
        channel="offline_sync" if payload.offline_sync else "online",
        detail={
            "client": payload.client,
            "is_auto_submit": payload.is_auto_submit,
            "answered": answered,
            "correct": correct,
            "device_submitted_at": payload.submitted_at.isoformat() if payload.submitted_at else None,
            "device_started_at": payload.started_at.isoformat() if payload.started_at else None,
        },
    )
    await db.flush()

    published = bool(exam.results_published)
    return {
        "ok": True,
        "already_submitted": False,
        "sync_status": "synced",
        "summary": {
            "total_questions": total_q,
            "answered": answered,
            "correct": correct,
            "wrong": wrong,
            "raw_score": raw_score,
            "total_mark": total_mark,
            "final_score": final_score if published else None,
            "percentage": percentage if published else None,
            "grade": grade if published else None,
        },
        "result_hidden": not published,
        "message": (
            "Exam submitted successfully. Your result will be available when your school publishes it."
            if not published
            else "Exam submitted successfully — see your result."
        ),
    }


class OfflineBatchIn(BaseModel):
    """§23 — encrypted-at-rest local queue flushed when internet returns."""
    attempt_id: str
    answers: list[dict] = []   # [{question_id, answer, is_flagged}]
    submit: bool = False
    is_auto_submit: bool = False
    started_at: Optional[datetime] = None
    submitted_at: Optional[datetime] = None
    client: Optional[str] = None


@router.post("/student/sync")
async def offline_sync(
    payload: OfflineBatchIn,
    credentials: HTTPAuthorizationCredentials | None = Depends(_exam_credentials),
    db: AsyncSession = Depends(get_db),
):
    """Batch sync of offline answers, then optional submit. Each answer is
    validated against the server's own attempt/question mapping (§30)."""
    user, _code = await _exam_student(db, credentials)
    try:
        aid = UUID(payload.attempt_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Attempt not found")
    attempt = (await db.execute(select(SchoolExamAttempt).where(SchoolExamAttempt.id == aid))).scalar_one_or_none()
    if not attempt or str(attempt.student_id) != str(user.id):
        raise HTTPException(status_code=404, detail="Attempt not found")
    exam = (await db.execute(select(SchoolExam).where(SchoolExam.id == attempt.exam_id))).scalar_one_or_none()
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")
    valid_qids = {
        str(q.id) for q in (
            await db.execute(select(SchoolExamQuestion).where(SchoolExamQuestion.exam_id == attempt.exam_id))
        ).scalars().all()
    }
    synced = 0
    if attempt.status != "submitted":
        for item in payload.answers or []:
            qid = str(item.get("question_id") or "")
            if qid not in valid_qids:
                continue  # forged/foreign question ids are dropped silently
            ans = (str(item.get("answer") or "") or None)
            row = (
                await db.execute(
                    select(SchoolExamAnswer).where(
                        SchoolExamAnswer.attempt_id == attempt.id,
                        SchoolExamAnswer.exam_question_id == UUID(qid),
                    )
                )
            ).scalar_one_or_none()
            if not row:
                row = SchoolExamAnswer(
                    school_id=attempt.school_id, attempt_id=attempt.id,
                    exam_question_id=UUID(qid), student_id=user.id,
                )
                db.add(row)
            if ans is not None:
                row.answer = ans.strip().upper()[:50] or None
            if item.get("is_flagged") is not None:
                row.is_flagged = bool(item.get("is_flagged"))
            row.synced_offline = True
            synced += 1
        await _sync_log(
            db, exam, user.id, "offline_batch", attempt_id=attempt.id, channel="offline_sync",
            detail={"synced": synced, "submit": bool(payload.submit)},
        )
        await db.flush()
    result = None
    if payload.submit:
        result = await submit_attempt(
            attempt.exam_id,
            SubmitIn(
                attempt_id=str(attempt.id),
                is_auto_submit=payload.is_auto_submit,
                offline_sync=True,
                started_at=payload.started_at,
                submitted_at=payload.submitted_at,
                client=payload.client,
            ),
            credentials,
            db,
        )
    return {"ok": True, "answers_synced": synced, "result": result}


@router.get("/student/results")
async def student_results(
    credentials: HTTPAuthorizationCredentials | None = Depends(_exam_credentials),
    db: AsyncSession = Depends(get_db),
):
    """§29 — student sees only PUBLISHED results."""
    user, _code = await _exam_student(db, credentials)
    rows = (
        await db.execute(
            select(SchoolExamResult, SchoolExam)
            .join(SchoolExam, SchoolExam.id == SchoolExamResult.exam_id)
            .where(
                SchoolExamResult.student_id == user.id,
                SchoolExamResult.is_published == True,  # noqa: E712
            )
            .order_by(SchoolExamResult.created_at.desc())
        )
    ).all()
    return {
        "results": [
            {
                "exam_id": str(exam.id),
                "exam_title": exam.title,
                "subject": exam.subject,
                "class_name": exam.class_name,
                "total_questions": r.total_questions,
                "questions_answered": r.questions_answered,
                "correct": r.correct_count,
                "wrong": r.wrong_count,
                "raw_score": r.raw_score,
                "total_mark": r.total_mark,
                "final_score": r.final_score,
                "percentage": r.percentage,
                "grade": r.grade,
                "date": r.created_at.isoformat() if r.created_at else None,
            }
            for r, exam in rows
        ]
    }
