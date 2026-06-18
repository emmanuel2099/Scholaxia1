from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel, EmailStr
from datetime import datetime
from typing import Optional
from app.core.database import get_db
from app.core.deps import require_admin
from app.core.security import hash_password, create_access_token, create_refresh_token
from app.models.user import User, UserRole, TeacherProfile, StudentProfile, KindProfile
from app.models.content import Book, LibraryTarget
from app.models.cbt import CBTExam, CBTQuestion
from app.models.community import CommunityPost, CommunityChannel
from app.services.media_service import generate_upload_signature, upload_file

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
        .where(User.role == UserRole.teacher, User.is_active == True)  # noqa: E712
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
    await db.flush()


@router.post("/teachers/remove-all")
async def remove_all_teachers(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Disable all active teacher accounts."""
    result = await db.execute(
        select(User).where(User.role == UserRole.teacher, User.is_active == True)  # noqa: E712
    )
    teachers = result.scalars().all()
    for user in teachers:
        user.is_active = False
    await db.flush()
    return {"removed": len(teachers)}

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
    scheduled_start: Optional[datetime] = None
    scheduled_end: Optional[datetime] = None


class CBTExamResponse(BaseModel):
    id: str
    title: str
    subject: str
    exam_type: str
    duration_minutes: int
    total_questions: int
    is_published: bool
    is_school_exam: bool = False
    scheduled_start: Optional[datetime] = None
    scheduled_end: Optional[datetime] = None


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
        scheduled_start=payload.scheduled_start,
        scheduled_end=payload.scheduled_end,
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
        is_school_exam=exam.is_school_exam,
        scheduled_start=exam.scheduled_start, scheduled_end=exam.scheduled_end,
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
            is_school_exam=e.is_school_exam,
            scheduled_start=e.scheduled_start, scheduled_end=e.scheduled_end,
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


# ── Platform Overview ─────────────────────────────────────────────────────────

@router.get("/overview")
async def admin_overview(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    from sqlalchemy import func
    from app.models.live_class import LiveClass, LiveSessionRequest, LiveSessionRequestStatus

    students = await db.execute(select(func.count()).select_from(User).where(User.role == UserRole.student))
    teachers = await db.execute(select(func.count()).select_from(User).where(User.role == UserRole.teacher))
    kind = await db.execute(select(func.count()).select_from(User).where(User.role == UserRole.kind))
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
        select(func.count()).select_from(StudentProfile).where(
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
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User, StudentProfile)
        .outerjoin(StudentProfile, StudentProfile.user_id == User.id)
        .where(User.role == UserRole.student)
        .order_by(User.created_at.desc())
    )
    rows = result.all()
    out = []
    for user, profile in rows:
        out.append(StudentAdminResponse(
            id=str(user.id),
            email=user.email,
            full_name=user.full_name,
            is_active=user.is_active,
            exam_type=profile.exam_type.value if profile and profile.exam_type else None,
            education_level=profile.education_level if profile else None,
            selected_subjects=profile.selected_subjects if profile and profile.selected_subjects else [],
            has_active_subscription=bool(profile and profile.has_active_subscription),
            created_at=user.created_at,
        ))
    return out


@router.delete("/students/{student_id}", status_code=status.HTTP_204_NO_CONTENT)
async def disable_student(
    student_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).where(User.id == student_id, User.role == UserRole.student))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="Student not found")
    user.is_active = False
    await db.flush()


@router.post("/students/remove-all")
async def remove_all_students(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Disable all active student accounts."""
    result = await db.execute(
        select(User).where(User.role == UserRole.student, User.is_active == True)  # noqa: E712
    )
    students = result.scalars().all()
    for user in students:
        user.is_active = False
    await db.flush()
    return {"removed": len(students)}


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
from app.services.notification_service import send_subject_notification


class AdminHostLiveClassRequest(BaseModel):
    title: str
    subject: str
    description: Optional[str] = None
    start_now: bool = False


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

    room_id = f"room-{uuid_lib.uuid4().hex[:12]}"
    live_class = LiveClass(
        teacher_id=current_user["sub"],
        subject=subject,
        title=title,
        description=payload.description,
        start_time=datetime.utcnow(),
        room_id=room_id,
        is_live=payload.start_now,
    )
    db.add(live_class)
    await db.flush()

    if payload.start_now:
        await send_subject_notification(
            db=db,
            subject=live_class.subject,
            title="Live class starting now",
            body=f"A {live_class.subject} live class is starting now.",
            notification_type="live_class",
            data={"class_id": str(live_class.id), "room_id": live_class.room_id},
        )

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
    await send_subject_notification(
        db=db,
        subject=live_class.subject,
        title="Live class starting now",
        body=f"A {live_class.subject} live class is starting now.",
        notification_type="live_class",
        data={"class_id": str(live_class.id), "room_id": live_class.room_id},
    )
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
    live_class.end_time = datetime.utcnow()
    att_res = await db.execute(
        select(ClassAttendance).where(
            ClassAttendance.live_class_id == class_id,
            ClassAttendance.left_at.is_(None),
        )
    )
    for att in att_res.scalars().all():
        att.left_at = datetime.utcnow()
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
