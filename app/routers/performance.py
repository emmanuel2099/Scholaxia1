"""
Performance Router
------------------
Recent CBT performance + learning analytics for students.
Teachers can view performance of students in their classes.

Student endpoints:
  GET /api/v1/performance/recent          — last N CBT sessions with scores
  GET /api/v1/performance/summary         — aggregate stats (avg score, streak, weak topics)
  GET /api/v1/performance/trend           — score trend over time per subject

Teacher / Admin:
  GET /api/v1/performance/students/{student_id}/recent  — view a specific student's performance
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from typing import Optional
from datetime import datetime, timedelta

from app.core.database import get_db
from app.core.deps import require_student, get_current_user
from app.models.cbt import CBTSession, CBTExam
from app.models.student_analytics import StudentLearningProfile, LessonSession
from app.models.user import User

router = APIRouter(prefix="/performance", tags=["Performance"])


# ── Student: Recent CBT sessions ──────────────────────────────────────────────

@router.get("/recent")
async def get_recent_performance(
    limit: int = Query(default=10, le=50),
    subject: Optional[str] = None,
    exam_type: Optional[str] = None,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    GET /api/v1/performance/recent
    Returns the student's most recent completed CBT sessions with:
    - exam title, subject, exam type
    - score, percentage, total correct/wrong
    - weak topics from that session
    - date taken
    """
    query = (
        select(CBTSession, CBTExam)
        .join(CBTExam, CBTExam.id == CBTSession.exam_id)
        .where(
            CBTSession.student_id == current_user["sub"],
            CBTSession.submitted_at.isnot(None),
        )
        .order_by(CBTSession.submitted_at.desc())
        .limit(limit)
    )

    if subject:
        query = query.where(CBTExam.subject == subject)
    if exam_type:
        query = query.where(CBTExam.exam_type == exam_type.upper())

    result = await db.execute(query)
    rows = result.all()

    sessions = []
    for session, exam in rows:
        sessions.append({
            "session_id": str(session.id),
            "exam_id": str(exam.id),
            "exam_title": exam.title,
            "subject": exam.subject,
            "exam_type": exam.exam_type,
            "score": session.score,
            "percentage": session.percentage,
            "total_correct": session.total_correct,
            "total_wrong": session.total_wrong,
            "total_questions": exam.total_questions,
            "weak_topics": session.weak_topics or [],
            "is_auto_submitted": session.is_auto_submitted,
            "taken_at": session.submitted_at,
            "duration_minutes": exam.duration_minutes,
        })

    return sessions


# ── Student: Summary stats ────────────────────────────────────────────────────

