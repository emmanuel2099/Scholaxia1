import json
import uuid
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.core.database import get_db
from app.core.deps import require_teacher_or_admin, require_student, get_current_user
from app.models.school_group import SchoolGroup
from app.models.user import User

router = APIRouter(prefix="/school-groups", tags=["School Groups"])


class CreateSchoolGroupRequest(BaseModel):
    school_name: str
    name: str
    student_ids: list[str] = []


class UpdateSchoolGroupRequest(BaseModel):
    school_name: str | None = None
    name: str | None = None
    student_ids: list[str] | None = None


def _group_dict(group: SchoolGroup, member_names: dict[str, str] | None = None) -> dict:
    ids = group.member_ids()
    members = [
        {"student_id": sid, "name": (member_names or {}).get(sid, "Student")}
        for sid in ids
    ]
    return {
        "id": str(group.id),
        "school_name": group.school_name,
        "name": group.name,
        "student_ids": ids,
        "members": members,
        "member_count": len(ids),
        "created_at": group.created_at,
    }


@router.get("/mine")
async def list_my_school_groups(
    current_user: dict = Depends(require_teacher_or_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(SchoolGroup)
        .where(SchoolGroup.teacher_id == current_user["sub"])
        .order_by(SchoolGroup.created_at.desc())
    )
    groups = result.scalars().all()
    all_ids = {sid for g in groups for sid in g.member_ids()}
    names: dict[str, str] = {}
    if all_ids:
        users_res = await db.execute(select(User).where(User.id.in_(list(all_ids))))
        names = {str(u.id): u.full_name for u in users_res.scalars().all()}
    return [_group_dict(g, names) for g in groups]


@router.post("/", status_code=201)
async def create_school_group(
    payload: CreateSchoolGroupRequest,
    current_user: dict = Depends(require_teacher_or_admin),
    db: AsyncSession = Depends(get_db),
):
    school_name = payload.school_name.strip()
    name = payload.name.strip()
    if not school_name or not name:
        raise HTTPException(status_code=400, detail="School name and group name are required")
    group = SchoolGroup(
        teacher_id=current_user["sub"],
        school_name=school_name,
        name=name,
        student_ids=json.dumps([str(x) for x in payload.student_ids]),
    )
    db.add(group)
    await db.flush()
    return _group_dict(group)


@router.patch("/{group_id}")
async def update_school_group(
    group_id: str,
    payload: UpdateSchoolGroupRequest,
    current_user: dict = Depends(require_teacher_or_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(SchoolGroup).where(SchoolGroup.id == group_id))
    group = result.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")
    if str(group.teacher_id) != current_user["sub"] and current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Not your group")
    if payload.school_name is not None:
        group.school_name = payload.school_name.strip()
    if payload.name is not None:
        group.name = payload.name.strip()
    if payload.student_ids is not None:
        group.student_ids = json.dumps([str(x) for x in payload.student_ids])
    return _group_dict(group)


@router.get("/student/mine")
async def list_student_school_groups(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """School groups this student was added to by their school/teacher (no self-join)."""
    sid = str(current_user["sub"])
    result = await db.execute(select(SchoolGroup).order_by(SchoolGroup.created_at.desc()))
    groups = [g for g in result.scalars().all() if sid in g.member_ids()]
    teacher_ids = list({str(g.teacher_id) for g in groups})
    teachers: dict[str, str] = {}
    if teacher_ids:
        tr = await db.execute(select(User).where(User.id.in_(teacher_ids)))
        teachers = {str(u.id): u.full_name for u in tr.scalars().all()}
    return [
        {
            "id": str(g.id),
            "school_name": g.school_name,
            "name": g.name,
            "teacher_name": teachers.get(str(g.teacher_id), "Teacher"),
            "type": "school",
            "member_count": len(g.member_ids()),
        }
        for g in groups
    ]


@router.get("/{group_id}")
async def get_school_group(
    group_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(SchoolGroup).where(SchoolGroup.id == group_id))
    group = result.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")
    role = current_user.get("role")
    sid = current_user["sub"]
    if role == "teacher" and str(group.teacher_id) != sid:
        raise HTTPException(status_code=403, detail="Not your group")
    if role == "student" and sid not in group.member_ids():
        raise HTTPException(status_code=403, detail="Not in this group")
    names: dict[str, str] = {}
    ids = group.member_ids()
    if ids:
        users_res = await db.execute(select(User).where(User.id.in_(ids)))
        names = {str(u.id): u.full_name for u in users_res.scalars().all()}
    return _group_dict(group, names)

