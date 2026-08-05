from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel, EmailStr, Field
from typing import Optional
from app.core.database import get_db
from app.core.security import hash_password, verify_password, create_access_token, create_refresh_token, issue_auth_tokens
from app.core.config import settings
from app.models.user import User, UserRole, StudentProfile, TeacherProfile, VendorProfile, KindProfile
from app.services.otp_service import (
    send_otp,
    verify_otp,
    store_pending_signup,
    load_pending_signup,
    clear_pending_signup,
)
from app.services.firebase_auth_service import (
    normalize_phone,
    phone_to_email,
    phone_from_firebase_token,
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
    purpose: str = "signup"  # signup | login | reset_password


class PasswordResetRequest(BaseModel):
    email: EmailStr
    otp: str = Field(..., min_length=4, max_length=10)
    new_password: str = Field(..., min_length=8, max_length=128)


class SignupStartRequest(BaseModel):
    email: EmailStr
    full_name: str = Field(..., min_length=2, max_length=255)
    password: str = Field(..., min_length=8, max_length=128)
    role: str = "student"  # student | kind | teacher | vendor
    age_group: str = "6-8"
    grade_level: Optional[str] = None
    parent_email: Optional[str] = None
    phone: Optional[str] = None
    location: Optional[str] = None
    address: Optional[str] = None
    subjects: Optional[list[str]] = None
    business_name: Optional[str] = None
    categories: Optional[list[str]] = None


class SignupVerifyRequest(BaseModel):
    email: EmailStr
    otp: str = Field(..., min_length=4, max_length=10)


class FirebaseAuthRequest(BaseModel):
    """Complete signup/login after Firebase Phone Auth SMS verification."""
    id_token: str = Field(..., min_length=20)
    mode: str = "login"  # login | signup
    full_name: Optional[str] = None
    password: Optional[str] = None
    role: str = "student"  # student | kind | teacher | vendor
    age_group: str = "6-8"
    grade_level: Optional[str] = None
    parent_email: Optional[str] = None


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
    location: Optional[str] = None
    is_approved: Optional[bool] = None
    business_name: Optional[str] = None
    vendor_categories: Optional[list] = None
    vendor_whatsapp: Optional[str] = None
    kyc_completed: Optional[bool] = None
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
            info.location = profile.location
            info.is_approved = bool(profile.is_approved)
    elif user.role == UserRole.vendor:
        res = await db.execute(select(VendorProfile).where(VendorProfile.user_id == user.id))
        profile = res.scalar_one_or_none()
        if profile:
            info.business_name = profile.business_name
            info.location = profile.location
            info.vendor_categories = profile.categories or []
            info.is_approved = bool(profile.is_approved)
            info.vendor_whatsapp = profile.whatsapp
            info.kyc_completed = bool(profile.kyc_completed and (profile.nin or "").strip())
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


async def _find_user_by_phone(db: AsyncSession, phone_e164: str) -> Optional[User]:
    res = await db.execute(select(User).where(User.phone == phone_e164))
    user = res.scalar_one_or_none()
    if user:
        return user
    email = phone_to_email(phone_e164)
    res = await db.execute(select(User).where(User.email == email))
    return res.scalar_one_or_none()


@router.post("/firebase", response_model=TokenResponse)
async def firebase_phone_auth(payload: FirebaseAuthRequest, db: AsyncSession = Depends(get_db)):
    """
    After the client verifies SMS with Firebase Phone Auth, send the ID token here.
    mode=login  → phone must already exist
    mode=signup → create student/kind account (requires full_name + password)
    """
    phone = phone_from_firebase_token(payload.id_token)
    mode = (payload.mode or "login").strip().lower()
    if mode not in ("login", "signup"):
        raise HTTPException(status_code=400, detail="mode must be login or signup")

    user = await _find_user_by_phone(db, phone)

    if mode == "login":
        if not user:
            raise HTTPException(
                status_code=404,
                detail="No account for this phone. Please sign up first.",
            )
        if not user.is_active:
            raise HTTPException(status_code=403, detail="Account disabled")
        user.is_verified = True
        await db.flush()
        user_info = await _build_user_info(user, db)
        access_token, refresh_token = await issue_auth_tokens(db, user)
        return TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            role=user.role,
            user=user_info,
        )

    # signup
    if user:
        raise HTTPException(status_code=400, detail="Phone already registered. Please log in.")

    full_name = (payload.full_name or "").strip()
    if len(full_name) < 2:
        raise HTTPException(status_code=400, detail="full_name is required for signup")
    password = payload.password or ""
    if len(password) < 8:
        raise HTTPException(status_code=400, detail="Password must be at least 8 characters")

    role = (payload.role or "student").strip().lower()
    if role not in ("student", "kind", "teacher", "vendor"):
        raise HTTPException(status_code=400, detail="role must be student, kind, teacher, or vendor")
    if role == "kind" and payload.age_group not in ("3-5", "6-8", "9-12"):
        raise HTTPException(status_code=400, detail="age_group must be 3-5, 6-8, or 9-12")

    role_map = {
        "student": UserRole.student,
        "kind": UserRole.kind,
        "teacher": UserRole.teacher,
        "vendor": UserRole.vendor,
    }
    user = User(
        email=phone_to_email(phone),
        phone=phone,
        hashed_password=hash_password(password),
        full_name=full_name,
        role=role_map.get(role, UserRole.student),
        is_verified=True,
        oauth_provider="firebase_phone",
        oauth_id=phone,
    )
    db.add(user)
    await db.flush()

    if role == "kind":
        db.add(
            KindProfile(
                user_id=user.id,
                age_group=payload.age_group or "6-8",
                grade_level=payload.grade_level,
                parent_email=payload.parent_email,
                favorite_subjects=[],
            )
        )
    elif role == "teacher":
        db.add(
            TeacherProfile(
                user_id=user.id,
                subjects=[],
                location=None,
                bio="",
                is_approved=False,
            )
        )
    elif role == "vendor":
        db.add(
            VendorProfile(
                user_id=user.id,
                business_name=full_name,
                location=None,
                categories=[],
                whatsapp=phone,
                is_approved=False,
            )
        )
    else:
        db.add(StudentProfile(user_id=user.id, selected_subjects=[]))
    await db.flush()

    user_info = await _build_user_info(user, db)
    access_token, refresh_token = await issue_auth_tokens(db, user)
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        role=user.role,
        user=user_info,
    )


