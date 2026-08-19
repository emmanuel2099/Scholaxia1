"""Paid annual CBT access and purchase-time subject locking."""
from __future__ import annotations

from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from datetime import timedelta

from app.core.cbt_packages import get_cbt_package
from app.core.datetime_utils import naive_utc_now
from app.models.payment import StudentEntitlement
from app.models.user import StudentProfile


ENTITLEMENT_TYPE = "cbt_package"


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


async def active_cbt_access(
    db: AsyncSession,
    user_id: str,
) -> dict[str, Any]:
    now = naive_utc_now()
    profile = (
        await db.execute(select(StudentProfile).where(StudentProfile.user_id == user_id))
    ).scalar_one_or_none()
    current = subject_snapshot(profile)
    entitlements = (
        await db.execute(
            select(StudentEntitlement)
            .where(
                StudentEntitlement.student_id == user_id,
                StudentEntitlement.entitlement_type == ENTITLEMENT_TYPE,
                StudentEntitlement.expires_at > now,
            )
            .order_by(StudentEntitlement.expires_at.desc())
        )
    ).scalars().all()

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
) -> StudentEntitlement:
    """Grant or extend a CBT package without requiring a live Paystack payment."""
    package = get_cbt_package(package_id)
    if not package:
        raise ValueError("Unknown CBT package")
    now = naive_utc_now()
    active_res = await db.execute(
        select(StudentEntitlement)
        .where(
            StudentEntitlement.student_id == user_id,
            StudentEntitlement.entitlement_type == ENTITLEMENT_TYPE,
            StudentEntitlement.entitlement_key == package_id,
            StudentEntitlement.expires_at > now,
        )
        .order_by(StudentEntitlement.expires_at.desc())
        .limit(1)
    )
    active = active_res.scalar_one_or_none()
    start = active.expires_at if active else now
    profile = (
        await db.execute(select(StudentProfile).where(StudentProfile.user_id == user_id))
    ).scalar_one_or_none()
    row = StudentEntitlement(
        student_id=user_id,
        entitlement_type=ENTITLEMENT_TYPE,
        entitlement_key=package_id,
        payment_id=payment_id,
        granted_at=now,
        expires_at=start + timedelta(days=package.duration_days),
        details=subject_snapshot(profile),
    )
    db.add(row)
    await db.flush()
    return row


async def has_board_access(
    db: AsyncSession,
    user_id: str,
    board: str,
) -> bool:
    access = await active_cbt_access(db, user_id)
    return normalize_board(board) in set(access["boards"])
