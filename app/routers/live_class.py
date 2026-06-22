import uuid
import time
import hashlib
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from datetime import datetime, timezone, timedelta
from typing import Optional
from app.core.database import get_db
from app.core.datetime_utils import naive_utc_now, to_naive_utc
from app.core.deps import require_teacher, require_teacher_or_admin, require_student, get_current_user
from app.core.config import settings
from app.models.live_class import LiveClass, ClassAttendance, LiveSessionRequest, LiveSessionRequestStatus
from app.models.user import StudentProfile, User
from app.core.subjects import subject_matches
from app.services.live_class_room import has_mic_access
from app.services.notification_service import send_subject_notification

router = APIRouter(prefix="/live-classes", tags=["Live Classes"])


# ── Agora token helper ────────────────────────────────────────────────────────

def _generate_agora_token(channel_id: str, uid: int, is_teacher: bool) -> str:
    """Generate an Agora RTC token. Falls back to a placeholder if no certificate."""
    if not settings.AGORA_APP_CERTIFICATE:
        # No certificate configured — return a placeholder so the app doesn't crash
        return f"AGORA_CERT_NOT_SET_{channel_id}_{uid}"
    try:
        from agora_token_builder import RtcTokenBuilder
        role = 1 if is_teacher else 2  # 1=Publisher, 2=Subscriber
        expire_ts = int(time.time()) + 3600  # 1 hour
        token = RtcTokenBuilder.buildTokenWithUid(
            settings.AGORA_APP_ID,
            settings.AGORA_APP_CERTIFICATE,
            channel_id,
            uid,
            role,
            expire_ts,
        )
        return token
    except Exception:
        return f"TOKEN_ERROR_{channel_id}_{uid}"


def _user_uid(user_id: str) -> int:
    """Convert UUID to a stable integer UID for Agora (Agora needs uint32)."""
    return int(hashlib.md5(user_id.encode()).hexdigest()[:8], 16) % (2**31)


def _can_manage_class(current_user: dict, live_class: LiveClass) -> bool:
    role = current_user.get("role")
    if role == "admin":
        return True
    return str(live_class.teacher_id) == current_user["sub"]


class CreateClassRequest(BaseModel):
    subject: str
    title: str
    description: Optional[str] = None
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None
    duration_minutes: Optional[int] = 60
    go_live_now: bool = False


class ClassResponse(BaseModel):
    id: str
    subject: str
    title: str
    teacher_id: str
    start_time: datetime
    is_live: bool
    room_id: str


@router.post("/", response_model=ClassResponse)
async def create_class(
    payload: CreateClassRequest,
    current_user: dict = Depends(require_teacher_or_admin),
    db: AsyncSession = Depends(get_db),
):
    room_id = f"room-{uuid.uuid4().hex[:12]}"
    now = naive_utc_now()
    duration = max(15, min(payload.duration_minutes or 60, 180))

    if payload.go_live_now:
        start = now
        end = to_naive_utc(payload.end_time) if payload.end_time else start + timedelta(minutes=duration)
        is_live = True
    else:
        start = to_naive_utc(payload.start_time) if payload.start_time else now + timedelta(hours=1)
        end = to_naive_utc(payload.end_time) if payload.end_time else start + timedelta(minutes=duration)
        is_live = False

    live_class = LiveClass(
        teacher_id=current_user["sub"],
        subject=payload.subject,
        title=payload.title,
        description=payload.description,
        start_time=start,
        end_time=end,
        room_id=room_id,
        is_live=is_live,
    )
    db.add(live_class)
    await db.flush()

    try:
        if is_live:
            await send_subject_notification(
                db=db,
                subject=live_class.subject,
                title="Live class starting now",
                body=f"Your {live_class.subject} class «{live_class.title}» is live now. Join from Live Class.",
                notification_type="live_class",
                data={"class_id": str(live_class.id), "room_id": live_class.room_id},
            )
        else:
            when = start.strftime("%d %b %Y at %I:%M %p")
            await send_subject_notification(
                db=db,
                subject=live_class.subject,
                title=f"Upcoming {live_class.subject} class",
                body=f"«{live_class.title}» is scheduled for {when}. Open Live Class to see upcoming sessions.",
                notification_type="live_class_upcoming",
                data={
                    "class_id": str(live_class.id),
                    "room_id": live_class.room_id,
                    "start_time": start.isoformat(),
                    "end_time": end.isoformat() if end else None,
                },
            )
    except Exception:
        pass

    return ClassResponse(
        id=str(live_class.id),
        subject=live_class.subject,
        title=live_class.title,
        teacher_id=str(live_class.teacher_id),
        start_time=live_class.start_time,
        is_live=live_class.is_live,
        room_id=live_class.room_id,
    )


