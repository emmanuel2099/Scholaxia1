import os
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel, EmailStr
from typing import Optional
from app.core.database import get_db
from app.core.deps import require_admin
from app.core.security import hash_password, create_access_token, create_refresh_token
from app.models.user import User, UserRole, TeacherProfile
from app.models.content import Book, LibraryTarget
from app.models.cbt import CBTExam, CBTQuestion
from app.services.media_service import generate_upload_signature

router = APIRouter(prefix="/admin", tags=["Admin"])


# ── Admin Self-Registration ───────────────────────────────────────────────────

class AdminRegisterRequest(BaseModel):
    email: EmailStr
    password: str
    full_name: str
    invite_code: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    role: str


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def admin_register(payload: AdminRegisterRequest, db: AsyncSession = Depends(get_db)):
    """Admin creates their own account using a secret invite code."""
    invite_code = os.getenv("ADMIN_INVITE_CODE", "SCHOLAXIA_ADMIN_2026")
    if payload.invite_code != invite_code:
        raise HTTPException(status_code=403, detail="Invalid invite code")
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
    return TokenResponse(
        access_token=create_access_token(str(user.id), user.role),
        refresh_token=create_refresh_token(str(user.id)),
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
    subjects: list[str]


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
    profile = TeacherProfile(user_id=user.id, subjects=payload.subjects, bio=payload.bio)
    db.add(profile)
    await db.flush()
    return TeacherResponse(id=str(user.id), email=user.email, full_name=user.full_name, subjects=payload.subjects)


@router.get("/teachers", response_model=list[TeacherResponse])
async def list_teachers(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User, TeacherProfile)
        .join(TeacherProfile, TeacherProfile.user_id == User.id)
        .where(User.role == UserRole.teacher)
    )
    rows = result.all()
    return [TeacherResponse(id=str(u.id), email=u.email, full_name=u.full_name, subjects=p.subjects) for u, p in rows]


@router.delete("/teachers/{teacher_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_teacher(
    teacher_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).where(User.id == teacher_id, User.role == UserRole.teacher))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="Teacher not found")
    user.is_active = False


# ── Library Management ────────────────────────────────────────────────────────

class AddBookRequest(BaseModel):
    title: str
    author: Optional[str] = None
    subject: str
    exam_type: Optional[str] = None
    file_key: str
    cover_image_url: Optional[str] = None
    description: Optional[str] = None
    total_pages: Optional[int] = None
    library_target: LibraryTarget = LibraryTarget.student


class BookResponse(BaseModel):
    id: str
    title: str
    subject: str
    library_target: str
    is_downloadable: bool
    allow_copy: bool
    allow_screenshot: bool


@router.post("/library/upload-url")
async def get_book_upload_url(current_user: dict = Depends(require_admin)):
    return generate_upload_signature(folder="books")


@router.post("/library/books", response_model=BookResponse, status_code=201)
async def add_book(
    payload: AddBookRequest,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    book = Book(
        title=payload.title, author=payload.author, subject=payload.subject,
        exam_type=payload.exam_type, file_key=payload.file_key,
        cover_image_url=payload.cover_image_url, description=payload.description,
        total_pages=payload.total_pages, library_target=payload.library_target,
        uploaded_by=current_user["sub"],
        is_downloadable=False, allow_copy=False, allow_screenshot=False, allow_print=False,
    )
    db.add(book)
    await db.flush()
    return BookResponse(
        id=str(book.id), title=book.title, subject=book.subject,
        library_target=book.library_target,
        is_downloadable=False, allow_copy=False, allow_screenshot=False,
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
    return [{"id": str(b.id), "title": b.title, "subject": b.subject,
             "library_target": b.library_target, "exam_type": b.exam_type, "created_at": b.created_at}
            for b in books]


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


class CBTExamCreate(BaseModel):
    title: str
    subject: str
    exam_type: str           # JAMB | WAEC | NECO | SCHOOL
    duration_minutes: int
    questions: list[CBTQuestionCreate]
    is_published: bool = True
    is_school_exam: bool = False
    ai_locked: bool = False
    camera_required: bool = False
    block_minimize: bool = False


class CBTExamResponse(BaseModel):
    id: str
    title: str
    subject: str
    exam_type: str
    duration_minutes: int
    total_questions: int
    is_published: bool


@router.post("/cbt/exams", response_model=CBTExamResponse, status_code=201)
async def create_cbt_exam(
    payload: CBTExamCreate,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin creates a CBT exam with all questions in one call."""
    if not payload.questions:
        raise HTTPException(status_code=400, detail="At least one question required")

    exam = CBTExam(
        title=payload.title,
        subject=payload.subject,
        exam_type=payload.exam_type.upper(),
        duration_minutes=payload.duration_minutes,
        total_questions=len(payload.questions),
        created_by=current_user["sub"],
        is_published=payload.is_published,
        is_school_exam=payload.is_school_exam,
        ai_locked=payload.ai_locked,
        camera_required=payload.camera_required,
        block_minimize=payload.block_minimize,
    )
    db.add(exam)
    await db.flush()

    for q in payload.questions:
        if q.correct_option.upper() not in ("A", "B", "C", "D"):
            raise HTTPException(status_code=400, detail=f"correct_option must be A/B/C/D, got: {q.correct_option}")
        db.add(CBTQuestion(
            exam_id=exam.id,
            question_text=q.question_text,
            option_a=q.option_a, option_b=q.option_b,
            option_c=q.option_c, option_d=q.option_d,
            correct_option=q.correct_option.upper(),
            explanation=q.explanation,
            topic=q.topic,
            image_url=q.image_url,
        ))

    await db.flush()
    return CBTExamResponse(
        id=str(exam.id), title=exam.title, subject=exam.subject,
        exam_type=exam.exam_type, duration_minutes=exam.duration_minutes,
        total_questions=exam.total_questions, is_published=exam.is_published,
    )


@router.get("/cbt/exams", response_model=list[CBTExamResponse])
async def admin_list_cbt_exams(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin lists all CBT exams including unpublished."""
    result = await db.execute(select(CBTExam).order_by(CBTExam.exam_type, CBTExam.subject))
    exams = result.scalars().all()
    return [
        CBTExamResponse(
            id=str(e.id), title=e.title, subject=e.subject,
            exam_type=e.exam_type, duration_minutes=e.duration_minutes,
            total_questions=e.total_questions, is_published=e.is_published,
        )
        for e in exams
    ]


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
    return {"id": str(exam.id), "is_published": exam.is_published}


@router.delete("/cbt/exams/{exam_id}", status_code=204)
async def delete_cbt_exam(
    exam_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin deletes an exam and all its questions."""
    result = await db.execute(select(CBTExam).where(CBTExam.id == exam_id))
    exam = result.scalar_one_or_none()
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")
    q_res = await db.execute(select(CBTQuestion).where(CBTQuestion.exam_id == exam_id))
    for q in q_res.scalars().all():
        await db.delete(q)
    await db.delete(exam)
