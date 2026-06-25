"""Student-created groups with admin approval for new members."""
import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_
from pydantic import BaseModel
from typing import Optional

from app.core.database import get_db
from app.core.deps import require_student
from app.services.live_class_access import parse_uuid
from app.models.student_group import (
    StudentGroup,
    StudentGroupMember,
    StudentGroupJoinRequest,
    StudentGroupMemberRole,
    StudentGroupJoinStatus,
)
from app.models.user import User

router = APIRouter(prefix="/student-groups", tags=["Student Groups"])


class CreateGroupRequest(BaseModel):
    name: str
    description: Optional[str] = None
    is_public: bool = True
    is_community_listed: bool = False


class JoinRequestBody(BaseModel):
    message: Optional[str] = None


class PromoteGroupRequest(BaseModel):
    is_community_listed: bool = True


@router.post("/")
async def create_group(
    payload: CreateGroupRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    name = (payload.name or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Group name is required.")
    creator = parse_uuid(current_user["sub"])
    group = StudentGroup(
        creator_id=creator,
        name=name,
        description=(payload.description or "").strip() or None,
        is_public=payload.is_public,
        is_community_listed=payload.is_community_listed,
    )
    db.add(group)
    await db.flush()
    db.add(
        StudentGroupMember(
            group_id=group.id,
            user_id=creator,
            role=StudentGroupMemberRole.admin,
        )
    )
    await db.flush()
    return {"id": str(group.id), "name": group.name, "message": "Group created — you are the admin."}


@router.get("/mine")
async def my_groups(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    uid = parse_uuid(current_user["sub"])
    mem_res = await db.execute(
        select(StudentGroupMember, StudentGroup)
        .join(StudentGroup, StudentGroup.id == StudentGroupMember.group_id)
        .where(StudentGroupMember.user_id == uid)
    )
    groups = []
    for mem, grp in mem_res.all():
        groups.append({
            "id": str(grp.id),
            "name": grp.name,
            "description": grp.description,
            "role": mem.role.value,
            "is_public": grp.is_public,
            "is_community_listed": grp.is_community_listed,
            "is_admin": mem.role == StudentGroupMemberRole.admin,
        })
    return groups


@router.get("/discover")
async def discover_groups(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    uid = parse_uuid(current_user["sub"])
    result = await db.execute(
        select(StudentGroup).where(
            StudentGroup.is_public == True,  # noqa: E712
            StudentGroup.is_community_listed == True,  # noqa: E712
        )
    )
    groups = []
    for grp in result.scalars().all():
        mem = await db.execute(
            select(StudentGroupMember).where(
                StudentGroupMember.group_id == grp.id,
                StudentGroupMember.user_id == uid,
            )
        )
        if mem.scalar_one_or_none():
            continue
        pending = await db.execute(
            select(StudentGroupJoinRequest).where(
                StudentGroupJoinRequest.group_id == grp.id,
                StudentGroupJoinRequest.user_id == uid,
                StudentGroupJoinRequest.status == StudentGroupJoinStatus.pending,
            )
        )
        groups.append({
            "id": str(grp.id),
            "name": grp.name,
            "description": grp.description,
            "pending_request": pending.scalar_one_or_none() is not None,
        })
    return groups


@router.post("/{group_id}/join-request")
async def request_join_group(
    group_id: str,
    payload: JoinRequestBody,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    grp_res = await db.execute(select(StudentGroup).where(StudentGroup.id == gid))
    group = grp_res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found.")
    if not group.is_public:
        raise HTTPException(status_code=403, detail="This group is private.")
    existing = await db.execute(
        select(StudentGroupMember).where(
            StudentGroupMember.group_id == gid,
            StudentGroupMember.user_id == uid,
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="You are already in this group.")
    pending = await db.execute(
        select(StudentGroupJoinRequest).where(
            StudentGroupJoinRequest.group_id == gid,
            StudentGroupJoinRequest.user_id == uid,
            StudentGroupJoinRequest.status == StudentGroupJoinStatus.pending,
        )
    )
    if pending.scalar_one_or_none():
        return {"message": "Request already pending — wait for the admin to approve."}
    db.add(
        StudentGroupJoinRequest(
            group_id=gid,
            user_id=uid,
            message=(payload.message or "").strip() or None,
        )
    )
    await db.flush()
    return {"message": "Join request sent. The group admin must approve you."}


@router.get("/{group_id}/join-requests")
async def list_join_requests(
    group_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    if not await _is_group_admin(db, gid, uid):
        raise HTTPException(status_code=403, detail="Only group admins can view requests.")
    result = await db.execute(
        select(StudentGroupJoinRequest, User)
        .join(User, User.id == StudentGroupJoinRequest.user_id)
        .where(
            StudentGroupJoinRequest.group_id == gid,
            StudentGroupJoinRequest.status == StudentGroupJoinStatus.pending,
        )
    )
    return [
        {
            "id": str(req.id),
            "user_id": str(req.user_id),
            "name": user.full_name or user.email,
            "message": req.message,
            "created_at": req.created_at.isoformat() if req.created_at else None,
        }
        for req, user in result.all()
    ]


@router.post("/{group_id}/join-requests/{request_id}/approve")
async def approve_join_request(
    group_id: str,
    request_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    rid = parse_uuid(request_id)
    uid = parse_uuid(current_user["sub"])
    if not await _is_group_admin(db, gid, uid):
        raise HTTPException(status_code=403, detail="Only group admins can approve members.")
    req_res = await db.execute(
        select(StudentGroupJoinRequest).where(
            StudentGroupJoinRequest.id == rid,
            StudentGroupJoinRequest.group_id == gid,
        )
    )
    req = req_res.scalar_one_or_none()
    if not req or req.status != StudentGroupJoinStatus.pending:
        raise HTTPException(status_code=404, detail="Request not found.")
    req.status = StudentGroupJoinStatus.approved
    db.add(
        StudentGroupMember(
            group_id=gid,
            user_id=req.user_id,
            role=StudentGroupMemberRole.member,
        )
    )
    await db.flush()
    return {"message": "Student approved and added to the group."}


@router.post("/{group_id}/join-requests/{request_id}/reject")
async def reject_join_request(
    group_id: str,
    request_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    rid = parse_uuid(request_id)
    uid = parse_uuid(current_user["sub"])
    if not await _is_group_admin(db, gid, uid):
        raise HTTPException(status_code=403, detail="Only group admins can reject members.")
    req_res = await db.execute(
        select(StudentGroupJoinRequest).where(
            StudentGroupJoinRequest.id == rid,
            StudentGroupJoinRequest.group_id == gid,
        )
    )
    req = req_res.scalar_one_or_none()
    if not req:
        raise HTTPException(status_code=404, detail="Request not found.")
    req.status = StudentGroupJoinStatus.rejected
    await db.flush()
    return {"message": "Request rejected."}


@router.patch("/{group_id}/community-list")
async def promote_to_community(
    group_id: str,
    payload: PromoteGroupRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    if not await _is_group_admin(db, gid, uid):
        raise HTTPException(status_code=403, detail="Only group admins can list the group in Community.")
    grp_res = await db.execute(select(StudentGroup).where(StudentGroup.id == gid))
    group = grp_res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found.")
    group.is_community_listed = payload.is_community_listed
    group.is_public = True
    await db.flush()
    return {
        "message": "Group is now visible in Community for others to request joining."
        if payload.is_community_listed
        else "Group removed from Community listing.",
    }


async def _is_group_admin(db: AsyncSession, group_id: uuid.UUID, user_id: uuid.UUID) -> bool:
    res = await db.execute(
        select(StudentGroupMember).where(
            StudentGroupMember.group_id == group_id,
            StudentGroupMember.user_id == user_id,
            StudentGroupMember.role == StudentGroupMemberRole.admin,
        )
    )
    return res.scalar_one_or_none() is not None
