from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import require_admin, require_student_or_kind
from app.models.content import Video

router = APIRouter(tags=["Video tutorials"])


def _video_dict(row: Video) -> dict:
    return {
        "id": str(row.id),
        "title": row.title,
        "subject": row.subject,
        "exam_type": row.exam_type,
        "video_url": row.video_url,
        "thumbnail_url": row.thumbnail_url,
        "duration_seconds": row.duration_seconds,
        "created_at": row.created_at.isoformat() if row.created_at else None,
    }


class VideoCreate(BaseModel):
    title: str = Field(..., min_length=2, max_length=255)
    subject: str = "General"
    exam_type: Optional[str] = None
    video_url: str = Field(..., min_length=8, max_length=500)
    thumbnail_url: Optional[str] = None


@router.get("/videos")
async def list_videos(
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    rows = (
        await db.execute(select(Video).order_by(Video.created_at.desc()).limit(200))
    ).scalars().all()
    return {"videos": [_video_dict(r) for r in rows]}


@router.get("/admin/videos")
async def admin_list_videos(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    rows = (
        await db.execute(select(Video).order_by(Video.created_at.desc()).limit(200))
    ).scalars().all()
    return {"videos": [_video_dict(r) for r in rows]}


@router.post("/admin/videos", status_code=201)
async def create_video(
    payload: VideoCreate,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    url = payload.video_url.strip()
    if not url.startswith(("http://", "https://")):
        raise HTTPException(status_code=400, detail="video_url must be an http(s) link")
    row = Video(
        title=payload.title.strip(),
        subject=(payload.subject or "General").strip(),
        exam_type=payload.exam_type,
        video_url=url,
        thumbnail_url=payload.thumbnail_url,
        uploaded_by=current_user["sub"],
    )
    db.add(row)
    await db.flush()
    return _video_dict(row)


@router.delete("/admin/videos/{video_id}")
async def delete_video(
    video_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    row = (await db.execute(select(Video).where(Video.id == video_id))).scalar_one_or_none()
    if not row:
        raise HTTPException(status_code=404, detail="Video not found")
    await db.delete(row)
    await db.flush()
    return {"ok": True}
