"""
Home / Discover feed for the student app.
Returns content only for the student's selected subjects and exam type.
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_, and_
from datetime import datetime
from typing import Optional

from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.subjects import subject_matches
from app.models.user import StudentProfile, User
from app.models.live_class import LiveClass, LiveSessionRequest
from app.models.content import BookRecommendation, RecommendationTarget
from app.models.cbt import CBTExam
from app.ai.recommendation_engine import get_recommendations
from app.ai.weakness_analyzer import get_weak_topics

router = APIRouter(prefix="/home", tags=["Home"])


async def _get_student_profile(db: AsyncSession, user_id: str) -> StudentProfile:
    result = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == user_id)
    )
    profile = result.scalar_one_or_none()
    if not profile or not profile.exam_type or not profile.selected_subjects:
        raise HTTPException(
            status_code=400,
            detail="Complete exam setup first at /students/setup-exam",
        )
    return profile


def _matches_subjects(item_subject: str, selected: list[str]) -> bool:
    return subject_matches(item_subject, selected)


async def _live_classes(
    db: AsyncSession,
    status: str,
    selected_subjects: list[str],
    limit: int = 10,
):
    now = datetime.utcnow()
    query = select(LiveClass)
    if status == "live":
        query = query.where(
            or_(
                LiveClass.is_live == True,  # noqa: E712
                and_(
                    LiveClass.start_time <= now,
                    or_(LiveClass.end_time > now, LiveClass.end_time.is_(None)),
                ),
            )
        )
    elif status == "upcoming":
        query = query.where(
            LiveClass.is_live == False,  # noqa: E712
            LiveClass.start_time > now,
            or_(LiveClass.end_time > now, LiveClass.end_time.is_(None)),
        )
    query = query.order_by(LiveClass.start_time.desc()).limit(limit * 3)
    result = await db.execute(query)
    classes = [
        c for c in result.scalars().all()
        if selected_subjects and _matches_subjects(c.subject, selected_subjects)
    ][:limit]

    teacher_ids = list({str(c.teacher_id) for c in classes})
    teachers_map = {}
    if teacher_ids:
        users_res = await db.execute(select(User).where(User.id.in_(teacher_ids)))
        teachers_map = {str(u.id): u.full_name for u in users_res.scalars().all()}

    return [
        {
            "id": str(c.id),
            "title": c.title,
            "subject": c.subject,
            "description": c.description,
            "teacher_name": teachers_map.get(str(c.teacher_id), "Unknown"),
            "start_time": c.start_time,
            "is_live": c.is_live,
            "room_id": c.room_id,
        }
        for c in classes
    ]


@router.get("/feed")
async def home_feed(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    GET /api/v1/home/feed
    Personalised feed — only the student's exam type and selected subjects.
    """
    role = current_user.get("role")

    profile = None
    selected_subjects: list[str] = []
    exam_type = None

    if role == "student":
        profile = await _get_student_profile(db, current_user["sub"])
        selected_subjects = profile.selected_subjects or []
        exam_type = str(profile.exam_type)

    if role == "student":
        targets = [RecommendationTarget.all, RecommendationTarget.student]
    elif role == "teacher":
        targets = [RecommendationTarget.all, RecommendationTarget.teacher]
    else:
        targets = list(RecommendationTarget)

    rec_query = (
        select(BookRecommendation)
        .where(
            BookRecommendation.is_active == True,  # noqa: E712
            BookRecommendation.target.in_(targets),
        )
        .order_by(BookRecommendation.created_at.desc())
        .limit(30)
    )
    if role == "student" and exam_type:
        rec_query = rec_query.where(
            or_(
                BookRecommendation.exam_type == exam_type,
                BookRecommendation.exam_type == "ALL",
                BookRecommendation.exam_type.is_(None),
            )
        )

    rec_result = await db.execute(rec_query)
    book_recs = [
        {
            "id": str(r.id),
            "title": r.title,
            "author": r.author,
            "subject": r.subject,
            "description": r.description,
            "cover_image_url": r.cover_image_url,
            "external_url": r.external_url,
            "has_library_book": r.book_id is not None,
            "type": "book",
        }
        for r in rec_result.scalars().all()
        if role != "student" or _matches_subjects(r.subject or "", selected_subjects)
    ][:12]

    # Library books + videos for each selected subject
    library_books = []
    library_videos = []
    weak_topics_all = []
    if role == "student":
        weak_map = await get_weak_topics(current_user["sub"])
        for subj in selected_subjects:
            weak_topics_all.extend(weak_map.get(subj, []))
            ai = await get_recommendations(
                db=db,
                student_id=current_user["sub"],
                subject=subj,
                education_level=profile.education_level or "SS2",
            )
            for b in ai.get("recommended_books", []):
                b = dict(b)
                b["subject"] = subj
                library_books.append(b)
            for v in ai.get("recommended_videos", []):
                v = dict(v)
                v["subject"] = subj
                library_videos.append(v)

    live_now = await _live_classes(db, "live", selected_subjects) if role == "student" else []
    upcoming = await _live_classes(db, "upcoming", selected_subjects) if role == "student" else []

    # School exams open or upcoming for student's subjects
    school_exams = []
    practice_exams = []
    if role == "student":
        now = datetime.utcnow()
        ex_res = await db.execute(select(CBTExam).where(CBTExam.is_published == True))  # noqa: E712
        for e in ex_res.scalars().all():
            if not _matches_subjects(e.subject, selected_subjects):
                continue
            summary = {
                "id": str(e.id),
                "title": e.title,
                "subject": e.subject,
                "exam_type": e.exam_type,
                "duration_minutes": e.duration_minutes,
                "total_questions": e.total_questions,
                "is_school_exam": e.is_school_exam,
                "scheduled_start": e.scheduled_start,
                "scheduled_end": e.scheduled_end,
            }
            if e.is_school_exam:
                school_exams.append(summary)
            elif e.exam_type.upper() == exam_type.upper():
                practice_exams.append(summary)

    my_requests = []
    if role == "student":
        req_result = await db.execute(
            select(LiveSessionRequest)
            .where(LiveSessionRequest.student_id == current_user["sub"])
            .order_by(LiveSessionRequest.created_at.desc())
            .limit(10)
        )
        my_requests = [
            {
                "id": str(r.id),
                "subject": r.subject,
                "topic": r.topic,
                "message": r.message,
                "preferred_time": r.preferred_time,
                "status": r.status.value if hasattr(r.status, "value") else r.status,
                "created_at": r.created_at,
            }
            for r in req_result.scalars().all()
            if _matches_subjects(r.subject, selected_subjects)
        ]

    return {
        "exam_type": exam_type,
        "selected_subjects": selected_subjects,
        "recommended_for_you": {
            "admin_picks": book_recs,
            "library_books": library_books[:15],
            "library_videos": library_videos[:15],
            "weak_topics": list(dict.fromkeys(weak_topics_all)),
        },
        "practice_exams": practice_exams,
        "school_exams": school_exams,
        "live_now": live_now,
        "upcoming_sessions": upcoming,
        "my_session_requests": my_requests,
    }
