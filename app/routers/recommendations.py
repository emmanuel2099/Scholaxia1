"""
Recommendations Router
----------------------
Admin posts book recommendations — students and teachers see them in their feed.

Admin endpoints:
  POST   /api/v1/recommendations          — create a recommendation
  GET    /api/v1/recommendations          — list all (admin view, includes inactive)
  PATCH  /api/v1/recommendations/{id}     — edit a recommendation
  DELETE /api/v1/recommendations/{id}     — soft-delete

Student / Teacher endpoints:
  GET    /api/v1/recommendations/feed     — personalised recommendations for the caller
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

from app.core.database import get_db
from app.core.deps import require_admin, get_current_user
from app.models.content import BookRecommendation, RecommendationTarget, Book

router = APIRouter(prefix="/recommendations", tags=["Recommendations"])


# ── Schemas ───────────────────────────────────────────────────────────────────

class CreateRecommendationRequest(BaseModel):
    title: str
    author: Optional[str] = None
    subject: Optional[str] = None
    description: Optional[str] = None
    cover_image_url: Optional[str] = None
    # Link to an existing library book (optional)
    book_id: Optional[str] = None
    # Or an external URL (e.g. Amazon, PDF link)
    external_url: Optional[str] = None
    target: RecommendationTarget = RecommendationTarget.all
    exam_type: Optional[str] = None        # JAMB | WAEC | NECO | ALL
    education_level: Optional[str] = None  # SS1 | SS2 | SS3 | JAMB


class UpdateRecommendationRequest(BaseModel):
    title: Optional[str] = None
    author: Optional[str] = None
    subject: Optional[str] = None
    description: Optional[str] = None
    cover_image_url: Optional[str] = None
    book_id: Optional[str] = None
    external_url: Optional[str] = None
    target: Optional[RecommendationTarget] = None
    exam_type: Optional[str] = None
    education_level: Optional[str] = None
    is_active: Optional[bool] = None


def _rec_dict(r: BookRecommendation) -> dict:
    return {
        "id": str(r.id),
        "title": r.title,
        "author": r.author,
        "subject": r.subject,
        "description": r.description,
        "cover_image_url": r.cover_image_url,
        "book_id": str(r.book_id) if r.book_id else None,
        "external_url": r.external_url,
        "target": r.target,
        "exam_type": r.exam_type,
        "education_level": r.education_level,
        "is_active": r.is_active,
        "created_at": r.created_at,
        "updated_at": r.updated_at,
    }


# ── Admin: Create ─────────────────────────────────────────────────────────────

@router.post("", status_code=201)
async def create_recommendation(
    payload: CreateRecommendationRequest,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Admin creates a book recommendation.
    - Set book_id to link to an existing library book (shows a 'Read Now' button).
    - Set external_url for books outside the library (Amazon, PDF link, etc.).
    - Both can be set together — library book takes priority in the app.
    """
    # Validate book_id if provided
    if payload.book_id:
        res = await db.execute(select(Book).where(Book.id == payload.book_id, Book.is_active == True))  # noqa: E712
        if not res.scalar_one_or_none():
            raise HTTPException(status_code=404, detail="Book not found in library")

    rec = BookRecommendation(
        title=payload.title,
        author=payload.author,
        subject=payload.subject,
        description=payload.description,
        cover_image_url=payload.cover_image_url,
        book_id=payload.book_id,
        external_url=payload.external_url,
        target=payload.target,
        exam_type=payload.exam_type,
        education_level=payload.education_level,
        created_by=current_user["sub"],
    )
    db.add(rec)
    await db.flush()
    return _rec_dict(rec)


# ── Admin: List all ───────────────────────────────────────────────────────────

@router.get("/admin")
async def admin_list_recommendations(
    target: Optional[RecommendationTarget] = None,
    subject: Optional[str] = None,
    exam_type: Optional[str] = None,
    active_only: bool = False,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin sees all recommendations including inactive ones."""
    query = select(BookRecommendation).order_by(BookRecommendation.created_at.desc())
    if target:
        query = query.where(BookRecommendation.target == target)
    if subject:
        query = query.where(BookRecommendation.subject == subject)
    if exam_type:
        query = query.where(BookRecommendation.exam_type == exam_type)
    if active_only:
        query = query.where(BookRecommendation.is_active == True)  # noqa: E712

    result = await db.execute(query)
    return [_rec_dict(r) for r in result.scalars().all()]


# ── Admin: Edit ───────────────────────────────────────────────────────────────

@router.patch("/{rec_id}")
async def update_recommendation(
    rec_id: str,
    payload: UpdateRecommendationRequest,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Admin edits any field of an existing recommendation."""
    result = await db.execute(
        select(BookRecommendation).where(BookRecommendation.id == rec_id)
    )
    rec = result.scalar_one_or_none()
    if not rec:
        raise HTTPException(status_code=404, detail="Recommendation not found")

    if payload.book_id is not None:
        if payload.book_id:
            res = await db.execute(select(Book).where(Book.id == payload.book_id, Book.is_active == True))  # noqa: E712
            if not res.scalar_one_or_none():
                raise HTTPException(status_code=404, detail="Book not found in library")
        rec.book_id = payload.book_id or None

    for field in ("title", "author", "subject", "description", "cover_image_url",
                  "external_url", "target", "exam_type", "education_level", "is_active"):
        val = getattr(payload, field)
        if val is not None:
            setattr(rec, field, val)

    rec.updated_at = datetime.utcnow()
    await db.flush()
    return _rec_dict(rec)


# ── Admin: Delete (soft) ──────────────────────────────────────────────────────

@router.delete("/{rec_id}", status_code=204)
async def delete_recommendation(
    rec_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Soft-delete: sets is_active=False so it disappears from student/teacher feed."""
    result = await db.execute(
        select(BookRecommendation).where(BookRecommendation.id == rec_id)
    )
    rec = result.scalar_one_or_none()
    if not rec:
        raise HTTPException(status_code=404, detail="Recommendation not found")
    rec.is_active = False


# ── Student / Teacher: Feed ───────────────────────────────────────────────────

@router.get("/feed")
async def get_recommendation_feed(
    subject: Optional[str] = None,
    exam_type: Optional[str] = None,
    limit: int = 20,
    offset: int = 0,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    GET /api/v1/recommendations/feed
    Returns active recommendations visible to the current user based on their role.
    - Students see: target='all' or target='student'
    - Teachers see: target='all' or target='teacher'
    Optional filters: subject, exam_type
    """
    role = current_user.get("role")

    if role == "student":
        targets = [RecommendationTarget.all, RecommendationTarget.student]
    elif role == "teacher":
        targets = [RecommendationTarget.all, RecommendationTarget.teacher]
    else:
        # admin sees everything
        targets = list(RecommendationTarget)

    query = (
        select(BookRecommendation)
        .where(
            BookRecommendation.is_active == True,  # noqa: E712
            BookRecommendation.target.in_(targets),
        )
        .order_by(BookRecommendation.created_at.desc())
        .limit(limit)
        .offset(offset)
    )

    if subject:
        query = query.where(BookRecommendation.subject == subject)
    if exam_type:
        query = query.where(BookRecommendation.exam_type == exam_type)

    result = await db.execute(query)
    recs = result.scalars().all()

    # For recs linked to a library book, include a flag so frontend knows
    # to show a 'Read in Library' button instead of just the external link
    out = []
    for r in recs:
        d = _rec_dict(r)
        d["has_library_book"] = r.book_id is not None
        out.append(d)

    return out
