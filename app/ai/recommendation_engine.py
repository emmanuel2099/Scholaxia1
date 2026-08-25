"""
Recommendation Engine
---------------------
Recommends books and videos from Scholaxia's internal library only.
Based on: student's selected subjects, weak topics, and education level.
No external content is ever recommended.
"""

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models.content import Book, Video
from app.ai.weakness_analyzer import get_weak_topics


async def get_recommendations(
    db: AsyncSession,
    student_id: str,
    subject: str,
    education_level: str,
) -> dict:
    """
    Returns recommended books and videos from the internal library
    based on subject and weak topics.
    """
    weak = await get_weak_topics(student_id)
    weak_topics_for_subject = weak.get(subject, [])

    books = []
    videos = []
    try:
        book_result = await db.execute(
            select(Book.id, Book.title, Book.author)
            .where(Book.subject == subject)
            .limit(5)
        )
        books = book_result.all()
    except Exception:
        try:
            await db.rollback()
        except Exception:
            pass
    try:
        video_result = await db.execute(
            select(Video.id, Video.title, Video.video_url, Video.thumbnail_url)
            .where(Video.subject == subject)
            .limit(5)
        )
        videos = video_result.all()
    except Exception:
        try:
            await db.rollback()
        except Exception:
            pass

    return {
        "weak_topics": weak_topics_for_subject,
        "recommended_books": [
            {"id": str(b.id), "title": b.title, "author": b.author}
            for b in books
        ],
        "recommended_videos": [
            {
                "id": str(v.id),
                "title": v.title,
                "video_url": v.video_url,
                "thumbnail": v.thumbnail_url,
            }
            for v in videos
        ],
    }