@router.post("/{class_id}/start")
async def start_class(
    class_id: str,
    current_user: dict = Depends(require_teacher_or_admin),
    db: AsyncSession = Depends(get_db),
):
    """Start a class and notify ONLY students subscribed to that subject."""
    result = await db.execute(select(LiveClass).where(LiveClass.id == class_id))
    live_class = result.scalar_one_or_none()
    if not live_class:
        raise HTTPException(status_code=404, detail="Class not found")
    if not _can_manage_class(current_user, live_class):
        raise HTTPException(status_code=403, detail="Not your class")

    live_class.is_live = True

    # Notify only students who selected this subject
    await send_subject_notification(
        db=db,
        subject=live_class.subject,
        title=f"Live class starting now",
        body=f"Your {live_class.subject} live class is starting now.",
        notification_type="live_class",
        data={"class_id": str(live_class.id), "room_id": live_class.room_id},
    )
    return {"message": "Class started", "room_id": live_class.room_id}


@router.post("/{class_id}/join")
async def join_class(
    class_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(LiveClass).where(LiveClass.id == class_id))
    live_class = result.scalar_one_or_none()
    if not live_class or not live_class.is_live:
        raise HTTPException(status_code=404, detail="Class not live")

    from app.models.payment import Payment, PaymentStatus
    paid_res = await db.execute(
        select(Payment).where(
            Payment.student_id == current_user["sub"],
            Payment.live_class_id == live_class.id,
            Payment.status == PaymentStatus.success,
        )
    )
    if not paid_res.scalar_one_or_none():
        raise HTTPException(
            status_code=402,
            detail="Payment required. Pay with Flutterwave before joining this live class.",
        )

    attendance = ClassAttendance(
        live_class_id=live_class.id,
        student_id=current_user["sub"],
        is_muted=True,
    )
    db.add(attendance)
    await db.flush()

    uid = _user_uid(current_user["sub"])
    token = _generate_agora_token(live_class.room_id, uid, is_teacher=False)
    expires_at = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()

    return {
        "class_id": str(live_class.id),
        "title": live_class.title,
        "subject": live_class.subject,
        "room_id": live_class.room_id,
        "agora_token": token,
        "uid": uid,
        "channel_id": live_class.room_id,
        "app_id": settings.AGORA_APP_ID,
        "is_muted": True,
        "expires_at": expires_at,
        "end_time": live_class.end_time.isoformat() if live_class.end_time else None,
    }


