import uuid
import hashlib
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_, and_
from pydantic import BaseModel
from datetime import datetime, timezone, timedelta
from typing import Optional
from app.core.database import get_db
from app.core.datetime_utils import naive_utc_now, to_naive_utc
from app.core.deps import require_teacher, require_teacher_or_admin, require_student, get_current_user, require_admin
from app.core.config import settings
from app.models.live_class import LiveClass, ClassAttendance, LiveSessionRequest, LiveSessionRequestStatus
from app.models.user import StudentProfile, User, UserRole
from app.core.subjects import subject_matches
from app.services.live_class_room import (
    has_mic_access,
    has_camera_access,
    has_publish_access,
    grant_mic,
    revoke_mic,
    grant_camera,
    revoke_camera,
)
from app.websockets import live_class_ws
from app.services.live_class_access import get_live_access_info, parse_uuid, consume_live_session
from app.services.notification_service import send_subject_notification, send_user_notification, send_admins_notification

router = APIRouter(prefix="/live-classes", tags=["Live Classes"])


@router.get("/livekit/status")
async def livekit_video_status(current_user: dict = Depends(get_current_user)):
    """Check whether live video (LiveKit) is configured on the server."""
    configured = _livekit_configured()
    return {
        "livekit_url": settings.LIVEKIT_URL if configured else "",
        "configured": configured,
        "video_available": configured,
        "message": (
            "Live video is ready."
            if configured
            else "Set LIVEKIT_URL, LIVEKIT_API_KEY, and LIVEKIT_API_SECRET on the server to enable camera, mic, and screen share."
        ),
    }


@router.get("/agora/status")
async def agora_video_status(current_user: dict = Depends(get_current_user)):
    """Deprecated alias — use /livekit/status."""
    return await livekit_video_status(current_user)


# ── LiveKit token helper ────────────────────────────────────────────────────────

def _livekit_configured() -> bool:
    return bool(
        (settings.LIVEKIT_URL or "").strip()
        and (settings.LIVEKIT_API_KEY or "").strip()
        and (settings.LIVEKIT_API_SECRET or "").strip()
    )


def _generate_livekit_token(
    room_name: str,
    identity: str,
    display_name: str,
    can_publish: bool,
) -> str:
    """Generate a LiveKit room JWT. Falls back to a placeholder if not configured."""
    if not _livekit_configured():
        return f"LIVEKIT_NOT_CONFIGURED_{room_name}"
    try:
        from livekit.api import AccessToken, VideoGrants

        token = AccessToken(settings.LIVEKIT_API_KEY, settings.LIVEKIT_API_SECRET)
        token.with_identity(identity)
        if display_name:
            token.with_name(display_name)
        token.with_ttl(timedelta(hours=6))
        token.with_grants(
            VideoGrants(
                room_join=True,
                room=room_name,
                can_publish=can_publish,
                can_subscribe=True,
                can_publish_data=True,
            )
        )
        return token.to_jwt()
    except Exception:
        return f"TOKEN_ERROR_{room_name}"


def _livekit_token_payload(
    room_id: str,
    user_id: str,
    display_name: str,
    can_publish: bool,
) -> dict:
    identity = str(user_id)
    token = _generate_livekit_token(room_id, identity, display_name, can_publish)
    expires_at = (datetime.now(timezone.utc) + timedelta(hours=6)).isoformat()
    return {
        "room_id": room_id,
        "channel_id": room_id,
        "livekit_token": token,
        "livekit_url": settings.LIVEKIT_URL,
        "token": token,
        "identity": identity,
        "can_publish": can_publish,
        "expires_at": expires_at,
    }


def _user_uid(user_id: str) -> int:
    """Legacy numeric UID (kept for older clients)."""
    return int(hashlib.md5(user_id.encode()).hexdigest()[:8], 16) % (2**31)


def _can_manage_class(current_user: dict, live_class: LiveClass) -> bool:
    role = current_user.get("role")
    if role == "admin":
        return True
    return str(live_class.teacher_id) == current_user["sub"]


