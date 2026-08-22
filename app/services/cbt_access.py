"""Paid annual CBT access and purchase-time subject locking."""
from __future__ import annotations

import json
import logging
import uuid
from datetime import timedelta
from typing import Any

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.cbt_packages import get_cbt_package
from app.core.database import engine
from app.core.datetime_utils import naive_utc_now
from app.models.payment import StudentEntitlement
from app.models.user import StudentProfile

logger = logging.getLogger(__name__)

ENTITLEMENT_TYPE = "cbt_package"


def _as_uuid(value) -> uuid.UUID:
    if isinstance(value, uuid.UUID):
        return value
    return uuid.UUID(str(value))


def normalize_board(value: str | None) -> str:
    board = (value or "").upper().strip().replace(" ", "_")
    if "JUNIOR" in board or board in {"BECE", "JSSCE"}:
        return "JUNIOR_WAEC"
    if "COMMON" in board or board in {"CE", "COMMONENTRANCE"}:
        return "COMMON_ENTRANCE"
    if "JAMB" in board or "UTME" in board:
        return "JAMB"
    if "NECO" in board:
        return "NECO"
    if "WAEC" in board or "WASSCE" in board:
        return "WAEC"
    return board


def _normalized_subjects(values: list | None) -> list[str]:
    return sorted(
        {
            " ".join(str(value).lower().strip().split())
            for value in (values or [])
            if str(value).strip()
        }
    )


def subject_snapshot(profile: StudentProfile | None) -> dict[str, Any]:
    if not profile:
        return {
            "jamb_subjects": [],
            "ssce_subjects": [],
            "ssce_exam_type": None,
        }
    return {
        "jamb_subjects": list(profile.jamb_subjects or []),
        "ssce_subjects": list(profile.ssce_subjects or profile.selected_subjects or []),
        "ssce_exam_type": normalize_board(profile.ssce_exam_type),
    }


def _snapshot_matches(
    board: str,
    details: dict | None,
    current: dict[str, Any],
) -> bool:
    # Existing purchases made before subject locking are grandfathered.
    if not details:
        return True
    key = "jamb_subjects" if board == "JAMB" else "ssce_subjects"
    return _normalized_subjects(details.get(key)) == _normalized_subjects(current.get(key))


async def ensure_student_entitlements_schema() -> None:
    """Create / patch student_entitlements so coupon + Paystack grants never hit ProgrammingError."""
    stmts = (
        """
        CREATE TABLE IF NOT EXISTS student_entitlements (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            student_id UUID NOT NULL REFERENCES users(id),
            entitlement_type VARCHAR(40) NOT NULL,
            entitlement_key VARCHAR(120) NOT NULL,
            payment_id UUID NULL REFERENCES payments(id),
            granted_at TIMESTAMP DEFAULT NOW(),
            expires_at TIMESTAMP NULL,
            details JSON NULL
        )
        """,
        "ALTER TABLE student_entitlements ADD COLUMN IF NOT EXISTS entitlement_type VARCHAR(40)",
        "ALTER TABLE student_entitlements ADD COLUMN IF NOT EXISTS entitlement_key VARCHAR(120)",
        "ALTER TABLE student_entitlements ADD COLUMN IF NOT EXISTS payment_id UUID NULL",
        "ALTER TABLE student_entitlements ADD COLUMN IF NOT EXISTS granted_at TIMESTAMP DEFAULT NOW()",
        "ALTER TABLE student_entitlements ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP NULL",
        "ALTER TABLE student_entitlements ADD COLUMN IF NOT EXISTS details JSON NULL",
        "CREATE INDEX IF NOT EXISTS ix_student_entitlements_student_id ON student_entitlements (student_id)",
        "CREATE INDEX IF NOT EXISTS ix_student_entitlements_type ON student_entitlements (entitlement_type)",
        "CREATE INDEX IF NOT EXISTS ix_student_entitlements_key ON student_entitlements (entitlement_key)",
    )
    try:
        async with engine.begin() as conn:
            for stmt in stmts:
                try:
                    await conn.execute(text(stmt))
                except Exception as exc:
                    logger.warning("student_entitlements schema stmt skipped: %s", exc)
    except Exception as exc:
        logger.warning("ensure_student_entitlements_schema failed: %s", exc)


