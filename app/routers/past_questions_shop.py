"""
Public Past Questions shop — browse and buy PDFs without a student account.
"""
from __future__ import annotations

import logging
import secrets
import uuid
from datetime import timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, EmailStr
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.datetime_utils import naive_utc_now
from app.models.content import Book, PastQuestionGuestAccess
from app.services.media_service import fetch_book_bytes

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/past-questions", tags=["Past Questions Shop"])

PAST_CATEGORY = "Past Questions"


def _is_past_question_book(book: Book) -> bool:
    cat = (getattr(book, "category", "") or "").strip().lower()
    return "past" in cat


def _public_card(book: Book) -> dict:
    year = getattr(book, "year", None)
    try:
        year = int(year) if year is not None else None
    except (TypeError, ValueError):
        year = None
    return {
        "id": str(book.id),
        "title": book.title,
        "subject": book.subject,
        "exam_type": (book.exam_type or "ALL"),
        "year": year,
        "description": book.description,
        "cover_image_url": book.cover_image_url,
        "price": float(getattr(book, "price", 0) or 0),
        "is_free": bool(getattr(book, "is_free", False)),
        "currency": "NGN",
        "category": getattr(book, "category", PAST_CATEGORY) or PAST_CATEGORY,
    }


def _matches_filters(card: dict, exam_type: Optional[str], subject: Optional[str], year: Optional[int], q: Optional[str]) -> bool:
    if exam_type and exam_type.upper() not in {"ALL", ""}:
        if str(card.get("exam_type") or "").upper() != exam_type.strip().upper():
            return False
    if subject and str(card.get("subject") or "").lower() != subject.strip().lower():
        return False
    if year is not None and card.get("year") != year:
        return False
    if q:
        hay = " ".join(
            str(card.get(k) or "")
            for k in ("title", "subject", "exam_type", "year", "description")
        ).lower()
        if q.strip().lower() not in hay:
            return False
    return True


@router.get("/catalog")
async def past_questions_catalog(
    exam_type: Optional[str] = None,
    subject: Optional[str] = None,
    year: Optional[int] = None,
    q: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
):
    """Public catalog — no login required. Never returns PDF URLs."""
    try:
        try:
            await db.execute(text("ALTER TABLE books ADD COLUMN IF NOT EXISTS year INTEGER NULL"))
        except Exception:
            logger.exception("past_questions catalog: year column ensure failed")
            try:
                await db.rollback()
            except Exception:
                pass

        rows = (
            await db.execute(
                text(
                    """
                    SELECT
                      id::text AS id,
                      title,
                      subject,
                      exam_type,
                      year,
                      description,
                      cover_image_url,
                      COALESCE(price, 0) AS price,
                      COALESCE(is_free, false) AS is_free,
                      COALESCE(category, 'Past Questions') AS category,
                      COALESCE(library_target::text, 'student') AS library_target
                    FROM books
                    WHERE COALESCE(is_active, true) = true
                      AND (
                        category ILIKE '%past%'
                        OR category = :past_category
                      )
                    ORDER BY created_at DESC NULLS LAST
                    """
                ),
                {"past_category": PAST_CATEGORY},
            )
        ).mappings().all()

        products = []
        for row in rows:
            target = str(row.get("library_target") or "student").replace("LibraryTarget.", "").lower()
            if target != "student":
                continue
            year_val = row.get("year")
            try:
                year_val = int(year_val) if year_val is not None else None
            except (TypeError, ValueError):
                year_val = None
            card = {
                "id": str(row["id"]),
                "title": row.get("title") or "",
                "subject": row.get("subject") or "",
                "exam_type": row.get("exam_type") or "ALL",
                "year": year_val,
                "description": row.get("description"),
                "cover_image_url": row.get("cover_image_url"),
                "price": float(row.get("price") or 0),
                "is_free": bool(row.get("is_free")),
                "currency": "NGN",
                "category": row.get("category") or PAST_CATEGORY,
            }
            if _matches_filters(card, exam_type, subject, year, q):
                products.append(card)

        products.sort(
            key=lambda p: (
                str(p.get("exam_type") or ""),
                str(p.get("subject") or ""),
                -(p.get("year") or 0),
                str(p.get("title") or ""),
            )
        )
        return {
            "products": products,
            "filters": {
                "exam_types": ["ALL", "JAMB", "WAEC", "NECO", "COMMON_ENTRANCE"],
            },
        }
    except Exception:
        logger.exception("past_questions catalog failed")
        raise HTTPException(status_code=500, detail="Unable to load past questions")


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
