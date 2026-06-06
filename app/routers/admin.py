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
    """Admin creates teacher accounts — teachers do NOT self-register."""
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
    return [
        TeacherResponse(id=str(u.id), email=u.email, full_name=u.full_name, subjects=p.subjects)
        for u, p in rows
    ]


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
        title=payload.title,
        author=payload.author,
        subject=payload.subject,
        exam_type=payload.exam_type,
        file_key=payload.file_key,
        cover_image_url=payload.cover_image_url,
        description=payload.description,
        total_pages=payload.total_pages,
        library_target=payload.library_target,
        uploaded_by=current_user["sub"],
        is_downloadable=False,
        allow_copy=False,
        allow_screenshot=False,
        allow_print=False,
    )
    db.add(book)
    await db.flush()

    return BookResponse(
        id=str(book.id),
        title=book.title,
        subject=book.subject,
        library_target=book.library_target,
        is_downloadable=False,
        allow_copy=False,
        allow_screenshot=False,
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
    return [
        {
            "id": str(b.id),
            "title": b.title,
            "subject": b.subject,
            "library_target": b.library_target,
            "exam_type": b.exam_type,
            "created_at": b.created_at,
        }
        for b in books
    ]


@router.post("/seed-cbt")
async def trigger_cbt_seed(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin triggers CBT seed manually — useful after deploy."""
    from app.core.seed import _seed_cbt_exams
    await _seed_cbt_exams(db)
    from sqlalchemy import select as sa_select
    from app.models.cbt import CBTExam
    result = await db.execute(sa_select(CBTExam).where(CBTExam.is_published == True))  # noqa
    exams = result.scalars().all()
    return {
        "status": "done",
        "exams_in_db": len(exams),
        "titles": [e.title for e in exams],
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
