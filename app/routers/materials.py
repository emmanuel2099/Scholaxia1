from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import Optional

from app.core.deps import require_student, require_teacher, get_current_user
from app.core.database import get_db
from app.core.subjects import subject_matches
from app.models.teacher_material import TeacherMaterial, MaterialPurchase
from app.models.user import StudentProfile, User

router = APIRouter(prefix="/materials", tags=["Teacher Materials"])


class CreateMaterialRequest(BaseModel):
    title: str
    subject: str
    material_type: str = "pdf"
    file_url: str
    description: Optional[str] = None
    is_free: bool = True
    price: float = 0.0


def _material_dict(m: TeacherMaterial, teacher_name: str = None, has_access: bool = False) -> dict:
    return {
        "id": str(m.id),
        "teacher_id": str(m.teacher_id),
        "teacher_name": teacher_name or "Teacher",
        "title": m.title,
        "subject": m.subject,
        "material_type": m.material_type,
        "file_url": m.file_url if (m.is_free or has_access) else None,
        "description": m.description,
        "is_free": m.is_free,
        "price": m.price,
        "has_access": m.is_free or has_access,
        "created_at": m.created_at.isoformat() if m.created_at else None,
    }


async def _student_has_access(db: AsyncSession, student_id: str, material_id: str, material: TeacherMaterial) -> bool:
    if material.is_free:
        return True
    result = await db.execute(
        select(MaterialPurchase).where(
            MaterialPurchase.student_id == student_id,
            MaterialPurchase.material_id == material_id,
        )
    )
    return result.scalar_one_or_none() is not None


@router.post("/", status_code=201)
async def create_material(
    payload: CreateMaterialRequest,
    current_user: dict = Depends(require_teacher),
    db: AsyncSession = Depends(get_db),
):
    if not payload.is_free and payload.price <= 0:
        raise HTTPException(status_code=400, detail="Paid materials need a price greater than 0")

    material = TeacherMaterial(
        teacher_id=current_user["sub"],
        title=payload.title.strip(),
        subject=payload.subject.strip(),
        material_type=payload.material_type,
        file_url=payload.file_url,
        description=payload.description,
        is_free=payload.is_free,
        price=0.0 if payload.is_free else payload.price,
    )
    db.add(material)
    await db.flush()
    return _material_dict(material, has_access=True)


@router.get("/mine")
async def teacher_materials(
    current_user: dict = Depends(require_teacher),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(TeacherMaterial)
        .where(TeacherMaterial.teacher_id == current_user["sub"], TeacherMaterial.is_active == True)
        .order_by(TeacherMaterial.created_at.desc())
    )
    return [_material_dict(m, has_access=True) for m in result.scalars().all()]


@router.delete("/{material_id}", status_code=204)
async def delete_material(
    material_id: str,
    current_user: dict = Depends(require_teacher),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(TeacherMaterial).where(TeacherMaterial.id == material_id))
    material = result.scalar_one_or_none()
    if not material or str(material.teacher_id) != current_user["sub"]:
        raise HTTPException(status_code=404, detail="Material not found")
    material.is_active = False
    return None


@router.get("/student")
async def student_materials(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    prof_res = await db.execute(select(StudentProfile).where(StudentProfile.user_id == current_user["sub"]))
    profile = prof_res.scalar_one_or_none()
    subjects = list(profile.selected_subjects or []) if profile else []

    result = await db.execute(
        select(TeacherMaterial, User)
        .join(User, User.id == TeacherMaterial.teacher_id)
        .where(TeacherMaterial.is_active == True)
        .order_by(TeacherMaterial.created_at.desc())
    )
    rows = result.all()
    out = []
    for material, teacher in rows:
        if subjects and not subject_matches(material.subject, subjects):
            continue
        has_access = await _student_has_access(db, current_user["sub"], str(material.id), material)
        out.append(_material_dict(material, teacher.full_name, has_access))
    return out


@router.get("/{material_id}/access")
async def material_access(
    material_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(TeacherMaterial).where(TeacherMaterial.id == material_id))
    material = result.scalar_one_or_none()
    if not material or not material.is_active:
        raise HTTPException(status_code=404, detail="Material not found")
    has_access = await _student_has_access(db, current_user["sub"], material_id, material)
    from app.core.config import settings
    return {
        "has_access": has_access,
        "is_free": material.is_free,
        "price": material.price,
        "public_key": settings.PAYSTACK_PUBLIC_KEY,
        "title": material.title,
    }
