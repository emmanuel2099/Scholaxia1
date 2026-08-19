from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Form
from fastapi.responses import Response
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, or_, text
from pydantic import BaseModel, EmailStr
from datetime import datetime
from typing import Optional
import json
import uuid
from app.core.database import get_db
from app.core.datetime_utils import naive_utc_now
from app.core.deps import require_admin
from app.core.security import hash_password, create_access_token, create_refresh_token, issue_auth_tokens
from app.models.user import User, UserRole, TeacherProfile, StudentProfile, KindProfile, VendorProfile
from app.models.content import Book, LibraryTarget
from app.models.cbt import CBTExam, CBTQuestion, CBTSession, ExamProctorLog, normalize_paper_kind
from app.models.community import CommunityPost, CommunityChannel
from app.models.student_group import StudentGroup, StudentGroupMember
from app.services.group_community import ensure_group_feed_post
from app.services.media_service import generate_upload_signature, upload_file
from app.services.cbt_import import CBT_IMPORT_TEMPLATE, normalize_exam_type, parse_cbt_file
from app.services.notification_service import (
    send_all_students_notification,
    send_all_teachers_notification,
    send_subject_notification,
    send_users_notification,
)
from app.services.student_cleanup import delete_student_user
from app.services.user_cleanup import purge_all_user_accounts, delete_teacher_user, clear_all_user_emails

router = APIRouter(prefix="/admin", tags=["Admin"])


# ── Admin Self-Registration ───────────────────────────────────────────────────

class AdminRegisterRequest(BaseModel):
    email: EmailStr
    password: str
    full_name: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    role: str


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def admin_register(payload: AdminRegisterRequest, db: AsyncSession = Depends(get_db)):
    """Admin creates their own account."""
    if len(payload.password) > 72:
        raise HTTPException(status_code=400, detail="Password must be 72 characters or less")
    existing = await db.execute(select(User).where(User.email == payload.email))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Email already registered")
    user = User(
        email=payload.email,
        hashed_password=hash_password(payload.password),
        full_name=payload.full_name,
        role=UserRole.admin,
        is_active=True,
        is_verified=True,
    )
    db.add(user)
    await db.flush()
    access_token, refresh_token = await issue_auth_tokens(db, user)
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        role=user.role,
    )


# ── Teacher Management ────────────────────────────────────────────────────────

class CreateTeacherRequest(BaseModel):
    email: EmailStr
    password: str
    full_name: str
    subjects: list[str]
    bio: str = ""


class TeacherResponse(BaseModel):
    id: str
    email: str
    full_name: str
    subjects: list[str] = []
    phone: Optional[str] = None
    location: Optional[str] = None
    is_approved: bool = False


