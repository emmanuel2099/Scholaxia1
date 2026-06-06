from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import List, Optional
from app.core.database import get_db
from app.core.deps import require_student
from app.models.user import StudentProfile, ExamType, User

router = APIRouter(prefix="/students", tags=["Students"])

SUBJECT_LIMITS = {
    ExamType.JAMB: 4,
    ExamType.WAEC: 9,
    ExamType.NECO: 9,
    ExamType.ALL: 9,
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


@router.post("/setup-exam")
async def setup_exam(
    payload: ExamSetupRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    limit = SUBJECT_LIMITS.get(payload.exam_type, 9)
    if len(payload.subjects) > limit:
        raise HTTPException(status_code=400, detail=f"{payload.exam_type} allows max {limit} subjects")

    result = await db.execute(select(StudentProfile).where(StudentProfile.user_id == current_user["sub"]))
    profile = result.scalar_one_or_none()

    if not profile:
        profile = StudentProfile(user_id=current_user["sub"])
        db.add(profile)

    profile.exam_type = payload.exam_type
    profile.selected_subjects = payload.subjects
    profile.education_level = payload.education_level
    await db.flush()

    return {"message": "Exam setup complete", "subjects": payload.subjects}


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
    )
