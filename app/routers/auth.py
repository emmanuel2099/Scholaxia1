from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel, EmailStr
from typing import Optional
from app.core.database import get_db
from app.core.security import hash_password, verify_password, create_access_token, create_refresh_token
from app.models.user import User, UserRole, StudentProfile, TeacherProfile, KindProfile

router = APIRouter(prefix="/auth", tags=["Authentication"])


class StudentSignupRequest(BaseModel):
    email: EmailStr
    password: str
    full_name: str


class KindSignupRequest(BaseModel):
    email: EmailStr
    password: str
    full_name: str
    age_group: str = "6-8"          # 3-5 | 6-8 | 9-12
    grade_level: Optional[str] = None
    parent_email: Optional[EmailStr] = None
    favorite_subjects: Optional[list] = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class OAuthRequest(BaseModel):
    provider: str  # google | apple
    token: str
    full_name: str = ""


class UserInfo(BaseModel):
    id: str
    email: str
    full_name: str
    role: str
    profile_picture: Optional[str] = None
    # Student-specific
    exam_type: Optional[str] = None
    selected_subjects: Optional[list] = None
    education_level: Optional[str] = None
    has_active_subscription: Optional[bool] = None
    # Teacher-specific
    subjects: Optional[list] = None
    bio: Optional[str] = None
    # Kind-specific
    age_group: Optional[str] = None
    grade_level: Optional[str] = None
    parent_email: Optional[str] = None
    favorite_subjects: Optional[list] = None
    learning_goals: Optional[str] = None


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    role: str
    user: UserInfo


async def _build_user_info(user: User, db: AsyncSession) -> UserInfo:
    """Build the UserInfo object with role-specific profile data."""
    info = UserInfo(
        id=str(user.id),
        email=user.email,
        full_name=user.full_name,
        role=user.role,
        profile_picture=user.profile_picture,
    )
    if user.role == UserRole.student:
        res = await db.execute(select(StudentProfile).where(StudentProfile.user_id == user.id))
        profile = res.scalar_one_or_none()
        if profile:
            info.exam_type = profile.exam_type
            info.selected_subjects = profile.selected_subjects or []
            info.education_level = profile.education_level
            info.has_active_subscription = profile.has_active_subscription
    elif user.role == UserRole.teacher:
        res = await db.execute(select(TeacherProfile).where(TeacherProfile.user_id == user.id))
        profile = res.scalar_one_or_none()
        if profile:
            info.subjects = profile.subjects or []
            info.bio = profile.bio
    elif user.role == UserRole.kind:
        res = await db.execute(select(KindProfile).where(KindProfile.user_id == user.id))
        profile = res.scalar_one_or_none()
        if profile:
            info.age_group = profile.age_group
            info.grade_level = profile.grade_level
            info.parent_email = profile.parent_email
            info.favorite_subjects = profile.favorite_subjects or []
            info.learning_goals = profile.learning_goals
    return info


@router.post("/student/signup", status_code=status.HTTP_201_CREATED)
async def student_signup(payload: StudentSignupRequest, db: AsyncSession = Depends(get_db)):
    """
    Student signup — auto-verified for now (OTP will be added back later).
    """
    existing = await db.execute(select(User).where(User.email == payload.email))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Email already registered")

    user = User(
        email=payload.email,
        hashed_password=hash_password(payload.password),
        full_name=payload.full_name,
        role=UserRole.student,
        is_verified=True,
    )
    db.add(user)
    await db.flush()

    # Auto-create student profile so /students/me works immediately
    profile = StudentProfile(user_id=user.id, selected_subjects=[])
    db.add(profile)
    await db.flush()

    user_info = await _build_user_info(user, db)
    return TokenResponse(
        access_token=create_access_token(str(user.id), user.role),
        refresh_token=create_refresh_token(str(user.id)),
        role=user.role,
        user=user_info,
    )


@router.post("/kind/signup", status_code=status.HTTP_201_CREATED)
async def kind_signup(payload: KindSignupRequest, db: AsyncSession = Depends(get_db)):
    """
    Young learner (Kind) signup — ages 3–12.
    Gets access to Sia Kind, the advanced child-safe AI tutor.
    """
    if payload.age_group not in ("3-5", "6-8", "9-12"):
        raise HTTPException(status_code=400, detail="age_group must be 3-5, 6-8, or 9-12")
    if len(payload.password) < 8:
        raise HTTPException(status_code=400, detail="Password must be at least 8 characters")

    existing = await db.execute(select(User).where(User.email == payload.email))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Email already registered")

    user = User(
        email=payload.email,
        hashed_password=hash_password(payload.password),
        full_name=payload.full_name,
        role=UserRole.kind,
        is_verified=True,
    )
    db.add(user)
    await db.flush()

    profile = KindProfile(
        user_id=user.id,
        age_group=payload.age_group,
        grade_level=payload.grade_level,
        parent_email=payload.parent_email,
        favorite_subjects=payload.favorite_subjects or [],
    )
    db.add(profile)
    await db.flush()

    user_info = await _build_user_info(user, db)
    return TokenResponse(
        access_token=create_access_token(str(user.id), user.role),
        refresh_token=create_refresh_token(str(user.id)),
        role=user.role,
        user=user_info,
    )


@router.post("/login")
async def login(payload: LoginRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == payload.email))
    user = result.scalar_one_or_none()

    if not user or not user.hashed_password or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account disabled")

    user_info = await _build_user_info(user, db)
    return TokenResponse(
        access_token=create_access_token(str(user.id), user.role),
        refresh_token=create_refresh_token(str(user.id)),
        role=user.role,
        user=user_info,
    )


@router.post("/oauth", response_model=TokenResponse)
async def oauth_login(payload: OAuthRequest, db: AsyncSession = Depends(get_db)):
    raise HTTPException(status_code=501, detail="OAuth not yet implemented")
