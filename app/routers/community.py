from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime

from app.core.database import get_db
from app.core.deps import require_student_or_kind, require_teacher, get_current_user
from app.models.community import (
    CommunityChannel, CommunityMessage, MessageReport,
    AssignmentSubmission, AssignmentStatus, AssignmentFileType, ChannelType,
    PostVisibility, CommunityPost,
)
from app.models.user import StudentProfile, UserRole, User
from app.services.moderation_service import check_message_content
from app.services.live_class_access import parse_uuid
from app.services.notification_service import (
    send_user_notification,
    send_all_students_notification,
    send_all_teachers_notification,
    send_channel_members_notification,
)
from app.services.media_service import upload_file
from app.services.group_community import parse_group_post
from app.models.student_group import (
    StudentGroup,
    StudentGroupMember,
    StudentGroupJoinRequest,
    StudentGroupJoinStatus,
    StudentGroupMemberRole,
)
from sqlalchemy import func, or_

import re

router = APIRouter(prefix="/community", tags=["Community"])

POST_COMMENT_RE = re.compile(r"^@post:([^\s]+)\s*([\s\S]*)$")

# ── Channels ──────────────────────────────────────────────────────────────────

@router.get("/channels")
async def list_channels(db: AsyncSession = Depends(get_db)):
    """
    Returns the two available channels:
      1. General Channel  (Art + Science + Commercial students — all in one)
      2. Teacher Announcement Channel (read-only for students)
    """
    result = await db.execute(select(CommunityChannel))
    channels = result.scalars().all()
    return [
        {
            "id": str(c.id),
            "name": c.name,
            "type": c.channel_type,
            "is_readonly_for_students": c.is_readonly_for_students,
        }
        for c in channels
    ]


