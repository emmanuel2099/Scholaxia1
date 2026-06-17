from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import List, Optional
from app.core.database import get_db
from app.core.deps import require_student
from app.core.subjects import AVAILABLE_SUBJECTS
from app.models.user import StudentProfile, ExamType, User

router = APIRouter(prefix="/students", tags=["Students"])

SUBJECT_LIMITS = {
    ExamType.JAMB: 4,
    ExamType.WAEC: 9,
    ExamType.NECO: 9,
    ExamType.ALL: 9,
}

SUBJECT_MINIMUMS = {
    ExamType.JAMB: 4,
    ExamType.WAEC: 1,
    ExamType.NECO: 1,
    ExamType.ALL: 1,
}


class ExamSetupRequest(BaseModel):
    exam_type: ExamType
    subjects: List[str]
    education_level: str  # JSS1, JSS2, SS1, SS2, SS3, JAMB


class ProfileResponse(BaseModel):
    user_id: str
    full_name: str
    email: str
    exam_type: Optional[str]
    selected_subjects: List[str]
    education_level: Optional[str]
    has_active_subscription: bool
    setup_complete: bool = False


@router.get("/subjects")
async def list_available_subjects():
    """Subjects students can pick during exam setup."""
    return {"subjects": AVAILABLE_SUBJECTS}


@router.get("/setup-status")
async def setup_status(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Returns whether the student has completed exam type + subject selection."""
    result = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == current_user["sub"])
    )
    profile = result.scalar_one_or_none()
    complete = bool(
        profile
        and profile.exam_type
        and profile.selected_subjects
        and len(profile.selected_subjects) >= SUBJECT_MINIMUMS.get(profile.exam_type, 1)
    )
    return {
        "setup_complete": complete,
        "exam_type": str(profile.exam_type) if profile and profile.exam_type else None,
        "selected_subjects": profile.selected_subjects if profile else [],
        "subject_limit": SUBJECT_LIMITS.get(profile.exam_type, 9) if profile and profile.exam_type else None,
    }


@router.post("/setup-exam")
async def setup_exam(
    payload: ExamSetupRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    limit = SUBJECT_LIMITS.get(payload.exam_type, 9)
    minimum = SUBJECT_MINIMUMS.get(payload.exam_type, 1)
    if len(payload.subjects) > limit:
        raise HTTPException(status_code=400, detail=f"{payload.exam_type.value} allows max {limit} subjects")
    if len(payload.subjects) < minimum:
        raise HTTPException(status_code=400, detail=f"{payload.exam_type.value} requires {minimum} subject(s)")

    # Deduplicate while preserving order
    seen = set()
    subjects = []
    for s in payload.subjects:
        key = s.strip()
        if key and key not in seen:
            seen.add(key)
            subjects.append(key)

    if payload.exam_type == ExamType.JAMB and len(subjects) != 4:
        raise HTTPException(status_code=400, detail="JAMB requires exactly 4 subjects")

    result = await db.execute(select(StudentProfile).where(StudentProfile.user_id == current_user["sub"]))
    profile = result.scalar_one_or_none()

    if not profile:
        profile = StudentProfile(user_id=current_user["sub"])
        db.add(profile)

    profile.exam_type = payload.exam_type
    profile.selected_subjects = subjects
    profile.education_level = payload.education_level
    await db.flush()

    return {
        "message": "Exam setup complete",
        "exam_type": payload.exam_type.value,
        "subjects": subjects,
        "setup_complete": True,
    }


@router.get("/me", response_model=ProfileResponse)
async def get_my_profile(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User).where(User.id == current_user["sub"])
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # Get or create student profile
    p_result = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == user.id)
    )
    profile = p_result.scalar_one_or_none()
    if not profile:
        profile = StudentProfile(user_id=user.id, selected_subjects=[])
        db.add(profile)
        await db.flush()

    return ProfileResponse(
        user_id=str(user.id),
        full_name=user.full_name,
        email=user.email,
        exam_type=str(profile.exam_type) if profile.exam_type else None,
        selected_subjects=profile.selected_subjects or [],
        education_level=profile.education_level,
        has_active_subscription=profile.has_active_subscription,
        setup_complete=bool(
            profile.exam_type
            and profile.selected_subjects
            and len(profile.selected_subjects) >= SUBJECT_MINIMUMS.get(profile.exam_type, 1)
        ),
    )
