from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from pydantic import BaseModel
from typing import Optional
from app.core.database import get_db
from app.core.deps import get_current_user
from app.services.live_class_access import parse_uuid
from app.models.notification import Notification, DeviceToken, NotificationType

router = APIRouter(prefix="/notifications", tags=["Notifications"])


class RegisterTokenRequest(BaseModel):
    token: str
    platform: str  # ios | android | web


@router.get("/")
async def get_notifications(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Notification)
        .where(Notification.user_id == current_user["sub"])
        .order_by(Notification.created_at.desc())
        .limit(50)
    )
    notifications = result.scalars().all()
    return [
        {
            "id": str(n.id),
            "type": n.type,
            "title": n.title,
            "body": n.body,
            "is_read": n.is_read,
            "created_at": n.created_at,
            "data": n.data,
        }
        for n in notifications
    ]


@router.post("/read-all")
async def mark_all_read(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await db.execute(
        update(Notification)
        .where(Notification.user_id == current_user["sub"], Notification.is_read == False)
        .values(is_read=True)
    )
    return {"message": "All notifications marked as read"}


class MarkTypesReadRequest(BaseModel):
    types: Optional[list[str]] = None


@router.post("/mark-types-read")
async def mark_types_read(
    payload: MarkTypesReadRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Mark unread notifications of given types as read (e.g. community after opening a group)."""
    type_names = payload.types or ["community_mention", "announcement"]
    allowed = {t.value for t in NotificationType}
    valid = [t for t in type_names if t in allowed]
    if not valid:
        return {"message": "No valid types", "marked": 0}
    enum_types = [NotificationType(t) for t in valid]
    result = await db.execute(
        update(Notification)
        .where(
            Notification.user_id == current_user["sub"],
            Notification.is_read == False,  # noqa: E712
            Notification.type.in_(enum_types),
        )
        .values(is_read=True)
    )
    return {"message": "Marked as read", "marked": result.rowcount or 0}


@router.post("/{notification_id}/read")
async def mark_notification_read(
    notification_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Mark a single notification as read (updates badge counter)."""
    nid = parse_uuid(notification_id)
    uid = parse_uuid(current_user["sub"])
    result = await db.execute(
        select(Notification).where(Notification.id == nid, Notification.user_id == uid)
    )
    row = result.scalar_one_or_none()
    if not row:
        raise HTTPException(status_code=404, detail="Notification not found")
    row.is_read = True
    await db.flush()
    return {"message": "Marked as read", "id": str(row.id)}


@router.post("/device-token")
async def register_device_token(
    payload: RegisterTokenRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(DeviceToken).where(DeviceToken.token == payload.token))
    existing = result.scalar_one_or_none()
    if existing:
        existing.user_id = current_user["sub"]
        existing.platform = payload.platform
    else:
        token = DeviceToken(user_id=current_user["sub"], token=payload.token, platform=payload.platform)
        db.add(token)
    return {"message": "Device token registered"}