async def active_cbt_access(
    db: AsyncSession,
    user_id: str,
) -> dict[str, Any]:
    now = naive_utc_now()
    try:
        student_uuid = _as_uuid(user_id)
    except Exception:
        student_uuid = user_id

    profile = None
    try:
        profile = (
            await db.execute(select(StudentProfile).where(StudentProfile.user_id == student_uuid))
        ).scalar_one_or_none()
    except Exception:
        logger.warning("active_cbt_access: could not load student profile", exc_info=True)
    current = subject_snapshot(profile)

    from app.models.user import User
    from app.models.school_campus import SchoolCampus

    try:
        user = (await db.execute(select(User).where(User.id == student_uuid))).scalar_one_or_none()
        if user and getattr(user, "school_id", None):
            campus = (
                await db.execute(select(SchoolCampus).where(SchoolCampus.id == user.school_id))
            ).scalar_one_or_none()
            if campus and getattr(campus, "subscription_active", False):
                boards = {"JAMB", "WAEC", "NECO", "JUNIOR_WAEC", "COMMON_ENTRANCE"}
                return {
                    "has_access": True,
                    "boards": sorted(boards),
                    "subject_change_boards": [],
                    "subject_change_requires_payment": False,
                    "active_packages": [{
                        "package_id": "school_subscription",
                        "name": campus.subscription_plan or "School plan",
                        "boards": sorted(boards),
                        "valid_boards": sorted(boards),
                        "changed_boards": [],
                        "expires_at": None,
                    }],
                    "current_subjects": current,
                    "via_school": True,
                }
    except Exception:
        logger.warning("active_cbt_access: school check failed", exc_info=True)

    await ensure_student_entitlements_schema()

    entitlements = []
    try:
        entitlements = (
            await db.execute(
                select(StudentEntitlement)
                .where(
                    StudentEntitlement.student_id == student_uuid,
                    StudentEntitlement.entitlement_type == ENTITLEMENT_TYPE,
                    StudentEntitlement.expires_at > now,
                )
                .order_by(StudentEntitlement.expires_at.desc())
            )
        ).scalars().all()
    except Exception:
        logger.warning("active_cbt_access: entitlement query failed", exc_info=True)
        entitlements = []

    boards: set[str] = set()
    changed_boards: set[str] = set()
    active: list[dict[str, Any]] = []
    for entitlement in entitlements:
        package = get_cbt_package(entitlement.entitlement_key)
        if not package:
            continue
        valid_boards: list[str] = []
        invalid_boards: list[str] = []
        for raw_board in package.boards:
            board = normalize_board(raw_board)
            if _snapshot_matches(board, entitlement.details, current):
                boards.add(board)
                valid_boards.append(board)
            else:
                changed_boards.add(board)
                invalid_boards.append(board)
        active.append(
            {
                "package_id": package.id,
                "name": package.name,
                "boards": list(package.boards),
                "valid_boards": valid_boards,
                "changed_boards": invalid_boards,
                "expires_at": entitlement.expires_at.isoformat()
                if entitlement.expires_at
                else None,
            }
        )

    changed_boards -= boards
    return {
        "has_access": bool(boards),
        "boards": sorted(boards),
        "subject_change_boards": sorted(changed_boards),
        "subject_change_requires_payment": bool(changed_boards),
        "active_packages": active,
        "current_subjects": current,
    }


