import secrets
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import require_school_staff
from app.core.security import hash_password
from app.models.cbt import CBTExam, CBTQuestion, CBTSession, ExamProctorLog
from app.models.school_campus import SchoolCampus
from app.models.school_office import SchoolExamCandidate
from app.models.user import StudentProfile, TeacherProfile, User, UserRole
from app.models.live_class import LiveClass
from app.core.datetime_utils import naive_utc_now

router = APIRouter(prefix="/admin/school-office", tags=["School office"])


async def _campus(db: AsyncSession, current_user: dict, school_id: str | None = None) -> SchoolCampus:
    sid = current_user.get("school_id") if current_user.get("role") == "school_admin" else school_id
    if not sid:
        raise HTTPException(status_code=400, detail="Main admin must add a school first, then pick it here")
    row = (await db.execute(select(SchoolCampus).where(SchoolCampus.id == sid))).scalar_one_or_none()
    if not row or not row.is_active:
        raise HTTPException(status_code=404, detail="School not found")
    return row


def _gen_rec() -> str:
    return "REC-" + datetime.utcnow().strftime("%Y") + "-" + secrets.token_hex(3).upper()


def _gen_candidate_id() -> str:
    return "SCH-" + datetime.utcnow().strftime("%Y") + "-" + secrets.token_hex(3).upper()


def _gen_access() -> str:
    return secrets.token_hex(4).upper()


def _candidate_dict(row: SchoolExamCandidate) -> dict:
    return {
        "id": str(row.id),
        "school_name": row.school_name,
        "class_name": row.class_name,
        "full_name": row.full_name,
        "email": row.email,
        "phone": row.phone,
        "rec_number": row.rec_number,
        "candidate_id": getattr(row, "candidate_id", None),
        "access_code": row.access_code,
        "subjects": list(row.subjects or []),
        "school_id": str(row.school_id) if getattr(row, "school_id", None) else None,
        "user_id": str(row.user_id) if row.user_id else None,
        "is_restricted": bool(row.is_restricted),
        "retake_exam_ids": list(row.retake_exam_ids or []),
        "created_at": row.created_at.isoformat() if row.created_at else None,
    }


class RegisterCandidateRequest(BaseModel):
    school_id: Optional[str] = None
    school_name: Optional[str] = None
    class_name: str = Field(..., min_length=2, max_length=40)
    full_name: str = Field(..., min_length=2, max_length=255)
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    subjects: list[str] = []


class SchoolTeacherRequest(BaseModel):
    school_id: Optional[str] = None
    full_name: str
    email: EmailStr
    password: str = Field(..., min_length=8)
    subjects: list[str] = []
    academic_classes: list[str] = []


class RetakeRequest(BaseModel):
    exam_id: str
    student_email: Optional[str] = None
    candidate_id: Optional[str] = None


