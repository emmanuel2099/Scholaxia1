"""Student-created groups with admin approval for new members."""
import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from pydantic import BaseModel
from typing import Optional

from app.core.database import get_db
from app.core.deps import require_student
from app.services.live_class_access import parse_uuid
from app.services.group_community import ensure_group_feed_post
from app.models.student_group import (
    StudentGroup,
    StudentGroupMember,
    StudentGroupJoinRequest,
    StudentGroupMessage,
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


class GroupMessageBody(BaseModel):
    content: str


class AddMemberBody(BaseModel):
    email: str


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
    if payload.is_community_listed:
        await ensure_group_feed_post(db, group)
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
            "member_count": await _member_count(db, grp.id),
        })
    return groups


@router.get("/community-listed")
async def community_listed_groups(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """All groups listed in Community (including ones you created or joined)."""
    uid = parse_uuid(current_user["sub"])
    result = await db.execute(
        select(StudentGroup).where(
            StudentGroup.is_public == True,  # noqa: E712
            StudentGroup.is_community_listed == True,  # noqa: E712
        )
    )
    out = []
    for grp in result.scalars().all():
        mem = await db.execute(
            select(StudentGroupMember).where(
                StudentGroupMember.group_id == grp.id,
                StudentGroupMember.user_id == uid,
            )
        )
        member = mem.scalar_one_or_none()
        pending = await db.execute(
            select(StudentGroupJoinRequest).where(
                StudentGroupJoinRequest.group_id == grp.id,
                StudentGroupJoinRequest.user_id == uid,
                StudentGroupJoinRequest.status == StudentGroupJoinStatus.pending,
            )
        )
        creator_res = await db.execute(select(User).where(User.id == grp.creator_id))
        creator = creator_res.scalar_one_or_none()
        out.append({
            "id": str(grp.id),
            "name": grp.name,
            "description": grp.description,
            "is_member": member is not None,
            "is_admin": member is not None and member.role == StudentGroupMemberRole.admin,
            "pending_request": pending.scalar_one_or_none() is not None,
            "creator_name": creator.full_name if creator else "Student",
            "member_count": await _member_count(db, grp.id),
            "created_at": grp.created_at.isoformat() if grp.created_at else None,
        })
    out.sort(key=lambda g: g["name"].lower())
    return out


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
    if payload.is_community_listed:
        await ensure_group_feed_post(db, group)
    return {
        "message": "Group is now visible in Community for others to request joining."
        if payload.is_community_listed
        else "Group removed from Community listing.",
    }


@router.get("/{group_id}")
async def get_group(
    group_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    grp = await _get_group_or_404(db, gid)
    mem = await _get_membership(db, gid, uid)
    creator_res = await db.execute(select(User).where(User.id == grp.creator_id))
    creator = creator_res.scalar_one_or_none()
    return {
        "id": str(grp.id),
        "name": grp.name,
        "description": grp.description,
        "is_community_listed": grp.is_community_listed,
        "is_member": mem is not None,
        "is_admin": mem is not None and mem.role == StudentGroupMemberRole.admin,
        "member_count": await _member_count(db, gid),
        "creator_name": creator.full_name if creator else "Student",
        "created_at": grp.created_at.isoformat() if grp.created_at else None,
    }


@router.get("/{group_id}/members")
async def list_group_members(
    group_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    if not await _get_membership(db, gid, uid):
        raise HTTPException(status_code=403, detail="Only group members can view the member list.")
    result = await db.execute(
        select(StudentGroupMember, User)
        .join(User, User.id == StudentGroupMember.user_id)
        .where(StudentGroupMember.group_id == gid)
        .order_by(StudentGroupMember.joined_at.asc())
    )
    return [
        {
            "user_id": str(mem.user_id),
            "name": user.full_name or user.email,
            "email": user.email,
            "role": mem.role.value,
            "joined_at": mem.joined_at.isoformat() if mem.joined_at else None,
        }
        for mem, user in result.all()
    ]


@router.post("/{group_id}/members")
async def add_group_member(
    group_id: str,
    payload: AddMemberBody,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    if not await _is_group_admin(db, gid, uid):
        raise HTTPException(status_code=403, detail="Only group admins can add members.")
    email = (payload.email or "").strip().lower()
    if not email:
        raise HTTPException(status_code=400, detail="Enter the student's email.")
    user_res = await db.execute(select(User).where(func.lower(User.email) == email))
    target = user_res.scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="No student found with that email.")
    existing = await _get_membership(db, gid, target.id)
    if existing:
        raise HTTPException(status_code=400, detail="That student is already in the group.")
    db.add(
        StudentGroupMember(
            group_id=gid,
            user_id=target.id,
            role=StudentGroupMemberRole.member,
        )
    )
    await db.flush()
    return {"message": f"{target.full_name or target.email} added to the group."}


@router.get("/{group_id}/messages")
async def list_group_messages(
    group_id: str,
    limit: int = 80,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    if not await _get_membership(db, gid, uid):
        raise HTTPException(status_code=403, detail="Join this group to open the chat room.")
    result = await db.execute(
        select(StudentGroupMessage, User)
        .join(User, User.id == StudentGroupMessage.user_id)
        .where(StudentGroupMessage.group_id == gid)
        .order_by(StudentGroupMessage.created_at.asc())
        .limit(min(limit, 200))
    )
    return [
        {
            "id": str(msg.id),
            "user_id": str(msg.user_id),
            "author_name": user.full_name or user.email,
            "content": msg.content,
            "created_at": msg.created_at.isoformat() if msg.created_at else None,
            "is_mine": str(msg.user_id) == str(uid),
        }
        for msg, user in result.all()
    ]


@router.post("/{group_id}/messages", status_code=201)
async def send_group_message(
    group_id: str,
    payload: GroupMessageBody,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    if not await _get_membership(db, gid, uid):
        raise HTTPException(status_code=403, detail="Join this group to send messages.")
    text = (payload.content or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="Message cannot be empty.")
    msg = StudentGroupMessage(group_id=gid, user_id=uid, content=text)
    db.add(msg)
    await db.flush()
    user_res = await db.execute(select(User).where(User.id == uid))
    user = user_res.scalar_one_or_none()
    return {
        "id": str(msg.id),
        "user_id": str(uid),
        "author_name": user.full_name if user else "Student",
        "content": text,
        "created_at": msg.created_at.isoformat() if msg.created_at else None,
        "is_mine": True,
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


async def _get_group_or_404(db: AsyncSession, group_id: uuid.UUID) -> StudentGroup:
    res = await db.execute(select(StudentGroup).where(StudentGroup.id == group_id))
    group = res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found.")
    return group


async def _get_membership(db: AsyncSession, group_id: uuid.UUID, user_id: uuid.UUID):
    res = await db.execute(
        select(StudentGroupMember).where(
            StudentGroupMember.group_id == group_id,
            StudentGroupMember.user_id == user_id,
        )
    )
    return res.scalar_one_or_none()


async def _member_count(db: AsyncSession, group_id: uuid.UUID) -> int:
    res = await db.execute(
        select(func.count()).select_from(StudentGroupMember).where(
            StudentGroupMember.group_id == group_id
        )
    )
    return int(res.scalar() or 0)
