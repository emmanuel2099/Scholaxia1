"""Permanently remove a student user and related records."""
import uuid
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User, StudentProfile, UserRole
from app.models.cbt import CBTSession, ExamProctorLog
from app.models.live_class import ClassAttendance, LiveSessionRequest
from app.models.community import (
    AssignmentSubmission,
    CommunityMessage,
    CommunityPost,
    MessageReport,
    PostLike,
)
from app.models.content import BookReadProgress, SavedBook
from app.models.notification import DeviceToken, Notification
from app.models.payment import Payment, Subscription
from app.models.review_report import Report, TeacherReview
from app.models.sia_note import SiaNote
from app.models.student_analytics import LessonSession, StudentLearningProfile


async def delete_student_user(db: AsyncSession, user_id: uuid.UUID) -> bool:
    result = await db.execute(
        select(User).where(User.id == user_id, User.role == UserRole.student)
    )
    user = result.scalar_one_or_none()
    if not user:
        return False

    session_ids = (
        await db.execute(select(CBTSession.id).where(CBTSession.student_id == user_id))
    ).scalars().all()
    if session_ids:
        await db.execute(
            delete(ExamProctorLog).where(ExamProctorLog.session_id.in_(session_ids))
        )
    await db.execute(delete(ExamProctorLog).where(ExamProctorLog.student_id == user_id))
    await db.execute(delete(CBTSession).where(CBTSession.student_id == user_id))

    await db.execute(delete(ClassAttendance).where(ClassAttendance.student_id == user_id))
    await db.execute(delete(LiveSessionRequest).where(LiveSessionRequest.student_id == user_id))

    post_ids = (
        await db.execute(select(CommunityPost.id).where(CommunityPost.author_id == user_id))
    ).scalars().all()
    if post_ids:
        await db.execute(delete(PostLike).where(PostLike.post_id.in_(post_ids)))
    await db.execute(delete(PostLike).where(PostLike.user_id == user_id))
    await db.execute(delete(CommunityPost).where(CommunityPost.author_id == user_id))

    message_ids = (
        await db.execute(select(CommunityMessage.id).where(CommunityMessage.sender_id == user_id))
    ).scalars().all()
    if message_ids:
        await db.execute(delete(MessageReport).where(MessageReport.message_id.in_(message_ids)))
    await db.execute(delete(MessageReport).where(MessageReport.reported_by == user_id))
    await db.execute(delete(CommunityMessage).where(CommunityMessage.sender_id == user_id))

    await db.execute(delete(AssignmentSubmission).where(AssignmentSubmission.student_id == user_id))
    await db.execute(delete(Notification).where(Notification.user_id == user_id))
    await db.execute(delete(DeviceToken).where(DeviceToken.user_id == user_id))
    await db.execute(delete(SiaNote).where(SiaNote.student_id == user_id))
    await db.execute(delete(LessonSession).where(LessonSession.student_id == user_id))
    await db.execute(delete(StudentLearningProfile).where(StudentLearningProfile.student_id == user_id))
    await db.execute(delete(Payment).where(Payment.student_id == user_id))
    await db.execute(delete(Subscription).where(Subscription.student_id == user_id))
    await db.execute(delete(TeacherReview).where(TeacherReview.student_id == user_id))
    await db.execute(delete(Report).where(Report.reporter_id == user_id))
    await db.execute(delete(Report).where(Report.target_id == user_id))
    await db.execute(delete(SavedBook).where(SavedBook.user_id == user_id))
    await db.execute(delete(BookReadProgress).where(BookReadProgress.user_id == user_id))

    await db.execute(delete(StudentProfile).where(StudentProfile.user_id == user_id))
    await db.delete(user)
    await db.flush()
    return True
