"""Permanently remove user accounts and related records."""
import uuid
from typing import Optional

from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User, StudentProfile, TeacherProfile, KindProfile, UserRole
from app.models.cbt import CBTSession, ExamProctorLog
from app.models.live_class import ClassAttendance, LiveClass, LiveSessionRequest
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
from app.models.wallet import TeacherWallet, WalletTransaction, WithdrawalRequest
from app.services.student_cleanup import delete_student_user


async def clear_all_live_classes(db: AsyncSession) -> int:
    count_res = await db.execute(select(LiveClass.id))
    ids = count_res.scalars().all()
    if not ids:
        return 0

    await db.execute(
        update(LiveSessionRequest)
        .where(LiveSessionRequest.linked_class_id.isnot(None))
        .values(linked_class_id=None)
    )
    await db.execute(
        update(WalletTransaction)
        .where(WalletTransaction.live_class_id.isnot(None))
        .values(live_class_id=None)
    )
    await db.execute(
        update(TeacherReview)
        .where(TeacherReview.live_class_id.isnot(None))
        .values(live_class_id=None)
    )
    await db.execute(delete(ClassAttendance))
    await db.execute(delete(LiveClass))
    await db.flush()
    return len(ids)


async def _delete_user_community(db: AsyncSession, user_id: uuid.UUID) -> None:
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


async def delete_teacher_user(db: AsyncSession, user_id: uuid.UUID) -> bool:
    result = await db.execute(
        select(User).where(User.id == user_id, User.role == UserRole.teacher)
    )
    user = result.scalar_one_or_none()
    if not user:
        return False

    class_ids = (
        await db.execute(select(LiveClass.id).where(LiveClass.teacher_id == user_id))
    ).scalars().all()
    for class_id in class_ids:
        await db.execute(
            update(LiveSessionRequest)
            .where(LiveSessionRequest.linked_class_id == class_id)
            .values(linked_class_id=None)
        )
        await db.execute(
            update(WalletTransaction)
            .where(WalletTransaction.live_class_id == class_id)
            .values(live_class_id=None)
        )
        await db.execute(
            update(TeacherReview)
            .where(TeacherReview.live_class_id == class_id)
            .values(live_class_id=None)
        )
        await db.execute(delete(ClassAttendance).where(ClassAttendance.live_class_id == class_id))
        await db.execute(delete(LiveClass).where(LiveClass.id == class_id))

    wallet = (
        await db.execute(select(TeacherWallet).where(TeacherWallet.teacher_id == user_id))
    ).scalar_one_or_none()
    if wallet:
        await db.execute(delete(WalletTransaction).where(WalletTransaction.wallet_id == wallet.id))
        await db.execute(delete(WithdrawalRequest).where(WithdrawalRequest.wallet_id == wallet.id))
        await db.execute(delete(TeacherWallet).where(TeacherWallet.id == wallet.id))
    await db.execute(delete(WalletTransaction).where(WalletTransaction.teacher_id == user_id))
    await db.execute(delete(WithdrawalRequest).where(WithdrawalRequest.teacher_id == user_id))

    await db.execute(delete(TeacherReview).where(TeacherReview.teacher_id == user_id))
    await db.execute(delete(Report).where(Report.reporter_id == user_id))
    await db.execute(delete(Report).where(Report.target_id == user_id))
    await db.execute(delete(Notification).where(Notification.user_id == user_id))
    await db.execute(delete(DeviceToken).where(DeviceToken.user_id == user_id))
    await _delete_user_community(db, user_id)
    await db.execute(delete(TeacherProfile).where(TeacherProfile.user_id == user_id))
    await db.delete(user)
    await db.flush()
    return True


async def delete_kind_user(db: AsyncSession, user_id: uuid.UUID) -> bool:
    result = await db.execute(
        select(User).where(User.id == user_id, User.role == UserRole.kind)
    )
    user = result.scalar_one_or_none()
    if not user:
        return False

    await db.execute(delete(Notification).where(Notification.user_id == user_id))
    await db.execute(delete(DeviceToken).where(DeviceToken.user_id == user_id))
    await db.execute(delete(SiaNote).where(SiaNote.student_id == user_id))
    await db.execute(delete(LessonSession).where(LessonSession.student_id == user_id))
    await db.execute(delete(StudentLearningProfile).where(StudentLearningProfile.student_id == user_id))
    await _delete_user_community(db, user_id)
    await db.execute(delete(KindProfile).where(KindProfile.user_id == user_id))
    await db.delete(user)
    await db.flush()
    return True


async def purge_all_user_accounts(
    db: AsyncSession,
    keep_admin_id: Optional[uuid.UUID] = None,
) -> dict:
    """
    Permanently delete all student, teacher, and kind accounts (all their emails).
    Admin and developer accounts are kept (optionally always keep keep_admin_id).
    """
    live_removed = await clear_all_live_classes(db)

    keep_ids = set()
    if keep_admin_id:
        keep_ids.add(keep_admin_id)

    admin_dev = await db.execute(
        select(User.id).where(User.role.in_([UserRole.admin, UserRole.developer]))
    )
    for uid in admin_dev.scalars().all():
        keep_ids.add(uid)

    removed = {"students": 0, "teachers": 0, "kind": 0, "live_classes": live_removed}

    students = (
        await db.execute(select(User).where(User.role == UserRole.student))
    ).scalars().all()
    for user in students:
        if user.id in keep_ids:
            continue
        if await delete_student_user(db, user.id):
            removed["students"] += 1

    teachers = (
        await db.execute(select(User).where(User.role == UserRole.teacher))
    ).scalars().all()
    for user in teachers:
        if user.id in keep_ids:
            continue
        if await delete_teacher_user(db, user.id):
            removed["teachers"] += 1

    kinds = (
        await db.execute(select(User).where(User.role == UserRole.kind))
    ).scalars().all()
    for user in kinds:
        if user.id in keep_ids:
            continue
        if await delete_kind_user(db, user.id):
            removed["kind"] += 1

    await db.flush()
    removed["total"] = removed["students"] + removed["teachers"] + removed["kind"]
    return removed
