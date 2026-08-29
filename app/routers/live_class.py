import uuid
import hashlib
import json
import secrets
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_, and_
from pydantic import BaseModel
from datetime import datetime, timezone, timedelta
from typing import Optional
from app.core.database import get_db
from app.core.datetime_utils import naive_utc_now, to_naive_utc
from app.core.deps import require_teacher, require_teacher_or_admin, require_student_or_kind, get_current_user, require_admin
from app.core.config import settings
from app.models.live_class import LiveClass, ClassAttendance, LiveSessionRequest, LiveSessionRequestStatus, LiveClassVisibility
from app.models.school_group import SchoolGroup
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
    get_board_replay_messages,
    room_board_state,
)
from app.websockets import live_class_ws
from app.services.live_class_access import get_live_access_info, parse_uuid, consume_live_session, live_class_requires_subscription, is_free_live_class
from app.services.notification_service import send_subject_notification, send_user_notification, send_admins_notification, send_all_students_notification
from app.services.access_code_delivery import deliver_access_codes_for_class
from app.models.live_class_access_code import LiveClassAccessCodeDelivery

router = APIRouter(prefix="/live-classes", tags=["Live Classes"])


@router.get("/board-sync/{room_id}")
async def board_sync_state(
    room_id: str,
    current_user: dict = Depends(get_current_user),
):
    """HTTP fallback so students always catch board state even if WebSocket hiccups."""
    rid = str(room_id or "").strip()
    if not rid:
        raise HTTPException(status_code=400, detail="room_id required")
    state = room_board_state.get(rid) or {}
    return {
        "open": bool(state.get("open")),
        "messages": get_board_replay_messages(rid),
    }


@router.get("/livekit/status")
async def livekit_video_status():
    """Public health check â€” does not expose secrets, only whether LiveKit is configured."""
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
async def agora_video_status():
    """Deprecated alias â€” use /livekit/status."""
    return await livekit_video_status()


@router.get("/join-preview")
async def join_preview(
    code: Optional[str] = Query(None, description="Meet-style join code, e.g. SX-A1B2C3D4"),
    class_id: Optional[str] = Query(None, description="Live class UUID"),
    db: AsyncSession = Depends(get_db),
):
    """Public preview for shareable join links (no login required)."""
    token = (code or class_id or "").strip()
    if not token:
        raise HTTPException(status_code=400, detail="Provide a join code or class id")

    live_class = None
    if class_id:
        try:
            cid = parse_uuid(class_id)
        except ValueError:
            raise HTTPException(status_code=404, detail="Class not found")
        result = await db.execute(select(LiveClass).where(LiveClass.id == cid))
        live_class = result.scalar_one_or_none()
    else:
        normalized = token.upper()
        result = await db.execute(select(LiveClass).where(LiveClass.join_code == normalized))
        live_class = result.scalar_one_or_none()
        if not live_class:
            try:
                cid = parse_uuid(token)
                result = await db.execute(select(LiveClass).where(LiveClass.id == cid))
                live_class = result.scalar_one_or_none()
            except ValueError:
                pass

    if not live_class:
        raise HTTPException(status_code=404, detail="Class not found. Check the link or code from your teacher.")

    if not live_class.join_code:
        live_class.join_code = f"SX-{secrets.token_hex(4).upper()}"
        await db.flush()

    teacher_name = "Teacher"
    try:
        user_res = await db.execute(select(User).where(User.id == live_class.teacher_id))
        teacher = user_res.scalar_one_or_none()
        if teacher and teacher.full_name:
            teacher_name = teacher.full_name
    except Exception:
        pass

    now = naive_utc_now()
    joinable = _class_is_active(live_class, now)
    vis = live_class.visibility or LiveClassVisibility.subject.value
    free = is_free_live_class(vis)
    return {
        "id": str(live_class.id),
        "title": live_class.title,
        "subject": live_class.subject,
        "teacher_name": teacher_name,
        "is_live": bool(live_class.is_live),
        "is_joinable": joinable,
        "join_code": live_class.join_code,
        "visibility": vis,
        "requires_payment": not free,
        "need_plan": not free,
        "is_free": free,
        "start_time": live_class.start_time.isoformat() if live_class.start_time else None,
        "end_time": live_class.end_time.isoformat() if live_class.end_time else None,
    }


class JoinByCodeRequest(BaseModel):
    code: str


