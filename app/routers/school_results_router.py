"""School results + scratch cards.

School staff: enter CA/exam scores, publish, generate & sell scratch cards.
Parents: public /check-result on the school's private link (PIN required).
Result PDF: photo + school name + QR code.
"""
from __future__ import annotations

import io
import secrets
from datetime import datetime, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy import func, select, update as sql_update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.datetime_utils import naive_utc_now
from app.core.deps import require_school_staff
from app.models.school_campus import SchoolCampus
from app.models.school_results import (
    ResultPublication,
    SchoolResult,
    SchoolScratchCard,
    ScratchCardSale,
    compute_grade,
    ordinal,
)
from app.models.user import StudentProfile, User, UserRole
from app.routers.school_core import require_school_feature

router = APIRouter(tags=["School results"])
public_router = APIRouter(tags=["Check result"])


async def _school(db: AsyncSession, sid: str) -> SchoolCampus:
    row = (
        await db.execute(select(SchoolCampus).where(SchoolCampus.id == UUID(sid)))
    ).scalar_one_or_none()
    if not row:
        raise HTTPException(status_code=404, detail="School not found")
    return row


# ------------------------------------------------------------ results ----

class ResultIn(BaseModel):
    student_id: str
    term_label: str = Field(max_length=80)
    session_label: str | None = None
    class_name: str | None = None
    subject: str
    ca_score: float = Field(ge=0, default=0)
    exam_score: float = Field(ge=0, default=0)
    remark: str | None = None