@router.post("/otp/send")
async def send_otp_email(payload: SendOtpRequest, db: AsyncSession = Depends(get_db)):
    """
    Send an OTP through the configured email provider.
    purpose=signup         → email must NOT be registered
    purpose=login          → email must already exist
    purpose=reset_password → email must already exist
    """
    email = payload.email.lower().strip()
    purpose = (payload.purpose or "signup").strip().lower()
    if purpose not in ("signup", "login", "reset_password"):
        raise HTTPException(
            status_code=400,
            detail="purpose must be signup, login, or reset_password",
        )

    existing = await _find_user_by_email(db, email)
    if purpose == "signup" and existing:
        raise HTTPException(status_code=400, detail="Email already registered. Please log in.")
    if purpose in ("login", "reset_password") and not existing:
        raise HTTPException(status_code=404, detail="No account found for this email.")

    name = existing.full_name if existing else "there"
    try:
        otp = await send_otp(email, name, purpose)
    except Exception as e:
        print(f"[OTP] email send failed for {email}: {e}")
        raise HTTPException(
            status_code=502,
            detail="Could not send email. Check the address and try again.",
        )
    out = {
        "ok": True,
        "message": "OTP sent to your email",
        "email": email,
        "expires_in_minutes": settings.OTP_EXPIRE_MINUTES,
    }
    if settings.DEBUG:
        out["debug_otp"] = otp
        out["message"] = f"OTP sent to your email (debug code: {otp})"
    return out


@router.post("/password/reset")
async def reset_password(payload: PasswordResetRequest, db: AsyncSession = Depends(get_db)):
    """Verify reset OTP and set a new password."""
    email = payload.email.lower().strip()
    if not await verify_otp(email, payload.otp, purpose="reset_password"):
        raise HTTPException(status_code=400, detail="Invalid or expired OTP")

    user = await _find_user_by_email(db, email)
    if not user:
        raise HTTPException(status_code=404, detail="No account found for this email.")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account disabled")

    user.hashed_password = hash_password(payload.new_password)
    await db.flush()
    return {"ok": True, "message": "Password updated. You can log in with your new password."}


