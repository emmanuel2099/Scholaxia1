import secrets
from typing import Optional
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal, get_db
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
    admin_full_name: str = ""
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
    from app.core.startup_db import ensure_school_campus_schema

    await ensure_school_campus_schema()
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
):
    """Use a fresh DB session after enum migrate. Auth's open transaction cannot see a new enum value."""
    from app.core.startup_db import ensure_postgres_enums, ensure_school_campus_schema

    await ensure_postgres_enums()
    await ensure_school_campus_schema()
    email = payload.admin_email.lower().strip()
    admin_name = (payload.admin_full_name or "").strip() or email.split("@")[0]
    try:
        created_by = UUID(str(current_user.get("sub")))
    except Exception:
        created_by = None

    async with AsyncSessionLocal() as db:
        try:
            existing = (
                await db.execute(text("SELECT id FROM users WHERE lower(email) = lower(:e) LIMIT 1"), {"e": email})
            ).first()
            if existing:
                raise HTTPException(status_code=400, detail="That admin email is already in use")
            campus = SchoolCampus(
                name=payload.name.strip(),
                city=(payload.city or "").strip() or None,
                state=(payload.state or "").strip() or None,
                code="SCH-" + secrets.token_hex(3).upper(),
                created_by=created_by,
            )
            db.add(campus)
            await db.flush()
            params = {
                "id": uuid4(),
                "email": email,
                "hp": hash_password(payload.admin_password),
                "name": admin_name,
                "role": "school_admin",
                "sid": campus.id,
            }
            last_exc = None
            for sql in (
                """
                INSERT INTO users (
                    id, email, hashed_password, full_name, role,
                    is_verified, is_active, school_id, token_version, created_at, updated_at
                ) VALUES (
                    :id, :email, :hp, :name, CAST(:role AS userrole),
                    true, true, :sid, 0, NOW(), NOW()
                )
                """,
                """
                INSERT INTO users (
                    id, email, hashed_password, full_name, role,
                    is_verified, is_active, school_id, created_at, updated_at
                ) VALUES (
                    :id, :email, :hp, :name, CAST(:role AS userrole),
                    true, true, :sid, NOW(), NOW()
                )
                """,
                """
                INSERT INTO users (
                    id, email, hashed_password, full_name, role,
                    is_verified, is_active, school_id, token_version
                ) VALUES (
                    :id, :email, :hp, :name, :role, true, true, :sid, 0
                )
                """,
                """
                INSERT INTO users (id, email, hashed_password, full_name, role, is_verified, is_active, school_id)
                VALUES (:id, :email, :hp, :name, :role, true, true, :sid)
                """,
            ):
                try:
                    async with db.begin_nested():
                        await db.execute(text(sql), params)
                    last_exc = None
                    break
                except Exception as exc:
                    last_exc = exc
            if last_exc:
                raise last_exc
            await db.commit()
            admins = await _admins_for(db, campus.id)
            return _school_dict(campus, admins)
        except HTTPException:
            await db.rollback()
            raise
        except Exception as exc:
            await db.rollback()
            raise HTTPException(
                status_code=500,
                detail="Could not create school: %s" % (str(exc).split("\n")[0][:240],),
            ) from exc


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
