from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel, EmailStr, Field
from typing import Optional
from app.core.database import get_db
from app.core.security import hash_password, verify_password, create_access_token, create_refresh_token
from app.core.config import settings
from app.models.user import User, UserRole, StudentProfile, TeacherProfile, KindProfile
from app.services.otp_service import (
    send_otp,
    verify_otp,
    store_pending_signup,
    load_pending_signup,
    clear_pending_signup,
)

router = APIRouter(prefix="/auth", tags=["Authentication"])


class StudentSignupRequest(BaseModel):
    """Legacy email signup (kept for older clients). Prefer phone OTP flow."""
    email: EmailStr
    password: str
    full_name: str


class KindSignupRequest(BaseModel):
    email: EmailStr
    password: str
    full_name: str
    age_group: str = "6-8"
    grade_level: Optional[str] = None
    parent_email: Optional[EmailStr] = None
    favorite_subjects: Optional[list] = None


class LoginRequest(BaseModel):
    password: str
    email: Optional[EmailStr] = None
    phone: Optional[str] = None  # legacy phone login (older clients)


class SendOtpRequest(BaseModel):
    email: EmailStr
    purpose: str = "signup"  # signup | login


class SignupStartRequest(BaseModel):
    email: EmailStr
    full_name: str = Field(..., min_length=2, max_length=255)
    password: str = Field(..., min_length=8, max_length=128)
    role: str = "student"  # student | kind
    age_group: str = "6-8"
    grade_level: Optional[str] = None
    parent_email: Optional[str] = None


class SignupVerifyRequest(BaseModel):
    email: EmailStr
    otp: str = Field(..., min_length=4, max_length=10)


class OAuthRequest(BaseModel):
    provider: str
    token: str
    full_name: str = ""


class UserInfo(BaseModel):
    id: str
    email: str
    full_name: str
    role: str
    profile_picture: Optional[str] = None
    phone: Optional[str] = None
    exam_type: Optional[str] = None
    selected_subjects: Optional[list] = None
    education_level: Optional[str] = None
    has_active_subscription: Optional[bool] = None
    subjects: Optional[list] = None
    bio: Optional[str] = None
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
    info = UserInfo(
        id=str(user.id),
        email=user.email,
        full_name=user.full_name,
        role=user.role,
        profile_picture=user.profile_picture,
        phone=getattr(user, "phone", None),
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


async def _find_user_by_email(db: AsyncSession, email: str) -> Optional[User]:
    res = await db.execute(select(User).where(User.email == email.lower()))
    return res.scalar_one_or_none()


@router.post("/otp/send")
async def send_otp_email(payload: SendOtpRequest, db: AsyncSession = Depends(get_db)):
    """
    Send email OTP via Brevo.
    purpose=signup → email must NOT be registered
    purpose=login  → email must already exist
    """
    email = payload.email.lower().strip()
    purpose = (payload.purpose or "signup").strip().lower()
    if purpose not in ("signup", "login"):
        raise HTTPException(status_code=400, detail="purpose must be signup or login")

    existing = await _find_user_by_email(db, email)
    if purpose == "signup" and existing:
        raise HTTPException(status_code=400, detail="Email already registered. Please log in.")
    if purpose == "login" and not existing:
        raise HTTPException(status_code=404, detail="No account found for this email.")

    name = existing.full_name if existing else "there"
    await send_otp(email, name, purpose)
    return {
        "ok": True,
        "message": "OTP sent to your email",
        "email": email,
        "expires_in_minutes": settings.OTP_EXPIRE_MINUTES,
    }


@router.post("/signup/start")
async def signup_start(payload: SignupStartRequest, db: AsyncSession = Depends(get_db)):
    """
    Step 1 — collect email, name, password; send email OTP.
    Call /auth/signup/verify with the OTP to create the account.
    """
    email = payload.email.lower().strip()
    role = (payload.role or "student").strip().lower()
    if role not in ("student", "kind"):
        raise HTTPException(status_code=400, detail="role must be student or kind")
    if len(payload.password) < 8:
        raise HTTPException(status_code=400, detail="Password must be at least 8 characters")
    if role == "kind" and payload.age_group not in ("3-5", "6-8", "9-12"):
        raise HTTPException(status_code=400, detail="age_group must be 3-5, 6-8, or 9-12")

    existing = await _find_user_by_email(db, email)
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered. Please log in.")

    pending = {
        "email": email,
        "full_name": payload.full_name.strip(),
        "password_hash": hash_password(payload.password),
        "role": role,
        "age_group": payload.age_group,
        "grade_level": payload.grade_level,
        "parent_email": payload.parent_email,
    }
    await store_pending_signup(email, pending)
    try:
        await send_otp(email, payload.full_name.strip(), "signup")
    except Exception as e:
        print(f"[OTP] Brevo send failed for {email}: {e}")
        raise HTTPException(
            status_code=502,
            detail="Could not send verification email. Check the address and try again.",
        )
    return {
        "ok": True,
        "message": "OTP sent to your email",
        "email": email,
        "expires_in_minutes": settings.OTP_EXPIRE_MINUTES,
    }


@router.post("/signup/verify", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def signup_verify(payload: SignupVerifyRequest, db: AsyncSession = Depends(get_db)):
    """Step 2 — verify email OTP and create the account."""
    email = payload.email.lower().strip()
    if not await verify_otp(email, payload.otp, purpose="signup"):
        raise HTTPException(status_code=400, detail="Invalid or expired OTP")

    pending = await load_pending_signup(email)
    if not pending:
        raise HTTPException(
            status_code=400,
            detail="Signup session expired. Please start signup again.",
        )

    existing = await _find_user_by_email(db, email)
    if existing:
        await clear_pending_signup(email)
        raise HTTPException(status_code=400, detail="Email already registered")

    role = pending.get("role") or "student"
    user = User(
        email=email,
        hashed_password=pending["password_hash"],
        full_name=pending["full_name"],
        role=UserRole.kind if role == "kind" else UserRole.student,
        is_verified=True,
    )
    db.add(user)
    await db.flush()

    if role == "kind":
        db.add(
            KindProfile(
                user_id=user.id,
                age_group=pending.get("age_group") or "6-8",
                grade_level=pending.get("grade_level"),
                parent_email=pending.get("parent_email"),
                favorite_subjects=[],
            )
        )
    else:
        db.add(StudentProfile(user_id=user.id, selected_subjects=[]))
    await db.flush()
    await clear_pending_signup(email)

    user_info = await _build_user_info(user, db)
    return TokenResponse(
        access_token=create_access_token(str(user.id), user.role),
        refresh_token=create_refresh_token(str(user.id)),
        role=user.role,
        user=user_info,
    )


@router.post("/student/signup", status_code=status.HTTP_201_CREATED)
async def student_signup(payload: StudentSignupRequest, db: AsyncSession = Depends(get_db)):
    """Legacy email signup — prefer /auth/signup/start + /auth/signup/verify."""
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
    db.add(StudentProfile(user_id=user.id, selected_subjects=[]))
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
    db.add(
        KindProfile(
            user_id=user.id,
            age_group=payload.age_group,
            grade_level=payload.grade_level,
            parent_email=payload.parent_email,
            favorite_subjects=payload.favorite_subjects or [],
        )
    )
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
    user = None
    email_raw = (payload.email or "").strip()
    phone_raw = (payload.phone or "").strip()

    if email_raw:
        user = await _find_user_by_email(db, email_raw)

    # Legacy clients that registered with a phone number
    if user is None and phone_raw:
        result = await db.execute(select(User).where(User.phone == phone_raw))
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