@router.get("/channels/{channel_id}/members")
async def get_channel_members(
    channel_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    GET /api/v1/community/channels/{channel_id}/members
    Returns all members of a channel:
      - Students who have joined this channel (via community_channel_id)
      - All teachers and admins (they can access all channels)
    """
    # Verify channel exists
    channel_result = await db.execute(select(CommunityChannel).where(CommunityChannel.id == channel_id))
    channel = channel_result.scalar_one_or_none()
    if not channel:
        raise HTTPException(status_code=404, detail="Channel not found")

    members = []

    # Get students who have joined this channel
    students_result = await db.execute(
        select(StudentProfile, User)
        .join(User, User.id == StudentProfile.user_id)
        .where(StudentProfile.community_channel_id == channel_id)
    )
    for profile, user in students_result.all():
        members.append({
            "id": str(user.id),
            "name": user.full_name,
            "email": user.email,
            "role": "student",
            "joined_at": profile.created_at if profile.created_at else user.created_at,
        })

    # Get all teachers and admins (they can access all channels)
    teachers_admins_result = await db.execute(
        select(User).where(User.role.in_([UserRole.teacher, UserRole.admin]))
    )
    for user in teachers_admins_result.scalars().all():
        members.append({
            "id": str(user.id),
            "name": user.full_name,
            "email": user.email,
            "role": user.role,
            "joined_at": user.created_at,
        })

    # Sort by role (teachers/admins first), then by name
    members.sort(key=lambda x: (0 if x["role"] in ["teacher", "admin"] else 1, x["name"]))

    return {
        "channel_id": channel_id,
        "channel_name": channel.name,
        "total_members": len(members),
        "members": members,
    }


# ── Join ──────────────────────────────────────────────────────────────────────

class JoinChannelRequest(BaseModel):
    channel_id: str


@router.post("/join")
async def join_channel(
    payload: JoinChannelRequest,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    """
    Students / kid learners join the General channel.
    Teacher Announcement channel cannot be joined — it's auto-visible to all.
    """
    if current_user.get("role") == "kind":
        channel_result = await db.execute(
            select(CommunityChannel).where(CommunityChannel.id == payload.channel_id)
        )
        channel = channel_result.scalar_one_or_none()
        if not channel:
            raise HTTPException(status_code=404, detail="Channel not found")
        if channel.channel_type == ChannelType.teacher_announcement:
            raise HTTPException(
                status_code=403,
                detail="Teacher announcement channel is read-only — no need to join",
            )
        return {"message": f"Joined {channel.name}"}

    result = await db.execute(select(StudentProfile).where(StudentProfile.user_id == current_user["sub"]))
    profile = result.scalar_one_or_none()
    if not profile:
        # Auto-create a minimal profile for users who registered before setup-exam was required
        profile = StudentProfile(user_id=current_user["sub"], selected_subjects=[])
        db.add(profile)
        await db.flush()

    channel_result = await db.execute(select(CommunityChannel).where(CommunityChannel.id == payload.channel_id))
    channel = channel_result.scalar_one_or_none()
    if not channel:
        raise HTTPException(status_code=404, detail="Channel not found")

    if channel.channel_type == ChannelType.teacher_announcement:
        raise HTTPException(status_code=403, detail="Teacher announcement channel is read-only — no need to join")

    profile.community_channel_id = channel.id
    return {"message": f"Joined {channel.name}"}


# ── Messages ──────────────────────────────────────────────────────────────────

class SendMessageRequest(BaseModel):
    channel_id: str
    content: str
    media_url: Optional[str] = None
    media_type: Optional[str] = None  # image | pdf


@router.post("/messages")
async def send_message(
    payload: SendMessageRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    channel_result = await db.execute(
        select(CommunityChannel).where(CommunityChannel.id == parse_uuid(payload.channel_id))
    )
    channel = channel_result.scalar_one_or_none()
    if not channel:
        raise HTTPException(status_code=404, detail="Channel not found")

    role = current_user.get("role")
    channel_id_str = str(channel.id)

    # Teacher announcement: only teachers/admins can post
    if channel.is_readonly_for_students and role in (UserRole.student, "kind"):
        raise HTTPException(status_code=403, detail="Only teachers and admins can post in this channel")

    # Students must have joined the general channel
    if role == UserRole.student:
        profile_result = await db.execute(
            select(StudentProfile).where(StudentProfile.user_id == current_user["sub"])
        )
        profile = profile_result.scalar_one_or_none()
        if not profile or str(profile.community_channel_id) != channel_id_str:
            raise HTTPException(status_code=403, detail="You must join this channel first")

    flagged, reason = await check_message_content(payload.content)
    if flagged:
        # Auto-eject student from community channel for links / phones / bad words.
        if role == UserRole.student or role == "student":
            profile_result = await db.execute(
                select(StudentProfile).where(StudentProfile.user_id == current_user["sub"])
            )
            profile = profile_result.scalar_one_or_none()
            if profile and profile.community_channel_id:
                profile.community_channel_id = None
                await db.flush()
                raise HTTPException(
                    status_code=403,
                    detail=(
                        "You were removed from Community for sharing a link, phone number, "
                        "or prohibited words. Rejoin later only after admin approval."
                    ),
                )
        raise HTTPException(status_code=400, detail=f"Message blocked: {reason}")

    sender_res = await db.execute(select(User).where(User.id == current_user["sub"]))
    sender = sender_res.scalar_one_or_none()
    sender_name = sender.full_name if sender else "Someone"

    message = CommunityMessage(
        channel_id=parse_uuid(payload.channel_id),
        sender_id=current_user["sub"],
        content=payload.content,
        media_url=payload.media_url,
        media_type=payload.media_type,
        is_flagged=False,
        flagged_reason=None,
    )
    db.add(message)
    await db.flush()

    # ── Notifications ─────────────────────────────────────────────────────
    try:
        comment_match = POST_COMMENT_RE.match(payload.content or "")
        if comment_match:
            post_id = comment_match.group(1)
            post_res = await db.execute(
                select(CommunityPost).where(CommunityPost.id == parse_uuid(post_id))
            )
            post = post_res.scalar_one_or_none()
            if post and str(post.author_id) != current_user["sub"]:
                await send_user_notification(
                    db=db,
                    user_id=str(post.author_id),
                    title="New comment on your post",
                    body=f"{sender_name}: {comment_match.group(2)[:120]}",
                    notification_type="community_mention",
                    data={"post_id": post_id, "channel_id": str(channel.id)},
                )
        elif channel.channel_type == ChannelType.teacher_announcement:
            preview = (payload.content or "New announcement")[:160]
            if payload.media_type == "audio":
                preview = "Voice announcement"
            await send_all_students_notification(
                db=db,
                title=f"Announcement from {sender_name}",
                body=preview,
                notification_type="announcement",
                data={"channel_id": str(channel.id), "message_id": str(message.id)},
            )
        elif channel.channel_type == ChannelType.general:
            preview = (payload.content or "New message")[:120]
            if payload.media_type == "audio":
                preview = f"{sender_name} sent a voice note"
            if role == UserRole.student:
                await send_all_teachers_notification(
                    db=db,
                    title="Community message",
                    body=f"{sender_name}: {preview}",
                    notification_type="community_mention",
                    data={"channel_id": str(channel.id), "message_id": str(message.id)},
                    exclude_user_id=current_user["sub"],
                )
            await send_channel_members_notification(
                db=db,
                channel_id=str(channel.id),
                title="New community message",
                body=f"{sender_name}: {preview}",
                notification_type="community_mention",
                data={"channel_id": str(channel.id), "message_id": str(message.id)},
                exclude_user_id=current_user["sub"],
            )
    except Exception:
        pass

    return {
        "id": str(message.id),
        "message_id": str(message.id),
        "status": "sent",
        "channel_id": str(channel.id),
        "sender_id": str(current_user["sub"]),
        "sender_name": sender_name,
        "author_name": sender_name,
        "author_picture": sender.profile_picture if sender else None,
        "profile_picture": sender.profile_picture if sender else None,
        "content": payload.content,
        "media_url": payload.media_url,
        "media_type": payload.media_type,
        "created_at": message.created_at.isoformat() if message.created_at else None,
    }


class ReportMessageRequest(BaseModel):
    message_id: str
    reason: str


@router.post("/messages/report")
async def report_message(
    payload: ReportMessageRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    report = MessageReport(
        message_id=payload.message_id,
        reported_by=current_user["sub"],
        reason=payload.reason,
    )
    db.add(report)
    await db.flush()
    return {"message": "Report submitted"}


# ── Assignment Board ──────────────────────────────────────────────────────────

class SubmitAssignmentRequest(BaseModel):
    channel_id: str
    tagged_teacher_id: str
    file_url: str
    file_type: AssignmentFileType   # "pdf" | "image"
    caption: Optional[str] = None


class AssignmentFileTypeConfirmRequest(BaseModel):
    """
    Frontend first calls /assignments/confirm-type to ask the student
    whether they want to send as PDF or plain image before uploading.
    This endpoint validates the choice and returns upload instructions.
    """
    file_type: AssignmentFileType


@router.post("/assignments/confirm-type")
async def confirm_assignment_file_type(
    payload: AssignmentFileTypeConfirmRequest,
    current_user: dict = Depends(require_student_or_kind),
):
    """
    Before submitting, the system asks: 'Send as PDF or plain image?'
    Returns upload instructions based on the student's choice.
    """
    if payload.file_type == AssignmentFileType.pdf:
        return {
            "file_type": "pdf",
            "message": "Please upload your assignment as a PDF file.",
            "accepted_mime_types": ["application/pdf"],
            "max_size_mb": 20,
        }
    return {
        "file_type": "image",
        "message": "Please upload your assignment as an image (JPG or PNG).",
        "accepted_mime_types": ["image/jpeg", "image/png"],
        "max_size_mb": 10,
    }


@router.post("/assignments", status_code=201)
async def submit_assignment(
    payload: SubmitAssignmentRequest,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    """
    Student tags a teacher and submits assignment (PDF or image).
    Teacher gets a notification. Other students cannot see this submission.
    """
    # Verify teacher exists
    teacher_result = await db.execute(
        select(User).where(User.id == payload.tagged_teacher_id, User.role == UserRole.teacher)
    )
    teacher = teacher_result.scalar_one_or_none()
    if not teacher:
        raise HTTPException(status_code=404, detail="Teacher not found")

    submission = AssignmentSubmission(
        channel_id=payload.channel_id,
        student_id=current_user["sub"],
        tagged_teacher_id=payload.tagged_teacher_id,
        file_url=payload.file_url,
        file_type=payload.file_type,
        caption=payload.caption,
    )
    db.add(submission)
    await db.flush()

    # Notify the tagged teacher
    student_result = await db.execute(select(User).where(User.id == current_user["sub"]))
    student = student_result.scalar_one()

    await send_user_notification(
        db=db,
        user_id=payload.tagged_teacher_id,
        title="New Assignment Submission",
        body=f"{student.full_name} tagged you and submitted an assignment.",
        notification_type="assignment_submission",
        data={"submission_id": str(submission.id)},
    )

    return {"submission_id": str(submission.id), "status": "submitted"}


@router.get("/assignments/mine")
async def my_assignments(
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    """Student views their own submissions and results (private)."""
    result = await db.execute(
        select(AssignmentSubmission)
        .where(AssignmentSubmission.student_id == current_user["sub"])
        .order_by(AssignmentSubmission.submitted_at.desc())
    )
    submissions = result.scalars().all()
    return [
        {
            "id": str(s.id),
            "file_type": s.file_type,
            "caption": s.caption,
            "status": s.status,
            "result_text": s.result_text,
            "result_score": s.result_score,
            "result_feedback": s.result_feedback,
            "result_posted_at": s.result_posted_at,
            "submitted_at": s.submitted_at,
        }
        for s in submissions
    ]


@router.get("/assignments/pending")
async def teacher_pending_assignments(
    current_user: dict = Depends(require_teacher),
    db: AsyncSession = Depends(get_db),
):
    """Teacher views all assignments tagged to them."""
    result = await db.execute(
        select(AssignmentSubmission)
        .where(
            AssignmentSubmission.tagged_teacher_id == current_user["sub"],
            AssignmentSubmission.status == AssignmentStatus.pending,
        )
        .order_by(AssignmentSubmission.submitted_at.asc())
    )
    submissions = result.scalars().all()
    return [
        {
            "id": str(s.id),
            "student_id": str(s.student_id),
            "file_url": s.file_url,
            "file_type": s.file_type,
            "caption": s.caption,
            "submitted_at": s.submitted_at,
        }
        for s in submissions
    ]


class PostResultRequest(BaseModel):
    result_text: str
    result_score: Optional[str] = None   # e.g. "85/100" or "B+"
    result_feedback: Optional[str] = None


@router.post("/assignments/{submission_id}/result")
async def post_assignment_result(
    submission_id: str,
    payload: PostResultRequest,
    current_user: dict = Depends(require_teacher),
    db: AsyncSession = Depends(get_db),
):
    """
    Teacher posts result for a submission.
    Result is PRIVATE — only the student who submitted can see it.
    Other students cannot see this result.
    """
    result = await db.execute(
        select(AssignmentSubmission).where(
            AssignmentSubmission.id == submission_id,
            AssignmentSubmission.tagged_teacher_id == current_user["sub"],
        )
    )
    submission = result.scalar_one_or_none()
    if not submission:
        raise HTTPException(status_code=404, detail="Submission not found")

    submission.result_text = payload.result_text
    submission.result_score = payload.result_score
    submission.result_feedback = payload.result_feedback
    submission.result_posted_at = datetime.utcnow()
    submission.status = AssignmentStatus.graded

    # Notify the student privately
    await send_user_notification(
        db=db,
        user_id=str(submission.student_id),
        title="Assignment Result Posted",
        body=f"Your teacher has reviewed your assignment. Check your result.",
        notification_type="assignment_result",
        data={"submission_id": submission_id},
    )

    return {"message": "Result posted", "submission_id": submission_id}


# ── Messages GET ──────────────────────────────────────────────────────────────

@router.get("/messages")
async def get_messages(
    channel_id: str,
    limit: int = 50,
    before_id: Optional[str] = None,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    GET /api/v1/community/messages?channel_id=xxx
    Returns recent messages in a channel, newest last.
    Optional cursor: before_id for pagination.
    """
    from app.models.community import CommunityMessage
    channel_uuid = parse_uuid(channel_id)
    query = (
        select(CommunityMessage)
        .where(
            CommunityMessage.channel_id == channel_uuid,
            CommunityMessage.is_deleted == False,  # noqa: E712
        )
        .order_by(CommunityMessage.created_at.desc())
        .limit(limit)
    )
    result = await db.execute(query)
    msgs = result.scalars().all()
    msgs = list(reversed(msgs))  # return oldest-first for display
    msgs = [m for m in msgs if not POST_COMMENT_RE.match(m.content or "")]

    # Fetch sender names in one query
    sender_ids = list({str(m.sender_id) for m in msgs})
    users_map = {}
    if sender_ids:
        sender_uuids = [parse_uuid(sid) for sid in sender_ids]
        users_result = await db.execute(select(User).where(User.id.in_(sender_uuids)))
        users_map, pictures_map = _user_maps(users_result.scalars().all())

    return [
        {
            "id": str(m.id),
            "channel_id": str(m.channel_id),
            "sender_id": str(m.sender_id),
            "sender_name": users_map.get(str(m.sender_id), "Unknown"),
            "author_name": users_map.get(str(m.sender_id), "Unknown"),
            "author_picture": pictures_map.get(str(m.sender_id)),
            "profile_picture": pictures_map.get(str(m.sender_id)),
            "content": m.content,
            "media_url": m.media_url,
            "media_type": m.media_type,
            "created_at": m.created_at,
        }
        for m in msgs
    ]


# ── Upload ────────────────────────────────────────────────────────────────────

COMMUNITY_ALLOWED_MIME = {
    "image/jpeg": ("image", "images"),
    "image/png": ("image", "images"),
    "image/webp": ("image", "images"),
    "application/pdf": ("pdf", "assignments"),
    "application/msword": ("doc", "assignments"),
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": ("doc", "assignments"),
    "audio/webm": ("audio", "videos"),
    "audio/mpeg": ("audio", "videos"),
    "audio/mp4": ("audio", "videos"),
    "audio/ogg": ("audio", "videos"),
    "audio/wav": ("audio", "videos"),
    "audio/x-m4a": ("audio", "videos"),
    "audio/aac": ("audio", "videos"),
}

_AUDIO_EXTENSIONS = (".m4a", ".aac", ".mp3", ".webm", ".ogg", ".wav")


def _resolve_community_upload(
    content_type: str | None, filename: str | None
) -> tuple[str, str]:
    ct = (content_type or "").split(";")[0].strip().lower()
    if ct in COMMUNITY_ALLOWED_MIME:
        return COMMUNITY_ALLOWED_MIME[ct]
    name = (filename or "").lower()
    if name.endswith(_AUDIO_EXTENSIONS):
        return ("audio", "videos")
    raise HTTPException(
        status_code=400,
        detail=(
            f"Unsupported file type '{content_type}'. "
            "Allowed: images, PDF, Word docs, and voice notes (.m4a, .webm, .mp3)."
        ),
    )


@router.post("/upload")
async def upload_community_file(
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    """
    POST /api/v1/community/upload
    Upload an image or document for use in a community post.
    Returns file_url and file_type to include in the post body.
    Accepted: JPEG, PNG, WebP, PDF, DOC, DOCX, audio voice notes (max 20MB).
    """
    file_type, folder = _resolve_community_upload(file.content_type, file.filename)

    content = await file.read()
    if len(content) > 20 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="File too large. Maximum size is 20MB.")

    try:
        result = upload_file(content, folder)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")

    return {
        "file_url": result["secure_url"],
        "file_type": file_type,
    }


# ── Posts (Feed) ──────────────────────────────────────────────────────────────

from app.models.community import CommunityPost, PostLike, PostReaction


class CreatePostRequest(BaseModel):
    channel_id: str
    content: str
    is_anonymous: bool = False
    visibility: PostVisibility = PostVisibility.everyone
    media_url: Optional[str] = None
    media_type: Optional[str] = None  # image | pdf | video | doc
    cbt_exam_id: Optional[str] = None


def _visibility_str(value) -> str:
    if value is None:
        return "everyone"
    return value.value if hasattr(value, "value") else str(value)


def _role_str(role) -> str:
    if role is None:
        return ""
    if hasattr(role, "value"):
        return str(role.value)
    return str(role)


ALLOWED_REACTION_EMOJIS = frozenset({"👍", "❤️", "😂", "🔥", "🎉"})


async def _reactions_for_posts(db: AsyncSession, post_ids: list[str], viewer_id: str):
    """Returns (counts_by_post, my_reaction_by_post)."""
    counts: dict[str, dict[str, int]] = {}
    mine: dict[str, str] = {}
    if not post_ids:
        return counts, mine
    post_uuids = [parse_uuid(pid) for pid in post_ids]
    viewer_uuid = parse_uuid(viewer_id)
    res = await db.execute(
        select(PostReaction).where(PostReaction.post_id.in_(post_uuids))
    )
    for row in res.scalars().all():
        pid = str(row.post_id)
        if pid not in counts:
            counts[pid] = {}
        counts[pid][row.emoji] = counts[pid].get(row.emoji, 0) + 1
        if str(row.user_id) == str(viewer_uuid):
            mine[pid] = row.emoji
    return counts, mine


def _user_maps(users) -> tuple[dict, dict]:
    """Return (names_by_id, pictures_by_id) for a list of User rows."""
    names = {}
    pictures = {}
    for u in users:
        names[str(u.id)] = u.full_name
        if u.profile_picture:
            pictures[str(u.id)] = u.profile_picture
    return names, pictures


def _serialize_post(
    p,
    users_map: dict,
    liked_ids: set,
    viewer_id: str,
    role,
    reactions=None,
    my_reaction=None,
    pictures_map: dict | None = None,
) -> dict:
    role_name = _role_str(role)
    viewer_uuid = str(viewer_id)
    show_author = (
        not p.is_anonymous
        or str(p.author_id) == viewer_uuid
        or role_name in ("teacher", "admin")
    )
    pictures_map = pictures_map or {}
    author_id = str(p.author_id) if show_author else None
    return {
        "id": str(p.id),
        "channel_id": str(p.channel_id),
        "author_id": author_id,
        "author_name": users_map.get(str(p.author_id), "Unknown") if show_author else "Anonymous",
        "author_picture": pictures_map.get(str(p.author_id)) if show_author else None,
        "profile_picture": pictures_map.get(str(p.author_id)) if show_author else None,
        "content": p.content,
        "media_url": p.media_url,
        "media_type": p.media_type,
        "is_anonymous": p.is_anonymous,
        "visibility": _visibility_str(p.visibility),
        "cbt_exam_id": str(p.cbt_exam_id) if p.cbt_exam_id else None,
        "is_pinned": p.is_pinned,
        "like_count": p.like_count or 0,
        "liked_by_me": str(p.id) in liked_ids,
        "reactions": reactions or {},
        "my_reaction": my_reaction or "",
        "created_at": p.created_at.isoformat() if p.created_at else None,
    }


async def _fetch_channel_posts(
    channel_id: str,
    limit: int,
    offset: int,
    current_user: dict,
    db: AsyncSession,
) -> list[dict]:
    role_name = _role_str(current_user.get("role"))
    channel_uuid = parse_uuid(channel_id)

    ch_res = await db.execute(select(CommunityChannel).where(CommunityChannel.id == channel_uuid))
    channel = ch_res.scalar_one_or_none()
    if not channel:
        raise HTTPException(status_code=404, detail="Channel not found")

    is_announcement = channel.channel_type == ChannelType.teacher_announcement

    query = (
        select(CommunityPost)
        .where(
            CommunityPost.channel_id == channel_uuid,
            CommunityPost.is_deleted == False,  # noqa: E712
            CommunityPost.group_id.is_(None),
        )
        .order_by(CommunityPost.created_at.desc())
        .limit(limit)
        .offset(offset)
    )
    if role_name not in ("teacher", "admin") and not is_announcement:
        # Use string literals — PostgreSQL enum + SQLAlchemy `.in_([Enum, ...])` 500s for students.
        query = query.where(
            CommunityPost.visibility.in_(["everyone", "class_only"])
        )

    result = await db.execute(query)
    posts = result.scalars().all()
    posts = [p for p in posts if not POST_COMMENT_RE.match(p.content or "")]

    author_ids = list({str(p.author_id) for p in posts})
    users_map: dict = {}
    pictures_map: dict = {}
    if author_ids:
        author_uuids = [parse_uuid(aid) for aid in author_ids]
        users_result = await db.execute(select(User).where(User.id.in_(author_uuids)))
        users_map, pictures_map = _user_maps(users_result.scalars().all())

    post_ids = [str(p.id) for p in posts]
    liked_ids: set[str] = set()
    if post_ids:
        post_uuids = [parse_uuid(pid) for pid in post_ids]
        viewer_uuid = parse_uuid(current_user["sub"])
        likes_result = await db.execute(
            select(PostLike).where(
                PostLike.post_id.in_(post_uuids),
                PostLike.user_id == viewer_uuid,
            )
        )
        liked_ids = {str(l.post_id) for l in likes_result.scalars().all()}

    viewer_id = current_user["sub"]
    reaction_counts, my_reactions = await _reactions_for_posts(db, post_ids, viewer_id)
    serialized = [
        _serialize_post(
            p,
            users_map,
            liked_ids,
            viewer_id,
            current_user.get("role"),
            reaction_counts.get(str(p.id), {}),
            my_reactions.get(str(p.id), ""),
            pictures_map,
        )
        for p in posts
    ]
    return await _enrich_group_posts(serialized, viewer_id, db)


async def _enrich_group_posts(posts: list[dict], viewer_id: str, db: AsyncSession) -> list[dict]:
    uid = parse_uuid(viewer_id)
    for p in posts:
        gid, extra = parse_group_post(p.get("content") or "")
        if not gid:
            continue
        try:
            group_uuid = parse_uuid(gid)
        except Exception:
            continue
        grp_res = await db.execute(select(StudentGroup).where(StudentGroup.id == group_uuid))
        grp = grp_res.scalar_one_or_none()
        if not grp:
            continue
        mem_res = await db.execute(
            select(StudentGroupMember).where(
                StudentGroupMember.group_id == group_uuid,
                StudentGroupMember.user_id == uid,
            )
        )
        member = mem_res.scalar_one_or_none()
        pending_res = await db.execute(
            select(StudentGroupJoinRequest).where(
                StudentGroupJoinRequest.group_id == group_uuid,
                StudentGroupJoinRequest.user_id == uid,
                StudentGroupJoinRequest.status == StudentGroupJoinStatus.pending,
            )
        )
        count_res = await db.execute(
            select(func.count()).select_from(StudentGroupMember).where(
                StudentGroupMember.group_id == group_uuid
            )
        )
        p["post_type"] = "group"
        p["group_id"] = gid
        p["group_name"] = grp.name
        p["group_description"] = grp.description or extra
        p["group_member_count"] = int(count_res.scalar() or 0)
        p["group_is_member"] = member is not None
        p["group_is_admin"] = member is not None and member.role == StudentGroupMemberRole.admin
        p["group_pending_request"] = pending_res.scalar_one_or_none() is not None
    return posts


@router.get("/feed")
async def community_feed(
    limit: int = 40,
    offset: int = 0,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Student feed — all posts from the General channel."""
    ch_res = await db.execute(
        select(CommunityChannel).where(CommunityChannel.channel_type == ChannelType.general)
    )
    channel = ch_res.scalar_one_or_none()
    if not channel:
        return []
    return await _fetch_channel_posts(str(channel.id), limit, offset, current_user, db)


@router.get("/posts")
async def list_posts(
    channel_id: str,
    limit: int = 30,
    offset: int = 0,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    GET /api/v1/community/posts?channel_id=xxx
    Returns paginated posts for a channel, newest first.
    """
    return await _fetch_channel_posts(channel_id, limit, offset, current_user, db)


@router.get("/post-comments")
async def list_post_comments(
    channel_id: str,
    limit: int = 200,
    offset: int = 0,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Return reply posts (@post:parent_id ...) for attaching comments in the feed."""
    channel_uuid = parse_uuid(channel_id)
    ch_res = await db.execute(select(CommunityChannel).where(CommunityChannel.id == channel_uuid))
    if not ch_res.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Channel not found")

    result = await db.execute(
        select(CommunityPost)
        .where(
            CommunityPost.channel_id == channel_uuid,
            CommunityPost.is_deleted == False,  # noqa: E712
            CommunityPost.content.like("@post:%"),
        )
        .order_by(CommunityPost.created_at.asc())
        .limit(min(limit, 300))
        .offset(offset)
    )
    posts = result.scalars().all()

    author_ids = list({str(p.author_id) for p in posts})
    users_map: dict = {}
    pictures_map: dict = {}
    if author_ids:
        author_uuids = [parse_uuid(aid) for aid in author_ids]
        users_result = await db.execute(select(User).where(User.id.in_(author_uuids)))
        users_map, pictures_map = _user_maps(users_result.scalars().all())

    viewer_id = current_user["sub"]
    return [
        _serialize_post(
            p, users_map, set(), viewer_id, current_user.get("role"), pictures_map=pictures_map
        )
        for p in posts
    ]


@router.get("/announcements")
async def list_announcements(
    limit: int = 40,
    offset: int = 0,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Teacher announcements for students — posts from the announcement channel."""
    ch_res = await db.execute(
        select(CommunityChannel).where(CommunityChannel.channel_type == ChannelType.teacher_announcement)
    )
    channel = ch_res.scalar_one_or_none()
    if not channel:
        return []
    return await _fetch_channel_posts(str(channel.id), limit, offset, current_user, db)


@router.post("/posts", status_code=201)
async def create_post(
    payload: CreatePostRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    POST /api/v1/community/posts
    Supports is_anonymous, visibility, media_url/media_type, and cbt_exam_id.
    """
    channel_res = await db.execute(
        select(CommunityChannel).where(CommunityChannel.id == parse_uuid(payload.channel_id))
    )
    channel = channel_res.scalar_one_or_none()
    if not channel:
        raise HTTPException(status_code=404, detail="Channel not found")

    role = current_user.get("role")
    if channel.is_readonly_for_students and role == "student":
        raise HTTPException(status_code=403, detail="Only teachers and admins can post in this channel")

    # teachers_only posts can only be created by teachers/admins
    if payload.visibility == PostVisibility.teachers_only and role == "student":
        raise HTTPException(status_code=403, detail="Students cannot create teachers_only posts")

    flagged, reason = await check_message_content(payload.content)
    if flagged:
        role = current_user.get("role")
        if role == "student":
            profile_result = await db.execute(
                select(StudentProfile).where(StudentProfile.user_id == current_user["sub"])
            )
            profile = profile_result.scalar_one_or_none()
            if profile and profile.community_channel_id:
                profile.community_channel_id = None
                await db.flush()
                raise HTTPException(
                    status_code=403,
                    detail=(
                        "You were removed from Community for sharing a link, phone number, "
                        "or prohibited words."
                    ),
                )
        raise HTTPException(status_code=400, detail=f"Post blocked: {reason}")

    comment_match = POST_COMMENT_RE.match(payload.content or "")

    post = CommunityPost(
        channel_id=parse_uuid(payload.channel_id),
        author_id=current_user["sub"],
        content=payload.content,
        is_anonymous=payload.is_anonymous,
        visibility=payload.visibility.value,
        media_url=payload.media_url,
        media_type=payload.media_type,
        cbt_exam_id=payload.cbt_exam_id,
    )
    db.add(post)
    await db.flush()

    author_res = await db.execute(select(User).where(User.id == current_user["sub"]))
    author = author_res.scalar_one_or_none()
    author_name = author.full_name if author else "Student"

    try:
        if comment_match:
            parent_id = comment_match.group(1)
            parent_res = await db.execute(
                select(CommunityPost).where(CommunityPost.id == parse_uuid(parent_id))
            )
            parent = parent_res.scalar_one_or_none()
            if parent and str(parent.author_id) != current_user["sub"]:
                await send_user_notification(
                    db=db,
                    user_id=str(parent.author_id),
                    title="New comment on your post",
                    body=f"{author_name}: {comment_match.group(2)[:120]}",
                    notification_type="community_mention",
                    data={"post_id": parent_id, "channel_id": str(channel.id)},
                )
        else:
            preview = (payload.content or "New post")[:160]
            if payload.media_type == "audio":
                preview = "Voice note"
            if channel.channel_type == ChannelType.teacher_announcement:
                await send_all_students_notification(
                    db=db,
                    title=f"Announcement: {channel.name}",
                    body=f"{author_name}: {preview}",
                    notification_type="announcement",
                    data={"channel_id": str(channel.id), "post_id": str(post.id)},
                )
            elif channel.channel_type == ChannelType.general:
                if role == UserRole.student:
                    await send_all_teachers_notification(
                        db=db,
                        title="New community post",
                        body=f"{author_name}: {preview}",
                        notification_type="community_mention",
                        data={"channel_id": str(channel.id), "post_id": str(post.id)},
                        exclude_user_id=current_user["sub"],
                    )
                await send_channel_members_notification(
                    db=db,
                    channel_id=str(channel.id),
                    title="New community post",
                    body=f"{author_name}: {preview}",
                    notification_type="community_mention",
                    data={"channel_id": str(channel.id), "post_id": str(post.id)},
                    exclude_user_id=current_user["sub"],
                )
    except Exception:
        pass

    return {
        "id": str(post.id),
        "channel_id": str(post.channel_id),
        "author_id": None if payload.is_anonymous else str(post.author_id),
        "author_name": "Anonymous" if payload.is_anonymous else author_name,
        "author_picture": None if payload.is_anonymous else (author.profile_picture if author else None),
        "profile_picture": None if payload.is_anonymous else (author.profile_picture if author else None),
        "content": post.content,
        "is_anonymous": post.is_anonymous,
        "visibility": _visibility_str(post.visibility),
        "media_url": post.media_url,
        "media_type": post.media_type,
        "cbt_exam_id": str(post.cbt_exam_id) if post.cbt_exam_id else None,
        "created_at": post.created_at.isoformat() if post.created_at else None,
    }


@router.post("/posts/{post_id}/like")
async def toggle_like(
    post_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    POST /api/v1/community/posts/{post_id}/like
    Toggles like — like if not liked, unlike if already liked.
    """
    post_res = await db.execute(
        select(CommunityPost).where(CommunityPost.id == parse_uuid(post_id), CommunityPost.is_deleted == False)  # noqa: E712
    )
    post = post_res.scalar_one_or_none()
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    post_uuid = parse_uuid(post_id)
    user_uuid = parse_uuid(current_user["sub"])
    existing = await db.execute(
        select(PostLike).where(
            PostLike.post_id == post_uuid,
            PostLike.user_id == user_uuid,
        )
    )
    like = existing.scalar_one_or_none()

    if like:
        await db.delete(like)
        post.like_count = max(0, post.like_count - 1)
        await db.flush()
        return {"liked": False, "like_count": post.like_count}
    else:
        db.add(PostLike(post_id=post_uuid, user_id=user_uuid))
        post.like_count += 1
        await db.flush()
        return {"liked": True, "like_count": post.like_count}


class ReactToPostRequest(BaseModel):
    emoji: str = ""


@router.post("/posts/{post_id}/react")
async def react_to_post(
    post_id: str,
    payload: ReactToPostRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Set or remove emoji reaction on a post (one emoji per user)."""
    post_res = await db.execute(
        select(CommunityPost).where(CommunityPost.id == parse_uuid(post_id), CommunityPost.is_deleted == False)  # noqa: E712
    )
    post = post_res.scalar_one_or_none()
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    emoji = (payload.emoji or "").strip()
    if emoji and emoji not in ALLOWED_REACTION_EMOJIS:
        raise HTTPException(status_code=400, detail="Emoji not allowed.")

    post_uuid = parse_uuid(post_id)
    user_uuid = parse_uuid(current_user["sub"])
    existing = await db.execute(
        select(PostReaction).where(
            PostReaction.post_id == post_uuid,
            PostReaction.user_id == user_uuid,
        )
    )
    reaction = existing.scalar_one_or_none()

    if not emoji:
        if reaction:
            await db.delete(reaction)
            await db.flush()
    elif reaction:
        if reaction.emoji == emoji:
            await db.delete(reaction)
            await db.flush()
        else:
            reaction.emoji = emoji
            await db.flush()
    else:
        db.add(PostReaction(post_id=post_uuid, user_id=user_uuid, emoji=emoji))
        await db.flush()

    counts, mine = await _reactions_for_posts(db, [post_id], current_user["sub"])
    return {
        "reactions": counts.get(post_id, {}),
        "my_reaction": mine.get(post_id, ""),
    }


# ── Pinned Posts ──────────────────────────────────────────────────────────────

@router.get("/channels/{channel_id}/pinned")
async def get_pinned_posts(
    channel_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    GET /api/v1/community/channels/{channel_id}/pinned
    Returns all pinned posts for a channel.
    """
    result = await db.execute(
        select(CommunityPost)
        .where(
            CommunityPost.channel_id == channel_id,
            CommunityPost.is_pinned == True,  # noqa: E712
            CommunityPost.is_deleted == False,  # noqa: E712
        )
        .order_by(CommunityPost.created_at.desc())
    )
    posts = result.scalars().all()

    author_ids = list({str(p.author_id) for p in posts})
    users_map: dict = {}
    pictures_map: dict = {}
    if author_ids:
        author_uuids = [parse_uuid(aid) for aid in author_ids]
        users_result = await db.execute(select(User).where(User.id.in_(author_uuids)))
        users_map, pictures_map = _user_maps(users_result.scalars().all())

    return [
        {
            "id": str(p.id),
            "author_id": str(p.author_id),
            "author_name": users_map.get(str(p.author_id), "Unknown"),
            "author_picture": pictures_map.get(str(p.author_id)),
            "profile_picture": pictures_map.get(str(p.author_id)),
            "content": p.content,
            "media_url": p.media_url,
            "like_count": p.like_count,
            "created_at": p.created_at,
        }
        for p in posts
    ]


@router.patch("/posts/{post_id}/pin")
async def pin_post(
    post_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    PATCH /api/v1/community/posts/{post_id}/pin
    Teachers and admins can pin/unpin posts.
    """
    role = current_user.get("role")
    if role not in ("teacher", "admin"):
        raise HTTPException(status_code=403, detail="Teachers and admins only")
    result = await db.execute(
        select(CommunityPost).where(CommunityPost.id == post_id)
    )
    post = result.scalar_one_or_none()
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    post.is_pinned = not post.is_pinned
    return {"post_id": post_id, "is_pinned": post.is_pinned}


class PostUpdate(BaseModel):
    content: str = Field(..., min_length=1, max_length=5000)


@router.patch("/posts/{post_id}")
async def update_own_post(
    post_id: str,
    payload: PostUpdate,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Author (or teacher/admin) can edit a community chat post."""
    result = await db.execute(select(CommunityPost).where(CommunityPost.id == post_id))
    post = result.scalar_one_or_none()
    if not post or post.is_deleted:
        raise HTTPException(status_code=404, detail="Post not found")
    uid = str(current_user["sub"])
    role = current_user.get("role")
    is_owner = str(post.author_id) == uid
    if not is_owner and role not in ("teacher", "admin"):
        raise HTTPException(status_code=403, detail="You can only edit your own messages")
    text = payload.content.strip()
    if not text:
        raise HTTPException(status_code=400, detail="Content required")
    post.content = text
    await db.flush()
    return {
        "id": str(post.id),
        "content": post.content,
        "author_id": str(post.author_id) if post.author_id else None,
        "updated_at": post.updated_at.isoformat() if post.updated_at else None,
        "message": "Post updated",
    }


@router.delete("/posts/{post_id}")
async def delete_own_post(
    post_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Author (or teacher/admin) can soft-delete a community chat post."""
    result = await db.execute(select(CommunityPost).where(CommunityPost.id == post_id))
    post = result.scalar_one_or_none()
    if not post or post.is_deleted:
        raise HTTPException(status_code=404, detail="Post not found")
    uid = str(current_user["sub"])
    role = current_user.get("role")
    is_owner = str(post.author_id) == uid
    if not is_owner and role not in ("teacher", "admin"):
        raise HTTPException(status_code=403, detail="You can only delete your own messages")
    post.is_deleted = True
    await db.flush()
    return {"message": "Post deleted", "id": post_id}