def _class_is_active(live_class: LiveClass, now: datetime) -> bool:
    """True when class is live or within its scheduled window."""
    if live_class.is_live:
        return True
    if live_class.start_time and live_class.start_time <= now:
        if live_class.end_time is None or live_class.end_time > now:
            return True
    return False


async def _notify_assigned_students_for_class(
    db: AsyncSession, teacher_id: str, live_class: LiveClass
) -> None:
    """Notify students admin assigned to this teacher when their class goes live."""
    try:
        tid = parse_uuid(teacher_id)
    except ValueError:
        return
    result = await db.execute(
        select(LiveSessionRequest).where(
            LiveSessionRequest.assigned_teacher_id == tid,
            LiveSessionRequest.status.in_([
                LiveSessionRequestStatus.approved,
                LiveSessionRequestStatus.scheduled,
            ]),
        )
    )
    notified = set()
    for req in result.scalars().all():
        if not subject_matches(live_class.subject, [req.subject]):
            continue
        sid = str(req.student_id)
        if sid in notified:
            continue
        notified.add(sid)
        try:
            await send_user_notification(
                db,
                sid,
                "Your teacher is live now",
                f"«{live_class.title}» ({live_class.subject}) — join from Live Class.",
                "live_class",
                {"class_id": str(live_class.id), "room_id": live_class.room_id},
            )
        except Exception:
            pass


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
            await _notify_assigned_students_for_class(db, current_user["sub"], live_class)
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

    was_live = live_class.is_live
    live_class.is_live = True
    now = naive_utc_now()
    if live_class.start_time and live_class.start_time > now:
        live_class.start_time = now
    if live_class.end_time and live_class.end_time <= now:
        live_class.end_time = now + timedelta(hours=2)

    if not was_live:
        await send_subject_notification(
            db=db,
            subject=live_class.subject,
            title="Live class starting now",
            body=f"Your {live_class.subject} live class is starting now.",
            notification_type="live_class",
            data={"class_id": str(live_class.id), "room_id": live_class.room_id},
        )
        await _notify_assigned_students_for_class(db, str(live_class.teacher_id), live_class)
    return {"message": "Class started", "room_id": live_class.room_id, "is_live": True}


@router.post("/{class_id}/join")
async def join_class(
    class_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(LiveClass).where(LiveClass.id == class_id))
    live_class = result.scalar_one_or_none()
    now = naive_utc_now()
    if not live_class or not _class_is_active(live_class, now):
        raise HTTPException(status_code=404, detail="Class not live")

    prof_res = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == current_user["sub"])
    )
    profile = prof_res.scalar_one_or_none()
    subjects = list(profile.selected_subjects or []) if profile else []
    if not subjects:
        raise HTTPException(
            status_code=400,
            detail="Add your subjects in profile setup to join live classes.",
        )
    if not subject_matches(live_class.subject, subjects):
        raise HTTPException(
            status_code=403,
            detail="This live class is not for one of your selected subjects.",
        )

    if not live_class.is_live:
        live_class.is_live = True

    access = await get_live_access_info(db, current_user["sub"], class_id)
    if not access["can_join"]:
        if access.get("active_plan") and access.get("sessions_left", 0) <= 0:
            raise HTTPException(
                status_code=402,
                detail="You have used all live sessions on your plan this month. Upgrade or renew your plan.",
            )
        raise HTTPException(
            status_code=402,
            detail="Choose a Scholaxia One-on-One Live Class plan before joining.",
        )

    student_uid = parse_uuid(current_user["sub"])
    existing = await db.execute(
        select(ClassAttendance).where(
            ClassAttendance.live_class_id == live_class.id,
            ClassAttendance.student_id == student_uid,
            ClassAttendance.is_removed == False,  # noqa: E712
        )
    )
    if existing.scalar_one_or_none():
        payload = _livekit_token_payload(
            live_class.room_id,
            current_user["sub"],
            current_user.get("email") or "student",
            can_publish=has_publish_access(live_class.room_id, current_user["sub"]),
        )
        return {
            **payload,
            "title": live_class.title,
            "subject": live_class.subject,
            "is_live": live_class.is_live,
            "end_time": live_class.end_time.isoformat() if live_class.end_time else None,
        }

    await consume_live_session(db, current_user["sub"])

    attendance = ClassAttendance(
        live_class_id=live_class.id,
        student_id=student_uid,
        is_muted=True,
    )
    db.add(attendance)
    await db.flush()

    payload = _livekit_token_payload(
        live_class.room_id,
        current_user["sub"],
        current_user.get("email") or "student",
        can_publish=False,
    )

    return {
        "class_id": str(live_class.id),
        "title": live_class.title,
        "subject": live_class.subject,
        **payload,
        "is_muted": True,
        "is_live": live_class.is_live,
        "end_time": live_class.end_time.isoformat() if live_class.end_time else None,
    }


