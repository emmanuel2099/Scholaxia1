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
from app.models.student_group import (
    StudentGroup,
    StudentGroupJoinRequest,
    StudentGroupMember,
    StudentGroupMessage,
)
from app.models.live_class_access_code import LiveClassAccessCodeDelivery
from app.models.marketplace import MarketplaceBooking
from app.models.sil import (
    SilAntiCheatEvent,
    SilChallengeInvite,
    SilCoinTransaction,
    SilDeviceReport,
    SilFlaggedMatch,
    SilLeagueProfile,
    SilMatch,
)


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
    await db.execute(delete(LiveClassAccessCodeDelivery).where(LiveClassAccessCodeDelivery.student_id == user_id))

    # SIL / Intellect League
    await db.execute(delete(SilCoinTransaction).where(SilCoinTransaction.user_id == user_id))
    await db.execute(delete(SilChallengeInvite).where(SilChallengeInvite.from_user_id == user_id))
    await db.execute(delete(SilChallengeInvite).where(SilChallengeInvite.to_user_id == user_id))
    await db.execute(delete(SilAntiCheatEvent).where(SilAntiCheatEvent.user_id == user_id))
    await db.execute(delete(SilFlaggedMatch).where(SilFlaggedMatch.user_id == user_id))
    await db.execute(delete(SilDeviceReport).where(SilDeviceReport.user_id == user_id))
    await db.execute(delete(SilMatch).where(SilMatch.player1_id == user_id))
    await db.execute(delete(SilMatch).where(SilMatch.player2_id == user_id))
    await db.execute(delete(SilLeagueProfile).where(SilLeagueProfile.user_id == user_id))

    # Student groups
    await db.execute(delete(StudentGroupMessage).where(StudentGroupMessage.user_id == user_id))
    await db.execute(delete(StudentGroupMember).where(StudentGroupMember.user_id == user_id))
    await db.execute(delete(StudentGroupJoinRequest).where(StudentGroupJoinRequest.user_id == user_id))
    created_groups = (
        await db.execute(select(StudentGroup.id).where(StudentGroup.creator_id == user_id))
    ).scalars().all()
    if created_groups:
        await db.execute(delete(StudentGroupMessage).where(StudentGroupMessage.group_id.in_(created_groups)))
        await db.execute(delete(StudentGroupMember).where(StudentGroupMember.group_id.in_(created_groups)))
        await db.execute(delete(StudentGroupJoinRequest).where(StudentGroupJoinRequest.group_id.in_(created_groups)))
        await db.execute(delete(StudentGroup).where(StudentGroup.id.in_(created_groups)))

    try:
        await db.execute(delete(MarketplaceBooking).where(MarketplaceBooking.user_id == user_id))
    except Exception:
        pass

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
