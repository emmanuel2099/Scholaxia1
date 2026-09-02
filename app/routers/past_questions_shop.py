"""
Public Past Questions shop — browse and buy PDFs without a student account.
"""
from __future__ import annotations

import secrets
import uuid
from datetime import timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.datetime_utils import naive_utc_now
from app.models.content import Book, LibraryTarget, PastQuestionGuestAccess
from app.services.media_service import fetch_book_bytes

router = APIRouter(prefix="/past-questions", tags=["Past Questions Shop"])

PAST_CATEGORY = "Past Questions"


def _is_past_question_book(book: Book) -> bool:
    cat = (getattr(book, "category", "") or "").strip().lower()
    return "past" in cat


def _public_card(book: Book) -> dict:
    return {
        "id": str(book.id),
        "title": book.title,
        "subject": book.subject,
        "exam_type": book.exam_type or "ALL",
        "year": getattr(book, "year", None),
        "description": book.description,
        "cover_image_url": book.cover_image_url,
        "price": float(getattr(book, "price", 0) or 0),
        "is_free": bool(getattr(book, "is_free", False)),
        "currency": "NGN",
        "category": getattr(book, "category", PAST_CATEGORY) or PAST_CATEGORY,
    }


@router.get("/catalog")
async def past_questions_catalog(
    exam_type: Optional[str] = None,
    subject: Optional[str] = None,
    year: Optional[int] = None,
    q: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
):
    """Public catalog — no login required. Never returns PDF URLs."""
    query = select(Book).where(
        Book.is_active.is_(True),
        Book.library_target == LibraryTarget.student,
        or_(
            Book.category.ilike("%past%"),
            Book.category == PAST_CATEGORY,
        ),
    )
    if exam_type and exam_type.upper() not in {"ALL", ""}:
        query = query.where(Book.exam_type.ilike(exam_type.strip()))
    if subject:
        query = query.where(Book.subject.ilike(subject.strip()))
    if year:
        query = query.where(Book.year == year)
    if q:
        term = f"%{q.strip()}%"
        query = query.where(
            or_(
                Book.title.ilike(term),
                Book.subject.ilike(term),
                Book.description.ilike(term),
                Book.exam_type.ilike(term),
            )
        )
    query = query.order_by(Book.exam_type, Book.subject, Book.year.desc().nullslast(), Book.title)
    books = (await db.execute(query)).scalars().all()
    return {
        "products": [_public_card(b) for b in books],
        "filters": {
            "exam_types": ["ALL", "JAMB", "WAEC", "NECO", "COMMON_ENTRANCE"],
        },
    }


@router.get("/products/{book_id}")
async def past_questions_product(
    book_id: str,
    db: AsyncSession = Depends(get_db),
):
    book = (
        await db.execute(select(Book).where(Book.id == book_id, Book.is_active.is_(True)))
    ).scalar_one_or_none()
    if not book or not _is_past_question_book(book):
        raise HTTPException(status_code=404, detail="Past question product not found")
    data = _public_card(book)
    data["locked"] = True
    data["message"] = "Pay to unlock the PDF. No student account required."
    return data


class GuestAccessLookup(BaseModel):
    email: EmailStr
    book_id: str


@router.post("/access/lookup")
async def lookup_guest_access(
    payload: GuestAccessLookup,
    db: AsyncSession = Depends(get_db),
):
    """Return existing guest access token after a prior successful purchase."""
    rows = (
        await db.execute(
            select(PastQuestionGuestAccess).where(
                PastQuestionGuestAccess.email == payload.email.strip().lower(),
                PastQuestionGuestAccess.book_id == uuid.UUID(str(payload.book_id)),
            )
        )
    ).scalars().all()
    if not rows:
        raise HTTPException(status_code=404, detail="No purchase found for this email and product")
    access = rows[-1]
    return {
        "access_token": access.access_token,
        "download_path": f"/api/v1/past-questions/download/{access.access_token}",
        "email": access.email,
        "book_id": str(access.book_id),
    }


@router.get("/download/{access_token}")
async def download_past_question_pdf(
    access_token: str,
    db: AsyncSession = Depends(get_db),
):
    """Stream PDF only when guest access token is valid (post-payment)."""
    token = (access_token or "").strip()
    if not token:
        raise HTTPException(status_code=404, detail="Invalid access token")
    access = (
        await db.execute(
            select(PastQuestionGuestAccess).where(PastQuestionGuestAccess.access_token == token)
        )
    ).scalar_one_or_none()
    if not access:
        raise HTTPException(status_code=404, detail="Access not found — payment may still be pending")
    if access.expires_at and access.expires_at < naive_utc_now():
        raise HTTPException(status_code=410, detail="Access link expired")

    book = (
        await db.execute(select(Book).where(Book.id == access.book_id, Book.is_active.is_(True)))
    ).scalar_one_or_none()
    if not book or not book.file_key:
        raise HTTPException(status_code=404, detail="PDF file not available")

    try:
        content, content_type = fetch_book_bytes(book.file_key)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Could not fetch PDF: {exc}") from exc

    filename = f"{(book.title or 'past-question').replace(' ', '_')[:80]}.pdf"
    return Response(
        content=content,
        media_type=content_type or "application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Cache-Control": "no-store",
        },
    )


def new_guest_access_token() -> str:
    return secrets.token_urlsafe(32)


async def grant_guest_past_question_access(
    db: AsyncSession,
    *,
    book_id: uuid.UUID,
    email: str,
    payment_id: uuid.UUID | None,
    payment_reference: str | None,
) -> PastQuestionGuestAccess:
    email_norm = (email or "").strip().lower()
    existing = (
        await db.execute(
            select(PastQuestionGuestAccess).where(
                PastQuestionGuestAccess.book_id == book_id,
                PastQuestionGuestAccess.email == email_norm,
                PastQuestionGuestAccess.payment_reference == payment_reference,
            )
        )
    ).scalar_one_or_none()
    if existing:
        return existing

    access = PastQuestionGuestAccess(
        book_id=book_id,
        email=email_norm,
        access_token=new_guest_access_token(),
        payment_id=payment_id,
        payment_reference=payment_reference,
        created_at=naive_utc_now(),
        expires_at=naive_utc_now() + timedelta(days=365),
    )
    db.add(access)
    await db.flush()
    return access
