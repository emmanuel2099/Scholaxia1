from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from pydantic import BaseModel
from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.notification import Notification, DeviceToken

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