@router.post("/school/results", status_code=201)
async def upsert_result(
    payload: ResultIn,
    current_user: dict = Depends(require_school_staff),
    _feat: dict = Depends(require_school_feature("results")),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Enter or update one subject result (CA + Exam → total, grade)."""
    school_id = current_user["school_id"]
    ca, exam = float(payload.ca_score or 0), float(payload.exam_score or 0)
    if ca > 100 or exam > 100:
        raise HTTPException(status_code=422, detail="Scores look too high")
    total = round(ca + exam, 2)
    row = (
        await db.execute(
            select(SchoolResult).where(
                SchoolResult.school_id == UUID(school_id),
                SchoolResult.student_id == UUID(payload.student_id),
                SchoolResult.term_label == payload.term_label,
                SchoolResult.subject == payload.subject,
            )
        )
    ).scalar_one_or_none()
    if row:
        row.ca_score, row.exam_score, row.total = ca, exam, total
        row.grade = compute_grade(total)
        row.remark = payload.remark
        row.class_name = payload.class_name or row.class_name
        row.session_label = payload.session_label or row.session_label
        row.entered_by = UUID(current_user["sub"])
    else:
        row = SchoolResult(
            school_id=UUID(school_id),
            student_id=UUID(payload.student_id),
            term_label=payload.term_label,
            session_label=payload.session_label,
            class_name=payload.class_name,
            subject=payload.subject,
            ca_score=ca,
            exam_score=exam,
            total=total,
            grade=compute_grade(total),
            remark=payload.remark,
            entered_by=UUID(current_user["sub"]),
        )
        db.add(row)
    await db.commit()
    return {"id": str(row.id), "total": total, "grade": row.grade}


@router.get("/school/results")
async def list_results(
    term_label: str,
    class_name: str | None = None,
    student_id: str | None = None,
    current_user: dict = Depends(require_school_staff),
    _feat: dict = Depends(require_school_feature("results")),
    db: AsyncSession = Depends(get_db),
) -> dict:
    stmt = select(SchoolResult).where(
        SchoolResult.school_id == UUID(current_user["school_id"]),
        SchoolResult.term_label == term_label,
    )
    if class_name:
        stmt = stmt.where(SchoolResult.class_name == class_name)
    if student_id:
        stmt = stmt.where(SchoolResult.student_id == UUID(student_id))
    rows = (await db.execute(stmt.order_by(SchoolResult.student_id, SchoolResult.subject))).scalars().all()
    return {
        "results": [
            {
                "id": str(r.id),
                "student_id": str(r.student_id),
                "term_label": r.term_label,
                "class_name": r.class_name,
                "subject": r.subject,
                "ca_score": float(r.ca_score),
                "exam_score": float(r.exam_score),
                "total": float(r.total),
                "grade": r.grade,
                "position": r.position,
                "remark": r.remark,
            }
            for r in rows
        ]
    }


@router.post("/school/results/recompute-positions")
async def recompute_positions(
    term_label: str,
    class_name: str,
    current_user: dict = Depends(require_school_staff),
    _feat: dict = Depends(require_school_feature("results")),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Rank students per subject within a class and write ordinal positions."""
    rows = (
        await db.execute(
            select(SchoolResult).where(
                SchoolResult.school_id == UUID(current_user["school_id"]),
                SchoolResult.term_label == term_label,
                SchoolResult.class_name == class_name,
            )
        )
    ).scalars().all()
    by_subject: dict[str, list[SchoolResult]] = {}
    for r in rows:
        by_subject.setdefault(r.subject, []).append(r)
    changed = 0
    for subject, group in by_subject.items():
        ordered = sorted(group, key=lambda r: (-float(r.total),))
        for i, r in enumerate(ordered, start=1):
            pos = ordinal(i)
            if r.position != pos:
                r.position = pos
                changed += 1
    await db.commit()
    return {"subjects": len(by_subject), "positions_updated": changed}


class PublishIn(BaseModel):
    term_label: str
    is_published: bool = True


@router.post("/school/results/publish")
async def publish_results(
    payload: PublishIn,
    current_user: dict = Depends(require_school_staff),
    _feat: dict = Depends(require_school_feature("results")),
    db: AsyncSession = Depends(get_db),
) -> dict:
    school_id = UUID(current_user["school_id"])
    row = (
        await db.execute(
            select(ResultPublication).where(
                ResultPublication.school_id == school_id,
                ResultPublication.term_label == payload.term_label,
            )
        )
    ).scalar_one_or_none()
    if row:
        row.is_published = payload.is_published
        row.published_at = naive_utc_now() if payload.is_published else None
    else:
        row = ResultPublication(
            school_id=school_id,
            term_label=payload.term_label,
            is_published=payload.is_published,
            published_at=naive_utc_now() if payload.is_published else None,
        )
        db.add(row)
    await db.commit()
    return {"term_label": payload.term_label, "is_published": row.is_published}


# ------------------------------------------------------- result PDF ----

@router.get("/school/results/report-card")
async def report_card_pdf(
    term_label: str,
    student_id: str,
    current_user: dict = Depends(require_school_staff),
    _feat: dict = Depends(require_school_feature("results")),
    db: AsyncSession = Depends(get_db),
):
    """PDF report card with photo, school name and QR verification code."""
    from app.services.result_pdf import build_report_card_pdf

    school = await _school(db, current_user["school_id"])
    student = (
        await db.execute(select(User).where(User.id == UUID(student_id)))
    ).scalar_one_or_none()
    if not student:
        raise HTTPException(status_code=404, detail="Student not found")
    rows = (
        await db.execute(
            select(SchoolResult).where(
                SchoolResult.school_id == school.id,
                SchoolResult.student_id == student.id,
                SchoolResult.term_label == term_label,
            )
        )
    ).scalars().all()
    if not rows:
        raise HTTPException(status_code=404, detail="No results for this student/term")

    # Class-average positions come straight from stored positions.
    pdf_bytes, filename = await build_report_card_pdf(
        db,
        school=school,
        student=student,
        term_label=term_label,
        results=rows,
    )
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ----------------------------------------------------- scratch cards ----

class CardGenIn(BaseModel):
    quantity: int = Field(ge=1, le=500)
    term_label: str | None = None
    student_id: str | None = None
    price_ngn: float = Field(default=0, ge=0)


@router.post("/school/scratch-cards/generate", status_code=201)
async def generate_cards(
    payload: CardGenIn,
    current_user: dict = Depends(require_school_staff),
    _feat: dict = Depends(require_school_feature("scratch_cards")),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Generate PINs the school sells to parents."""
    school_id = UUID(current_user["school_id"])
    cards = []
    for _ in range(payload.quantity):
        while True:
            pin = "SCH-" + secrets.token_hex(5).upper()  # e.g. SCH-3F9A2C41B7
            if not (
                await db.execute(select(SchoolScratchCard.id).where(SchoolScratchCard.pin == pin))
            ).scalar_one_or_none():
                break
        card = SchoolScratchCard(
            school_id=school_id,
            pin=pin,
            serial=f"SC-{secrets.token_hex(3).upper()}",
            student_id=UUID(payload.student_id) if payload.student_id else None,
            term_label=payload.term_label,
            price_ngn=payload.price_ngn,
        )
        db.add(card)
        cards.append(card)
    await db.flush()
    if payload.price_ngn:
        db.add(
            ScratchCardSale(
                school_id=school_id,
                card_id=cards[0].id,
                quantity=payload.quantity,
                unit_price_ngn=payload.price_ngn,
                total_ngn=payload.price_ngn * payload.quantity,
                sold_by=current_user.get("email"),
            )
        )
    await db.commit()
    return {
        "generated": len(cards),
        "total_ngn": float(payload.price_ngn) * payload.quantity,
        "cards": [{"pin": c.pin, "serial": c.serial} for c in cards],
    }


@router.get("/school/scratch-cards")
async def list_cards(
    is_used: bool | None = None,
    limit: int = Query(default=200, le=1000),
    current_user: dict = Depends(require_school_staff),
    _feat: dict = Depends(require_school_feature("scratch_cards")),
    db: AsyncSession = Depends(get_db),
) -> dict:
    stmt = select(SchoolScratchCard).where(
        SchoolScratchCard.school_id == UUID(current_user["school_id"])
    )
    if is_used is not None:
        stmt = stmt.where(SchoolScratchCard.is_used.is_(is_used))
    rows = (await db.execute(stmt.order_by(SchoolScratchCard.created_at.desc()).limit(limit))).scalars().all()
    total = (
        await db.execute(
            select(func.count()).where(SchoolScratchCard.school_id == UUID(current_user["school_id"]))
        )
    ).scalar()
    used = (
        await db.execute(
            select(func.count()).where(
                SchoolScratchCard.school_id == UUID(current_user["school_id"]),
                SchoolScratchCard.is_used.is_(True),
            )
        )
    ).scalar()
    return {
        "total": total,
        "used": used,
        "unused": int(total) - int(used),
        "cards": [
            {
                "pin": c.pin,
                "serial": c.serial,
                "is_used": c.is_used,
                "used_at": c.used_at.isoformat() if c.used_at else None,
                "price_ngn": float(c.price_ngn),
            }
            for c in rows
        ],
    }


# --------------------------------------------------- public check-result ----

class CheckResultIn(BaseModel):
    slug: str
    pin: str
    student_id: str | None = None
    admission_number: str | None = None
    term_label: str


@public_router.post("/public/check-result")
async def check_result(payload: CheckResultIn, db: AsyncSession = Depends(get_db)) -> dict:
    """Parent enters PIN + term (+ student/admission no) on the school's link."""
    school = (
        await db.execute(
            select(SchoolCampus).where(SchoolCampus.slug == payload.slug.lower().strip(), SchoolCampus.is_active.is_(True))
        )
    ).scalar_one_or_none()
    if not school:
        raise HTTPException(status_code=404, detail="School not found")

    pub = (
        await db.execute(
            select(ResultPublication).where(
                ResultPublication.school_id == school.id,
                ResultPublication.term_label == payload.term_label,
                ResultPublication.is_published.is_(True),
            )
        )
    ).scalar_one_or_none()
    if not pub:
        raise HTTPException(status_code=403, detail="Results for this term are not published yet")

    card = (
        await db.execute(select(SchoolScratchCard).where(SchoolScratchCard.pin == payload.pin.strip().upper()))
    ).scalar_one_or_none()
    if not card or card.school_id != school.id:
        raise HTTPException(status_code=404, detail="Invalid PIN for this school")
    if card.is_used and card.used_for_student and payload.student_id and str(card.used_for_student) != payload.student_id:
        raise HTTPException(status_code=403, detail="This PIN was already used for another student")
    if card.expires_at and card.expires_at < naive_utc_now():
        raise HTTPException(status_code=403, detail="This PIN has expired")

    student: User | None = None
    if payload.student_id:
        student = (
            await db.execute(select(User).where(User.id == UUID(payload.student_id), User.school_id == school.id))
        ).scalar_one_or_none()
    elif payload.admission_number:
        prof = (
            await db.execute(
                select(StudentProfile, User)
                .join(User, User.id == StudentProfile.user_id)
                .where(StudentProfile.school_student_id == payload.admission_number.strip(), User.school_id == school.id)
            )
        ).first()
        student = prof[1] if prof else None
    if not student:
        raise HTTPException(status_code=404, detail="Student not found in this school")

    # Burn the PIN on first successful use (one student per card).
    if not card.is_used:
        card.is_used = True
        card.used_at = naive_utc_now()
        card.used_for_student = student.id
        card.times_used = 1
        await db.commit()

    rows = (
        await db.execute(
            select(SchoolResult).where(
                SchoolResult.school_id == school.id,
                SchoolResult.student_id == student.id,
                SchoolResult.term_label == payload.term_label,
            ).order_by(SchoolResult.subject)
        )
    ).scalars().all()
    if not rows:
        raise HTTPException(status_code=404, detail="No results yet for this term")

    grand_total = sum(float(r.total) for r in rows)
    return {
        "school": {"name": school.name, "slug": school.slug},
        "student": {
            "id": str(student.id),
            "name": student.full_name,
            "photo_url": student.profile_picture,
            "class_name": rows[0].class_name,
            "admission_no": payload.admission_number,
        },
        "term_label": payload.term_label,
        "subjects": [
            {
                "subject": r.subject,
                "ca_score": float(r.ca_score),
                "exam_score": float(r.exam_score),
                "total": float(r.total),
                "grade": r.grade,
                "position": r.position,
                "remark": r.remark,
            }
            for r in rows
        ],
        "grand_total": round(grand_total, 2),
        "average": round(grand_total / len(rows), 2) if rows else 0,
    }