async def grant_cbt_package(
    db: AsyncSession,
    user_id: str,
    package_id: str,
    *,
    payment_id=None,
) -> StudentEntitlement | dict:
    """Grant or extend a CBT package without requiring a live Paystack payment."""
    package = get_cbt_package(package_id)
    if not package:
        raise ValueError("Unknown CBT package")

    await ensure_student_entitlements_schema()

    student_uuid = _as_uuid(user_id)
    pay_uuid = _as_uuid(payment_id) if payment_id else None
    now = naive_utc_now()
    details = {"jamb_subjects": [], "ssce_subjects": [], "ssce_exam_type": None}

    # Use SAVEPOINTs so a failed SELECT/INSERT cannot abort the outer redeem transaction
    try:
        async with db.begin_nested():
            profile = (
                await db.execute(
                    select(StudentProfile).where(StudentProfile.user_id == student_uuid)
                )
            ).scalar_one_or_none()
            details = subject_snapshot(profile)
    except Exception:
        logger.warning("grant_cbt_package: profile load skipped", exc_info=True)

    start = now
    try:
        async with db.begin_nested():
            res = await db.execute(
                text(
                    """
                    SELECT expires_at FROM student_entitlements
                    WHERE student_id = CAST(:sid AS uuid)
                      AND entitlement_type = :etype
                      AND entitlement_key = :ekey
                      AND expires_at IS NOT NULL
                      AND expires_at > :now
                    ORDER BY expires_at DESC
                    LIMIT 1
                    """
                ),
                {
                    "sid": str(student_uuid),
                    "etype": ENTITLEMENT_TYPE,
                    "ekey": package_id,
                    "now": now,
                },
            )
            row = res.first()
            if row and row[0]:
                start = row[0]
    except Exception:
        logger.warning("grant_cbt_package: active lookup skipped", exc_info=True)

    expires = start + timedelta(days=package.duration_days)
    new_id = uuid.uuid4()

    inserted = False
    last_err: Exception | None = None

    # Prefer the simplest insert first (fewest columns / least schema risk)
    for attempt, sql, params in (
        (
            "minimal",
            """
            INSERT INTO student_entitlements (
                id, student_id, entitlement_type, entitlement_key, granted_at, expires_at
            ) VALUES (
                CAST(:id AS uuid), CAST(:sid AS uuid), :etype, :ekey, :gat, :exp
            )
            """,
            {
                "id": str(new_id),
                "sid": str(student_uuid),
                "etype": ENTITLEMENT_TYPE,
                "ekey": package_id,
                "gat": now,
                "exp": expires,
            },
        ),
        (
            "with_payment",
            """
            INSERT INTO student_entitlements (
                id, student_id, entitlement_type, entitlement_key,
                payment_id, granted_at, expires_at
            ) VALUES (
                CAST(:id AS uuid), CAST(:sid AS uuid), :etype, :ekey,
                CAST(:pid AS uuid), :gat, :exp
            )
            """,
            {
                "id": str(new_id),
                "sid": str(student_uuid),
                "etype": ENTITLEMENT_TYPE,
                "ekey": package_id,
                "pid": str(pay_uuid) if pay_uuid else None,
                "gat": now,
                "exp": expires,
            },
        ),
    ):
        try:
            async with db.begin_nested():
                await db.execute(text(sql), params)
            inserted = True
            break
        except Exception as exc:
            last_err = exc
            logger.warning("grant insert %s failed: %s", attempt, exc)

    if not inserted:
        raise RuntimeError(str(getattr(last_err, "orig", None) or last_err)[:220])

    # Best-effort: attach subject snapshot (never fail the grant)
    try:
        async with db.begin_nested():
            await db.execute(
                text(
                    """
                    UPDATE student_entitlements
                    SET details = CAST(:details AS json)
                    WHERE id = CAST(:id AS uuid)
                    """
                ),
                {"id": str(new_id), "details": json.dumps(details)},
            )
    except Exception:
        logger.warning("grant_cbt_package: details update skipped", exc_info=True)

    try:
        await db.flush()
    except Exception:
        pass

    try:
        async with db.begin_nested():
            ent = (
                await db.execute(select(StudentEntitlement).where(StudentEntitlement.id == new_id))
            ).scalar_one_or_none()
            if ent:
                return ent
    except Exception:
        pass

    return {
        "id": str(new_id),
        "student_id": str(student_uuid),
        "entitlement_type": ENTITLEMENT_TYPE,
        "entitlement_key": package_id,
        "expires_at": expires.isoformat() if hasattr(expires, "isoformat") else str(expires),
    }



async def has_board_access(
    db: AsyncSession,
    user_id: str,
    board: str,
) -> bool:
    access = await active_cbt_access(db, user_id)
    return normalize_board(board) in set(access["boards"])