@router.get("/{class_id}/token")
async def get_livekit_token(
    class_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get a fresh LiveKit token for a live class room."""
    result = await db.execute(select(LiveClass).where(LiveClass.id == class_id))
    live_class = result.scalar_one_or_none()
    if not live_class:
        raise HTTPException(status_code=404, detail="Class not found")

    is_teacher = (
        str(live_class.teacher_id) == current_user["sub"]
        or current_user.get("role") == "admin"
    )
    can_publish = is_teacher or has_publish_access(live_class.room_id, current_user["sub"])
    display = current_user.get("email") or current_user.get("sub") or "user"
    payload = _livekit_token_payload(
        live_class.room_id,
        current_user["sub"],
        display,
        can_publish=can_publish,
    )

    return {
        **payload,
        "uid": _user_uid(current_user["sub"]),
        "end_time": live_class.end_time.isoformat() if live_class.end_time else None,
        "is_live": live_class.is_live,
    }


@router.get("/{class_id}/students")
async def list_class_students(
    class_id: str,
    current_user: dict = Depends(require_teacher_or_admin),
    db: AsyncSession = Depends(get_db),
):
    """List students currently in (or who joined) a live class — for mic management."""
    class_uuid = parse_uuid(class_id)
    result = await db.execute(select(LiveClass).where(LiveClass.id == class_uuid))
    live_class = result.scalar_one_or_none()
    if not live_class:
        raise HTTPException(status_code=404, detail="Class not found")
    if not _can_manage_class(current_user, live_class):
        raise HTTPException(status_code=403, detail="Not your class")

    att_result = await db.execute(
        select(ClassAttendance).where(
            ClassAttendance.live_class_id == class_uuid,
            ClassAttendance.is_removed == False,  # noqa: E712
            ClassAttendance.left_at.is_(None),
        )
    )
    attendances = att_result.scalars().all()
    if not attendances:
        return []

    student_ids = [a.student_id for a in attendances]
    users_res = await db.execute(select(User).where(User.id.in_(student_ids)))
    users_map = {str(u.id): u for u in users_res.scalars().all()}

    out = []
    for att in attendances:
        sid = str(att.student_id)
        user = users_map.get(sid)
        mic_allowed = has_mic_access(live_class.room_id, sid)
        camera_allowed = has_camera_access(live_class.room_id, sid)
        out.append({
            "student_id": sid,
            "name": user.full_name if user else "Student",
            "email": user.email if user else "",
            "is_muted": bool(att.is_muted) and not mic_allowed,
            "mic_allowed": mic_allowed,
            "camera_allowed": camera_allowed,
            "joined_at": att.joined_at.isoformat() if att.joined_at else None,
        })
    out.sort(key=lambda x: x["name"].lower())
    return out


@router.post("/{class_id}/students/{student_id}/unmute")
async def unmute_student(
    class_id: str,
    student_id: str,
    current_user: dict = Depends(require_teacher_or_admin),
    db: AsyncSession = Depends(get_db),
):
    class_uuid = parse_uuid(class_id)
    student_uuid = parse_uuid(student_id)
    result = await db.execute(select(LiveClass).where(LiveClass.id == class_uuid))
    live_class = result.scalar_one_or_none()
    if not live_class:
        raise HTTPException(status_code=404, detail="Class not found")
    if not _can_manage_class(current_user, live_class):
        raise HTTPException(status_code=403, detail="Not your class")

    result = await db.execute(
        select(ClassAttendance).where(
            ClassAttendance.live_class_id == class_uuid,
            ClassAttendance.student_id == student_uuid,
            ClassAttendance.is_removed == False,  # noqa: E712
            ClassAttendance.left_at.is_(None),
        )
    )
    attendance = result.scalar_one_or_none()
    if not attendance:
        raise HTTPException(status_code=404, detail="Student not in class")
    attendance.is_muted = False
    grant_mic(live_class.room_id, str(student_id))
    try:
        await live_class_ws.notify_mic_granted(live_class.room_id, str(student_id))
    except Exception:
        pass
    return {"message": "Student can speak now", "mic_allowed": True}


@router.post("/{class_id}/students/{student_id}/mute")
async def mute_student(
    class_id: str,
    student_id: str,
    current_user: dict = Depends(require_teacher_or_admin),
    db: AsyncSession = Depends(get_db),
):
    class_uuid = parse_uuid(class_id)
    student_uuid = parse_uuid(student_id)
    result = await db.execute(select(LiveClass).where(LiveClass.id == class_uuid))
    live_class = result.scalar_one_or_none()
    if not live_class:
        raise HTTPException(status_code=404, detail="Class not found")
    if not _can_manage_class(current_user, live_class):
        raise HTTPException(status_code=403, detail="Not your class")

    result = await db.execute(
        select(ClassAttendance).where(
            ClassAttendance.live_class_id == class_uuid,
            ClassAttendance.student_id == student_uuid,
        )
    )
    attendance = result.scalar_one_or_none()
    if not attendance:
        raise HTTPException(status_code=404, detail="Student not in class")
    attendance.is_muted = True
    revoke_mic(live_class.room_id, str(student_id))
    try:
        await live_class_ws.notify_mic_revoked(live_class.room_id, str(student_id))
    except Exception:
        pass
    return {"message": "Student muted", "mic_allowed": False}


@router.post("/{class_id}/students/{student_id}/allow-camera")
async def allow_student_camera(
    class_id: str,
    student_id: str,
    current_user: dict = Depends(require_teacher_or_admin),
    db: AsyncSession = Depends(get_db),
):
    class_uuid = parse_uuid(class_id)
    student_uuid = parse_uuid(student_id)
    result = await db.execute(select(LiveClass).where(LiveClass.id == class_uuid))
    live_class = result.scalar_one_or_none()
    if not live_class:
        raise HTTPException(status_code=404, detail="Class not found")
    if not _can_manage_class(current_user, live_class):
        raise HTTPException(status_code=403, detail="Not your class")

    result = await db.execute(
        select(ClassAttendance).where(
            ClassAttendance.live_class_id == class_uuid,
            ClassAttendance.student_id == student_uuid,
            ClassAttendance.is_removed == False,  # noqa: E712
            ClassAttendance.left_at.is_(None),
        )
    )
    attendance = result.scalar_one_or_none()
    if not attendance:
        raise HTTPException(status_code=404, detail="Student not in class")
    grant_camera(live_class.room_id, str(student_id))
    try:
        await live_class_ws.notify_camera_granted(live_class.room_id, str(student_id))
    except Exception:
        pass
    return {"message": "Student can turn on camera", "camera_allowed": True}


@router.post("/{class_id}/students/{student_id}/revoke-camera")
async def revoke_student_camera(
    class_id: str,
    student_id: str,
    current_user: dict = Depends(require_teacher_or_admin),
    db: AsyncSession = Depends(get_db),
):
    class_uuid = parse_uuid(class_id)
    student_uuid = parse_uuid(student_id)
    result = await db.execute(select(LiveClass).where(LiveClass.id == class_uuid))
    live_class = result.scalar_one_or_none()
    if not live_class:
        raise HTTPException(status_code=404, detail="Class not found")
    if not _can_manage_class(current_user, live_class):
        raise HTTPException(status_code=403, detail="Not your class")

    revoke_camera(live_class.room_id, str(student_id))
    try:
        await live_class_ws.notify_camera_revoked(live_class.room_id, str(student_id))
    except Exception:
        pass
    return {"message": "Student camera access removed", "camera_allowed": False}


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
        # Live now OR within scheduled window (started but teacher has not tapped Start yet)
        query = query.where(
            or_(
                LiveClass.is_live == True,  # noqa: E712
                and_(
                    LiveClass.start_time <= now,
                    or_(LiveClass.end_time > now, LiveClass.end_time.is_(None)),
                ),
            )
        )
    elif status == "upcoming":
        query = query.where(
            LiveClass.is_live == False,  # noqa: E712
            LiveClass.start_time > now,
            or_(LiveClass.end_time > now, LiveClass.end_time.is_(None)),
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

    # Students: only classes matching profile subjects (e.g. Maths → Mathematics live)
    if role == "student":
        prof_res = await db.execute(
            select(StudentProfile).where(StudentProfile.user_id == current_user["sub"])
        )
        profile = prof_res.scalar_one_or_none()
        subjects = list(profile.selected_subjects or []) if profile else []
        if subjects:
            classes = [c for c in classes if subject_matches(c.subject, subjects)]
        else:
            classes = []

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


class AssignSessionRequest(BaseModel):
    teacher_id: str


def _request_dict(
    req: LiveSessionRequest,
    student_name: str = None,
    teacher_name: str = None,
) -> dict:
    return {
        "id": str(req.id),
        "student_id": str(req.student_id),
        "student_name": student_name,
        "subject": req.subject,
        "topic": req.topic,
        "message": req.message,
        "preferred_time": req.preferred_time,
        "status": req.status.value if hasattr(req.status, "value") else req.status,
        "assigned_teacher_id": str(req.assigned_teacher_id) if req.assigned_teacher_id else None,
        "assigned_teacher_name": teacher_name,
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

    student_res = await db.execute(select(User).where(User.id == req.student_id))
    student = student_res.scalar_one_or_none()
    student_label = student.full_name if student else "A student"
    try:
        await send_admins_notification(
            db,
            "New live class request",
            f"{student_label} requested help with {req.subject}"
            + (f" — {req.topic}" if req.topic else ""),
            "live_class_request",
            {"request_id": str(req.id), "subject": req.subject},
        )
    except Exception:
        pass

    return _request_dict(req, student.full_name if student else None)


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
    """Teachers see assigned requests; admins see all."""
    role = current_user.get("role")
    if role not in ("teacher", "admin"):
        raise HTTPException(status_code=403, detail="Teachers and admins only")

    query = select(LiveSessionRequest).order_by(LiveSessionRequest.created_at.desc()).limit(limit)
    if role == "teacher":
        try:
            tid = parse_uuid(current_user["sub"])
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid user id")
        query = query.where(LiveSessionRequest.assigned_teacher_id == tid)
    if status:
        query = query.where(LiveSessionRequest.status == status)
    if subject:
        query = query.where(LiveSessionRequest.subject.ilike(f"%{subject}%"))

    result = await db.execute(query)
    requests = result.scalars().all()

    student_ids = list({str(r.student_id) for r in requests})
    teacher_ids = list({str(r.assigned_teacher_id) for r in requests if r.assigned_teacher_id})
    user_ids = list(set(student_ids + teacher_ids))
    users_res = await db.execute(select(User).where(User.id.in_(user_ids))) if user_ids else None
    names_map = {}
    if users_res:
        names_map = {str(u.id): u.full_name for u in users_res.scalars().all()}

    return [
        _request_dict(
            r,
            names_map.get(str(r.student_id)),
            names_map.get(str(r.assigned_teacher_id)) if r.assigned_teacher_id else None,
        )
        for r in requests
    ]


@router.post("/requests/{request_id}/assign")
async def assign_session_request(
    request_id: str,
    payload: AssignSessionRequest,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin assigns a student session request to a teacher."""
    result = await db.execute(select(LiveSessionRequest).where(LiveSessionRequest.id == request_id))
    req = result.scalar_one_or_none()
    if not req:
        raise HTTPException(status_code=404, detail="Request not found")

    try:
        teacher_uuid = parse_uuid(payload.teacher_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid teacher id")

    teacher_res = await db.execute(
        select(User).where(User.id == teacher_uuid, User.role == UserRole.teacher)
    )
    teacher = teacher_res.scalar_one_or_none()
    if not teacher:
        raise HTTPException(status_code=404, detail="Teacher not found")

    req.assigned_teacher_id = teacher_uuid
    req.status = LiveSessionRequestStatus.approved
    req.reviewed_by = current_user["sub"]
    req.reviewed_at = naive_utc_now()
    await db.flush()

    student_res = await db.execute(select(User).where(User.id == req.student_id))
    student = student_res.scalar_one_or_none()
    student_name = student.full_name if student else "Student"

    try:
        await send_user_notification(
            db,
            str(teacher.id),
            "New student assigned to you",
            f"{student_name} — {req.subject}"
            + (f" ({req.topic})" if req.topic else "")
            + ". Open My Students to host their class.",
            "live_class_request",
            {"request_id": str(req.id), "student_id": str(req.student_id), "subject": req.subject},
        )
        await send_user_notification(
            db,
            str(req.student_id),
            "Teacher assigned",
            f"{teacher.full_name} will host your {req.subject} session. You'll be notified when they go live.",
            "live_class_request",
            {"request_id": str(req.id), "teacher_id": str(teacher.id)},
        )
    except Exception:
        pass

    return _request_dict(req, student_name, teacher.full_name)


@router.patch("/requests/{request_id}")
async def update_session_request(
    request_id: str,
    payload: UpdateSessionRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Admin updates request status. Teachers cannot approve unassigned requests."""
    role = current_user.get("role")
    if role not in ("teacher", "admin"):
        raise HTTPException(status_code=403, detail="Teachers and admins only")

    result = await db.execute(select(LiveSessionRequest).where(LiveSessionRequest.id == request_id))
    req = result.scalar_one_or_none()
    if not req:
        raise HTTPException(status_code=404, detail="Request not found")

    if role == "teacher":
        if not req.assigned_teacher_id or str(req.assigned_teacher_id) != current_user["sub"]:
            raise HTTPException(status_code=403, detail="Not assigned to you")
        if payload.status in (LiveSessionRequestStatus.approved, LiveSessionRequestStatus.dismissed):
            raise HTTPException(status_code=403, detail="Only admin can approve or dismiss requests")

    req.status = payload.status
    req.reviewed_by = current_user["sub"]
    req.reviewed_at = naive_utc_now()
    if payload.linked_class_id:
        req.linked_class_id = payload.linked_class_id
    await db.flush()

    student_res = await db.execute(select(User).where(User.id == req.student_id))
    student = student_res.scalar_one_or_none()
    teacher_name = None
    if req.assigned_teacher_id:
        t_res = await db.execute(select(User).where(User.id == req.assigned_teacher_id))
        t = t_res.scalar_one_or_none()
        teacher_name = t.full_name if t else None
    return _request_dict(req, student.full_name if student else None, teacher_name)


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

    try:
        await send_subject_notification(
            db,
            live_class.subject,
            title="Live class ended",
            body=f"{live_class.title} has ended.",
            notification_type="live_class",
            data={"class_id": str(live_class.id), "event": "class_ended"},
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