@router.get("/summary")
async def get_performance_summary(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    GET /api/v1/performance/summary
    Returns aggregated performance stats:
    - total CBT sessions taken
    - average percentage across all sessions
    - best and worst score
    - all-time weak topics (aggregated)
    - learning profile: streak, study minutes, confidence level
    - per-subject average scores
    """
    # All completed sessions
    result = await db.execute(
        select(CBTSession, CBTExam)
        .join(CBTExam, CBTExam.id == CBTSession.exam_id)
        .where(
            CBTSession.student_id == current_user["sub"],
            CBTSession.submitted_at.isnot(None),
        )
        .order_by(CBTSession.submitted_at.desc())
    )
    rows = result.all()

    if not rows:
        # Return a zero-state summary
        return {
            "total_sessions": 0,
            "avg_percentage": 0,
            "best_percentage": 0,
            "worst_percentage": 0,
            "weak_topics": [],
            "subject_averages": {},
            "streak_days": 0,
            "total_study_minutes": 0,
            "confidence_level": "building",
            "last_active_at": None,
        }

    percentages = [s.percentage for s, _ in rows if s.percentage is not None]
    all_weak = []
    for session, _ in rows:
        all_weak.extend(session.weak_topics or [])

    # Count weak topic frequency
    weak_freq: dict = {}
    for t in all_weak:
        weak_freq[t] = weak_freq.get(t, 0) + 1
    top_weak = sorted(weak_freq, key=lambda k: weak_freq[k], reverse=True)[:10]

    # Per-subject averages
    subject_scores: dict = {}
    for session, exam in rows:
        if session.percentage is None:
            continue
        s = exam.subject
        if s not in subject_scores:
            subject_scores[s] = []
        subject_scores[s].append(session.percentage)

    subject_averages = {
        s: round(sum(scores) / len(scores), 1)
        for s, scores in subject_scores.items()
    }

    # Learning profile
    profile_res = await db.execute(
        select(StudentLearningProfile).where(
            StudentLearningProfile.student_id == current_user["sub"]
        )
    )
    profile = profile_res.scalar_one_or_none()

    return {
        "total_sessions": len(rows),
        "avg_percentage": round(sum(percentages) / len(percentages), 1) if percentages else 0,
        "best_percentage": round(max(percentages), 1) if percentages else 0,
        "worst_percentage": round(min(percentages), 1) if percentages else 0,
        "weak_topics": top_weak,
        "subject_averages": subject_averages,
        "streak_days": profile.streak_days if profile else 0,
        "total_study_minutes": profile.total_study_minutes if profile else 0,
        "confidence_level": profile.confidence_level if profile else "building",
        "last_active_at": profile.last_active_at if profile else None,
    }


# ── Student: Score trend per subject ─────────────────────────────────────────

@router.get("/trend")
async def get_score_trend(
    subject: Optional[str] = None,
    days: int = Query(default=30, le=180),
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    GET /api/v1/performance/trend?subject=Mathematics&days=30
    Returns chronological score data points for charting a trend line.
    If subject is omitted, returns data across all subjects.
    """
    since = datetime.utcnow() - timedelta(days=days)

    query = (
        select(CBTSession, CBTExam)
        .join(CBTExam, CBTExam.id == CBTSession.exam_id)
        .where(
            CBTSession.student_id == current_user["sub"],
            CBTSession.submitted_at.isnot(None),
            CBTSession.submitted_at >= since,
        )
        .order_by(CBTSession.submitted_at.asc())
    )

    if subject:
        query = query.where(CBTExam.subject == subject)

    result = await db.execute(query)
    rows = result.all()

    return {
        "subject": subject or "all",
        "days": days,
        "data_points": [
            {
                "date": session.submitted_at.strftime("%Y-%m-%d"),
                "percentage": session.percentage,
                "subject": exam.subject,
                "exam_title": exam.title,
            }
            for session, exam in rows
            if session.percentage is not None
        ],
    }


# ── Teacher/Admin: View a specific student's performance ─────────────────────

@router.get("/students/{student_id}/recent")
async def get_student_performance(
    student_id: str,
    limit: int = Query(default=10, le=50),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    GET /api/v1/performance/students/{student_id}/recent
    Teachers and admins view a student's recent CBT history.
    Students can view their own (student_id == their own id).
    """
    role = current_user.get("role")
    if role == "student" and current_user["sub"] != student_id:
        raise HTTPException(status_code=403, detail="You can only view your own performance")
    if role not in ("student", "teacher", "admin"):
        raise HTTPException(status_code=403, detail="Not authorised")

    # Verify student exists
    user_res = await db.execute(select(User).where(User.id == student_id))
    user = user_res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="Student not found")

    result = await db.execute(
        select(CBTSession, CBTExam)
        .join(CBTExam, CBTExam.id == CBTSession.exam_id)
        .where(
            CBTSession.student_id == student_id,
            CBTSession.submitted_at.isnot(None),
        )
        .order_by(CBTSession.submitted_at.desc())
        .limit(limit)
    )
    rows = result.all()

    return {
        "student_id": student_id,
        "student_name": user.full_name,
        "sessions": [
            {
                "session_id": str(s.id),
                "exam_title": e.title,
                "subject": e.subject,
                "exam_type": e.exam_type,
                "percentage": s.percentage,
                "total_correct": s.total_correct,
                "total_wrong": s.total_wrong,
                "weak_topics": s.weak_topics or [],
                "taken_at": s.submitted_at,
            }
            for s, e in rows
        ],
    }
