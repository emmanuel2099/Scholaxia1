"""Student-created groups with admin approval for new members."""
import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from pydantic import BaseModel
from typing import Optional

from app.core.database import get_db
from app.core.deps import require_student_or_kind
from app.services.live_class_access import parse_uuid
from app.services.group_community import ensure_group_feed_post
from app.services.moderation_service import check_message_content
from app.models.student_group import (
    StudentGroup,
    StudentGroupMember,
    StudentGroupJoinRequest,
    StudentGroupMessage,
    StudentGroupMemberRole,
    StudentGroupJoinStatus,
)
from app.models.user import User
from app.models.community import (
    CommunityPost,
    CommunityChannel,
    ChannelType,
    PostLike,
    PostVisibility,
)
from app.routers.community import POST_COMMENT_RE, _serialize_post

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


class UpdateGroupRequest(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None


class GroupMessageBody(BaseModel):
    content: str


class GroupPostBody(BaseModel):
    content: str
    media_url: Optional[str] = None
    media_type: Optional[str] = None


class AddMemberBody(BaseModel):
    email: str


def _group_dict(grp: StudentGroup, mem, pending, member_count: int, creator_name: str = "Student") -> dict:
    return {
        "id": str(grp.id),
        "name": grp.name,
        "description": grp.description,
        "is_public": grp.is_public,
        "is_community_listed": grp.is_community_listed,
        "is_approved": grp.is_approved,
        "is_member": mem is not None,
        "is_admin": mem is not None and mem.role == StudentGroupMemberRole.admin,
        "pending_request": pending,
        "creator_name": creator_name,
        "member_count": member_count,
        "created_at": grp.created_at.isoformat() if grp.created_at else None,
    }


@router.post("/")
async def create_group(
    payload: CreateGroupRequest,
    current_user: dict = Depends(require_student_or_kind),
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
        is_approved=False,
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
    return {
        "id": str(group.id),
        "name": group.name,
        "is_approved": False,
        "message": "Group submitted — a Scholaxia admin must approve it before it becomes active.",
    }


@router.get("/mine")
async def my_groups(
    current_user: dict = Depends(require_student_or_kind),
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
            "is_approved": grp.is_approved,
            "is_admin": mem.role == StudentGroupMemberRole.admin,
            "member_count": await _member_count(db, grp.id),
        })
    return groups


@router.get("/community-listed")
async def community_listed_groups(
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    """All groups listed in Community (including ones you created or joined)."""
    uid = parse_uuid(current_user["sub"])
    result = await db.execute(
        select(StudentGroup).where(
            StudentGroup.is_public == True,  # noqa: E712
            StudentGroup.is_community_listed == True,  # noqa: E712
            StudentGroup.is_approved == True,  # noqa: E712
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
            "is_approved": grp.is_approved,
            "pending_request": pending.scalar_one_or_none() is not None,
            "creator_name": creator.full_name if creator else "Student",
            "member_count": await _member_count(db, grp.id),
            "created_at": grp.created_at.isoformat() if grp.created_at else None,
        })
    out.sort(key=lambda g: g["name"].lower())
    return out


@router.get("/discover")
async def discover_groups(
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    uid = parse_uuid(current_user["sub"])
    result = await db.execute(
        select(StudentGroup).where(
            StudentGroup.is_public == True,  # noqa: E712
            StudentGroup.is_community_listed == True,  # noqa: E712
            StudentGroup.is_approved == True,  # noqa: E712
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
    current_user: dict = Depends(require_student_or_kind),
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
    if not group.is_approved:
        raise HTTPException(status_code=403, detail="This group is not active yet — waiting for admin approval.")
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
    current_user: dict = Depends(require_student_or_kind),
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
    current_user: dict = Depends(require_student_or_kind),
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
    current_user: dict = Depends(require_student_or_kind),
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


@router.patch("/{group_id}")
async def update_group(
    group_id: str,
    payload: UpdateGroupRequest,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    group = await _get_group_or_404(db, gid)
    if str(group.creator_id) != str(uid) and not await _is_group_admin(db, gid, uid):
        raise HTTPException(status_code=403, detail="Only the group creator can rename this group.")
    name = (payload.name or "").strip() if payload.name is not None else None
    if name is not None:
        if not name:
            raise HTTPException(status_code=400, detail="Group name cannot be empty.")
        group.name = name
    if payload.description is not None:
        group.description = (payload.description or "").strip() or None
    await db.flush()
    return {"id": str(group.id), "name": group.name, "description": group.description, "message": "Group updated."}


@router.delete("/{group_id}")
async def delete_group(
    group_id: str,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    group = await _get_group_or_404(db, gid)
    if str(group.creator_id) != str(uid):
        raise HTTPException(status_code=403, detail="Only the group creator can delete this group.")
    from sqlalchemy import delete as sql_delete

    await db.execute(sql_delete(StudentGroupJoinRequest).where(StudentGroupJoinRequest.group_id == gid))
    await db.execute(sql_delete(StudentGroupMessage).where(StudentGroupMessage.group_id == gid))
    await db.execute(sql_delete(StudentGroupMember).where(StudentGroupMember.group_id == gid))
    await db.execute(sql_delete(CommunityPost).where(CommunityPost.group_id == gid))
    await db.execute(sql_delete(StudentGroup).where(StudentGroup.id == gid))
    await db.flush()
    return {"message": "Group deleted."}


@router.patch("/{group_id}/community-list")
async def promote_to_community(
    group_id: str,
    payload: PromoteGroupRequest,
    current_user: dict = Depends(require_student_or_kind),
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
    if not group.is_approved:
        raise HTTPException(status_code=403, detail="Group must be approved by admin before listing in Community.")
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
    current_user: dict = Depends(require_student_or_kind),
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
        "is_approved": grp.is_approved,
        "is_member": mem is not None,
        "is_admin": mem is not None and mem.role == StudentGroupMemberRole.admin,
        "member_count": await _member_count(db, gid),
        "creator_name": creator.full_name if creator else "Student",
        "created_at": grp.created_at.isoformat() if grp.created_at else None,
    }


@router.get("/{group_id}/members")
async def list_group_members(
    group_id: str,
    current_user: dict = Depends(require_student_or_kind),
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
    current_user: dict = Depends(require_student_or_kind),
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


@router.get("/{group_id}/posts")
async def list_group_posts(
    group_id: str,
    limit: int = 50,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    group = await _get_group_or_404(db, gid)
    if not await _get_membership(db, gid, uid):
        raise HTTPException(status_code=403, detail="Join this group to view posts.")
    if not group.is_approved:
        raise HTTPException(status_code=403, detail="This group is waiting for admin approval.")

    result = await db.execute(
        select(CommunityPost)
        .where(
            CommunityPost.group_id == gid,
            CommunityPost.is_deleted == False,  # noqa: E712
        )
        .order_by(CommunityPost.created_at.desc())
        .limit(min(limit, 100))
    )
    posts = result.scalars().all()
    posts = [p for p in posts if not POST_COMMENT_RE.match(p.content or "")]
    posts = list(reversed(posts))

    author_ids = list({str(p.author_id) for p in posts})
    users_map = {}
    if author_ids:
        author_uuids = [parse_uuid(aid) for aid in author_ids]
        users_result = await db.execute(select(User).where(User.id.in_(author_uuids)))
        users_map = {str(u.id): u.full_name for u in users_result.scalars().all()}

    post_ids = [str(p.id) for p in posts]
    liked_ids: set[str] = set()
    if post_ids:
        post_uuids = [parse_uuid(pid) for pid in post_ids]
        likes_result = await db.execute(
            select(PostLike).where(
                PostLike.post_id.in_(post_uuids),
                PostLike.user_id == uid,
            )
        )
        liked_ids = {str(like.post_id) for like in likes_result.scalars().all()}

    role = current_user.get("role")
    return [
        _serialize_post(p, users_map, liked_ids, current_user["sub"], role)
        for p in posts
    ]


@router.post("/{group_id}/posts", status_code=201)
async def create_group_post(
    group_id: str,
    payload: GroupPostBody,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    group = await _get_group_or_404(db, gid)
    if not await _get_membership(db, gid, uid):
        raise HTTPException(status_code=403, detail="Join this group to post.")
    if not group.is_approved:
        raise HTTPException(status_code=403, detail="This group is waiting for admin approval.")

    text = (payload.content or "").strip()
    if not text and not payload.media_url:
        raise HTTPException(status_code=400, detail="Post cannot be empty.")

    flagged, reason = await check_message_content(text or "")
    if flagged:
        raise HTTPException(status_code=400, detail=reason)

    ch_res = await db.execute(
        select(CommunityChannel).where(CommunityChannel.channel_type == ChannelType.general)
    )
    channel = ch_res.scalar_one_or_none()
    if not channel:
        raise HTTPException(status_code=503, detail="Community channel not configured.")

    post = CommunityPost(
        channel_id=channel.id,
        author_id=uid,
        group_id=gid,
        content=text or ("Voice note" if payload.media_type == "audio" else ""),
        media_url=payload.media_url,
        media_type=payload.media_type,
        visibility=PostVisibility.everyone.value,
    )
    db.add(post)
    await db.flush()

    user_res = await db.execute(select(User).where(User.id == uid))
    user = user_res.scalar_one_or_none()
    author_name = user.full_name if user else "Student"

    return {
        "id": str(post.id),
        "channel_id": str(post.channel_id),
        "author_id": str(uid),
        "author_name": author_name,
        "content": post.content,
        "media_url": post.media_url,
        "media_type": post.media_type,
        "like_count": 0,
        "liked_by_me": False,
        "created_at": post.created_at.isoformat() if post.created_at else None,
    }


@router.get("/{group_id}/messages")
async def list_group_messages(
    group_id: str,
    limit: int = 80,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    if not await _get_membership(db, gid, uid):
        raise HTTPException(status_code=403, detail="Join this group to open the chat room.")
    group = await _get_group_or_404(db, gid)
    if not group.is_approved:
        raise HTTPException(status_code=403, detail="This group is waiting for admin approval.")
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
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    if not await _get_membership(db, gid, uid):
        raise HTTPException(status_code=403, detail="Join this group to send messages.")
    group = await _get_group_or_404(db, gid)
    if not group.is_approved:
        raise HTTPException(status_code=403, detail="This group is waiting for admin approval.")
    text = (payload.content or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="Message cannot be empty.")
    flagged, reason = await check_message_content(text)
    if flagged:
        raise HTTPException(status_code=400, detail=reason)
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


# ── Group voice calls (WhatsApp-style, groups only) ───────────────────────────

# In-memory active calls: group_id -> {caller_id, caller_name, room_id, started_at}
_active_group_calls: dict[str, dict] = {}


def _group_call_room(group_id: str) -> str:
    return f"group-voice-{group_id}"


async def _notify_group_members_call(
    db: AsyncSession,
    group_id,
    caller_id,
    caller_name: str,
    group_name: str,
):
    from app.services.notification_service import send_user_notification
    from datetime import datetime

    members = await db.execute(
        select(StudentGroupMember).where(StudentGroupMember.group_id == group_id)
    )
    for mem in members.scalars().all():
        if str(mem.user_id) == str(caller_id):
            continue
        try:
            await send_user_notification(
                db,
                user_id=str(mem.user_id),
                title=f"Group call · {group_name}",
                body=f"{caller_name} is calling the group. Tap to join.",
                notification_type="group_call",
                data={
                    "type": "group_call",
                    "group_id": str(group_id),
                    "caller_id": str(caller_id),
                    "caller_name": caller_name,
                },
            )
        except Exception:
            pass


@router.post("/{group_id}/calls/start")
async def start_group_voice_call(
    group_id: str,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    if not await _get_membership(db, gid, uid):
        raise HTTPException(status_code=403, detail="Join this group to call.")
    group = await _get_group_or_404(db, gid)
    if not group.is_approved:
        raise HTTPException(status_code=403, detail="Group not approved yet.")

    key = str(gid)
    existing = _active_group_calls.get(key)
    if existing and existing.get("caller_id") != str(uid):
        # Someone already calling — join that call instead of replacing.
        pass
    else:
        user_res = await db.execute(select(User).where(User.id == uid))
        user = user_res.scalar_one_or_none()
        caller_name = (user.full_name if user else None) or current_user.get("email") or "Member"
        from datetime import datetime, timezone
        room_id = _group_call_room(key)
        _active_group_calls[key] = {
            "caller_id": str(uid),
            "caller_name": caller_name,
            "room_id": room_id,
            "group_name": group.name,
            "started_at": datetime.now(timezone.utc).isoformat(),
        }
        await _notify_group_members_call(db, gid, uid, caller_name, group.name)

    call = _active_group_calls[key]
    from app.routers.live_class import _livekit_token_payload
    display = current_user.get("email") or current_user.get("sub") or "user"
    payload = _livekit_token_payload(
        call["room_id"],
        str(uid),
        display,
        can_publish=True,
    )
    return {
        "active": True,
        "group_id": key,
        "group_name": call.get("group_name") or group.name,
        "caller_id": call["caller_id"],
        "caller_name": call["caller_name"],
        "room_id": call["room_id"],
        **payload,
    }


@router.get("/{group_id}/calls/active")
async def get_active_group_call(
    group_id: str,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    if not await _get_membership(db, gid, uid):
        raise HTTPException(status_code=403, detail="Not a member.")
    call = _active_group_calls.get(str(gid))
    if not call:
        return {"active": False}
    return {
        "active": True,
        "group_id": str(gid),
        "group_name": call.get("group_name"),
        "caller_id": call["caller_id"],
        "caller_name": call["caller_name"],
        "room_id": call["room_id"],
        "started_at": call.get("started_at"),
    }


@router.post("/{group_id}/calls/join")
async def join_group_voice_call(
    group_id: str,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    if not await _get_membership(db, gid, uid):
        raise HTTPException(status_code=403, detail="Not a member.")
    call = _active_group_calls.get(str(gid))
    if not call:
        raise HTTPException(status_code=404, detail="No active call.")
    from app.routers.live_class import _livekit_token_payload
    display = current_user.get("email") or current_user.get("sub") or "user"
    payload = _livekit_token_payload(
        call["room_id"],
        str(uid),
        display,
        can_publish=True,
    )
    return {
        "active": True,
        "group_id": str(gid),
        "group_name": call.get("group_name"),
        "caller_id": call["caller_id"],
        "caller_name": call["caller_name"],
        "room_id": call["room_id"],
        **payload,
    }


@router.post("/{group_id}/calls/end")
async def end_group_voice_call(
    group_id: str,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    gid = parse_uuid(group_id)
    uid = parse_uuid(current_user["sub"])
    if not await _get_membership(db, gid, uid):
        raise HTTPException(status_code=403, detail="Not a member.")
    key = str(gid)
    call = _active_group_calls.get(key)
    if call:
        # Any member can leave; caller (or alone) ending clears the call.
        _active_group_calls.pop(key, None)
    return {"active": False, "message": "Call ended"}


@router.post("/{group_id}/calls/decline")
async def decline_group_voice_call(
    group_id: str,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    # Decline is local — we just acknowledge; ring stops on client.
    return {"declined": True}


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