@router.get("/{class_id}/token")
async def get_agora_token(
    class_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get a fresh Agora RTC token for a live class room."""
    result = await db.execute(select(LiveClass).where(LiveClass.id == class_id))
    live_class = result.scalar_one_or_none()
    if not live_class:
        raise HTTPException(status_code=404, detail="Class not found")

    is_teacher = (
        str(live_class.teacher_id) == current_user["sub"]
        or current_user.get("role") == "admin"
    )
    uid = _user_uid(current_user["sub"])
    can_publish = is_teacher or has_mic_access(live_class.room_id, current_user["sub"])
    token = _generate_agora_token(live_class.room_id, uid, is_teacher=can_publish)
    expires_at = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()

    return {
        "token": token,
        "channel_id": live_class.room_id,
        "uid": uid,
        "app_id": settings.AGORA_APP_ID,
        "expires_at": expires_at,
        "end_time": live_class.end_time.isoformat() if live_class.end_time else None,
        "is_live": live_class.is_live,
    }


@router.post("/{class_id}/students/{student_id}/unmute")
async def unmute_student(
    class_id: str,
    student_id: str,
    current_user: dict = Depends(require_teacher_or_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(ClassAttendance).where(
            ClassAttendance.live_class_id == class_id,
            ClassAttendance.student_id == student_id,
        )
    )
    attendance = result.scalar_one_or_none()
    if not attendance:
        raise HTTPException(status_code=404, detail="Student not in class")
    attendance.is_muted = False
    return {"message": "Student unmuted"}


@router.post("/{class_id}/students/{student_id}/remove")
async def remove_student(
    class_id: str,
    student_id: str,
    current_user: dict = Depends(require_teacher),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(ClassAttendance).where(
            ClassAttendance.live_class_id == class_id,
            ClassAttendance.student_id == student_id,
        )
    )
    attendance = result.scalar_one_or_none()
    if not attendance:
        raise HTTPException(status_code=404, detail="Student not in class")
    attendance.is_removed = True
    return {"message": "Student removed"}


# ── Session Listing Endpoints ─────────────────────────────────────────────────

@router.get("/")
async def list_live_classes(
    subject: Optional[str] = None,
    status: Optional[str] = None,   # live | upcoming | past
    limit: int = 20,
    offset: int = 0,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    GET /api/v1/live-classes/
    Returns live class sessions filterable by subject and status.
    - status=live      → only currently live classes
    - status=upcoming  → scheduled in the future, not yet live
    - status=past      → already ended (is_live=False and end_time is set)
    - omit status      → all classes
    """
    now = naive_utc_now()
    query = select(LiveClass)

    if subject:
        query = query.where(LiveClass.subject == subject)

    if status == "live":
        query = query.where(LiveClass.is_live == True)  # noqa: E712
    elif status == "upcoming":
        query = query.where(
            LiveClass.is_live == False,  # noqa: E712
            (LiveClass.end_time > now) | (LiveClass.end_time.is_(None)),
            LiveClass.start_time > now - timedelta(days=30),
        )
    elif status == "past":
        query = query.where(
            LiveClass.is_live == False,  # noqa: E712
            LiveClass.end_time.isnot(None),
        )

    # Teachers only see their own classes
    role = current_user.get("role")
    if role == "teacher":
        query = query.where(LiveClass.teacher_id == current_user["sub"])

    query = query.order_by(LiveClass.start_time.desc()).limit(limit).offset(offset)
    result = await db.execute(query)
    classes = result.scalars().all()

    # Students only see classes matching their selected subjects
    if role == "student":
        prof_res = await db.execute(
            select(StudentProfile).where(StudentProfile.user_id == current_user["sub"])
        )
        profile = prof_res.scalar_one_or_none()
        subjects = list(profile.selected_subjects or []) if profile else []
        if subjects:
            classes = [c for c in classes if subject_matches(c.subject, subjects)]

    # Fetch teacher names
    teacher_ids = list({str(c.teacher_id) for c in classes})
    from app.models.user import User
    users_res = await db.execute(
        select(User).where(User.id.in_(teacher_ids))
    )
    teachers_map = {str(u.id): u.full_name for u in users_res.scalars().all()}

    return [
        {
            "id": str(c.id),
            "title": c.title,
            "subject": c.subject,
            "description": c.description,
            "teacher_id": str(c.teacher_id),
            "teacher_name": teachers_map.get(str(c.teacher_id), "Unknown"),
            "start_time": c.start_time,
            "end_time": c.end_time,
            "is_live": c.is_live,
            "room_id": c.room_id,
            "recording_url": c.recording_url,
            "created_at": c.created_at,
        }
        for c in classes
    ]


# ── Live Session Requests ─────────────────────────────────────────────────────

class CreateSessionRequest(BaseModel):
    subject: str
    topic: Optional[str] = None
    message: Optional[str] = None
    preferred_time: Optional[datetime] = None


class UpdateSessionRequest(BaseModel):
    status: LiveSessionRequestStatus
    linked_class_id: Optional[str] = None


def _request_dict(req: LiveSessionRequest, student_name: str = None) -> dict:
    return {
        "id": str(req.id),
        "student_id": str(req.student_id),
        "student_name": student_name,
        "subject": req.subject,
        "topic": req.topic,
        "message": req.message,
        "preferred_time": req.preferred_time,
        "status": req.status.value if hasattr(req.status, "value") else req.status,
        "linked_class_id": str(req.linked_class_id) if req.linked_class_id else None,
        "created_at": req.created_at,
        "reviewed_at": req.reviewed_at,
    }


@router.post("/requests", status_code=201)
async def create_session_request(
    payload: CreateSessionRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Student requests a live session on a subject."""
    req = LiveSessionRequest(
        student_id=current_user["sub"],
        subject=payload.subject.strip(),
        topic=payload.topic,
        message=payload.message,
        preferred_time=payload.preferred_time,
    )
    db.add(req)
    await db.flush()
    return _request_dict(req)


@router.get("/requests/mine")
async def my_session_requests(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Student's own live session requests."""
    result = await db.execute(
        select(LiveSessionRequest)
        .where(LiveSessionRequest.student_id == current_user["sub"])
        .order_by(LiveSessionRequest.created_at.desc())
    )
    return [_request_dict(r) for r in result.scalars().all()]


@router.get("/requests")
async def list_session_requests(
    status: Optional[str] = None,
    subject: Optional[str] = None,
    limit: int = 30,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Teachers and admins view pending live session requests."""
    role = current_user.get("role")
    if role not in ("teacher", "admin"):
        raise HTTPException(status_code=403, detail="Teachers and admins only")

    query = select(LiveSessionRequest).order_by(LiveSessionRequest.created_at.desc()).limit(limit)
    if status:
        query = query.where(LiveSessionRequest.status == status)
    if subject:
        query = query.where(LiveSessionRequest.subject.ilike(f"%{subject}%"))

    result = await db.execute(query)
    requests = result.scalars().all()

    student_ids = list({str(r.student_id) for r in requests})
    users_res = await db.execute(select(User).where(User.id.in_(student_ids)))
    names_map = {str(u.id): u.full_name for u in users_res.scalars().all()}

    return [_request_dict(r, names_map.get(str(r.student_id))) for r in requests]


@router.patch("/requests/{request_id}")
async def update_session_request(
    request_id: str,
    payload: UpdateSessionRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Teacher or admin updates request status (approve, schedule, dismiss)."""
    role = current_user.get("role")
    if role not in ("teacher", "admin"):
        raise HTTPException(status_code=403, detail="Teachers and admins only")

    result = await db.execute(select(LiveSessionRequest).where(LiveSessionRequest.id == request_id))
    req = result.scalar_one_or_none()
    if not req:
        raise HTTPException(status_code=404, detail="Request not found")

    req.status = payload.status
    req.reviewed_by = current_user["sub"]
    req.reviewed_at = naive_utc_now()
    if payload.linked_class_id:
        req.linked_class_id = payload.linked_class_id
    await db.flush()

    student_res = await db.execute(select(User).where(User.id == req.student_id))
    student = student_res.scalar_one_or_none()
    return _request_dict(req, student.full_name if student else None)


@router.get("/{class_id}")
async def get_class_detail(
    class_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    GET /api/v1/live-classes/{class_id}
    Full details for a single class including attendance count.
    """
    result = await db.execute(select(LiveClass).where(LiveClass.id == class_id))
    live_class = result.scalar_one_or_none()
    if not live_class:
        raise HTTPException(status_code=404, detail="Class not found")

    # Attendance count
    att_result = await db.execute(
        select(ClassAttendance).where(ClassAttendance.live_class_id == class_id)
    )
    attendances = att_result.scalars().all()
    active_count = sum(1 for a in attendances if not a.is_removed and a.left_at is None)

    from app.models.user import User
    teacher_res = await db.execute(select(User).where(User.id == live_class.teacher_id))
    teacher = teacher_res.scalar_one_or_none()

    return {
        "id": str(live_class.id),
        "title": live_class.title,
        "subject": live_class.subject,
        "description": live_class.description,
        "teacher_id": str(live_class.teacher_id),
        "teacher_name": teacher.full_name if teacher else "Unknown",
        "start_time": live_class.start_time,
        "end_time": live_class.end_time,
        "is_live": live_class.is_live,
        "room_id": live_class.room_id,
        "recording_url": live_class.recording_url,
        "is_recording_enabled": live_class.is_recording_enabled,
        "total_attendees": len(attendances),
        "active_attendees": active_count,
        "created_at": live_class.created_at,
    }


@router.post("/{class_id}/end")
async def end_class(
    class_id: str,
    recording_url: Optional[str] = None,
    current_user: dict = Depends(require_teacher_or_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    POST /api/v1/live-classes/{class_id}/end
    Teacher ends the class. Sets is_live=False, records end_time.
    Optionally attach a recording URL.
    """
    result = await db.execute(select(LiveClass).where(LiveClass.id == class_id))
    live_class = result.scalar_one_or_none()
    if not live_class:
        raise HTTPException(status_code=404, detail="Class not found")
    if not _can_manage_class(current_user, live_class):
        raise HTTPException(status_code=403, detail="Not your class")

    live_class.is_live = False
    live_class.end_time = naive_utc_now()
    if recording_url:
        live_class.recording_url = recording_url

    # Mark all still-in-class students as left
    att_res = await db.execute(
        select(ClassAttendance).where(
            ClassAttendance.live_class_id == class_id,
            ClassAttendance.left_at.is_(None),
        )
    )
    for att in att_res.scalars().all():
        att.left_at = naive_utc_now()

    try:
        from app.websockets.live_class_ws import broadcast as ws_broadcast
        await ws_broadcast(
            live_class.room_id,
            {
                "event": "class_ended",
                "class_id": class_id,
                "message": "Class ended by the teacher.",
            },
        )
    except Exception:
        pass

    return {"message": "Class ended", "class_id": class_id, "end_time": live_class.end_time}


@router.post("/{class_id}/leave")
async def leave_class(
    class_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Student leaves a live class — records left_at time."""
    result = await db.execute(
        select(ClassAttendance).where(
            ClassAttendance.live_class_id == class_id,
            ClassAttendance.student_id == current_user["sub"],
            ClassAttendance.left_at.is_(None),
        )
    )
    att = result.scalar_one_or_none()
    if not att:
        raise HTTPException(status_code=404, detail="Attendance record not found")

    att.left_at = naive_utc_now()
    return {"message": "Left class", "left_at": att.left_at}


@router.get("/history/mine")
async def my_class_history(
    limit: int = 20,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    GET /api/v1/live-classes/history/mine
    Students: classes they attended.
    Teachers: classes they hosted (past + upcoming).
    """
    role = current_user.get("role")

    if role == "student":
        result = await db.execute(
            select(ClassAttendance, LiveClass)
            .join(LiveClass, LiveClass.id == ClassAttendance.live_class_id)
            .where(ClassAttendance.student_id == current_user["sub"])
            .order_by(ClassAttendance.joined_at.desc())
            .limit(limit)
        )
        rows = result.all()

        from app.models.user import User
        teacher_ids = list({str(lc.teacher_id) for _, lc in rows})
        users_res = await db.execute(select(User).where(User.id.in_(teacher_ids)))
        teachers_map = {str(u.id): u.full_name for u in users_res.scalars().all()}

        return [
            {
                "class_id": str(lc.id),
                "title": lc.title,
                "subject": lc.subject,
                "teacher_name": teachers_map.get(str(lc.teacher_id), "Unknown"),
                "joined_at": att.joined_at,
                "left_at": att.left_at,
                "was_removed": att.is_removed,
                "is_live": lc.is_live,
                "recording_url": lc.recording_url,
            }
            for att, lc in rows
        ]

    elif role == "teacher":
        result = await db.execute(
            select(LiveClass)
            .where(LiveClass.teacher_id == current_user["sub"])
            .order_by(LiveClass.start_time.desc())
            .limit(limit)
        )
        classes = result.scalars().all()
        return [
            {
                "id": str(c.id),
                "title": c.title,
                "subject": c.subject,
                "start_time": c.start_time,
                "end_time": c.end_time,
                "is_live": c.is_live,
                "room_id": c.room_id,
                "recording_url": c.recording_url,
            }
            for c in classes
        ]

    raise HTTPException(status_code=403, detail="Not authorised")