@router.post("/signup/start")
async def signup_start(payload: SignupStartRequest, db: AsyncSession = Depends(get_db)):
    """
    Step 1 — collect email, name, password; send email OTP.
    Call /auth/signup/verify with the OTP to create the account.
    """
    email = payload.email.lower().strip()
    role = (payload.role or "student").strip().lower()
    if role not in ("student", "kind", "teacher", "vendor"):
        raise HTTPException(
            status_code=400,
            detail="role must be student, kind, teacher, or vendor",
        )
    if len(payload.password) < 8:
        raise HTTPException(status_code=400, detail="Password must be at least 8 characters")
    if role == "kind" and payload.age_group not in ("3-5", "6-8", "9-12"):
        raise HTTPException(status_code=400, detail="age_group must be 3-5, 6-8, or 9-12")
    if role == "teacher" and not (payload.subjects or []):
        raise HTTPException(status_code=400, detail="Teacher subjects are required")
    if role == "vendor" and not (payload.business_name or "").strip():
        raise HTTPException(status_code=400, detail="Business name is required for vendor signup")
    if role == "vendor" and not (payload.location or "").strip():
        raise HTTPException(status_code=400, detail="Location is required for vendor signup")
    if role == "vendor" and not (payload.address or "").strip():
        raise HTTPException(status_code=400, detail="Address is required for vendor signup")
    if role == "vendor" and len((payload.phone or "").strip()) < 7:
        raise HTTPException(status_code=400, detail="WhatsApp / phone number is required for vendor signup")

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
        "phone": (payload.phone or "").strip() or None,
        "location": (payload.location or "").strip() or None,
        "address": (payload.address or "").strip() or None,
        "subjects": payload.subjects or [],
        "business_name": (payload.business_name or "").strip() or None,
        "categories": payload.categories or [],
    }
    await store_pending_signup(email, pending)
    try:
        otp = await send_otp(email, payload.full_name.strip(), "signup")
    except Exception as e:
        print(f"[OTP] email send failed for {email}: {e}")
        raise HTTPException(
            status_code=502,
            detail="Could not send verification email. Check the address and try again.",
        )
    out = {
        "ok": True,
        "message": "OTP sent to your email",
        "email": email,
        "expires_in_minutes": settings.OTP_EXPIRE_MINUTES,
    }
    if settings.DEBUG:
        out["debug_otp"] = otp
        out["message"] = f"OTP sent to your email (debug code: {otp})"
    return out


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
    role_map = {
        "student": UserRole.student,
        "kind": UserRole.kind,
        "teacher": UserRole.teacher,
        "vendor": UserRole.vendor,
    }
    user = User(
        email=email,
        hashed_password=pending["password_hash"],
        full_name=pending["full_name"],
        role=role_map.get(role, UserRole.student),
        is_verified=True,
        phone=pending.get("phone"),
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
    elif role == "teacher":
        db.add(
            TeacherProfile(
                user_id=user.id,
                subjects=pending.get("subjects") or [],
                location=pending.get("location"),
                bio="",
                is_approved=False,
            )
        )
    elif role == "vendor":
        vendor_phone = (pending.get("phone") or "").strip() or None
        db.add(
            VendorProfile(
                user_id=user.id,
                business_name=pending.get("business_name") or user.full_name,
                location=pending.get("location"),
                address=pending.get("address"),
                whatsapp=vendor_phone,
                categories=pending.get("categories") or [],
                is_approved=False,
                kyc_completed=False,
            )
        )
    else:
        db.add(StudentProfile(user_id=user.id, selected_subjects=[]))
    await db.flush()
    await clear_pending_signup(email)

    user_info = await _build_user_info(user, db)
    access_token, refresh_token = await issue_auth_tokens(db, user)
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
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
    access_token, refresh_token = await issue_auth_tokens(db, user)
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
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
    access_token, refresh_token = await issue_auth_tokens(db, user)
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
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
        try:
            phone = normalize_phone(phone_raw)
        except HTTPException:
            phone = phone_raw
        user = await _find_user_by_phone(db, phone)

    if not user or not user.hashed_password or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account disabled")

    user_info = await _build_user_info(user, db)
    access_token, refresh_token = await issue_auth_tokens(db, user)
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        role=user.role,
        user=user_info,
    )


@router.post("/oauth", response_model=TokenResponse)
async def oauth_login(payload: OAuthRequest, db: AsyncSession = Depends(get_db)):
    raise HTTPException(status_code=501, detail="OAuth not yet implemented")
