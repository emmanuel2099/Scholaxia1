"""
Background scheduler for live classes:
- Auto-start when start_time is reached
- Auto-end when end_time is reached
- Notify students and broadcast WebSocket events
"""
import asyncio
from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.core.datetime_utils import naive_utc_now
from app.models.live_class import LiveClass, ClassAttendance
from app.services.notification_service import send_subject_notification
from app.websockets.live_class_ws import broadcast as ws_broadcast

_scheduler_task = None


async def run_live_class_scheduler():
    while True:
        try:
            await _tick()
        except Exception as exc:
            print(f"[live_class_scheduler] tick error: {exc}")
        await asyncio.sleep(60)


async def _tick():
    now = naive_utc_now()
    async with AsyncSessionLocal() as db:
        # ── Auto-start scheduled classes ─────────────────────────────────────
        start_res = await db.execute(
            select(LiveClass).where(
                LiveClass.is_live == False,  # noqa: E712
                LiveClass.start_time <= now,
                (LiveClass.end_time.is_(None)) | (LiveClass.end_time > now),
            )
        )
        for live_class in start_res.scalars().all():
            live_class.is_live = True
            try:
                await send_subject_notification(
                    db=db,
                    subject=live_class.subject,
                    title="Live class starting now",
                    body=f"Your {live_class.subject} class \"{live_class.title}\" is live — join now.",
                    notification_type="live_class",
                    data={
                        "class_id": str(live_class.id),
                        "room_id": live_class.room_id,
                    },
                )
            except Exception:
                pass
            try:
                await ws_broadcast(
                    live_class.room_id,
                    {
                        "event": "class_started",
                        "class_id": str(live_class.id),
                        "title": live_class.title,
                        "subject": live_class.subject,
                    },
                )
            except Exception:
                pass
            print(f"[live_class_scheduler] auto-started class {live_class.id}")

        # ── Auto-end classes at scheduled end_time ───────────────────────────
        end_res = await db.execute(
            select(LiveClass).where(
                LiveClass.is_live == True,  # noqa: E712
                LiveClass.end_time.isnot(None),
                LiveClass.end_time <= now,
            )
        )
        for live_class in end_res.scalars().all():
            live_class.is_live = False
            att_res = await db.execute(
                select(ClassAttendance).where(
                    ClassAttendance.live_class_id == live_class.id,
                    ClassAttendance.left_at.is_(None),
                )
            )
            for att in att_res.scalars().all():
                att.left_at = now
            try:
                await ws_broadcast(
                    live_class.room_id,
                    {
                        "event": "class_ended",
                        "class_id": str(live_class.id),
                        "message": "Class ended at the scheduled time.",
                    },
                )
            except Exception:
                pass
            print(f"[live_class_scheduler] auto-ended class {live_class.id}")

        await db.commit()


def start_live_class_scheduler():
    global _scheduler_task
    if _scheduler_task is not None:
        return
    _scheduler_task = asyncio.create_task(run_live_class_scheduler())