@router.post("/teachers", response_model=TeacherResponse, status_code=status.HTTP_201_CREATED)
async def create_teacher(
    payload: CreateTeacherRequest,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin creates teacher accounts."""
    existing = await db.execute(select(User).where(User.email == payload.email))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Email already in use")
    user = User(
        email=payload.email,
        hashed_password=hash_password(payload.password),
        full_name=payload.full_name,
        role=UserRole.teacher,
        is_verified=True,
    )
    db.add(user)
    await db.flush()
    profile = TeacherProfile(user_id=user.id, subjects=payload.subjects, bio=payload.bio, is_approved=True)
    db.add(profile)
    await db.flush()
    return TeacherResponse(
        id=str(user.id),
        email=user.email,
        full_name=user.full_name,
        subjects=payload.subjects,
        is_approved=True,
    )


@router.get("/teachers", response_model=list[TeacherResponse])
async def list_teachers(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """All teacher accounts, including pending signups missing a profile row."""
    result = await db.execute(
        select(User, TeacherProfile)
        .outerjoin(TeacherProfile, TeacherProfile.user_id == User.id)
        .where(User.role == UserRole.teacher)
        .order_by(User.created_at.desc())
    )
    rows = result.all()
    out: list[TeacherResponse] = []
    created = False
    for u, p in rows:
        if p is None:
            p = TeacherProfile(
                user_id=u.id,
                subjects=[],
                bio="",
                is_approved=False,
            )
            db.add(p)
            created = True
        out.append(
            TeacherResponse(
                id=str(u.id),
                email=u.email,
                full_name=u.full_name,
                subjects=list(p.subjects or []),
                phone=u.phone,
                location=p.location,
                is_approved=bool(p.is_approved),
            )
        )
    if created:
        await db.flush()
    out.sort(key=lambda t: (t.is_approved, t.full_name.lower()))
    return out


@router.post("/teachers/{teacher_id}/approve")
async def approve_teacher(
    teacher_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(TeacherProfile, User)
        .join(User, User.id == TeacherProfile.user_id)
        .where(User.id == teacher_id, User.role == UserRole.teacher)
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Teacher not found")
    profile, _ = row
    profile.is_approved = True
    await db.flush()
    return {"message": "Teacher approved", "teacher_id": teacher_id, "is_approved": True}


@router.post("/teachers/{teacher_id}/reject")
async def reject_teacher(
    teacher_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(TeacherProfile, User)
        .join(User, User.id == TeacherProfile.user_id)
        .where(User.id == teacher_id, User.role == UserRole.teacher)
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Teacher not found")
    profile, _ = row
    profile.is_approved = False
    await db.flush()
    return {"message": "Teacher access locked", "teacher_id": teacher_id, "is_approved": False}


class VendorAdminResponse(BaseModel):
    id: str
    email: str
    full_name: str
    business_name: str
    location: Optional[str] = None
    address: Optional[str] = None
    phone: Optional[str] = None
    whatsapp: Optional[str] = None
    is_approved: bool = False
    kyc_completed: bool = False
    nin: Optional[str] = None


class VendorApproveRequest(BaseModel):
    whatsapp: str
    is_approved: bool = True


@router.get("/vendors", response_model=list[VendorAdminResponse])
async def list_vendors(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User, VendorProfile)
        .join(VendorProfile, VendorProfile.user_id == User.id)
        .where(User.role == UserRole.vendor, User.is_active == True)  # noqa: E712
        .order_by(User.created_at.desc())
    )
    out = []
    for u, p in result.all():
        out.append(
            VendorAdminResponse(
                id=str(u.id),
                email=u.email,
                full_name=u.full_name,
                business_name=p.business_name,
                location=p.location,
                address=p.address,
                phone=u.phone,
                whatsapp=(p.whatsapp or u.phone or None),
                is_approved=bool(p.is_approved),
                kyc_completed=bool(p.kyc_completed and (p.nin or "").strip()),
                nin=p.nin,
            )
        )
    return out


@router.post("/vendors/{vendor_id}/approve")
async def approve_vendor(
    vendor_id: str,
    payload: VendorApproveRequest,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Approve a vendor and store their WhatsApp for marketplace contact."""
    wa = (payload.whatsapp or "").strip()
    if len(wa) < 7:
        raise HTTPException(status_code=400, detail="WhatsApp number is required to approve a vendor.")
    result = await db.execute(
        select(VendorProfile, User)
        .join(User, User.id == VendorProfile.user_id)
        .where(User.id == vendor_id, User.role == UserRole.vendor)
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Vendor not found")
    profile, user = row
    profile.whatsapp = wa
    profile.is_approved = bool(payload.is_approved)
    await db.flush()
    if profile.is_approved:
        await send_users_notification(
            db,
            [str(user.id)],
            title="Vendor account approved",
            body=(
                "Scholaxia approved your vendor store. Complete KYC (NIN), "
                "then you can list products for students."
            ),
            notification_type="announcement",
            data={"type": "vendor_approved"},
        )
    return {
        "message": "Vendor updated",
        "vendor_id": vendor_id,
        "is_approved": profile.is_approved,
        "whatsapp": profile.whatsapp,
    }


@router.post("/vendors/{vendor_id}/reject")
async def reject_vendor(
    vendor_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(VendorProfile, User)
        .join(User, User.id == VendorProfile.user_id)
        .where(User.id == vendor_id, User.role == UserRole.vendor)
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Vendor not found")
    profile, _ = row
    profile.is_approved = False
    await db.flush()
    return {"message": "Vendor access locked", "vendor_id": vendor_id, "is_approved": False}


@router.delete("/teachers/{teacher_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_teacher(
    teacher_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    import uuid as _uuid
    try:
        uid = _uuid.UUID(teacher_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid teacher id")
    deleted = await delete_teacher_user(db, uid)
    if not deleted:
        raise HTTPException(status_code=404, detail="Teacher not found")


@router.post("/teachers/remove-all")
async def remove_all_teachers(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Permanently delete every teacher account."""
    result = await db.execute(select(User).where(User.role == UserRole.teacher))
    teachers = result.scalars().all()
    removed = 0
    for user in teachers:
        if await delete_teacher_user(db, user.id):
            removed += 1
    await db.flush()
    return {"removed": removed}

class AddBookRequest(BaseModel):
    title: str
    author: Optional[str] = None
    subject: str
    exam_type: Optional[str] = None
    file_key: str
    cover_image_url: Optional[str] = None
    description: Optional[str] = None
    total_pages: Optional[int] = None
    category: str = "Books"
    education_level: Optional[str] = None
    term: Optional[str] = None
    scheme_week: Optional[int] = None
    scheme_topic: Optional[str] = None
    library_target: LibraryTarget = LibraryTarget.student
    is_free: bool = True
    price: float = 0.0
    is_downloadable: bool = False


class PatchBookRequest(BaseModel):
    is_downloadable: Optional[bool] = None


class BookResponse(BaseModel):
    id: str
    title: str
    subject: str
    library_target: str
    is_downloadable: bool
    allow_copy: bool
    allow_screenshot: bool


@router.post("/library/upload-file")
async def upload_library_pdf(
    file: UploadFile = File(...),
    current_user: dict = Depends(require_admin),
):
    """Upload a PDF into the authenticated books folder; returns file_key for create."""
    name = (file.filename or "book.pdf").strip() or "book.pdf"
    content_type = (file.content_type or "").split(";")[0].strip().lower()
    content = await file.read()
    is_pdf = (
        content_type in ("application/pdf", "application/x-pdf")
        or name.lower().endswith(".pdf")
        or (content[:5] == b"%PDF-")
    )
    if not is_pdf:
        raise HTTPException(
            status_code=400,
            detail="Library needs a PDF file, not an image. Choose a .pdf.",
        )
    if not content:
        raise HTTPException(status_code=400, detail="Empty PDF file.")
    if len(content) > 40 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="PDF too large (max 40MB).")
    try:
        result = upload_file(content, "books", filename=name)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Upload failed: {e}")
    return {
        "file_key": (result.get("secure_url") or result["public_id"]),
        "secure_url": result.get("secure_url") or "",
        "filename": name,
    }


@router.post("/library/upload-url")
async def get_book_upload_url(current_user: dict = Depends(require_admin)):
    return generate_upload_signature(folder="books")


@router.post("/library/books", response_model=BookResponse, status_code=201)
async def add_book(
    payload: AddBookRequest,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    category = (payload.category or "Books").strip()
    is_free = bool(payload.is_free)
    price = float(payload.price or 0)
    # Past Questions are always paid — students unlock via Paystack.
    if "past" in category.lower():
        is_free = False
        if price <= 0:
            raise HTTPException(
                status_code=400,
                detail="Past Questions must be paid. Enter a price greater than zero.",
            )
    if not is_free and price <= 0:
        raise HTTPException(
            status_code=400,
            detail="Set a price greater than zero for a paid material.",
        )
    book = Book(
        title=payload.title, author=payload.author, subject=payload.subject,
        exam_type=payload.exam_type, file_key=payload.file_key,
        cover_image_url=payload.cover_image_url, description=payload.description,
        total_pages=payload.total_pages,
        category=category,
        education_level=payload.education_level,
        term=payload.term,
        scheme_week=payload.scheme_week,
        scheme_topic=payload.scheme_topic,
        library_target=payload.library_target,
        is_free=is_free,
        price=0.0 if is_free else max(price, 0),
        uploaded_by=current_user["sub"],
        is_downloadable=bool(payload.is_downloadable),
        allow_copy=False, allow_screenshot=False, allow_print=False,
    )
    db.add(book)
    await db.flush()
    try:
        notify = (
            send_all_teachers_notification
            if book.library_target == LibraryTarget.teacher
            else send_all_students_notification
        )
        await notify(
            db=db,
            title="New library book",
            body=f"«{book.title}» ({book.subject}) is now in your library.",
            notification_type="announcement",
            data={"type": "library_book", "book_id": str(book.id)},
        )
    except Exception:
        pass
    target = book.library_target
    return BookResponse(
        id=str(book.id), title=book.title, subject=book.subject,
        library_target=target.value if hasattr(target, "value") else str(target),
        is_downloadable=bool(book.is_downloadable),
        allow_copy=False, allow_screenshot=False,
    )


@router.get("/library/books")
async def list_all_books(
    library_target: Optional[LibraryTarget] = None,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    query = select(Book).where(Book.is_active == True)  # noqa: E712
    if library_target:
        query = query.where(Book.library_target == library_target)
    result = await db.execute(query.order_by(Book.created_at.desc()))
    books = result.scalars().all()
    return [{"id": str(b.id), "title": b.title, "author": b.author,
             "subject": b.subject, "category": getattr(b, "category", "Books"),
             "education_level": getattr(b, "education_level", None),
             "term": getattr(b, "term", None),
             "scheme_week": getattr(b, "scheme_week", None),
             "scheme_topic": getattr(b, "scheme_topic", None),
             "library_target": b.library_target, "exam_type": b.exam_type,
             "is_free": getattr(b, "is_free", True),
             "price": float(getattr(b, "price", 0) or 0),
             "is_downloadable": bool(getattr(b, "is_downloadable", False)),
             "created_at": b.created_at}
            for b in books]


@router.patch("/library/books/{book_id}")
async def patch_library_book(
    book_id: str,
    payload: PatchBookRequest,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Book).where(Book.id == book_id))
    book = result.scalar_one_or_none()
    if not book:
        raise HTTPException(status_code=404, detail="Book not found")
    if payload.is_downloadable is not None:
        book.is_downloadable = bool(payload.is_downloadable)
    await db.flush()
    return {
        "id": str(book.id),
        "is_downloadable": bool(book.is_downloadable),
    }


@router.delete("/library/books/{book_id}", status_code=204)
async def remove_book(
    book_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Book).where(Book.id == book_id))
    book = result.scalar_one_or_none()
    if not book:
        raise HTTPException(status_code=404, detail="Book not found")
    book.is_active = False


@router.post("/library/books/{book_id}/replace-file")
async def replace_library_file(
    book_id: str,
    file: UploadFile = File(...),
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Upload a new PDF onto an existing library item (fixes missing Cloudinary files)."""
    result = await db.execute(select(Book).where(Book.id == book_id))
    book = result.scalar_one_or_none()
    if not book or not book.is_active:
        raise HTTPException(status_code=404, detail="Book not found")
    name = (file.filename or "book.pdf").strip() or "book.pdf"
    content_type = (file.content_type or "").split(";")[0].strip().lower()
    content = await file.read()
    is_pdf = (
        content_type in ("application/pdf", "application/x-pdf")
        or name.lower().endswith(".pdf")
        or content[:5] == b"%PDF-"
    )
    if not is_pdf:
        raise HTTPException(status_code=400, detail="Choose a .pdf file.")
    if not content:
        raise HTTPException(status_code=400, detail="Empty PDF file.")
    if len(content) > 40 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="PDF too large (max 40MB).")
    try:
        uploaded = upload_file(content, "books", filename=name)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Upload failed: {e}")
    book.file_key = uploaded.get("secure_url") or uploaded["public_id"]
    await db.flush()
    return {"ok": True, "id": str(book.id), "title": book.title}


# ── CBT Management ────────────────────────────────────────────────────────────

class CBTQuestionCreate(BaseModel):
    question_text: str
    option_a: str
    option_b: str
    option_c: str
    option_d: str
    correct_option: str   # A, B, C, or D
    explanation: Optional[str] = None
    topic: Optional[str] = None
    image_url: Optional[str] = None


def _normalize_cbt_year(raw) -> Optional[int]:
    if raw is None or str(raw).strip() == "":
        return None
    try:
        year = int(str(raw).strip()[:4])
    except (TypeError, ValueError):
        raise HTTPException(status_code=400, detail="Year must be a number like 2019")
    if year < 1990 or year > 2100:
        raise HTTPException(status_code=400, detail="Year must be between 1990 and 2100")
    return year


class CBTExamCreate(BaseModel):
    title: str
    subject: str
    exam_type: str           # JAMB | WAEC | NECO | SCHOOL | COMMON_ENTRANCE
    year: Optional[int] = None  # exam year — required from admin UI
    duration_minutes: int
    questions: list[CBTQuestionCreate]
    is_published: bool = True
    is_school_exam: bool = False
    paper_kind: str = "cbt_practice"
    ai_locked: bool = False
    camera_required: bool = False
    block_minimize: bool = False
    scheduled_start: Optional[datetime] = None
    scheduled_end: Optional[datetime] = None


class CBTExamResponse(BaseModel):
    id: str
    title: str
    subject: str
    exam_type: str
    year: Optional[int] = None
    duration_minutes: int
    total_questions: int
    is_published: bool
    is_school_exam: bool = False
    paper_kind: str = "cbt_practice"
    scheduled_start: Optional[datetime] = None
    scheduled_end: Optional[datetime] = None


async def _persist_cbt_exam(
    db: AsyncSession,
    payload: CBTExamCreate,
    created_by: str,
) -> CBTExam:
    if not payload.questions:
        raise HTTPException(status_code=400, detail="At least one question required")

    subject = (payload.subject or "").strip()
    if not subject:
        raise HTTPException(status_code=400, detail="Subject is required")
    year = _normalize_cbt_year(payload.year)
    if year is None:
        raise HTTPException(status_code=400, detail="Exam year is required")

    try:
        exam_type = normalize_exam_type(payload.exam_type)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    kind = "cbt_practice" if payload.is_school_exam else normalize_paper_kind(payload.paper_kind)
    exam = CBTExam(
        title=payload.title,
        subject=subject,
        exam_type=exam_type,
        year=year,
        duration_minutes=payload.duration_minutes,
        total_questions=len(payload.questions),
        created_by=created_by,
        is_published=payload.is_published,
        is_school_exam=payload.is_school_exam,
        paper_kind=kind,
        ai_locked=payload.ai_locked,
        camera_required=payload.camera_required,
        block_minimize=payload.block_minimize,
        scheduled_start=payload.scheduled_start,
        scheduled_end=payload.scheduled_end,
    )
    db.add(exam)
    await db.flush()

    for q in payload.questions:
        if q.correct_option.upper() not in ("A", "B", "C", "D"):
            raise HTTPException(
                status_code=400,
                detail=f"correct_option must be A/B/C/D, got: {q.correct_option}",
            )
        db.add(
            CBTQuestion(
                exam_id=exam.id,
                question_text=q.question_text,
                option_a=q.option_a,
                option_b=q.option_b,
                option_c=q.option_c,
                option_d=q.option_d,
                correct_option=q.correct_option.upper(),
                explanation=q.explanation,
                topic=q.topic,
                image_url=q.image_url,
            )
        )

    await db.flush()
    return exam


def _exam_to_response(exam: CBTExam) -> CBTExamResponse:
    return CBTExamResponse(
        id=str(exam.id),
        title=exam.title,
        subject=exam.subject,
        exam_type=exam.exam_type,
        year=exam.year,
        duration_minutes=exam.duration_minutes,
        total_questions=exam.total_questions,
        is_published=exam.is_published,
        is_school_exam=exam.is_school_exam,
        paper_kind=normalize_paper_kind(getattr(exam, "paper_kind", None)),
        scheduled_start=exam.scheduled_start,
        scheduled_end=exam.scheduled_end,
    )


async def _notify_published_exam(db: AsyncSession, exam: CBTExam) -> None:
    if not exam.is_published:
        return
    title = "New CBT exam"
    body = f"«{exam.title}» ({exam.subject}) is now available."
    data = {
        "type": "cbt_exam",
        "exam_id": str(exam.id),
        "subject": exam.subject,
    }
    assigned = [str(user_id) for user_id in (exam.assigned_student_ids or [])]
    if assigned:
        await send_users_notification(
            db, assigned, title, body, "cbt_reminder", data
        )
    else:
        await send_subject_notification(
            db, exam.subject, title, body, "cbt_reminder", data
        )


@router.post("/cbt/exams", response_model=CBTExamResponse, status_code=201)
async def create_cbt_exam(
    payload: CBTExamCreate,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin creates a CBT exam with all questions in one call."""
    exam = await _persist_cbt_exam(db, payload, current_user["sub"])
    try:
        await _notify_published_exam(db, exam)
    except Exception:
        pass
    return _exam_to_response(exam)


@router.get("/cbt/exams", response_model=list[CBTExamResponse])
async def admin_list_cbt_exams(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin lists all CBT exams including unpublished."""
    result = await db.execute(select(CBTExam).order_by(CBTExam.exam_type, CBTExam.subject))
    exams = result.scalars().all()
    return [_exam_to_response(e) for e in exams]


@router.patch("/cbt/exams/{exam_id}/publish")
async def toggle_publish(
    exam_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Toggle publish/unpublish an exam."""
    result = await db.execute(select(CBTExam).where(CBTExam.id == exam_id))
    exam = result.scalar_one_or_none()
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")
    exam.is_published = not exam.is_published
    await db.flush()
    if exam.is_published:
        try:
            await _notify_published_exam(db, exam)
        except Exception:
            pass
    return {"id": str(exam.id), "is_published": exam.is_published}


async def _delete_cbt_exam_cascade(db: AsyncSession, exam: CBTExam) -> None:
    """Remove an exam plus sessions, proctor logs, questions, and post links."""
    sessions = (
        await db.execute(select(CBTSession).where(CBTSession.exam_id == exam.id))
    ).scalars().all()
    for session in sessions:
        logs = (
            await db.execute(
                select(ExamProctorLog).where(ExamProctorLog.session_id == session.id)
            )
        ).scalars().all()
        for log in logs:
            await db.delete(log)
        await db.delete(session)

    posts = (
        await db.execute(
            select(CommunityPost).where(CommunityPost.cbt_exam_id == exam.id)
        )
    ).scalars().all()
    for post in posts:
        post.cbt_exam_id = None

    questions = (
        await db.execute(select(CBTQuestion).where(CBTQuestion.exam_id == exam.id))
    ).scalars().all()
    for question in questions:
        await db.delete(question)

    await db.delete(exam)


@router.delete("/cbt/exams/{exam_id}", status_code=204)
async def delete_cbt_exam(
    exam_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin deletes an exam and all related sessions/questions."""
    result = await db.execute(select(CBTExam).where(CBTExam.id == exam_id))
    exam = result.scalar_one_or_none()
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")
    await _delete_cbt_exam_cascade(db, exam)


@router.delete("/cbt/exams", status_code=200)
async def delete_all_cbt_exams(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin deletes every CBT exam (practice + school), including related data."""
    result = await db.execute(select(CBTExam))
    exams = result.scalars().all()
    deleted = 0
    for exam in exams:
        await _delete_cbt_exam_cascade(db, exam)
        deleted += 1
    return {"deleted_count": deleted}


@router.get("/cbt/import-template")
async def cbt_import_template(current_user: dict = Depends(require_admin)):
    """Download a sample JSON file for bulk CBT upload."""
    body = json.dumps(CBT_IMPORT_TEMPLATE, indent=2)
    return Response(
        content=body,
        media_type="application/json",
        headers={"Content-Disposition": 'attachment; filename="cbt_exam_template.json"'},
    )


@router.post("/cbt/import")
async def import_cbt_file(
    file: UploadFile = File(...),
    title: Optional[str] = Form(None),
    subject: Optional[str] = Form(None),
    year: Optional[str] = Form(None),
    exam_type: Optional[str] = Form(None),
    duration_minutes: Optional[int] = Form(30),
    is_published: str = Form("true"),
    skip_duplicates: str = Form("true"),
    paper_kind: Optional[str] = Form("cbt_practice"),
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Upload a .json or .csv CBT file. Questions are saved as normal exams in the database
    and appear in the student app like any other CBT (not as a downloadable file).
    Subject and year from the form are required and applied to every imported exam.
    """
    content = await file.read()
    if len(content) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="File too large. Maximum size is 10MB.")

    form_subject = (subject or "").strip()
    form_year = _normalize_cbt_year(year)
    if not form_subject:
        raise HTTPException(status_code=400, detail="Pick a subject before uploading")
    if form_year is None:
        raise HTTPException(status_code=400, detail="Pick the exam year before uploading")

    defaults = {
        "title": (title or "").strip() or None,
        "subject": form_subject,
        "year": form_year,
        "exam_type": (exam_type or "JAMB").strip().upper(),
        "duration_minutes": duration_minutes or 30,
        "is_published": is_published.strip().lower() in {"1", "true", "yes", "on"},
    }
    skip_dup = skip_duplicates.strip().lower() in {"1", "true", "yes", "on"}

    try:
        exam_payloads = parse_cbt_file(file.filename or "upload.json", content, defaults)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    created: list[dict] = []
    skipped: list[str] = []

    for raw in exam_payloads:
        # Form subject/year always win so the exam slots correctly on the platform.
        raw["subject"] = form_subject
        raw["year"] = form_year
        if skip_dup:
            existing = await db.execute(
                select(CBTExam).where(CBTExam.title == raw["title"])
            )
            if existing.scalar_one_or_none():
                skipped.append(raw["title"])
                continue

        payload = CBTExamCreate(
            title=raw["title"],
            subject=form_subject,
            year=form_year,
            exam_type=raw["exam_type"],
            duration_minutes=raw["duration_minutes"],
            is_published=raw.get("is_published", True),
            is_school_exam=raw.get("is_school_exam", False),
            paper_kind=normalize_paper_kind(paper_kind),
            questions=[CBTQuestionCreate(**q) for q in raw["questions"]],
        )
        exam = await _persist_cbt_exam(db, payload, current_user["sub"])
        try:
            await _notify_published_exam(db, exam)
        except Exception:
            pass
        created.append(
            {
                "id": str(exam.id),
                "title": exam.title,
                "subject": exam.subject,
                "year": exam.year,
                "exam_type": exam.exam_type,
                "total_questions": exam.total_questions,
                "is_published": exam.is_published,
            }
        )

    if not created and skipped:
        raise HTTPException(
            status_code=409,
            detail=f"All exams already exist: {', '.join(skipped)}",
        )

    return {
        "created": created,
        "created_count": len(created),
        "skipped": skipped,
        "skipped_count": len(skipped),
    }


@router.post("/cbt/import/preview")
async def preview_cbt_import(
    file: UploadFile = File(...),
    current_user: dict = Depends(require_admin),
):
    """
    Extract questions from an uploaded PDF, DOCX, JSON, or CSV WITHOUT saving anything.
    Returns editable questions with per-question confidence + issues so the admin
    can review and fix them, then save via POST /cbt/import/confirm.
    """
    from app.services.cbt_pdf_parser import (
        LOW_CONFIDENCE_THRESHOLD,
        PDFParseError,
        parse_docx_questions,
        parse_pdf_questions,
    )

    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="Uploaded file is empty")
    if len(content) > 15 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="File too large. Maximum size is 15MB.")

    name = (file.filename or "").lower()
    is_pdf = name.endswith(".pdf") or content[:5] == b"%PDF-"
    is_docx = name.endswith(".docx")

    if is_pdf or is_docx:
        try:
            result = parse_docx_questions(content) if is_docx else parse_pdf_questions(content)
        except PDFParseError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        low_conf = sum(
            1 for q in result["questions"] if q["confidence"] < LOW_CONFIDENCE_THRESHOLD
        )
        return {
            "source": "docx" if is_docx else "pdf",
            "questions": result["questions"],
            "total_questions": len(result["questions"]),
            "answer_key_found": result["answer_key_found"],
            "warnings": result["warnings"],
            "low_confidence_count": low_conf,
            "low_confidence_threshold": LOW_CONFIDENCE_THRESHOLD,
        }

    # JSON/CSV preview — reuse the strict parser but don't persist.
    defaults = {"title": "Preview", "subject": "Preview", "year": 2000}
    try:
        exams = parse_cbt_file(file.filename or "upload.json", content, defaults)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    questions = []
    for exam in exams:
        for i, q in enumerate(exam["questions"], start=1):
            questions.append({**q, "number": i, "confidence": 1.0, "issues": []})
    return {
        "source": "json" if name.endswith(".json") else "csv",
        "questions": questions,
        "total_questions": len(questions),
        "answer_key_found": True,
        "warnings": [],
        "low_confidence_count": 0,
        "low_confidence_threshold": 0.0,
    }


class CBTImportConfirmQuestion(BaseModel):
    question_text: str
    option_a: str
    option_b: str
    option_c: str
    option_d: str
    correct_option: str
    explanation: Optional[str] = None
    topic: Optional[str] = None
    confidence: Optional[float] = None  # carried from preview; low values block publishing


class CBTImportConfirmRequest(BaseModel):
    title: str
    subject: str
    year: Optional[int] = None
    exam_type: str = "JAMB"
    duration_minutes: int = 60
    is_published: bool = True
    skip_duplicates: bool = True
    paper_kind: str = "cbt_practice"
    questions: list[CBTImportConfirmQuestion]


@router.post("/cbt/import/confirm")
async def confirm_cbt_import(
    payload: CBTImportConfirmRequest,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Save admin-reviewed questions (from /cbt/import/preview) as a CBT exam.
    If any question still carries a low confidence score, the exam is saved
    UNPUBLISHED so unverified content never reaches students automatically.
    """
    from app.services.cbt_pdf_parser import LOW_CONFIDENCE_THRESHOLD

    if not payload.questions:
        raise HTTPException(status_code=400, detail="No questions to save")

    subject = (payload.subject or "").strip()
    if not subject:
        raise HTTPException(status_code=400, detail="Pick a subject before saving")
    year = _normalize_cbt_year(payload.year)
    if year is None:
        raise HTTPException(status_code=400, detail="Pick the exam year before saving")

    if payload.skip_duplicates:
        existing = await db.execute(
            select(CBTExam).where(CBTExam.title == payload.title.strip())
        )
        if existing.scalar_one_or_none():
            raise HTTPException(
                status_code=409,
                detail=f"An exam titled '{payload.title.strip()}' already exists.",
            )

    low_conf = sum(
        1 for q in payload.questions
        if q.confidence is not None and q.confidence < LOW_CONFIDENCE_THRESHOLD
    )
    publish = payload.is_published and low_conf == 0

    exam_payload = CBTExamCreate(
        title=payload.title.strip(),
        subject=subject,
        year=year,
        exam_type=payload.exam_type,
        duration_minutes=payload.duration_minutes,
        is_published=publish,
        paper_kind=normalize_paper_kind(payload.paper_kind),
        questions=[
            CBTQuestionCreate(
                question_text=q.question_text,
                option_a=q.option_a,
                option_b=q.option_b,
                option_c=q.option_c,
                option_d=q.option_d,
                correct_option=q.correct_option,
                explanation=q.explanation,
                topic=q.topic,
            )
            for q in payload.questions
        ],
    )
    exam = await _persist_cbt_exam(db, exam_payload, current_user["sub"])
    note = None
    if payload.is_published and not publish:
        note = (
            f"{low_conf} question(s) are still low-confidence, so the exam was saved "
            "unpublished. Review them in the exam list, then publish."
        )
    return {
        "id": str(exam.id),
        "title": exam.title,
        "subject": exam.subject,
        "year": exam.year,
        "exam_type": exam.exam_type,
        "total_questions": exam.total_questions,
        "is_published": exam.is_published,
        "note": note,
    }


@router.post("/seed-cbt")
async def seed_cbt(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Seed WAEC, NECO, and JAMB CBT exams (skips exams that already exist)."""
    from app.core.seed import seed_cbt_exams

    created = await seed_cbt_exams(db)
    await db.commit()
    return {"created": created, "count": len(created)}


@router.post("/cbt/purge-samples")
async def purge_sample_cbt_exams(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Delete the built-in SAMPLE exams only (the ones added by seeding).
    Safety rules: only exams whose title matches the seed list AND that were
    not created by an admin/teacher are considered; any sample exam a student
    has already taken is kept so no results are lost.
    """
    from app.core.seed import sample_exam_titles

    titles = sample_exam_titles()
    result = await db.execute(
        select(CBTExam).where(
            CBTExam.title.in_(titles),
            CBTExam.created_by.is_(None),
        )
    )
    exams = result.scalars().all()

    deleted: list[str] = []
    kept: list[str] = []
    for exam in exams:
        sessions = await db.execute(
            select(func.count()).select_from(CBTSession).where(CBTSession.exam_id == exam.id)
        )
        if (sessions.scalar() or 0) > 0:
            kept.append(exam.title)
            continue
        await _delete_cbt_exam_cascade(db, exam)
        deleted.append(exam.title)

    return {
        "deleted": deleted,
        "deleted_count": len(deleted),
        "kept_with_results": kept,
    }


CBT_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}


@router.post("/cbt/upload-image")
async def upload_cbt_question_image(
    file: UploadFile = File(...),
    current_user: dict = Depends(require_admin),
):
    """Upload a diagram or figure for a CBT question."""
    if file.content_type not in CBT_IMAGE_TYPES:
        raise HTTPException(
            status_code=400,
            detail="Unsupported image type. Use JPEG, PNG, WebP, or GIF.",
        )
    content = await file.read()
    if len(content) > 5 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Image too large. Maximum size is 5MB.")
    try:
        result = upload_file(content, "cbt")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")
    return {"image_url": result["secure_url"]}


class InternalExamQuestionIn(BaseModel):
    question_text: str
    option_a: str
    option_b: str
    option_c: str
    option_d: str
    correct_option: str
    explanation: Optional[str] = None
    topic: Optional[str] = None
    image_url: Optional[str] = None


class InternalExamCreate(BaseModel):
    title: str
    subject: str
    teacher_id: str
    duration_minutes: int = 45
    questions: list[InternalExamQuestionIn]
    student_ids: list[str] = []  # empty = all students whose profile includes this subject
    notes_url: Optional[str] = None
    notes_title: Optional[str] = None
    is_published: bool = True


@router.post("/internal-exams", status_code=201)
async def admin_create_internal_exam(
    payload: InternalExamCreate,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin uploads an internal exam for a teacher + subject (and optional students)."""
    if not payload.questions:
        raise HTTPException(status_code=400, detail="At least one question is required")
    subject = (payload.subject or "").strip()
    if not subject:
        raise HTTPException(status_code=400, detail="Subject is required")

    teacher_res = await db.execute(
        select(User).where(User.id == payload.teacher_id, User.role == UserRole.teacher)
    )
    teacher = teacher_res.scalar_one_or_none()
    if not teacher:
        raise HTTPException(status_code=404, detail="Teacher not found")

    student_ids: list[str] = []
    for sid in payload.student_ids or []:
        sid = str(sid).strip()
        if not sid:
            continue
        s_res = await db.execute(
            select(User).where(User.id == sid, User.role == UserRole.student)
        )
        if not s_res.scalar_one_or_none():
            raise HTTPException(status_code=400, detail=f"Student not found: {sid}")
        student_ids.append(sid)

    exam = CBTExam(
        title=payload.title.strip(),
        subject=subject,
        exam_type="SCHOOL",
        duration_minutes=max(5, min(int(payload.duration_minutes or 45), 300)),
        total_questions=len(payload.questions),
        created_by=teacher.id,
        is_published=payload.is_published,
        is_school_exam=True,
        ai_locked=False,
        camera_required=False,
        block_minimize=False,
        assigned_student_ids=student_ids or None,
        notes_url=(payload.notes_url or "").strip() or None,
        notes_title=(payload.notes_title or "").strip() or None,
    )
    db.add(exam)
    await db.flush()

    for q in payload.questions:
        if q.correct_option.upper() not in ("A", "B", "C", "D"):
            raise HTTPException(status_code=400, detail="correct_option must be A/B/C/D")
        db.add(
            CBTQuestion(
                exam_id=exam.id,
                question_text=q.question_text,
                option_a=q.option_a,
                option_b=q.option_b,
                option_c=q.option_c,
                option_d=q.option_d,
                correct_option=q.correct_option.upper(),
                explanation=q.explanation,
                topic=q.topic,
                image_url=q.image_url,
            )
        )
    await db.flush()
    try:
        await _notify_published_exam(db, exam)
    except Exception:
        pass
    return {
        "id": str(exam.id),
        "title": exam.title,
        "subject": exam.subject,
        "teacher_id": str(teacher.id),
        "teacher_name": teacher.full_name or teacher.email,
        "total_questions": exam.total_questions,
        "assigned_students": len(student_ids),
        "notes_url": exam.notes_url,
        "is_published": exam.is_published,
    }


@router.get("/internal-exams")
async def admin_list_internal_exams(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(CBTExam)
        .where(CBTExam.is_school_exam == True)  # noqa: E712
        .order_by(CBTExam.created_at.desc())
    )
    exams = result.scalars().all()
    teacher_ids = {e.created_by for e in exams if e.created_by}
    teachers = {}
    if teacher_ids:
        t_res = await db.execute(select(User).where(User.id.in_(teacher_ids)))
        teachers = {u.id: u for u in t_res.scalars().all()}

    out = []
    for e in exams:
        teacher = teachers.get(e.created_by) if e.created_by else None
        assigned = e.assigned_student_ids or []
        out.append(
            {
                "id": str(e.id),
                "title": e.title,
                "subject": e.subject,
                "teacher_id": str(e.created_by) if e.created_by else None,
                "teacher_name": (teacher.full_name or teacher.email) if teacher else "—",
                "duration_minutes": e.duration_minutes,
                "total_questions": e.total_questions,
                "assigned_count": len(assigned) if assigned else 0,
                "assign_mode": "selected_students" if assigned else "subject_match",
                "notes_url": e.notes_url,
                "notes_title": e.notes_title,
                "is_published": e.is_published,
                "created_at": e.created_at.isoformat() if e.created_at else None,
            }
        )
    return out


@router.post("/external-exams", status_code=201)
async def admin_create_external_exam(
    payload: InternalExamCreate,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Create external/offline school exam (alias of POST /admin/internal-exams)."""
    return await admin_create_internal_exam(payload=payload, current_user=current_user, db=db)


@router.get("/external-exams")
async def admin_list_external_exams(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """List external school exams (alias of GET /admin/internal-exams)."""
    return await admin_list_internal_exams(current_user=current_user, db=db)


@router.post("/internal-exams/upload-notes")
async def admin_upload_internal_notes(
    file: UploadFile = File(...),
    current_user: dict = Depends(require_admin),
):
    """Upload PDF/image notes attached to an internal exam."""
    name = (file.filename or "notes").strip()
    content_type = (file.content_type or "").split(";")[0].strip().lower()
    content = await file.read()
    is_pdf = (
        content_type == "application/pdf"
        or name.lower().endswith(".pdf")
        or content[:5] == b"%PDF-"
    )
    is_image = content_type in CBT_IMAGE_TYPES or name.lower().endswith(
        (".jpg", ".jpeg", ".png", ".webp", ".gif")
    )
    if not is_pdf and not is_image:
        raise HTTPException(status_code=400, detail="Upload a PDF, JPEG, PNG, WebP, or GIF.")
    if len(content) > 12 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="File too large (max 12MB).")
    folder = "assignments" if is_pdf else "images"
    try:
        result = upload_file(content, folder, filename=name)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")
    return {
        "notes_url": result["secure_url"],
        "notes_title": file.filename or "Notes",
    }


@router.get("/internal-exams/submissions")
async def admin_internal_exam_submissions(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin view of student internal-exam submissions / requests status."""
    rows = await db.execute(
        select(CBTSession, User, CBTExam)
        .join(User, User.id == CBTSession.student_id)
        .join(CBTExam, CBTExam.id == CBTSession.exam_id)
        .where(
            CBTExam.is_school_exam == True,  # noqa: E712
            CBTSession.submitted_at != None,  # noqa: E711
        )
        .order_by(CBTSession.submitted_at.desc())
        .limit(200)
    )
    data = rows.all()
    teacher_ids = {exam.created_by for _, _, exam in data if exam.created_by}
    teachers = {}
    if teacher_ids:
        t_res = await db.execute(select(User).where(User.id.in_(teacher_ids)))
        teachers = {u.id: u for u in t_res.scalars().all()}

    out = []
    for session, user, exam in data:
        teacher = teachers.get(exam.created_by) if exam.created_by else None
        out.append(
            {
                "session_id": str(session.id),
                "student_name": user.full_name or user.email,
                "exam_title": exam.title,
                "subject": exam.subject,
                "teacher_name": (teacher.full_name or teacher.email) if teacher else "—",
                "percentage": session.percentage,
                "total_correct": session.total_correct,
                "total_wrong": session.total_wrong,
                "submitted_at": session.submitted_at.isoformat() if session.submitted_at else None,
            }
        )
    return out


# ── Platform Overview ─────────────────────────────────────────────────────────

@router.get("/overview")
async def admin_overview(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    from sqlalchemy import func
    from app.models.live_class import LiveClass, LiveSessionRequest, LiveSessionRequestStatus

    students = await db.execute(
        select(func.count()).select_from(User).where(
            User.role == UserRole.student,
            User.is_active == True,  # noqa: E712
        )
    )
    teachers = await db.execute(
        select(func.count()).select_from(User).where(
            User.role == UserRole.teacher,
            User.is_active == True,  # noqa: E712
        )
    )
    kind = await db.execute(
        select(func.count()).select_from(User).where(
            User.role == UserRole.kind,
            User.is_active == True,  # noqa: E712
        )
    )
    exams = await db.execute(select(func.count()).select_from(CBTExam))
    live_now = await db.execute(
        select(func.count()).select_from(LiveClass).where(LiveClass.is_live == True)  # noqa: E712
    )
    pending_reqs = await db.execute(
        select(func.count()).select_from(LiveSessionRequest).where(
            LiveSessionRequest.status == LiveSessionRequestStatus.pending
        )
    )
    setup_done = await db.execute(
        select(func.count())
        .select_from(StudentProfile)
        .join(User, User.id == StudentProfile.user_id)
        .where(
            User.role == UserRole.student,
            User.is_active == True,  # noqa: E712
            StudentProfile.exam_type.isnot(None),
            func.cardinality(StudentProfile.selected_subjects) > 0,
        )
    )
    return {
        "students": students.scalar() or 0,
        "teachers": teachers.scalar() or 0,
        "kind_learners": kind.scalar() or 0,
        "cbt_exams": exams.scalar() or 0,
        "live_classes_now": live_now.scalar() or 0,
        "pending_session_requests": pending_reqs.scalar() or 0,
        "students_with_subjects": setup_done.scalar() or 0,
    }


# ── Student Management ────────────────────────────────────────────────────────

class StudentAdminResponse(BaseModel):
    id: str
    email: str
    full_name: str
    is_active: bool
    exam_type: Optional[str] = None
    education_level: Optional[str] = None
    selected_subjects: list[str] = []
    has_active_subscription: bool = False
    created_at: Optional[datetime] = None


@router.get("/students", response_model=list[StudentAdminResponse])
async def list_students(
    active_only: bool = True,
    q: Optional[str] = None,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    query = (
        select(User, StudentProfile)
        .outerjoin(StudentProfile, StudentProfile.user_id == User.id)
        .where(User.role == UserRole.student)
    )
    if q and q.strip():
        like = f"%{q.strip().lower()}%"
        query = query.where(
            or_(
                func.lower(User.email).like(like),
                func.lower(User.full_name).like(like),
            )
        )
    if active_only:
        query = query.where(User.is_active == True)  # noqa: E712
    query = query.order_by(User.created_at.desc())
    try:
        result = await db.execute(query)
        rows = result.all()
    except Exception:
        await db.rollback()
        sql_rows = (
            await db.execute(
                text(
                    """
                    SELECT u.id, u.email, u.full_name, COALESCE(u.is_active, true) AS is_active,
                           u.created_at, sp.education_level, sp.exam_type::text AS exam_type,
                           sp.selected_subjects, COALESCE(sp.has_active_subscription, false) AS has_active_subscription
                    FROM users u
                    LEFT JOIN student_profiles sp ON sp.user_id = u.id
                    WHERE u.role::text = 'student'
                    ORDER BY u.created_at DESC
                    """
                )
            )
        ).mappings().all()
        return [
            StudentAdminResponse(
                id=str(r["id"]),
                email=r["email"],
                full_name=r["full_name"],
                is_active=bool(r["is_active"]),
                exam_type=r["exam_type"],
                education_level=r["education_level"],
                selected_subjects=list(r["selected_subjects"] or []),
                has_active_subscription=bool(r["has_active_subscription"]),
                created_at=r["created_at"],
            )
            for r in sql_rows
        ]
    out = []
    for user, profile in rows:
        try:
            et = None
            if profile and profile.exam_type:
                et = profile.exam_type.value if hasattr(profile.exam_type, "value") else str(profile.exam_type)
            out.append(StudentAdminResponse(
                id=str(user.id),
                email=user.email,
                full_name=user.full_name,
                is_active=user.is_active,
                exam_type=et,
                education_level=profile.education_level if profile else None,
                selected_subjects=profile.selected_subjects if profile and profile.selected_subjects else [],
                has_active_subscription=bool(profile and profile.has_active_subscription),
                created_at=user.created_at,
            ))
        except Exception:
            continue
    return out


class LiveSubscriptionAdminResponse(BaseModel):
    id: str
    email: str
    full_name: str
    plan_id: Optional[str] = None
    plan_name: Optional[str] = None
    paid: bool = False
    sessions_left: int = 0
    sessions_used: int = 0
    sessions_total: int = 0
    expires_at: Optional[datetime] = None
    last_payment_at: Optional[datetime] = None
    last_payment_amount: Optional[float] = None


class LiveSubscriptionUpdateRequest(BaseModel):
    plan_id: Optional[str] = None
    sessions_used: Optional[int] = None
    expires_at: Optional[datetime] = None
    grant: bool = True  # False = revoke


@router.get("/live-plans")
async def admin_list_live_plans(current_user: dict = Depends(require_admin)):
    from app.core.live_class_plans import all_plans_dict

    return {"plans": all_plans_dict()}


@router.get("/live-subscriptions", response_model=list[LiveSubscriptionAdminResponse])
async def list_live_subscriptions(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Students with live class plan / payment access for admin review."""
    from app.services.live_class_access import get_live_access_info
    from app.models.payment import Payment, PaymentStatus
    from app.core.skills_programs import is_skill_plan_key

    try:
        result = await db.execute(
            select(User, StudentProfile)
            .outerjoin(StudentProfile, StudentProfile.user_id == User.id)
            .where(User.role == UserRole.student, User.is_active == True)  # noqa: E712
            .order_by(User.created_at.desc())
        )
        rows = result.all()
    except Exception:
        await db.rollback()
        return []
    out = []
    for user, profile in rows:
        try:
            plan_id = profile.live_plan_id if profile else None
            if plan_id and is_skill_plan_key(plan_id):
                continue
            access = await get_live_access_info(db, str(user.id))
            active = access.get("active_plan") or {}
            last_pay_at = None
            last_pay_amt = None
            try:
                pay_res = await db.execute(
                    select(Payment)
                    .where(
                        Payment.student_id == user.id,
                        Payment.status == PaymentStatus.success,
                        Payment.live_plan_id.isnot(None),
                    )
                    .order_by(Payment.created_at.desc())
                    .limit(1)
                )
                last_pay = pay_res.scalar_one_or_none()
                if last_pay and last_pay.live_plan_id and not is_skill_plan_key(last_pay.live_plan_id):
                    last_pay_at = last_pay.created_at
                    last_pay_amt = float(last_pay.amount) if last_pay.amount is not None else None
            except Exception:
                await db.rollback()

            if not access.get("paid") and not (profile and profile.live_plan_id and not is_skill_plan_key(profile.live_plan_id)):
                continue

            out.append(LiveSubscriptionAdminResponse(
                id=str(user.id),
                email=user.email,
                full_name=user.full_name,
                plan_id=active.get("plan_id") or (profile.live_plan_id if profile else None),
                plan_name=active.get("plan_name"),
                paid=bool(access.get("paid")),
                sessions_left=int(access.get("sessions_left") or 0),
                sessions_used=int(active.get("sessions_used") or 0),
                sessions_total=int(active.get("sessions_total") or 0),
                expires_at=access.get("valid_until"),
                last_payment_at=last_pay_at,
                last_payment_amount=last_pay_amt,
            ))
        except Exception:
            try:
                await db.rollback()
            except Exception:
                pass
            continue
    return out


@router.patch("/live-subscriptions/{student_id}")
async def update_live_subscription(
    student_id: str,
    payload: LiveSubscriptionUpdateRequest,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Grant, update, or revoke a student's live-class subscription."""
    from app.core.live_class_plans import get_plan
    from app.core.datetime_utils import naive_utc_now
    from datetime import timedelta
    from app.core.config import settings

    try:
        uid = uuid.UUID(student_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid student id")

    user_res = await db.execute(
        select(User).where(User.id == uid, User.role == UserRole.student)
    )
    user = user_res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="Student not found")

    p_res = await db.execute(select(StudentProfile).where(StudentProfile.user_id == uid))
    profile = p_res.scalar_one_or_none()
    if not profile:
        profile = StudentProfile(user_id=uid, selected_subjects=[])
        db.add(profile)
        await db.flush()

    if not payload.grant:
        profile.live_plan_id = None
        profile.live_plan_expires_at = None
        profile.live_plan_sessions_used = 0
        profile.has_active_subscription = False
        await db.flush()
        return {"message": "Subscription revoked", "student_id": str(uid), "paid": False}

    plan_id = (payload.plan_id or profile.live_plan_id or "").strip()
    if not plan_id:
        raise HTTPException(status_code=400, detail="Choose a live plan")
    plan = get_plan(plan_id)
    if not plan:
        raise HTTPException(status_code=400, detail=f"Unknown plan: {plan_id}")

    profile.live_plan_id = plan.id
    if payload.expires_at is not None:
        profile.live_plan_expires_at = payload.expires_at.replace(tzinfo=None) if payload.expires_at.tzinfo else payload.expires_at
    elif not profile.live_plan_expires_at:
        profile.live_plan_expires_at = naive_utc_now() + timedelta(days=settings.LIVE_CLASS_MONTHLY_DAYS)
    if payload.sessions_used is not None:
        profile.live_plan_sessions_used = max(0, int(payload.sessions_used))
    elif profile.live_plan_sessions_used is None:
        profile.live_plan_sessions_used = 0
    profile.has_active_subscription = True
    await db.flush()

    sessions_used = int(profile.live_plan_sessions_used or 0)
    return {
        "message": "Subscription updated",
        "student_id": str(uid),
        "plan_id": plan.id,
        "plan_name": plan.name,
        "sessions_used": sessions_used,
        "sessions_left": max(0, plan.sessions - sessions_used),
        "expires_at": profile.live_plan_expires_at.isoformat() if profile.live_plan_expires_at else None,
        "paid": True,
    }


@router.get("/skills-enrollments")
async def list_skills_enrollments(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Students who enrolled / paid for Skills training programs."""
    from app.models.payment import Payment, PaymentStatus
    from app.core.skills_programs import (
        is_skill_plan_key,
        skill_id_from_plan_key,
        get_skill_program,
    )

    result = await db.execute(
        select(Payment, User)
        .join(User, User.id == Payment.student_id)
        .where(
            Payment.live_plan_id.isnot(None),
            Payment.live_plan_id.like("skill:%"),
        )
        .order_by(Payment.created_at.desc())
        .limit(300)
    )
    out = []
    for payment, user in result.all():
        plan_key = payment.live_plan_id or ""
        if not is_skill_plan_key(plan_key):
            continue
        skill_id = skill_id_from_plan_key(plan_key)
        program = get_skill_program(skill_id) or {}
        out.append(
            {
                "payment_id": str(payment.id),
                "student_id": str(user.id),
                "student_name": user.full_name or user.email,
                "email": user.email,
                "skill_id": skill_id,
                "skill_title": program.get("title") or skill_id,
                "skill_fee": program.get("fee"),
                "amount_paid": float(payment.amount) if payment.amount is not None else None,
                "status": payment.status.value if payment.status else None,
                "description": payment.description,
                "created_at": payment.created_at.isoformat() if payment.created_at else None,
            }
        )
    return out


@router.delete("/students/{student_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_student(
    student_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    import uuid as _uuid
    try:
        uid = _uuid.UUID(student_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid student id")
    deleted = await delete_student_user(db, uid)
    if not deleted:
        raise HTTPException(status_code=404, detail="Student not found")


@router.post("/students/remove-all")
async def remove_all_students(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Permanently delete every student account."""
    result = await db.execute(select(User).where(User.role == UserRole.student))
    students = result.scalars().all()
    removed = 0
    for user in students:
        if await delete_student_user(db, user.id):
            removed += 1
    await db.flush()
    return {"removed": removed}


@router.post("/users/purge-all")
async def purge_all_users(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Permanently delete all student, teacher, and kind accounts (all their emails). Keeps admin accounts."""
    import uuid as _uuid

    admin_id = _uuid.UUID(current_user["sub"])
    result = await purge_all_user_accounts(db, keep_admin_id=admin_id)
    await db.flush()
    return result


@router.post("/users/clear-emails")
async def clear_all_emails(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Free all student/teacher/kind emails for re-signup.
    Renames them to cleared_<id>@cleared.local and disables those accounts.
    Admin accounts are kept.
    """
    import uuid as _uuid

    admin_id = _uuid.UUID(current_user["sub"])
    result = await clear_all_user_emails(db, keep_admin_id=admin_id)
    await db.flush()
    return result


# ── Community moderation ──────────────────────────────────────────────────────

@router.get("/community/posts")
async def admin_list_community_posts(
    channel_id: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """All student community posts for admin review."""
    query = (
        select(CommunityPost, User, CommunityChannel)
        .join(User, User.id == CommunityPost.author_id)
        .join(CommunityChannel, CommunityChannel.id == CommunityPost.channel_id)
        .where(CommunityPost.is_deleted == False)  # noqa: E712
        .order_by(CommunityPost.created_at.desc())
        .limit(limit)
        .offset(offset)
    )
    if channel_id:
        query = query.where(CommunityPost.channel_id == channel_id)

    result = await db.execute(query)
    rows = result.all()
    return [
        {
            "id": str(post.id),
            "channel_id": str(post.channel_id),
            "channel_name": channel.name,
            "author_id": str(post.author_id),
            "author_name": user.full_name,
            "author_email": user.email,
            "content": post.content,
            "media_url": post.media_url,
            "media_type": post.media_type,
            "is_anonymous": post.is_anonymous,
            "like_count": post.like_count,
            "created_at": post.created_at,
        }
        for post, user, channel in rows
    ]


@router.delete("/community/conversations", status_code=200)
async def admin_clear_all_conversations(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Wipe every conversation: General chat, announcements, feed posts/comments,
    all student groups (and their chats), and group discover listings.
    """
    from sqlalchemy import delete as sa_delete, update as sa_update, func as sa_func
    from app.models.community import CommunityMessage
    from app.models.student_group import (
        StudentGroup,
        StudentGroupMember,
        StudentGroupJoinRequest,
        StudentGroupMessage,
    )

    group_msg_count = (
        await db.execute(select(sa_func.count()).select_from(StudentGroupMessage))
    ).scalar() or 0
    group_count = (
        await db.execute(select(sa_func.count()).select_from(StudentGroup))
    ).scalar() or 0

    # Soft-delete ALL feed posts first (General + Announcements + group cards)
    post_res = await db.execute(
        sa_update(CommunityPost)
        .where(CommunityPost.is_deleted == False)  # noqa: E712
        .values(is_deleted=True)
    )

    msg_res = await db.execute(
        sa_update(CommunityMessage)
        .where(CommunityMessage.is_deleted == False)  # noqa: E712
        .values(is_deleted=True)
    )

    # Remove groups and related rows (FK-safe order)
    await db.execute(sa_delete(StudentGroupMessage))
    await db.execute(sa_delete(StudentGroupJoinRequest))
    await db.execute(sa_delete(StudentGroupMember))
    # Detach posts from groups so groups can be deleted without orphan FK issues
    await db.execute(
        sa_update(CommunityPost)
        .where(CommunityPost.group_id.is_not(None))
        .values(group_id=None)
    )
    await db.execute(sa_delete(StudentGroup))

    await db.flush()
    return {
        "groups_deleted": int(group_count),
        "group_messages_deleted": int(group_msg_count),
        "community_messages_deleted": int(msg_res.rowcount or 0),
        "community_posts_deleted": int(post_res.rowcount or 0),
    }


@router.delete("/community/posts/{post_id}", status_code=status.HTTP_204_NO_CONTENT)
async def admin_delete_community_post(
    post_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(CommunityPost).where(CommunityPost.id == post_id))
    post = result.scalar_one_or_none()
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    post.is_deleted = True
    await db.flush()


# ── Live class management ───────────────────────────────────────────────────────

import uuid as uuid_lib
from sqlalchemy import delete, update, func
from app.models.live_class import LiveClass, ClassAttendance, LiveSessionRequest
from app.models.wallet import WalletTransaction
from app.models.review_report import TeacherReview
class AdminHostLiveClassRequest(BaseModel):
    title: str
    subject: str
    description: Optional[str] = None
    start_now: bool = False
    visibility: Optional[str] = None
    academic_class: Optional[str] = None


@router.post("/live-classes", status_code=status.HTTP_201_CREATED)
async def admin_host_live_class(
    payload: AdminHostLiveClassRequest,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin hosts a live class (create, optionally go live immediately)."""
    title = payload.title.strip()
    subject = payload.subject.strip()
    if not title or not subject:
        raise HTTPException(status_code=400, detail="Title and subject are required")

    vis = (payload.visibility or "public").strip().lower()
    if vis not in ("public", "private", "subject", "school_group", "class_level"):
        vis = "public"
    room_id = f"room-{uuid_lib.uuid4().hex[:12]}"
    live_class = LiveClass(
        teacher_id=current_user["sub"],
        subject=subject,
        title=title,
        description=payload.description,
        start_time=naive_utc_now(),
        room_id=room_id,
        is_live=payload.start_now,
        visibility=vis,
        academic_class=(payload.academic_class or "").strip().upper() or None,
        join_code=f"SX-{uuid_lib.uuid4().hex[:8].upper()}",
    )
    db.add(live_class)
    await db.flush()

    if payload.start_now:
        try:
            await send_subject_notification(
                db=db,
                subject=live_class.subject,
                title="Live class starting now",
                body=f"A {live_class.subject} live class is starting now.",
                notification_type="live_class",
                data={"class_id": str(live_class.id), "room_id": live_class.room_id},
            )
        except Exception:
            pass  # class is still live even if notifications fail

    return {
        "id": str(live_class.id),
        "title": live_class.title,
        "subject": live_class.subject,
        "is_live": live_class.is_live,
        "room_id": live_class.room_id,
        "start_time": live_class.start_time,
    }


@router.post("/live-classes/{class_id}/start")
async def admin_start_live_class(
    class_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(LiveClass).where(LiveClass.id == class_id))
    live_class = result.scalar_one_or_none()
    if not live_class:
        raise HTTPException(status_code=404, detail="Class not found")

    live_class.is_live = True
    try:
        await send_subject_notification(
            db=db,
            subject=live_class.subject,
            title="Live class starting now",
            body=f"A {live_class.subject} live class is starting now.",
            notification_type="live_class",
            data={"class_id": str(live_class.id), "room_id": live_class.room_id},
        )
    except Exception:
        pass
    return {"message": "Class started", "room_id": live_class.room_id}


@router.post("/live-classes/{class_id}/end")
async def admin_end_live_class(
    class_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(LiveClass).where(LiveClass.id == class_id))
    live_class = result.scalar_one_or_none()
    if not live_class:
        raise HTTPException(status_code=404, detail="Class not found")

    live_class.is_live = False
    live_class.end_time = naive_utc_now()
    att_res = await db.execute(
        select(ClassAttendance).where(
            ClassAttendance.live_class_id == class_id,
            ClassAttendance.left_at.is_(None),
        )
    )
    for att in att_res.scalars().all():
        att.left_at = naive_utc_now()
    return {"message": "Class ended", "class_id": class_id}


async def _clear_live_class_references(db: AsyncSession, class_id: Optional[str] = None) -> None:
    if class_id:
        await db.execute(
            update(LiveSessionRequest)
            .where(LiveSessionRequest.linked_class_id == class_id)
            .values(linked_class_id=None)
        )
        await db.execute(
            update(WalletTransaction)
            .where(WalletTransaction.live_class_id == class_id)
            .values(live_class_id=None)
        )
        await db.execute(
            update(TeacherReview)
            .where(TeacherReview.live_class_id == class_id)
            .values(live_class_id=None)
        )
        await db.execute(delete(ClassAttendance).where(ClassAttendance.live_class_id == class_id))
        await db.execute(delete(LiveClass).where(LiveClass.id == class_id))
        return

    await db.execute(
        update(LiveSessionRequest)
        .where(LiveSessionRequest.linked_class_id.isnot(None))
        .values(linked_class_id=None)
    )
    await db.execute(
        update(WalletTransaction)
        .where(WalletTransaction.live_class_id.isnot(None))
        .values(live_class_id=None)
    )
    await db.execute(
        update(TeacherReview)
        .where(TeacherReview.live_class_id.isnot(None))
        .values(live_class_id=None)
    )
    await db.execute(delete(ClassAttendance))
    await db.execute(delete(LiveClass))


@router.delete("/live-classes/remove-all")
async def remove_all_live_classes(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Remove every live class record (clears test/dummy data)."""
    count_res = await db.execute(select(func.count()).select_from(LiveClass))
    total = count_res.scalar() or 0
    await _clear_live_class_references(db)
    await db.flush()
    return {"removed": total}


@router.delete("/live-classes/{class_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_live_class(
    class_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(LiveClass).where(LiveClass.id == class_id))
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Class not found")
    await _clear_live_class_references(db, class_id)
    await db.flush()


# ── Student group approval ────────────────────────────────────────────────────

@router.get("/student-groups")
async def list_all_student_groups(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """All student groups (for admin moderation / clear follow-up)."""
    result = await db.execute(
        select(StudentGroup, User)
        .join(User, User.id == StudentGroup.creator_id)
        .order_by(StudentGroup.created_at.desc())
    )
    out = []
    for grp, creator in result.all():
        mem_count = await db.execute(
            select(func.count()).select_from(StudentGroupMember).where(
                StudentGroupMember.group_id == grp.id
            )
        )
        out.append({
            "id": str(grp.id),
            "name": grp.name,
            "description": grp.description or "",
            "creator_name": creator.full_name or creator.email,
            "creator_email": creator.email,
            "is_community_listed": grp.is_community_listed,
            "is_approved": grp.is_approved,
            "member_count": int(mem_count.scalar() or 0),
            "created_at": grp.created_at.isoformat() if grp.created_at else None,
        })
    return out


@router.get("/student-groups/pending")
async def list_pending_student_groups(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(StudentGroup, User)
        .join(User, User.id == StudentGroup.creator_id)
        .where(StudentGroup.is_approved == False)  # noqa: E712
        .order_by(StudentGroup.created_at.desc())
    )
    out = []
    for grp, creator in result.all():
        mem_count = await db.execute(
            select(func.count()).select_from(StudentGroupMember).where(
                StudentGroupMember.group_id == grp.id
            )
        )
        out.append({
            "id": str(grp.id),
            "name": grp.name,
            "description": grp.description or "",
            "creator_name": creator.full_name or creator.email,
            "creator_email": creator.email,
            "is_community_listed": grp.is_community_listed,
            "member_count": int(mem_count.scalar() or 0),
            "created_at": grp.created_at.isoformat() if grp.created_at else None,
        })
    return out


@router.post("/student-groups/{group_id}/approve")
async def approve_student_group(
    group_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    gid = uuid.UUID(group_id)
    res = await db.execute(select(StudentGroup).where(StudentGroup.id == gid))
    group = res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found.")
    if group.is_approved:
        return {"message": "Group is already approved."}
    group.is_approved = True
    await db.flush()
    if group.is_community_listed:
        await ensure_group_feed_post(db, group)
    return {"message": f'Group "{group.name}" is now active.'}


@router.post("/student-groups/{group_id}/reject")
async def reject_student_group(
    group_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    gid = uuid.UUID(group_id)
    res = await db.execute(select(StudentGroup).where(StudentGroup.id == gid))
    group = res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found.")
    group.is_approved = False
    group.is_community_listed = False
    await db.flush()
    return {"message": f'Group "{group.name}" was rejected and remains inactive.'}


# ── Kind (Kids) Learners ──────────────────────────────────────────────────────

class KindAdminResponse(BaseModel):
    id: str
    email: str
    full_name: str
    is_active: bool
    age_group: Optional[str] = None
    grade_level: Optional[str] = None
    parent_email: Optional[str] = None
    favorite_subjects: list[str] = []
    created_at: Optional[datetime] = None


@router.get("/kind-learners", response_model=list[KindAdminResponse])
async def list_kind_learners(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User, KindProfile)
        .outerjoin(KindProfile, KindProfile.user_id == User.id)
        .where(User.role == UserRole.kind)
        .order_by(User.created_at.desc())
    )
    rows = result.all()
    return [
        KindAdminResponse(
            id=str(user.id),
            email=user.email,
            full_name=user.full_name,
            is_active=user.is_active,
            age_group=profile.age_group if profile else None,
            grade_level=profile.grade_level if profile else None,
            parent_email=profile.parent_email if profile else None,
            favorite_subjects=profile.favorite_subjects if profile and profile.favorite_subjects else [],
            created_at=user.created_at,
        )
        for user, profile in rows
    ]
