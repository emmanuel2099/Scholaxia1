from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

from app.core.database import get_db
from app.core.deps import require_student, require_teacher, get_current_user
from app.models.community import (
    CommunityChannel, CommunityMessage, MessageReport,
    AssignmentSubmission, AssignmentStatus, AssignmentFileType, ChannelType,
)
from app.models.user import StudentProfile, UserRole, User
from app.services.moderation_service import check_message_content
from app.services.notification_service import send_user_notification

router = APIRouter(prefix="/community", tags=["Community"])

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


# ── Join ──────────────────────────────────────────────────────────────────────

class JoinChannelRequest(BaseModel):
    channel_id: str


@router.post("/join")
async def join_channel(
    payload: JoinChannelRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    Students join the General channel.
    Teacher Announcement channel cannot be joined — it's auto-visible to all.
    """
    result = await db.execute(select(StudentProfile).where(StudentProfile.user_id == current_user["sub"]))
    profile = result.scalar_one_or_none()
    if not profile:
        raise HTTPException(status_code=404, detail="Student profile not found")

    if not profile.has_active_subscription:
        raise HTTPException(status_code=403, detail="Active subscription required to join community")

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
    channel_result = await db.execute(select(CommunityChannel).where(CommunityChannel.id == payload.channel_id))
    channel = channel_result.scalar_one_or_none()
    if not channel:
        raise HTTPException(status_code=404, detail="Channel not found")

    role = current_user.get("role")

    # Teacher announcement: only teachers/admins can post
    if channel.is_readonly_for_students and role == UserRole.student:
        raise HTTPException(status_code=403, detail="Only teachers and admins can post in this channel")

    # Students must have joined the general channel
    if role == UserRole.student:
        profile_result = await db.execute(
            select(StudentProfile).where(StudentProfile.user_id == current_user["sub"])
        )
        profile = profile_result.scalar_one_or_none()
        if not profile or str(profile.community_channel_id) != payload.channel_id:
            raise HTTPException(status_code=403, detail="You must join this channel first")

    flagged, reason = await check_message_content(payload.content)

    message = CommunityMessage(
        channel_id=payload.channel_id,
        sender_id=current_user["sub"],
        content=payload.content,
        media_url=payload.media_url,
        media_type=payload.media_type,
        is_flagged=flagged,
        flagged_reason=reason,
    )
    db.add(message)
    await db.flush()

    if flagged:
        raise HTTPException(status_code=400, detail=f"Message blocked: {reason}")

    return {"message_id": str(message.id), "status": "sent"}


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
    current_user: dict = Depends(require_student),
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
    current_user: dict = Depends(require_student),
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
    current_user: dict = Depends(require_student),
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
    query = (
        select(CommunityMessage)
        .where(
            CommunityMessage.channel_id == channel_id,
            CommunityMessage.is_deleted == False,  # noqa: E712
        )
        .order_by(CommunityMessage.created_at.desc())
        .limit(limit)
    )
    result = await db.execute(query)
    msgs = result.scalars().all()
    msgs = list(reversed(msgs))  # return oldest-first for display

    # Fetch sender names in one query
    sender_ids = list({str(m.sender_id) for m in msgs})
    users_result = await db.execute(select(User).where(User.id.in_(sender_ids)))
    users_map = {str(u.id): u.full_name for u in users_result.scalars().all()}

    return [
        {
            "id": str(m.id),
            "channel_id": str(m.channel_id),
            "sender_id": str(m.sender_id),
            "sender_name": users_map.get(str(m.sender_id), "Unknown"),
            "content": m.content,
            "media_url": m.media_url,
            "media_type": m.media_type,
            "created_at": m.created_at,
        }
        for m in msgs
    ]


# ── Posts (Feed) ──────────────────────────────────────────────────────────────

from app.models.community import CommunityPost, PostLike


class CreatePostRequest(BaseModel):
    channel_id: str
    content: str
    media_url: Optional[str] = None
    media_type: Optional[str] = None  # image | pdf | video


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
    result = await db.execute(
        select(CommunityPost)
        .where(
            CommunityPost.channel_id == channel_id,
            CommunityPost.is_deleted == False,  # noqa: E712
        )
        .order_by(CommunityPost.created_at.desc())
        .limit(limit)
        .offset(offset)
    )
    posts = result.scalars().all()

    author_ids = list({str(p.author_id) for p in posts})
    users_result = await db.execute(select(User).where(User.id.in_(author_ids)))
    users_map = {str(u.id): u.full_name for u in users_result.scalars().all()}

    # Check which posts the current user has liked
    post_ids = [str(p.id) for p in posts]
    likes_result = await db.execute(
        select(PostLike).where(
            PostLike.post_id.in_(post_ids),
            PostLike.user_id == current_user["sub"],
        )
    )
    liked_ids = {str(l.post_id) for l in likes_result.scalars().all()}

    return [
        {
            "id": str(p.id),
            "channel_id": str(p.channel_id),
            "author_id": str(p.author_id),
            "author_name": users_map.get(str(p.author_id), "Unknown"),
            "content": p.content,
            "media_url": p.media_url,
            "media_type": p.media_type,
            "is_pinned": p.is_pinned,
            "like_count": p.like_count,
            "liked_by_me": str(p.id) in liked_ids,
            "created_at": p.created_at,
        }
        for p in posts
    ]


@router.post("/posts", status_code=201)
async def create_post(
    payload: CreatePostRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    POST /api/v1/community/posts
    Any logged-in user can create a post. Students blocked in readonly channels.
    """
    channel_res = await db.execute(
        select(CommunityChannel).where(CommunityChannel.id == payload.channel_id)
    )
    channel = channel_res.scalar_one_or_none()
    if not channel:
        raise HTTPException(status_code=404, detail="Channel not found")

    role = current_user.get("role")
    if channel.is_readonly_for_students and role == "student":
        raise HTTPException(status_code=403, detail="Only teachers and admins can post in this channel")

    flagged, reason = await check_message_content(payload.content)
    if flagged:
        raise HTTPException(status_code=400, detail=f"Post blocked: {reason}")

    post = CommunityPost(
        channel_id=payload.channel_id,
        author_id=current_user["sub"],
        content=payload.content,
        media_url=payload.media_url,
        media_type=payload.media_type,
    )
    db.add(post)
    await db.flush()

    return {
        "id": str(post.id),
        "channel_id": str(post.channel_id),
        "content": post.content,
        "created_at": post.created_at,
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
        select(CommunityPost).where(CommunityPost.id == post_id, CommunityPost.is_deleted == False)  # noqa: E712
    )
    post = post_res.scalar_one_or_none()
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    existing = await db.execute(
        select(PostLike).where(
            PostLike.post_id == post_id,
            PostLike.user_id == current_user["sub"],
        )
    )
    like = existing.scalar_one_or_none()

    if like:
        await db.delete(like)
        post.like_count = max(0, post.like_count - 1)
        return {"liked": False, "like_count": post.like_count}
    else:
        db.add(PostLike(post_id=post_id, user_id=current_user["sub"]))
        post.like_count += 1
        return {"liked": True, "like_count": post.like_count}


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
    users_result = await db.execute(select(User).where(User.id.in_(author_ids)))
    users_map = {str(u.id): u.full_name for u in users_result.scalars().all()}

    return [
        {
            "id": str(p.id),
            "author_id": str(p.author_id),
            "author_name": users_map.get(str(p.author_id), "Unknown"),
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
