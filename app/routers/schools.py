import secrets
from typing import Optional
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select, text
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
    try:
        rows = (
            await db.execute(
                text(
                    """
                    SELECT id, email, full_name, COALESCE(is_active, true) AS is_active
                    FROM users
                    WHERE school_id = :sid AND role::text = 'school_admin'
                    ORDER BY full_name
                    """
                ),
                {"sid": school_id},
            )
        ).mappings().all()
        return [
            {
                "id": str(u["id"]),
                "email": u["email"],
                "full_name": u["full_name"],
                "is_active": bool(u["is_active"]),
            }
            for u in rows
        ]
    except Exception:
        try:
            await db.rollback()
        except Exception:
            pass
        return []


@router.get("/")
async def list_schools(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    try:
        rows = (await db.execute(select(SchoolCampus).order_by(SchoolCampus.created_at.desc()))).scalars().all()
    except Exception:
        await db.rollback()
        return {"schools": []}
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
    from app.core.startup_db import ensure_postgres_enums

    await ensure_postgres_enums()
    email = payload.admin_email.lower().strip()
    existing = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=400, detail="That admin email is already in use")
    try:
        created_by = UUID(str(current_user.get("sub")))
    except Exception:
        created_by = None
    campus = SchoolCampus(
        name=payload.name.strip(),
        city=(payload.city or "").strip() or None,
        state=(payload.state or "").strip() or None,
        code="SCH-" + secrets.token_hex(3).upper(),
        created_by=created_by,
    )
    db.add(campus)
    await db.flush()
    admin_id = uuid4()
    params = {
        "id": admin_id,
        "email": email,
        "hp": hash_password(payload.admin_password),
        "name": payload.admin_full_name.strip(),
        "role": "school_admin",
        "sid": campus.id,
    }
    insert_sql = """
        INSERT INTO users (
            id, email, hashed_password, full_name, role,
            is_verified, is_active, school_id, token_version, created_at, updated_at
        )
        VALUES (
            :id, :email, :hp, :name, {role_sql},
            true, true, :sid, 0, NOW(), NOW()
        )
    """
    try:
        async with db.begin_nested():
            await db.execute(text(insert_sql.format(role_sql="CAST(:role AS userrole)")), params)
    except Exception:
        try:
            async with db.begin_nested():
                await db.execute(text(insert_sql.format(role_sql=":role")), params)
        except Exception as exc:
            raise HTTPException(
                status_code=500,
                detail="Could not create the school admin (%s). Deploy the latest backend and try again."
                % type(exc).__name__,
            ) from exc
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
