import json
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import delete, select
from app.models.user import StudentProfile, User, UserRole
from app.models.notification import Notification, DeviceToken, NotificationType
import firebase_admin
from firebase_admin import messaging, credentials
from app.core.config import settings
from app.core.subjects import subject_matches

# Initialize Firebase once
_firebase_initialized = False


def init_firebase():
    global _firebase_initialized
    if _firebase_initialized:
        return
    try:
        if settings.FIREBASE_CREDENTIALS_JSON:
            cred_dict = json.loads(settings.FIREBASE_CREDENTIALS_JSON)
            cred = credentials.Certificate(cred_dict)
        else:
            cred = credentials.Certificate(settings.FIREBASE_CREDENTIALS_PATH)
        firebase_admin.initialize_app(cred)
        _firebase_initialized = True
    except Exception:
        pass  # Firebase not configured yet


async def send_all_students_notification(
    db: AsyncSession,
    title: str,
    body: str,
    notification_type: str,
    data: dict = None,
    exclude_user_id: str = None,
):
    """Notify every student (in-app + push)."""
    result = await db.execute(select(StudentProfile))
    profiles = result.scalars().all()
    student_ids = [
        str(p.user_id) for p in profiles
        if not exclude_user_id or str(p.user_id) != exclude_user_id
    ]
    if not student_ids:
        return

    try:
        ntype = NotificationType(notification_type)
    except ValueError:
        ntype = NotificationType.announcement

    for student_id in student_ids:
        db.add(Notification(
            user_id=student_id,
            type=ntype,
            title=title,
            body=body,
            data=json.dumps(data or {}),
        ))
    await db.flush()
    await _send_push_to_users(db, student_ids, title, body, data or {})


async def send_all_teachers_notification(
    db: AsyncSession,
    title: str,
    body: str,
    notification_type: str,
    data: dict = None,
    exclude_user_id: str = None,
):
    """Notify every teacher (in-app + push)."""
    result = await db.execute(select(User).where(User.role == UserRole.teacher))
    teachers = result.scalars().all()
    teacher_ids = [
        str(t.id) for t in teachers
        if not exclude_user_id or str(t.id) != exclude_user_id
    ]
    if not teacher_ids:
        return

    try:
        ntype = NotificationType(notification_type)
    except ValueError:
        ntype = NotificationType.announcement

    for teacher_id in teacher_ids:
        db.add(Notification(
            user_id=teacher_id,
            type=ntype,
            title=title,
            body=body,
            data=json.dumps(data or {}),
        ))
    await db.flush()
    await _send_push_to_users(db, teacher_ids, title, body, data or {})


async def send_admins_notification(
    db: AsyncSession,
    title: str,
    body: str,
    notification_type: str,
    data: dict = None,
):
    """Notify every admin (in-app + push)."""
    result = await db.execute(select(User).where(User.role == UserRole.admin))
    admins = result.scalars().all()
    admin_ids = [str(a.id) for a in admins]
    if not admin_ids:
        return

    try:
        ntype = NotificationType(notification_type)
    except ValueError:
        ntype = NotificationType.announcement

    for admin_id in admin_ids:
        db.add(Notification(
            user_id=admin_id,
            type=ntype,
            title=title,
            body=body,
            data=json.dumps(data or {}),
        ))
    await db.flush()
    await _send_push_to_users(db, admin_ids, title, body, data or {})


async def send_channel_members_notification(
    db: AsyncSession,
    channel_id: str,
    title: str,
    body: str,
    notification_type: str,
    data: dict = None,
    exclude_user_id: str = None,
):
    """Notify students who joined a community channel."""
    result = await db.execute(
        select(StudentProfile).where(StudentProfile.community_channel_id == channel_id)
    )
    profiles = result.scalars().all()
    user_ids = [
        str(p.user_id) for p in profiles
        if not exclude_user_id or str(p.user_id) != exclude_user_id
    ]
    if not user_ids:
        return

    try:
        ntype = NotificationType(notification_type)
    except ValueError:
        ntype = NotificationType.community_mention

    for uid in user_ids:
        db.add(Notification(
            user_id=uid,
            type=ntype,
            title=title,
            body=body,
            data=json.dumps(data or {}),
        ))
    await db.flush()
    await _send_push_to_users(db, user_ids, title, body, data or {})


