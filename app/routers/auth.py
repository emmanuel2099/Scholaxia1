from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel, EmailStr
from app.core.database import get_db
from app.core.security import hash_password, verify_password, create_access_token, create_refresh_token
from app.models.user import User, UserRole, StudentProfile

router = APIRouter(prefix="/auth", tags=["Authentication"])


class StudentSignupRequest(BaseModel):
    email: EmailStr
    password: str
    full_name: str


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class OAuthRequest(BaseModel):
    provider: str  # google | apple
    token: str
    full_name: str = ""


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    role: str


@router.post("/student/signup", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
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

    return TokenResponse(
        access_token=create_access_token(str(user.id), user.role),
        refresh_token=create_refresh_token(str(user.id)),
        role=user.role,
    )


@router.post("/login", response_model=TokenResponse)
async def login(payload: LoginRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == payload.email))
    user = result.scalar_one_or_none()

    if not user or not user.hashed_password or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account disabled")

    return TokenResponse(
        access_token=create_access_token(str(user.id), user.role),
        refresh_token=create_refresh_token(str(user.id)),
        role=user.role,
    )


@router.post("/oauth", response_model=TokenResponse)
async def oauth_login(payload: OAuthRequest, db: AsyncSession = Depends(get_db)):
    raise HTTPException(status_code=501, detail="OAuth not yet implemented")
