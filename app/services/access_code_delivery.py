"""Deliver per-class join codes to eligible students (Access Code tab)."""
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.live_class import LiveClass, LiveClassVisibility
from app.models.live_class_access_code import LiveClassAccessCodeDelivery
from app.models.school_group import SchoolGroup
from app.models.user import User, StudentProfile
from app.core.subjects import subject_matches


def _parse_id_list(raw: str | None) -> list[str]:
    if not raw:
        return []
    import json
    try:
        data = json.loads(raw)
        return [str(x) for x in data] if isinstance(data, list) else []
    except (json.JSONDecodeError, TypeError):
        return []


def _class_visibility(live_class: LiveClass) -> str:
    v = getattr(live_class, "visibility", None)
    return v.value if hasattr(v, "value") else str(v or LiveClassVisibility.subject.value)


async def _recipient_ids(db: AsyncSession, live_class: LiveClass) -> list[str]:
    vis = _class_visibility(live_class)
    if vis == LiveClassVisibility.private.value:
        return _parse_id_list(live_class.invited_student_ids)
    if vis == LiveClassVisibility.school_group.value and live_class.school_group_id:
        group_res = await db.execute(select(SchoolGroup).where(SchoolGroup.id == live_class.school_group_id))
        group = group_res.scalar_one_or_none()
        return group.member_ids() if group else []

    # Public: platform-wide — deliver the code to every student.
    if vis == LiveClassVisibility.public.value:
        res = await db.execute(select(StudentProfile))
        return [str(p.user_id) for p in res.scalars().all()]

    # Subject / legacy: only students who selected this subject.
    res = await db.execute(select(StudentProfile))
    out = []
    for profile in res.scalars().all():
        subs = list(profile.selected_subjects or [])
        if not subs:
            continue
        if subject_matches(live_class.subject, subs):
            out.append(str(profile.user_id))
    return out


async def deliver_access_codes_for_class(
    db: AsyncSession,
    live_class: LiveClass,
    teacher_name: str = "Teacher",
    *,
    live_now: bool = True,
) -> None:
    if not live_class.join_code:
        import secrets
        live_class.join_code = f"SX-{secrets.token_hex(4).upper()}"

    recipients = await _recipient_ids(db, live_class)
    vis = _class_visibility(live_class)
    code = live_class.join_code

    for sid in recipients:
        try:
            student_uuid = __import__("uuid").UUID(sid)
        except ValueError:
            continue
        existing = await db.execute(
            select(LiveClassAccessCodeDelivery).where(
                LiveClassAccessCodeDelivery.student_id == student_uuid,
                LiveClassAccessCodeDelivery.live_class_id == live_class.id,
            )
        )
        row = existing.scalar_one_or_none()
        if row:
            row.join_code = code
            row.title = live_class.title
            row.subject = live_class.subject
            row.teacher_name = teacher_name
            row.visibility = vis
            row.is_read = False
        else:
            db.add(
                LiveClassAccessCodeDelivery(
                    student_id=student_uuid,
                    live_class_id=live_class.id,
                    join_code=code,
                    title=live_class.title,
                    subject=live_class.subject,
                    teacher_name=teacher_name,
                    visibility=vis,
                )
            )