@router.get("/access-codes/mine")
async def my_access_codes(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Access codes delivered to this student (Access Code tab)."""
    try:
        sid = parse_uuid(current_user["sub"])
        now = naive_utc_now()
        try:
            await _heal_stale_live_flags(db, now)
        except Exception:
            pass
        result = await db.execute(
            select(LiveClassAccessCodeDelivery, LiveClass)
            .join(LiveClass, LiveClass.id == LiveClassAccessCodeDelivery.live_class_id)
            .where(LiveClassAccessCodeDelivery.student_id == sid)
            .order_by(LiveClassAccessCodeDelivery.created_at.desc())
            .limit(100)
        )
        codes = []
        unread = 0
        for row, live_class in result.all():
            live_flag = bool(live_class.is_live) and _class_is_active(live_class, now)
            if not live_flag:
                continue
            entry = {
                "id": str(row.id),
                "class_id": str(row.live_class_id),
                "join_code": row.join_code,
                "title": row.title,
                "subject": row.subject,
                "teacher_name": row.teacher_name,
                "visibility": row.visibility,
                "is_read": row.is_read,
                "is_used": row.is_used,
                "is_class_live": True,
                "created_at": row.created_at.isoformat() if row.created_at else None,
            }
            codes.append(entry)
            if not row.is_read:
                unread += 1
        return {"unread_count": unread, "codes": codes}
    except Exception as exc:
        import logging
        logging.getLogger(__name__).exception("my_access_codes failed: %s", exc)
        try:
            await db.rollback()
        except Exception:
            pass
        # Empty list beats a broken Access Codes panel — join still works from Live cards.
        return {"unread_count": 0, "codes": [], "warning": str(exc)}


@router.post("/access-codes/mark-read")
async def mark_access_codes_read(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sid = parse_uuid(current_user["sub"])
    result = await db.execute(
        select(LiveClassAccessCodeDelivery).where(
            LiveClassAccessCodeDelivery.student_id == sid,
            LiveClassAccessCodeDelivery.is_read == False,  # noqa: E712
        )
    )
    for row in result.scalars().all():
        row.is_read = True
    await db.flush()
    return {"message": "Marked as read"}


class ClearAccessCodesRequest(BaseModel):
    mode: str = "old"  # old = used or class ended; all = remove every code


@router.post("/access-codes/clear")
async def clear_access_codes(
    payload: ClearAccessCodesRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Remove old or all access code entries from the student's Access Code tab."""
    sid = parse_uuid(current_user["sub"])
    result = await db.execute(
        select(LiveClassAccessCodeDelivery, LiveClass)
        .join(LiveClass, LiveClass.id == LiveClassAccessCodeDelivery.live_class_id)
        .where(LiveClassAccessCodeDelivery.student_id == sid)
    )
    rows = result.all()
    removed = 0
    now = naive_utc_now()
    for delivery, live_class in rows:
        if payload.mode == "all":
            await db.delete(delivery)
            removed += 1
            continue
        ended = live_class.end_time is not None and live_class.end_time < now
        if delivery.is_used or ended:
            await db.delete(delivery)
            removed += 1
    await db.flush()
    return {"message": "Access codes cleared", "removed": removed}


@router.post("/join-by-code")
async def join_class_by_code(
    payload: JoinByCodeRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Join a live class using the unique access code for that class."""
    normalized = (payload.code or "").strip().upper()
    if not normalized:
        raise HTTPException(status_code=400, detail="Enter the access code from your Access Code tab.")

    # Normalize SX-XXXX / spaced digits so students can paste flexibly
    compact = normalized.replace(" ", "").replace("-", "")
    result = await db.execute(select(LiveClass).where(LiveClass.join_code == normalized))
    live_class = result.scalar_one_or_none()
    if not live_class and compact != normalized:
        result = await db.execute(
            select(LiveClass).where(LiveClass.join_code == compact)
        )
        live_class = result.scalar_one_or_none()
    if not live_class:
        # Try matching SX- prefix variants
        result = await db.execute(
            select(LiveClass).where(LiveClass.join_code.ilike(f"%{compact[-8:]}"))
        )
        candidates = result.scalars().all()
        if len(candidates) == 1:
            live_class = candidates[0]
    if not live_class:
        raise HTTPException(status_code=404, detail="Invalid or expired class code.")

    sid = parse_uuid(current_user["sub"])
    delivery = await db.execute(
        select(LiveClassAccessCodeDelivery).where(
            LiveClassAccessCodeDelivery.student_id == sid,
            LiveClassAccessCodeDelivery.live_class_id == live_class.id,
        )
    )
    delivery_row = delivery.scalar_one_or_none()

    now = naive_utc_now()
    status = _session_status(live_class, now)
    if status == "ENDED":
        raise HTTPException(status_code=410, detail="This class has ended.")
    if status == "SCHEDULED" and not live_class.is_live:
        raise HTTPException(
            status_code=404,
            detail="Your teacher has not started this class yet.",
        )

    prof_res = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == current_user["sub"])
    )
    profile = prof_res.scalar_one_or_none()
    can_access, detail = await _student_can_access_class(
        db, current_user["sub"], live_class, profile
    )
    # Private class access code IS the invite — student joins free (no subscription).
    if not can_access and _class_visibility(live_class) == LiveClassVisibility.private.value:
        can_access, detail = True, ""
        try:
            invited = _parse_id_list(live_class.invited_student_ids)
            uid = str(current_user["sub"])
            if uid not in invited:
                invited.append(uid)
                live_class.invited_student_ids = json.dumps(invited)
        except Exception:
            pass
    if not can_access:
        raise HTTPException(status_code=403, detail=detail)

    if not _class_is_active(live_class, now):
        if status == "ENDED":
            raise HTTPException(status_code=410, detail="This class has ended.")
        raise HTTPException(
            status_code=404,
            detail="Your teacher has not started this class yet.",
        )

    if delivery_row:
        delivery_row.is_read = True
        delivery_row.is_used = True
    elif _class_visibility(live_class) in (
        LiveClassVisibility.public.value,
        LiveClassVisibility.private.value,
    ):
        db.add(
            LiveClassAccessCodeDelivery(
                student_id=sid,
                live_class_id=live_class.id,
                join_code=live_class.join_code,
                title=live_class.title,
                subject=live_class.subject,
                teacher_name="Teacher",
                visibility=_class_visibility(live_class),
                is_read=True,
                is_used=True,
            )
        )

    return await join_class(str(live_class.id), current_user, db)


# â”€â”€ LiveKit token helper â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
    role: str = "student",
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
        # Clients use metadata.role to pin the teacher on the main stage.
        role_norm = str(role or "student").strip().lower().replace("userrole.", "")
        try:
            token.with_metadata(json.dumps({"role": role_norm or "student"}))
        except Exception:
            pass
        token.with_ttl(timedelta(hours=6))
        grants_kw = {
            "room_join": True,
            "room": room_name,
            "can_publish": bool(can_publish),
            "can_subscribe": True,
            "can_publish_data": True,
        }
        # Explicit sources so teacher screen share is never blocked by cloud defaults.
        if can_publish and role_norm in ("teacher", "admin", "host"):
            grants_kw["can_publish_sources"] = [
                "camera",
                "microphone",
                "screen_share",
                "screen_share_audio",
            ]
        token.with_grants(VideoGrants(**grants_kw))
        return token.to_jwt()
    except Exception:
        return f"TOKEN_ERROR_{room_name}"


def _livekit_token_payload(
    room_id: str,
    user_id: str,
    display_name: str,
    can_publish: bool,
    role: str = "student",
) -> dict:
    identity = str(user_id)
    token = _generate_livekit_token(
        room_id, identity, display_name, can_publish, role=role
    )
    expires_at = (datetime.now(timezone.utc) + timedelta(hours=6)).isoformat()
    return {
        "room_id": room_id,
        "channel_id": room_id,
        "livekit_token": token,
        "livekit_url": settings.LIVEKIT_URL,
        "token": token,
        "identity": identity,
        "can_publish": can_publish,
        "role": role,
        "expires_at": expires_at,
    }


def _user_uid(user_id: str) -> int:
    """Legacy numeric UID (kept for older clients)."""
    return int(hashlib.md5(user_id.encode()).hexdigest()[:8], 16) % (2**31)


def _can_manage_class(current_user: dict, live_class: LiveClass) -> bool:
    role = str(current_user.get("role") or "").strip().lower().replace("userrole.", "")
    if role == "admin":
        return True
    return str(live_class.teacher_id) == str(current_user.get("sub") or "")


async def _active_attendance(
    db: AsyncSession,
    live_class_id,
    student_id: str,
) -> ClassAttendance | None:
    try:
        cid = live_class_id if not isinstance(live_class_id, str) else parse_uuid(live_class_id)
        sid = parse_uuid(student_id)
    except ValueError:
        return None
    result = await db.execute(
        select(ClassAttendance).where(
            ClassAttendance.live_class_id == cid,
            ClassAttendance.student_id == sid,
            ClassAttendance.is_removed == False,  # noqa: E712
            ClassAttendance.left_at.is_(None),
        )
    )
    return result.scalar_one_or_none()


async def _ensure_attendance_for_unmute(
    db: AsyncSession,
    live_class_id,
    student_uuid,
) -> ClassAttendance:
    """Find or create attendance so unmute always works for students in class."""
    att = await _active_attendance(db, live_class_id, str(student_uuid))
    if att:
        return att
    cid = live_class_id if not isinstance(live_class_id, str) else parse_uuid(live_class_id)
    result = await db.execute(
        select(ClassAttendance).where(
            ClassAttendance.live_class_id == cid,
            ClassAttendance.student_id == student_uuid,
            ClassAttendance.is_removed == False,  # noqa: E712
        ).order_by(ClassAttendance.joined_at.desc())
    )
    att = result.scalar_one_or_none()
    if att:
        att.left_at = None
        att.is_muted = False
        return att
    att = ClassAttendance(
        live_class_id=cid,
        student_id=student_uuid,
        is_muted=False,
    )
    db.add(att)
    await db.flush()
    return att


def _mic_allowed_for(room_id: str, student_id: str, attendance: ClassAttendance | None) -> bool:
    if has_mic_access(room_id, student_id):
        return True
    # Open mic for anyone actively in class unless teacher muted them.
    return attendance is not None and not bool(attendance.is_muted)


def _camera_allowed_for(
    room_id: str,
    student_id: str,
    attendance: ClassAttendance | None = None,
) -> bool:
    if has_camera_access(room_id, student_id):
        return True
    # Joined students may publish camera by default (same as mic), unless muted.
    return attendance is not None and not attendance.is_muted


def _can_publish_for_student(
    room_id: str,
    student_id: str,
    attendance: ClassAttendance | None,
) -> bool:
    if has_publish_access(room_id, student_id):
        return True
    return _mic_allowed_for(room_id, student_id, attendance) or _camera_allowed_for(
        room_id, student_id, attendance
    )


def _class_is_active(live_class: LiveClass, now: datetime) -> bool:
    """True when class is live or within its scheduled window."""
    # Past scheduled end must never stay joinable / ringable, even if is_live stuck true.
    if live_class.end_time and live_class.end_time <= now:
        return False
    if live_class.is_live:
        return True
    if live_class.start_time and live_class.start_time <= now:
        if live_class.end_time is None or live_class.end_time > now:
            return True
    return False


def _session_status(live_class: LiveClass, now: datetime | None = None) -> str:
    """SCHEDULED | LOBBY | LIVE | ENDED — derived from existing columns."""
    from app.services.live_class_room import derive_session_status

    now = now or naive_utc_now()
    return derive_session_status(
        is_live=bool(live_class.is_live),
        start_time=live_class.start_time,
        end_time=live_class.end_time,
        now=now,
    )


async def _heal_stale_live_flags(db: AsyncSession, now: datetime | None = None) -> None:
    """Best-effort clear of stuck is_live rows (savepoint — never poisons list SELECT)."""
    from sqlalchemy import text as sql_text

    now = now or naive_utc_now()
    try:
        async with db.begin_nested():
            await db.execute(
                sql_text(
                    """
                    UPDATE live_classes
                    SET is_live = FALSE,
                        end_time = COALESCE(end_time, :now)
                    WHERE COALESCE(is_live, false) = true
                      AND (
                        (end_time IS NOT NULL AND end_time <= :now)
                        OR (start_time IS NOT NULL AND start_time <= :cutoff)
                      )
                    """
                ),
                {"now": now, "cutoff": now - timedelta(hours=4)},
            )
    except Exception:
        return


def _parse_id_list(raw: str | None) -> list[str]:
    if not raw:
        return []
    try:
        data = json.loads(raw)
        return [str(x) for x in data] if isinstance(data, list) else []
    except (json.JSONDecodeError, TypeError):
        return []


def _class_visibility(live_class: LiveClass) -> str:
    return (live_class.visibility or LiveClassVisibility.subject.value).lower()


async def _student_can_access_class(
    db: AsyncSession,
    student_id: str,
    live_class: LiveClass,
    profile: StudentProfile | None,
) -> tuple[bool, str]:
    vis = _class_visibility(live_class)
    if vis == LiveClassVisibility.public.value:
        return True, ""
    if vis == LiveClassVisibility.private.value:
        invited = _parse_id_list(live_class.invited_student_ids)
        if student_id in invited:
            return True, ""
        return False, "This is a private class. You were not invited."
    if vis == LiveClassVisibility.class_level.value:
        want = (live_class.academic_class or "").replace(" ", "").upper()
        have = (profile.education_level if profile else "") or ""
        have = have.replace(" ", "").upper()
        if want and have and (want == have or have.startswith(want) or want.startswith(have)):
            return True, ""
        return False, "This live class is only for " + (live_class.academic_class or "that class") + "."
    if vis == LiveClassVisibility.school_group.value:
        if not live_class.school_group_id:
            return False, "School group not configured for this class."
        group_res = await db.execute(
            select(SchoolGroup).where(SchoolGroup.id == live_class.school_group_id)
        )
        group = group_res.scalar_one_or_none()
        if not group:
            return False, "School group not found."
        if student_id in group.member_ids():
            return True, ""
        return False, "This class is only for students in the school group."
    subjects = list(profile.selected_subjects or []) if profile else []
    if not subjects:
        return False, "Add your subjects in profile setup to join live classes."
    if not subject_matches(live_class.subject, subjects):
        return False, "This live class is not for one of your selected subjects."
    return True, ""


async def _notify_for_class(
    db: AsyncSession,
    live_class: LiveClass,
    *,
    live_now: bool,
    start: datetime | None = None,
    end: datetime | None = None,
) -> None:
    vis = _class_visibility(live_class)
    data = {
        "class_id": str(live_class.id),
        "room_id": live_class.room_id,
        "join_code": live_class.join_code,
        "visibility": vis,
    }
    try:
        teacher_res = await db.execute(select(User).where(User.id == live_class.teacher_id))
        teacher_user = teacher_res.scalar_one_or_none()
        teacher_name = teacher_user.full_name if teacher_user else "Teacher"
        await deliver_access_codes_for_class(
            db, live_class, teacher_name, live_now=live_now
        )
        if vis == LiveClassVisibility.public.value:
            # Public = platform-wide: notify every student.
            if live_now:
                await send_all_students_notification(
                    db=db,
                    title="Live class starting now",
                    body=f"Â«{live_class.title}Â» is live â€” copy your code from the app popup.",
                    notification_type="live_class",
                    data=data,
                )
            else:
                when = (start or live_class.start_time).strftime("%d %b %Y at %I:%M %p")
                await send_all_students_notification(
                    db=db,
                    title="Upcoming platform live class",
                    body=f"Â«{live_class.title}Â» is scheduled for {when}.",
                    notification_type="live_class",
                    data={**data, "start_time": (start or live_class.start_time).isoformat()},
                )
        elif vis == LiveClassVisibility.private.value:
            title = "Private live class starting now" if live_now else "Private live class scheduled"
            body_live = f"Â«{live_class.title}Â» â€” code {live_class.join_code} is in your Access Code tab."
            body_up = f"Â«{live_class.title}Â» is scheduled. Only invited students can join."
            for sid in _parse_id_list(live_class.invited_student_ids):
                await send_user_notification(db, sid, title, body_live if live_now else body_up, "live_class", data)
        elif vis == LiveClassVisibility.school_group.value and live_class.school_group_id:
            group_res = await db.execute(
                select(SchoolGroup).where(SchoolGroup.id == live_class.school_group_id)
            )
            group = group_res.scalar_one_or_none()
            if group:
                title = f"{group.school_name} â€” class is live" if live_now else f"{group.name} â€” upcoming class"
                body = (
                    f"Â«{live_class.title}Â» is live â€” code {live_class.join_code} in Access Code tab."
                    if live_now
                    else f"Â«{live_class.title}Â» scheduled for {group.name}."
                )
                for sid in group.member_ids():
                    await send_user_notification(db, sid, title, body, "live_class", data)
        else:
            if live_now:
                await send_subject_notification(
                    db=db,
                    subject=live_class.subject,
                    title="Live class starting now",
                    body=f"Your {live_class.subject} class Â«{live_class.title}Â» is live. Join from your dashboard.",
                    notification_type="live_class",
                    data=data,
                )
            else:
                when = (start or live_class.start_time).strftime("%d %b %Y at %I:%M %p")
                await send_subject_notification(
                    db=db,
                    subject=live_class.subject,
                    title=f"Upcoming {live_class.subject} class",
                    body=f"Â«{live_class.title}Â» is scheduled for {when}.",
                    notification_type="live_class_upcoming",
                    data={
                        **data,
                        "start_time": (start or live_class.start_time).isoformat(),
                        "end_time": end.isoformat() if end else None,
                    },
                )
    except Exception:
        pass


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
                f"Â«{live_class.title}Â» ({live_class.subject}) â€” join from Live Class.",
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
    visibility: Optional[str] = "public"
    invited_student_ids: Optional[list[str]] = None
    invited_student_emails: Optional[list[str]] = None
    school_group_id: Optional[str] = None
    academic_class: Optional[str] = None


class ClassResponse(BaseModel):
    id: str
    subject: str
    title: str
    teacher_id: str
    start_time: datetime
    is_live: bool
    room_id: str
    visibility: str = "public"
    join_code: Optional[str] = None
    school_group_id: Optional[str] = None


@router.post("/", response_model=ClassResponse)
async def create_class(
    payload: CreateClassRequest,
    current_user: dict = Depends(require_teacher_or_admin),
    db: AsyncSession = Depends(get_db),
):
    room_id = f"room-{uuid.uuid4().hex[:12]}"
    join_code = f"SX-{secrets.token_hex(4).upper()}"
    now = naive_utc_now()
    duration = max(15, min(payload.duration_minutes or 60, 180))

    vis = (payload.visibility or LiveClassVisibility.public.value).lower()
    if vis not in {v.value for v in LiveClassVisibility}:
        vis = LiveClassVisibility.public.value

    invited_ids: list[str] = [str(x).strip() for x in (payload.invited_student_ids or []) if str(x).strip()]
    unresolved_emails: list[str] = []
    if vis == LiveClassVisibility.private.value:
        # Resolve any emails supplied by the teacher into student ids.
        seen = set(invited_ids)
        for raw in (payload.invited_student_emails or []):
            email = str(raw).strip().lower()
            if not email:
                continue
            res = await db.execute(
                select(User).where(
                    User.email == email,
                    User.role == UserRole.student,
                    User.is_active == True,  # noqa: E712
                )
            )
            user = res.scalar_one_or_none()
            if user and str(user.id) not in seen:
                invited_ids.append(str(user.id))
                seen.add(str(user.id))
            elif not user:
                unresolved_emails.append(email)
        if unresolved_emails:
            raise HTTPException(
                status_code=400,
                detail="No student found for: " + ", ".join(unresolved_emails),
            )

    if vis == LiveClassVisibility.private.value and not invited_ids:
        raise HTTPException(status_code=400, detail="Select at least one student for a private class.")
    if vis == LiveClassVisibility.school_group.value and not payload.school_group_id:
        raise HTTPException(status_code=400, detail="Select a school group for this class.")

    school_group_uuid = None
    if vis == LiveClassVisibility.school_group.value:
        school_group_uuid = parse_uuid(payload.school_group_id)
        group_res = await db.execute(select(SchoolGroup).where(SchoolGroup.id == school_group_uuid))
        group = group_res.scalar_one_or_none()
        if not group or str(group.teacher_id) != current_user["sub"]:
            raise HTTPException(status_code=403, detail="Invalid school group")

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
        join_code=join_code,
        visibility=vis,
        invited_student_ids=json.dumps(invited_ids) if vis == LiveClassVisibility.private.value else None,
        school_group_id=school_group_uuid,
        academic_class=(payload.academic_class or "").strip().upper() or None,
        is_live=is_live,
    )
    db.add(live_class)
    await db.flush()

    try:
        await _notify_for_class(db, live_class, live_now=is_live, start=start, end=end)
        if is_live:
            await _notify_assigned_students_for_class(db, current_user["sub"], live_class)
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
        visibility=live_class.visibility,
        join_code=live_class.join_code,
        school_group_id=str(live_class.school_group_id) if live_class.school_group_id else None,
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

    try:
        from app.services.live_class_room import set_room_meta

        set_room_meta(
            str(live_class.room_id or ""),
            classId=str(live_class.id),
            sessionStatus="LIVE",
        )
    except Exception:
        pass

    if not was_live:
        await _notify_for_class(db, live_class, live_now=True)
        await _notify_assigned_students_for_class(db, str(live_class.teacher_id), live_class)
    # Open mics for everyone already in the room so teacher â†” students hear each other.
    att_res = await db.execute(
        select(ClassAttendance).where(
            ClassAttendance.live_class_id == live_class.id,
            ClassAttendance.is_removed == False,  # noqa: E712
            ClassAttendance.left_at.is_(None),
        )
    )
    for att in att_res.scalars().all():
        att.is_muted = False
        try:
            from app.services.live_class_room import grant_mic, grant_camera
            grant_mic(live_class.room_id, str(att.student_id))
            grant_camera(live_class.room_id, str(att.student_id))
        except Exception:
            pass
    await db.flush()
    return {"message": "Class started", "room_id": live_class.room_id, "is_live": True, "join_code": live_class.join_code}


@router.post("/{class_id}/join")
async def join_class(
    class_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Join a live class and return LiveKit credentials.

    Keep DB work minimal and always rollback after a failed SQL statement so the
    async session is never left aborted (that caused greenlet_spawn / xd2s).
    """
    import logging
    import uuid as uuid_lib
    from sqlalchemy import text as sql_text

    log = logging.getLogger(__name__)

    async def _safe_rollback():
        try:
            await db.rollback()
        except Exception:
            pass

    try:
        class_uuid = parse_uuid(class_id)
        student_uid = parse_uuid(current_user["sub"])
        sid = str(student_uid)

        result = await db.execute(select(LiveClass).where(LiveClass.id == class_uuid))
        live_class = result.scalar_one_or_none()
        now = naive_utc_now()
        if not live_class or not _class_is_active(live_class, now):
            raise HTTPException(status_code=404, detail="Class not live")

        # Snapshot immediately — never read ORM attrs after a rollback
        room_id = str(live_class.room_id or "")
        title = live_class.title or "Live class"
        subject = live_class.subject or ""
        teacher_id = str(live_class.teacher_id)
        visibility = _class_visibility(live_class)
        is_live = bool(live_class.is_live)
        end_time_iso = live_class.end_time.isoformat() if live_class.end_time else None
        invited_raw = live_class.invited_student_ids
        school_group_id = str(live_class.school_group_id) if live_class.school_group_id else None

        if visibility == LiveClassVisibility.private.value:
            invited = _parse_id_list(invited_raw)
            if sid not in invited:
                raise HTTPException(status_code=403, detail="This is a private class. You were not invited.")
        elif visibility == LiveClassVisibility.school_group.value and school_group_id:
            try:
                group_res = await db.execute(
                    select(SchoolGroup).where(SchoolGroup.id == parse_uuid(school_group_id))
                )
                group = group_res.scalar_one_or_none()
                members = group.member_ids() if group else []
                if sid not in members:
                    raise HTTPException(
                        status_code=403,
                        detail="This class is only for students in the school group.",
                    )
            except HTTPException:
                raise
            except Exception as gexc:
                log.warning("school group check skipped: %s", gexc)

        if not is_live:
            # Do not resurrect a class that already has an end_time in the past
            if end_time_iso:
                try:
                    from datetime import datetime as _dt
                    et = _dt.fromisoformat(str(end_time_iso).replace("Z", ""))
                    if et <= now:
                        raise HTTPException(status_code=404, detail="Class has ended")
                except HTTPException:
                    raise
                except Exception:
                    pass
            try:
                await db.execute(
                    sql_text(
                        "UPDATE live_classes SET is_live = TRUE WHERE id = :cid "
                        "AND COALESCE(is_live, false) = false "
                        "AND (end_time IS NULL OR end_time > NOW())"
                    ),
                    {"cid": str(class_uuid)},
                )
                await db.flush()
                is_live = True
            except Exception:
                await _safe_rollback()
                is_live = True

        # Live board cards are joinable without a plan (matches Join now UX).
        requires_plan = (
            (not is_live)
            and live_class_requires_subscription(visibility)
            and not is_free_live_class(visibility)
        )
        if requires_plan:
            try:
                access = await get_live_access_info(db, sid, class_id)
            except Exception as access_exc:
                log.warning("live access check failed: %s", access_exc)
                await _safe_rollback()
                access = {"can_join": True}
            if not access.get("can_join"):
                if access.get("active_plan") and access.get("sessions_left", 0) <= 0:
                    raise HTTPException(
                        status_code=402,
                        detail="You have used all live sessions on your plan this month. Upgrade or renew your plan.",
                    )
                raise HTTPException(
                    status_code=402,
                    detail="Choose a Scholaxia One-on-One Live Class plan before joining.",
                )

        teacher_name = "Teacher"
        try:
            from app.models.user import User

            teacher_res = await db.execute(select(User).where(User.id == parse_uuid(teacher_id)))
            teacher_user = teacher_res.scalar_one_or_none()
            if teacher_user and teacher_user.full_name:
                teacher_name = str(teacher_user.full_name)
        except Exception:
            await _safe_rollback()
        teacher_meta = {"teacher_id": teacher_id, "teacher_name": teacher_name}

        # Best-effort attendance — never block the LiveKit token
        att_id = str(uuid_lib.uuid4())
        try:
            existing = (
                await db.execute(
                    sql_text(
                        """
                        SELECT id::text FROM class_attendances
                        WHERE live_class_id = CAST(:cid AS uuid) AND student_id = CAST(:sid AS uuid)
                        ORDER BY joined_at DESC NULLS LAST
                        LIMIT 1
                        """
                    ),
                    {"cid": str(class_uuid), "sid": sid},
                )
            ).first()
            if existing:
                await db.execute(
                    sql_text(
                        """
                        UPDATE class_attendances
                        SET left_at = NULL
                        WHERE id = CAST(:aid AS uuid)
                        """
                    ),
                    {"aid": str(existing[0])},
                )
                await db.flush()
            else:
                await db.execute(
                    sql_text(
                        """
                        INSERT INTO class_attendances (id, live_class_id, student_id, joined_at, is_muted)
                        VALUES (CAST(:aid AS uuid), CAST(:cid AS uuid), CAST(:sid AS uuid), NOW(), FALSE)
                        """
                    ),
                    {"aid": att_id, "cid": str(class_uuid), "sid": sid},
                )
                await db.flush()
        except Exception as att_exc:
            log.warning("attendance write skipped: %s", att_exc)
            await _safe_rollback()

        try:
            from app.services.live_class_room import grant_mic, grant_camera, set_room_meta, upsert_participant

            grant_mic(room_id, sid)
            grant_camera(room_id, sid)
            set_room_meta(
                room_id,
                classId=str(class_uuid),
                sessionStatus="LIVE" if is_live else "LOBBY",
            )
            upsert_participant(
                room_id,
                sid,
                role="student",
                name=current_user.get("email") or "Student",
            )
        except Exception:
            pass

        if not room_id:
            raise HTTPException(
                status_code=500,
                detail="This class has no room id. Ask the teacher to restart it.",
            )

        payload = _livekit_token_payload(
            room_id,
            sid,
            current_user.get("email") or "student",
            can_publish=True,
            role="student",
        )
        return {
            "class_id": str(class_uuid),
            "title": title,
            "subject": subject,
            **teacher_meta,
            **payload,
            "is_muted": False,
            "is_live": is_live,
            "session_status": "LIVE" if is_live else "LOBBY",
            "end_time": end_time_iso,
            "mic_allowed": True,
            "camera_allowed": True,
        }
    except HTTPException:
        raise
    except Exception as exc:
        log.exception("join_class failed: %s", exc)
        await _safe_rollback()
        short = str(exc).split("(Background")[0].strip()[:180]
        raise HTTPException(
            status_code=500,
            detail=f"Could not join live class: {short}",
        ) from exc


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
    uid = current_user["sub"]
    att = None if is_teacher else await _active_attendance(db, live_class.id, uid)
    # Keep publish rights open for active students unless teacher muted them.
    if att is not None and not att.is_muted:
        try:
            from app.services.live_class_room import grant_mic, grant_camera
            grant_mic(live_class.room_id, uid)
            grant_camera(live_class.room_id, uid)
        except Exception:
            pass
    can_publish = is_teacher or _can_publish_for_student(live_class.room_id, uid, att)
    display = current_user.get("email") or current_user.get("sub") or "user"
    payload = _livekit_token_payload(
        live_class.room_id,
        uid,
        display,
        can_publish=can_publish,
        role="teacher" if is_teacher else "student",
    )
    mic_ok = is_teacher or _mic_allowed_for(live_class.room_id, uid, att)
    cam_ok = is_teacher or _camera_allowed_for(live_class.room_id, uid, att)

    return {
        **payload,
        "uid": _user_uid(uid),
        "teacher_id": str(live_class.teacher_id),
        "end_time": live_class.end_time.isoformat() if live_class.end_time else None,
        "is_live": live_class.is_live,
        "mic_allowed": mic_ok,
        "camera_allowed": cam_ok,
        "can_publish": can_publish,
    }


@router.get("/{class_id}/presence")
async def class_presence(
    class_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Who is in this live class right now (HTTP fallback when chat WS is slow).
    Available to the teacher and any student with active attendance.
    """
    class_uuid = parse_uuid(class_id)
    result = await db.execute(select(LiveClass).where(LiveClass.id == class_uuid))
    live_class = result.scalar_one_or_none()
    if not live_class:
        raise HTTPException(status_code=404, detail="Class not found")

    uid = current_user["sub"]
    is_teacher = (
        str(live_class.teacher_id) == uid
        or current_user.get("role") == "admin"
    )
    att = None if is_teacher else await _active_attendance(db, live_class.id, uid)
    if not is_teacher and att is None:
        raise HTTPException(status_code=403, detail="Join the class first")

    att_result = await db.execute(
        select(ClassAttendance).where(
            ClassAttendance.live_class_id == class_uuid,
            ClassAttendance.is_removed == False,  # noqa: E712
            ClassAttendance.left_at.is_(None),
        )
    )
    attendances = att_result.scalars().all()
    student_ids = [a.student_id for a in attendances]
    users_map: dict = {}
    if student_ids:
        users_res = await db.execute(select(User).where(User.id.in_(student_ids)))
        users_map = {str(u.id): u for u in users_res.scalars().all()}

    teacher_res = await db.execute(select(User).where(User.id == live_class.teacher_id))
    teacher = teacher_res.scalar_one_or_none()

    students = []
    for row in attendances:
        sid = str(row.student_id)
        user = users_map.get(sid)
        students.append({
            "student_id": sid,
            "name": user.full_name if user else "Student",
            "mic_allowed": _mic_allowed_for(live_class.room_id, sid, row),
            "camera_allowed": _camera_allowed_for(live_class.room_id, sid, row),
            "is_teacher": False,
        })
    students.sort(key=lambda x: (x["name"] or "").lower())

    return {
        "class_id": str(live_class.id),
        "room_id": live_class.room_id,
        "is_live": bool(live_class.is_live),
        "session_status": _session_status(live_class),
        "teacher_id": str(live_class.teacher_id),
        "teacher_name": teacher.full_name if teacher else "Teacher",
        "active_attendees": len(students),
        "students": students,
    }


@router.get("/{class_id}/students")
async def list_class_students(
    class_id: str,
    current_user: dict = Depends(require_teacher_or_admin),
    db: AsyncSession = Depends(get_db),
):
    """List students currently in (or who joined) a live class â€” for mic management."""
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
        mic_allowed = _mic_allowed_for(live_class.room_id, sid, att)
        camera_allowed = _camera_allowed_for(live_class.room_id, sid, att)
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


@router.get("/{class_id}/attendance")
async def class_attendance(
    class_id: str,
    current_user: dict = Depends(require_teacher_or_admin),
    db: AsyncSession = Depends(get_db),
):
    """Attendance log for a class (join times, leave times)."""
    class_uuid = parse_uuid(class_id)
    result = await db.execute(select(LiveClass).where(LiveClass.id == class_uuid))
    live_class = result.scalar_one_or_none()
    if not live_class:
        raise HTTPException(status_code=404, detail="Class not found")
    if not _can_manage_class(current_user, live_class):
        raise HTTPException(status_code=403, detail="Not your class")

    att_result = await db.execute(
        select(ClassAttendance).where(ClassAttendance.live_class_id == class_uuid)
        .order_by(ClassAttendance.joined_at.asc())
    )
    attendances = att_result.scalars().all()
    student_ids = [a.student_id for a in attendances]
    users_map: dict[str, User] = {}
    if student_ids:
        users_res = await db.execute(select(User).where(User.id.in_(student_ids)))
        users_map = {str(u.id): u for u in users_res.scalars().all()}

    return {
        "class_id": str(live_class.id),
        "title": live_class.title,
        "total_joined": len(attendances),
        "records": [
            {
                "student_id": str(att.student_id),
                "name": users_map.get(str(att.student_id)).full_name if users_map.get(str(att.student_id)) else "Student",
                "joined_at": att.joined_at.isoformat() if att.joined_at else None,
                "left_at": att.left_at.isoformat() if att.left_at else None,
                "is_removed": bool(att.is_removed),
            }
            for att in attendances
        ],
    }


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
        attendance = await _ensure_attendance_for_unmute(db, class_uuid, student_uuid)
    attendance.is_muted = False
    attendance.left_at = None
    grant_mic(live_class.room_id, str(student_uuid))
    await db.flush()
    try:
        await live_class_ws.notify_mic_granted(live_class.room_id, str(student_uuid))
    except Exception:
        pass
    return {"message": "Student can speak now", "mic_allowed": True, "student_id": str(student_uuid)}


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


# â”€â”€ Session Listing Endpoints â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
    - status=live      â†’ only currently live classes
    - status=upcoming  â†’ scheduled in the future, not yet live
    - status=past      â†’ already ended (is_live=False and end_time is set)
    - omit status      â†’ all classes
    """
    now = naive_utc_now()
    # Never let heal block listing — coerce flags in the response either way.
    try:
        await _heal_stale_live_flags(db, now)
    except Exception:
        pass
    query = select(LiveClass)

    if subject:
        query = query.where(LiveClass.subject == subject)

    if status == "live":
        query = query.where(LiveClass.is_live == True)  # noqa: E712
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
    role = str(current_user.get("role") or "").strip().lower().replace("userrole.", "")
    if role == "teacher":
        try:
            query = query.where(LiveClass.teacher_id == parse_uuid(current_user["sub"]))
        except Exception:
            query = query.where(LiveClass.teacher_id == current_user["sub"])

    query = query.order_by(LiveClass.start_time.desc()).limit(limit).offset(offset)
    try:
        result = await db.execute(query)
        classes = result.scalars().all()
    except Exception:
        import logging
        logging.getLogger(__name__).exception("list_live_classes query failed")
        return []

    # Students: filter by visibility / access rules
    if role == "student":
        try:
            prof_res = await db.execute(
                select(StudentProfile).where(StudentProfile.user_id == current_user["sub"])
            )
            profile = prof_res.scalar_one_or_none()
            visible = []
            for c in classes:
                try:
                    ok, _ = await _student_can_access_class(db, current_user["sub"], c, profile)
                    if ok:
                        visible.append(c)
                except Exception:
                    # Never fail the whole Live Now list because one class check blew up
                    if is_free_live_class(getattr(c, "visibility", None)):
                        visible.append(c)
            classes = visible
        except Exception:
            classes = [
                c for c in classes
                if is_free_live_class(getattr(c, "visibility", None))
            ]
    elif role == "kind":
        classes = [
            c for c in classes
            if _class_visibility(c) == LiveClassVisibility.public.value
        ]

    # Fetch teacher names (parse UUIDs — string IN() can miss rows on Postgres)
    teacher_ids = list({str(c.teacher_id) for c in classes if c.teacher_id})
    teachers_map = {}
    if teacher_ids:
        from app.models.user import User
        try:
            teacher_uuids = []
            for tid in teacher_ids:
                try:
                    teacher_uuids.append(parse_uuid(tid))
                except Exception:
                    pass
            if teacher_uuids:
                users_res = await db.execute(
                    select(User).where(User.id.in_(teacher_uuids))
                )
                teachers_map = {
                    str(u.id): (u.full_name or "Teacher") for u in users_res.scalars().all()
                }
        except Exception:
            teachers_map = {}

    out = []
    for c in classes:
        # Coerce response only — DB heal is best-effort above (savepoint).
        live_flag = bool(c.is_live)
        stale_end = bool(c.end_time and c.end_time <= now)
        stale_long = bool(c.start_time and c.start_time <= (now - timedelta(hours=4)))
        if stale_end or stale_long:
            live_flag = False
        status_label = "live" if live_flag else (
            "past" if (c.end_time and c.end_time <= now) else "upcoming"
        )
        out.append({
            "id": str(c.id),
            "title": c.title,
            "subject": c.subject,
            "description": c.description,
            "teacher_id": str(c.teacher_id),
            "teacher_name": teachers_map.get(str(c.teacher_id), "Teacher"),
            "start_time": c.start_time.isoformat() + "Z" if c.start_time else None,
            "end_time": c.end_time.isoformat() + "Z" if c.end_time else None,
            "is_live": live_flag,
            "status": status_label,
            "room_id": c.room_id,
            "recording_url": c.recording_url,
            "created_at": c.created_at.isoformat() + "Z" if c.created_at else None,
            "visibility": c.visibility or LiveClassVisibility.subject.value,
            "join_code": c.join_code,
            "is_free": is_free_live_class(c.visibility),
            "requires_payment": not is_free_live_class(c.visibility),
            "school_group_id": str(c.school_group_id) if c.school_group_id else None,
        })
    return out


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
    current_user: dict = Depends(get_current_user),
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
            + (f" â€” {req.topic}" if req.topic else ""),
            "live_class_request",
            {"request_id": str(req.id), "subject": req.subject},
        )
    except Exception:
        pass

    return _request_dict(req, student.full_name if student else None)


@router.get("/requests/mine")
async def my_session_requests(
    current_user: dict = Depends(get_current_user),
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
            f"{student_name} â€” {req.subject}"
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
    """Admin or assigned teacher can approve/update session requests."""
    role = current_user.get("role")
    if role not in ("teacher", "admin"):
        raise HTTPException(status_code=403, detail="Teachers and admins only")

    result = await db.execute(select(LiveSessionRequest).where(LiveSessionRequest.id == request_id))
    req = result.scalar_one_or_none()
    if not req:
        raise HTTPException(status_code=404, detail="Request not found")

    if role == "teacher":
        # Teachers may approve/host for requests assigned to them â€” no admin gate.
        # They may also claim an unassigned request by approving it for themselves.
        if req.assigned_teacher_id and str(req.assigned_teacher_id) != current_user["sub"]:
            raise HTTPException(status_code=403, detail="Not assigned to you")
        if not req.assigned_teacher_id and payload.status == LiveSessionRequestStatus.approved:
            req.assigned_teacher_id = current_user["sub"]

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
    import logging
    from sqlalchemy import text as sql_text

    log = logging.getLogger(__name__)
    try:
        cid = parse_uuid(class_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid class id")

    result = await db.execute(select(LiveClass).where(LiveClass.id == cid))
    live_class = result.scalar_one_or_none()
    if not live_class:
        raise HTTPException(status_code=404, detail="Class not found")
    if not _can_manage_class(current_user, live_class):
        raise HTTPException(status_code=403, detail="Not your class")

    room_id = str(live_class.room_id or "")
    subject = live_class.subject or ""
    title = live_class.title or "Live class"
    ended_at = naive_utc_now()

    # Always mutate the loaded ORM row (guaranteed to persist on session commit).
    live_class.is_live = False
    live_class.end_time = ended_at
    if recording_url:
        live_class.recording_url = recording_url
    await db.flush()

    # Belt-and-suspenders SQL update (CAST so UUID bind never silently matches 0 rows).
    try:
        upd = await db.execute(
            sql_text(
                """
                UPDATE live_classes
                SET is_live = FALSE, end_time = :ended
                WHERE id = CAST(:cid AS uuid)
                """
            ),
            {"cid": str(cid), "ended": ended_at},
        )
        await db.flush()
        if getattr(upd, "rowcount", None) == 0:
            log.warning("end_class SQL matched 0 rows for %s", cid)
    except Exception as upd_exc:
        log.warning("end_class SQL update skipped: %s", upd_exc)

    try:
        await db.execute(
            sql_text(
                """
                UPDATE class_attendances
                SET left_at = :ended
                WHERE live_class_id = CAST(:cid AS uuid) AND left_at IS NULL
                """
            ),
            {"cid": str(cid), "ended": ended_at},
        )
        await db.flush()
    except Exception as att_exc:
        log.warning("end_class attendance update skipped: %s", att_exc)

    try:
        from sqlalchemy import delete as sql_delete

        await db.execute(
            sql_delete(LiveClassAccessCodeDelivery).where(
                LiveClassAccessCodeDelivery.live_class_id == cid
            )
        )
        await db.flush()
    except Exception as del_exc:
        log.warning("end_class access-code cleanup skipped: %s", del_exc)

    # Commit before refresh/notify so a later failure cannot roll back is_live=false
    try:
        await db.commit()
    except Exception as commit_exc:
        log.warning("end_class commit failed: %s", commit_exc)
        try:
            await db.rollback()
        except Exception:
            pass
        raise HTTPException(status_code=500, detail="Could not save class end state")

    try:
        result2 = await db.execute(select(LiveClass).where(LiveClass.id == cid))
        live_class = result2.scalar_one_or_none() or live_class
    except Exception:
        pass

    if live_class and live_class.is_live:
        try:
            live_class.is_live = False
            live_class.end_time = ended_at
            await db.flush()
            await db.commit()
        except Exception:
            pass

    try:
        from app.websockets.live_class_ws import broadcast as ws_broadcast

        if room_id:
            await ws_broadcast(
                room_id,
                {
                    "event": "class_ended",
                    "class_id": str(cid),
                    "message": "Class ended by the teacher.",
                },
            )
    except Exception:
        pass

    try:
        await send_subject_notification(
            db,
            subject,
            title="Live class ended",
            body=f"{title} has ended.",
            notification_type="live_class",
            data={"class_id": str(cid), "event": "class_ended"},
        )
    except Exception:
        pass

    return {
        "message": "Class ended",
        "class_id": str(cid),
        "is_live": bool(live_class.is_live),
        "end_time": live_class.end_time.isoformat() if live_class.end_time else ended_at.isoformat(),
    }


@router.post("/{class_id}/leave")
async def leave_class(
    class_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Student leaves a live class â€” records left_at time."""
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
