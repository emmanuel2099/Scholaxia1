import secrets
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import require_admin
from app.core.security import hash_password
from app.models.school_campus import SchoolCampus
from app.models.user import User, UserRole

router = APIRouter(prefix="/admin/schools", tags=["Schools"])


def _school_dict(row: SchoolCampus, admins: list | None = None) -> dict:
    return {
        "id": str(row.id),
        "name": row.name,
        "code": row.code,
        "city": row.city,
        "state": row.state,
        "is_active": bool(row.is_active),
        "created_at": row.created_at.isoformat() if row.created_at else None,
        "admins": admins or [],
    }


class CreateSchoolRequest(BaseModel):
    name: str = Field(..., min_length=2, max_length=255)
    city: Optional[str] = None
    state: Optional[str] = None
    admin_full_name: str = Field(..., min_length=2, max_length=255)
    admin_email: EmailStr
    admin_password: str = Field(..., min_length=8)


class AddSchoolAdminRequest(BaseModel):
    full_name: str = Field(..., min_length=2, max_length=255)
    email: EmailStr
    password: str = Field(..., min_length=8)


async def _admins_for(db: AsyncSession, school_id) -> list[dict]:
    rows = (
        await db.execute(
            select(User).where(User.school_id == school_id, User.role == UserRole.school_admin)
        )
    ).scalars().all()
    return [
        {"id": str(u.id), "email": u.email, "full_name": u.full_name, "is_active": u.is_active}
        for u in rows
    ]


@router.get("/")
async def list_schools(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    rows = (await db.execute(select(SchoolCampus).order_by(SchoolCampus.created_at.desc()))).scalars().all()
    out = []
    for row in rows:
        out.append(_school_dict(row, await _admins_for(db, row.id)))
    return {"schools": out}


@router.post("/", status_code=201)
async def create_school(
    payload: CreateSchoolRequest,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    email = payload.admin_email.lower().strip()
    existing = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=400, detail="That admin email is already in use")
    campus = SchoolCampus(
        name=payload.name.strip(),
        city=(payload.city or "").strip() or None,
        state=(payload.state or "").strip() or None,
        code="SCH-" + secrets.token_hex(3).upper(),
        created_by=current_user["sub"],
    )
    db.add(campus)
    await db.flush()
    admin = User(
        email=email,
        hashed_password=hash_password(payload.admin_password),
        full_name=payload.admin_full_name.strip(),
        role=UserRole.school_admin,
        is_verified=True,
        is_active=True,
        school_id=campus.id,
    )
    db.add(admin)
    await db.flush()
    return _school_dict(campus, await _admins_for(db, campus.id))


@router.post("/{school_id}/admins", status_code=201)
async def add_school_admin(
    school_id: str,
    payload: AddSchoolAdminRequest,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    campus = (await db.execute(select(SchoolCampus).where(SchoolCampus.id == school_id))).scalar_one_or_none()
    if not campus:
        raise HTTPException(status_code=404, detail="School not found")
    email = payload.email.lower().strip()
    existing = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=400, detail="That email is already in use")
    admin = User(
        email=email,
        hashed_password=hash_password(payload.password),
        full_name=payload.full_name.strip(),
        role=UserRole.school_admin,
        is_verified=True,
        is_active=True,
        school_id=UUID(school_id),
    )
    db.add(admin)
    await db.flush()
    return {"id": str(admin.id), "email": admin.email, "full_name": admin.full_name, "school_id": school_id}


@router.patch("/{school_id}/active")
async def set_school_active(
    school_id: str,
    is_active: bool,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    campus = (await db.execute(select(SchoolCampus).where(SchoolCampus.id == school_id))).scalar_one_or_none()
    if not campus:
        raise HTTPException(status_code=404, detail="School not found")
    campus.is_active = is_active
    await db.flush()
    return _school_dict(campus)