async def send_subject_notification(
    db: AsyncSession,
    subject: str,
    title: str,
    body: str,
    notification_type: str,
    data: dict = None,
):
    """
    Send push + in-app notifications ONLY to students who selected the given subject.
    Uses flexible matching (e.g. "Maths" in profile matches "Mathematics" class).
    """
    result = await db.execute(select(StudentProfile))
    profiles = result.scalars().all()
    student_ids = [
        str(p.user_id) for p in profiles
        if p.selected_subjects and subject_matches(subject, list(p.selected_subjects))
    ]

    try:
        ntype = NotificationType(notification_type)
    except ValueError:
        ntype = NotificationType.cbt_reminder

    # Save in-app notifications
    for student_id in student_ids:
        notification = Notification(
            user_id=student_id,
            type=ntype,
            title=title,
            body=body,
            data=json.dumps(data or {}),
        )
        db.add(notification)

    await db.flush()

    # Send push notifications via FCM
    await _send_push_to_users(db, student_ids, title, body, data or {})


def _is_unregistered_token_error(error: Exception) -> bool:
    if isinstance(error, messaging.UnregisteredError):
        return True
    code = str(getattr(error, "code", "") or "").lower()
    name = error.__class__.__name__.lower()
    message = str(error).lower()
    return (
        "unregistered" in name
        or code in {"unregistered", "registration-token-not-registered"}
        or "registration token is not registered" in message
    )


async def _send_push_to_users(db: AsyncSession, user_ids: list, title: str, body: str, data: dict):
    init_firebase()
    if not _firebase_initialized:
        return

    result = await db.execute(
        select(DeviceToken).where(DeviceToken.user_id.in_(user_ids))
    )
    tokens = result.scalars().all()

    fcm_tokens = [t.token for t in tokens]
    if not fcm_tokens:
        return

    # Batch send (FCM supports up to 500 per batch)
    for i in range(0, len(fcm_tokens), 500):
        batch = fcm_tokens[i:i + 500]
        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in data.items()},
            tokens=batch,
            android=messaging.AndroidConfig(priority="high"),
            apns=messaging.APNSConfig(headers={"apns-priority": "10"}),
        )
        response = messaging.send_each_for_multicast(message)
        invalid_tokens = [
            token
            for token, send_response in zip(batch, response.responses)
            if not send_response.success
            and send_response.exception is not None
            and _is_unregistered_token_error(send_response.exception)
        ]
        if invalid_tokens:
            await db.execute(
                delete(DeviceToken).where(DeviceToken.token.in_(invalid_tokens))
            )
            await db.flush()


async def send_users_notification(
    db: AsyncSession,
    user_ids: list[str],
    title: str,
    body: str,
    notification_type: str,
    data: dict = None,
    exclude_user_id: str = None,
):
    """Notify a specific set of users (in-app + push), without duplicates."""
    recipients = list(dict.fromkeys(
        str(user_id) for user_id in user_ids
        if user_id and (
            not exclude_user_id or str(user_id) != str(exclude_user_id)
        )
    ))
    if not recipients:
        return

    try:
        ntype = NotificationType(notification_type)
    except ValueError:
        ntype = NotificationType.announcement

    for user_id in recipients:
        db.add(Notification(
            user_id=user_id,
            type=ntype,
            title=title,
            body=body,
            data=json.dumps(data or {}),
        ))
    await db.flush()
    await _send_push_to_users(db, recipients, title, body, data or {})


async def send_user_notification(
    db: AsyncSession,
    user_id: str,
    title: str,
    body: str,
    notification_type: str,
    data: dict = None,
):
    """
    Send a notification to a single specific user.
    """
    # Map string to enum safely
    try:
        ntype = NotificationType(notification_type)
    except ValueError:
        ntype = NotificationType.announcement

    notification = Notification(
        user_id=user_id,
        type=ntype,
        title=title,
        body=body,
        data=json.dumps(data or {}),
    )
    db.add(notification)
    await db.flush()

    await _send_push_to_users(db, [user_id], title, body, data or {})
