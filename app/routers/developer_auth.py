"""
Developer Portal Auth
----------------------
Developers register here to get API keys.
Separate from student/teacher auth — uses the same users table with role=developer.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel, EmailStr
from app.core.database import get_db
from app.core.security import hash_password, verify_password, create_access_token, create_refresh_token, issue_auth_tokens
from app.models.user import User, UserRole

router = APIRouter(prefix="/developer/auth", tags=["Developer Portal"])


class DevSignupRequest(BaseModel):
    email: EmailStr
    password: str
    full_name: str
    company_name: str = ""


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    role: str


@router.post("/signup", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def developer_signup(payload: DevSignupRequest, db: AsyncSession = Depends(get_db)):
    existing = await db.execute(select(User).where(User.email == payload.email))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Email already registered")

    user = User(
        email=payload.email,
        hashed_password=hash_password(payload.password),
        full_name=payload.full_name,
        role=UserRole.developer,
    )
    db.add(user)
    await db.flush()

    access_token, refresh_token = await issue_auth_tokens(db, user)
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        role=user.role,
    )


@router.post("/login", response_model=TokenResponse)
async def developer_login(payload: LoginRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == payload.email))
    user = result.scalar_one_or_none()

    if not user or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    if user.role != UserRole.developer:
        raise HTTPException(status_code=403, detail="Not a developer account")

    access_token, refresh_token = await issue_auth_tokens(db, user)
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        role=user.role,
    )