@router.get("/me")
async def school_office_me(
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    if current_user.get("role") == "admin":
        schools = (await db.execute(select(SchoolCampus).order_by(SchoolCampus.name))).scalars().all()
        return {
            "role": "admin",
            "school_id": None,
            "school_name": None,
            "schools": [{"id": str(s.id), "name": s.name, "code": s.code} for s in schools if s.is_active],
        }
    campus = await _campus(db, current_user)
    return {
        "role": "school_admin",
        "school_id": str(campus.id),
        "school_name": campus.name,
        "schools": [{"id": str(campus.id), "name": campus.name, "code": campus.code}],
    }


@router.post("/candidates", status_code=201)
async def register_candidate(
    payload: RegisterCandidateRequest,
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    campus = await _campus(db, current_user, payload.school_id)
    row = SchoolExamCandidate(
        school_id=campus.id,
        school_name=campus.name,
        class_name=payload.class_name.strip().upper(),
        full_name=payload.full_name.strip(),
        email=str(payload.email).lower() if payload.email else None,
        phone=payload.phone,
        rec_number=_gen_rec(),
        candidate_id=_gen_candidate_id(),
        access_code=_gen_access(),
        subjects=[s.strip() for s in payload.subjects if str(s).strip()],
        created_by=current_user["sub"],
    )
    db.add(row)
    await db.flush()
    return _candidate_dict(row)


@router.get("/candidates")
async def list_candidates(
    q: Optional[str] = Query(None),
    class_name: Optional[str] = Query(None),
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    query = select(SchoolExamCandidate).order_by(SchoolExamCandidate.created_at.desc())
    sid = current_user.get("school_id") if current_user.get("role") == "school_admin" else school_id
    if sid:
        query = query.where(SchoolExamCandidate.school_id == sid)
    if q:
        like = f"%{q.strip().lower()}%"
        query = query.where(
            or_(
                func.lower(SchoolExamCandidate.email).like(like),
                func.lower(SchoolExamCandidate.full_name).like(like),
                func.lower(SchoolExamCandidate.rec_number).like(like),
                func.lower(SchoolExamCandidate.access_code).like(like),
            )
        )
    if class_name:
        query = query.where(SchoolExamCandidate.class_name == class_name.strip().upper())
    rows = (await db.execute(query.limit(400))).scalars().all()
    return {"candidates": [_candidate_dict(r) for r in rows], "count": len(rows)}


@router.get("/candidates/{candidate_id}/slip")
async def candidate_slip(
    candidate_id: str,
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    row = (
        await db.execute(select(SchoolExamCandidate).where(SchoolExamCandidate.id == candidate_id))
    ).scalar_one_or_none()
    if not row:
        raise HTTPException(status_code=404, detail="Student not found")
    data = _candidate_dict(row)
    data["print_title"] = f"{row.school_name} — Exam registration slip"
    return data


class SchoolStudentIn(BaseModel):
    school_id: Optional[str] = None
    full_name: str
    email: EmailStr
    class_name: str
    student_id: Optional[str] = None
    password: Optional[str] = None


def _student_row(user: User, profile: StudentProfile | None, campus: SchoolCampus) -> dict:
    return {
        "id": str(user.id),
        "full_name": user.full_name,
        "email": user.email,
        "class_name": profile.education_level if profile else None,
        "student_id": getattr(profile, "school_student_id", None) if profile else None,
        "is_active": user.is_active,
        "school_name": campus.name,
    }


async def _create_school_student(db: AsyncSession, campus: SchoolCampus, payload: SchoolStudentIn) -> tuple[User, str]:
    email = str(payload.email).lower()
    existing = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=400, detail=f"Email already in use: {email}")
    password = (payload.password or "").strip() or secrets.token_urlsafe(8)
    sid = (payload.student_id or "").strip().upper() or (
        (campus.code or "STU").upper()[:8] + "-" + secrets.token_hex(2).upper()
    )
    user = User(
        email=email,
        hashed_password=hash_password(password),
        full_name=payload.full_name.strip(),
        role=UserRole.student,
        is_verified=True,
        is_active=True,
        school_id=campus.id,
    )
    db.add(user)
    await db.flush()
    db.add(
        StudentProfile(
            user_id=user.id,
            education_level=payload.class_name.strip().upper(),
            school_student_id=sid,
            has_active_subscription=bool(getattr(campus, "subscription_active", False)),
        )
    )
    await db.flush()
    return user, password


@router.get("/students")
async def list_school_students(
    q: Optional[str] = Query(None),
    class_name: Optional[str] = Query(None),
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    campus = await _campus(db, current_user, school_id)
    rows = (
        await db.execute(
            select(User, StudentProfile)
            .outerjoin(StudentProfile, StudentProfile.user_id == User.id)
            .where(User.role == UserRole.student, User.school_id == campus.id)
            .order_by(User.full_name)
        )
    ).all()
    needle = (q or "").strip().lower()
    cls = (class_name or "").strip().upper()
    out = []
    for user, profile in rows:
        if cls and (profile.education_level if profile else "") != cls:
            continue
        blob = " ".join([user.full_name, user.email, getattr(profile, "school_student_id", None) or ""]).lower()
        if needle and needle not in blob:
            continue
        out.append(_student_row(user, profile, campus))
    return {"students": out, "subscription_active": bool(campus.subscription_active), "subscription_plan": campus.subscription_plan}


@router.post("/students", status_code=201)
async def add_school_student(
    payload: SchoolStudentIn,
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    campus = await _campus(db, current_user, payload.school_id)
    user, password = await _create_school_student(db, campus, payload)
    profile = (await db.execute(select(StudentProfile).where(StudentProfile.user_id == user.id))).scalar_one_or_none()
    data = _student_row(user, profile, campus)
    data["password"] = password
    return data


@router.post("/students/import")
async def import_school_students(
    file: UploadFile = File(...),
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    import csv
    import io

    campus = await _campus(db, current_user, school_id)
    raw = (await file.read()).decode("utf-8-sig", errors="replace")
    reader = csv.DictReader(io.StringIO(raw))
    created = []
    errors = []
    for i, row in enumerate(reader, start=2):
        name = (row.get("name") or row.get("full_name") or "").strip()
        email = (row.get("email") or "").strip()
        klass = (row.get("class") or row.get("class_name") or "").strip()
        sid = (row.get("student_id") or row.get("id") or "").strip()
        password = (row.get("password") or "").strip() or None
        if not name or not email or not klass:
            errors.append(f"Row {i}: name, email and class are required")
            continue
        try:
            user, pw = await _create_school_student(
                db,
                campus,
                SchoolStudentIn(full_name=name, email=email, class_name=klass, student_id=sid or None, password=password),
            )
            profile = (await db.execute(select(StudentProfile).where(StudentProfile.user_id == user.id))).scalar_one()
            item = _student_row(user, profile, campus)
            item["password"] = pw
            created.append(item)
        except HTTPException as exc:
            errors.append(f"Row {i}: {exc.detail}")
    await db.flush()
    return {"created": created, "created_count": len(created), "errors": errors}


class StudentPatchIn(BaseModel):
    class_name: Optional[str] = None
    student_id: Optional[str] = None
    is_active: Optional[bool] = None
    password: Optional[str] = None


@router.patch("/students/{user_id}")
async def update_school_student(
    user_id: str,
    payload: StudentPatchIn,
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    campus = await _campus(db, current_user, None if current_user.get("role") == "school_admin" else None)
    user = (await db.execute(select(User).where(User.id == user_id, User.school_id == campus.id))).scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="Student not found")
    profile = (await db.execute(select(StudentProfile).where(StudentProfile.user_id == user.id))).scalar_one_or_none()
    if payload.class_name and profile:
        profile.education_level = payload.class_name.strip().upper()
    if payload.student_id and profile:
        profile.school_student_id = payload.student_id.strip().upper()
    if payload.is_active is not None:
        user.is_active = payload.is_active
    new_password = None
    if payload.password:
        new_password = payload.password.strip()
        user.hashed_password = hash_password(new_password)
        user.token_version = int(user.token_version or 0) + 1
    await db.flush()
    data = _student_row(user, profile, campus)
    if new_password:
        data["password"] = new_password
    return data


@router.post("/teachers", status_code=201)
async def add_school_teacher(
    payload: SchoolTeacherRequest,
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    campus = await _campus(db, current_user, payload.school_id)
    existing = (await db.execute(select(User).where(User.email == payload.email.lower()))).scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=400, detail="Email already in use")
    user = User(
        email=payload.email.lower(),
        hashed_password=hash_password(payload.password),
        full_name=payload.full_name.strip(),
        role=UserRole.teacher,
        is_verified=True,
        is_active=True,
        school_id=campus.id,
    )
    db.add(user)
    await db.flush()
    db.add(
        TeacherProfile(
            user_id=user.id,
            subjects=payload.subjects,
            academic_classes=[c.strip().upper() for c in payload.academic_classes if str(c).strip()],
            is_approved=True,
            school_id=campus.id,
        )
    )
    await db.flush()
    return {
        "id": str(user.id),
        "email": user.email,
        "full_name": user.full_name,
        "subjects": payload.subjects,
        "academic_classes": payload.academic_classes,
        "is_approved": True,
    }


@router.get("/teachers")
async def list_school_teachers(
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    campus = await _campus(db, current_user, school_id)
    rows = (
        await db.execute(
            select(User, TeacherProfile)
            .outerjoin(TeacherProfile, TeacherProfile.user_id == User.id)
            .where(User.role == UserRole.teacher, User.school_id == campus.id)
            .order_by(User.full_name)
        )
    ).all()
    return {
        "teachers": [
            {
                "id": str(u.id),
                "full_name": u.full_name,
                "email": u.email,
                "subjects": (p.subjects if p else []) or [],
                "academic_classes": (p.academic_classes if p else []) or [],
            }
            for u, p in rows
        ]
    }


@router.get("/results")
async def print_results(
    class_name: Optional[str] = Query(None),
    subject: Optional[str] = Query(None),
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    campus = await _campus(db, current_user, school_id)
    query = (
        select(CBTSession, CBTExam, User)
        .join(CBTExam, CBTExam.id == CBTSession.exam_id)
        .join(User, User.id == CBTSession.student_id)
        .where(
            CBTSession.submitted_at.isnot(None),
            CBTExam.is_school_exam == True,  # noqa: E712
            CBTExam.school_id == campus.id,
        )
        .order_by(CBTSession.submitted_at.desc())
    )
    if subject:
        query = query.where(func.lower(CBTExam.subject) == subject.strip().lower())
    rows = (await db.execute(query.limit(500))).all()
    out = []
    for session, exam, user in rows:
        if class_name:
            cand = (
                await db.execute(
                    select(SchoolExamCandidate).where(
                        func.lower(SchoolExamCandidate.email) == (user.email or "").lower(),
                        SchoolExamCandidate.class_name == class_name.strip().upper(),
                    )
                )
            ).scalar_one_or_none()
            if not cand:
                continue
        out.append(
            {
                "student_name": user.full_name,
                "email": user.email,
                "exam_title": exam.title,
                "subject": exam.subject,
                "score": session.score,
                "percentage": session.percentage,
                "total_correct": session.total_correct,
                "total_wrong": session.total_wrong,
                "submitted_at": session.submitted_at.isoformat() if session.submitted_at else None,
            }
        )
    return {"results": out, "count": len(out)}


@router.post("/retake")
async def grant_retake(
    payload: RetakeRequest,
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    student_id = None
    candidate = None
    if payload.candidate_id:
        candidate = (
            await db.execute(
                select(SchoolExamCandidate).where(SchoolExamCandidate.id == payload.candidate_id)
            )
        ).scalar_one_or_none()
        if candidate and candidate.user_id:
            student_id = candidate.user_id
        elif candidate and candidate.email:
            user = (
                await db.execute(select(User).where(func.lower(User.email) == candidate.email.lower()))
            ).scalar_one_or_none()
            student_id = user.id if user else None
    if payload.student_email:
        user = (
            await db.execute(select(User).where(func.lower(User.email) == payload.student_email.lower()))
        ).scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="No student account for that email")
        student_id = user.id
    if not student_id:
        raise HTTPException(status_code=400, detail="Could not match a student account to retake")
    session_ids = (
        await db.execute(
            select(CBTSession.id).where(
                CBTSession.exam_id == payload.exam_id,
                CBTSession.student_id == student_id,
            )
        )
    ).scalars().all()
    if session_ids:
        await db.execute(delete(ExamProctorLog).where(ExamProctorLog.session_id.in_(session_ids)))
    await db.execute(
        delete(CBTSession).where(
            CBTSession.exam_id == payload.exam_id,
            CBTSession.student_id == student_id,
        )
    )
    if candidate:
        ids = list(candidate.retake_exam_ids or [])
        if payload.exam_id not in ids:
            ids.append(payload.exam_id)
        candidate.retake_exam_ids = ids
    await db.flush()
    return {"ok": True, "message": "Student can retake this exam."}


@router.get("/exam-counts")
async def exam_counts(
    school_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    query = select(CBTExam).where(CBTExam.is_school_exam == True).order_by(CBTExam.created_at.desc())  # noqa: E712
    sid = current_user.get("school_id") if current_user.get("role") == "school_admin" else school_id
    if sid:
        query = query.where(CBTExam.school_id == sid)
    exams = (await db.execute(query)).scalars().all()
    out = []
    for exam in exams:
        taken = (
            await db.execute(
                select(func.count(CBTSession.id)).where(
                    CBTSession.exam_id == exam.id,
                    CBTSession.submitted_at.isnot(None),
                )
            )
        ).scalar() or 0
        out.append(
            {
                "id": str(exam.id),
                "title": exam.title,
                "subject": exam.subject,
                "is_published": exam.is_published,
                "taken_count": int(taken),
                "scheduled_start": exam.scheduled_start.isoformat() if exam.scheduled_start else None,
                "scheduled_end": exam.scheduled_end.isoformat() if exam.scheduled_end else None,
            }
        )
    return {"exams": out}


class SchoolExamQuestionIn(BaseModel):
    question_text: str
    option_a: str
    option_b: str
    option_c: str
    option_d: str
    correct_option: str = "A"


class SchoolExamCreate(BaseModel):
    school_id: Optional[str] = None
    title: str
    subject: str
    duration_minutes: int = 45
    scheduled_start: Optional[datetime] = None
    scheduled_end: Optional[datetime] = None
    questions: list[SchoolExamQuestionIn] = []
    is_published: bool = True


class SchoolExamSchedule(BaseModel):
    scheduled_start: Optional[datetime] = None
    scheduled_end: Optional[datetime] = None
    is_published: Optional[bool] = None


@router.post("/exams", status_code=201)
async def create_school_exam(
    payload: SchoolExamCreate,
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    campus = await _campus(db, current_user, payload.school_id)
    if not payload.questions:
        raise HTTPException(status_code=400, detail="Add at least one question")
    exam = CBTExam(
        title=payload.title.strip(),
        subject=payload.subject.strip(),
        exam_type="SCHOOL",
        duration_minutes=max(5, min(int(payload.duration_minutes or 45), 300)),
        total_questions=len(payload.questions),
        created_by=current_user["sub"],
        is_published=payload.is_published,
        is_school_exam=True,
        school_id=campus.id,
        scheduled_start=payload.scheduled_start,
        scheduled_end=payload.scheduled_end,
        ai_locked=True,
        camera_required=False,
        block_minimize=True,
    )
    db.add(exam)
    await db.flush()
    for q in payload.questions:
        opt = (q.correct_option or "A").upper()
        if opt not in ("A", "B", "C", "D"):
            raise HTTPException(status_code=400, detail="correct_option must be A/B/C/D")
        db.add(
            CBTQuestion(
                exam_id=exam.id,
                question_text=q.question_text,
                option_a=q.option_a,
                option_b=q.option_b,
                option_c=q.option_c,
                option_d=q.option_d,
                correct_option=opt,
            )
        )
    await db.flush()
    return {"id": str(exam.id), "title": exam.title, "subject": exam.subject, "total_questions": exam.total_questions}


@router.patch("/exams/{exam_id}")
async def schedule_school_exam(
    exam_id: str,
    payload: SchoolExamSchedule,
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    exam = (await db.execute(select(CBTExam).where(CBTExam.id == exam_id))).scalar_one_or_none()
    if not exam or not exam.is_school_exam:
        raise HTTPException(status_code=404, detail="Exam not found")
    if current_user.get("role") == "school_admin" and str(exam.school_id) != str(current_user.get("school_id")):
        raise HTTPException(status_code=403, detail="This exam is not in your school")
    if payload.scheduled_start is not None:
        exam.scheduled_start = payload.scheduled_start
    if payload.scheduled_end is not None:
        exam.scheduled_end = payload.scheduled_end
    if payload.is_published is not None:
        exam.is_published = payload.is_published
    await db.flush()
    return {"ok": True, "id": str(exam.id)}


@router.post("/live-classes", status_code=201)
async def host_school_live_class(
    payload: dict,
    current_user: dict = Depends(require_school_staff),
    db: AsyncSession = Depends(get_db),
):
    campus = await _campus(db, current_user, payload.get("school_id"))
    vis = str(payload.get("visibility") or "class_level").strip().lower()
    if vis not in ("class_level", "private", "public"):
        vis = "class_level"
    live_class = LiveClass(
        teacher_id=current_user["sub"],
        subject=str(payload.get("subject") or "").strip(),
        title=str(payload.get("title") or "").strip(),
        start_time=naive_utc_now(),
        room_id="room-" + secrets.token_hex(6),
        join_code="SX-" + secrets.token_hex(4).upper(),
        is_live=bool(payload.get("start_now")),
        visibility=vis,
        academic_class=(str(payload.get("academic_class") or "").strip().upper() or None),
        school_id=campus.id,
    )
    if not live_class.title or not live_class.subject:
        raise HTTPException(status_code=400, detail="Title and subject are required")
    db.add(live_class)
    await db.flush()
    return {
        "id": str(live_class.id),
        "title": live_class.title,
        "subject": live_class.subject,
        "is_live": live_class.is_live,
        "school_name": campus.name,
    }
