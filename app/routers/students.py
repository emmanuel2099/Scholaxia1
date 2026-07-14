from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import List, Optional
from app.core.database import get_db
from app.core.deps import require_student
from app.core.security import create_access_token, create_refresh_token
from app.core.subjects import AVAILABLE_SUBJECTS
from app.models.user import StudentProfile, ExamType, User, UserRole, KindProfile

router = APIRouter(prefix="/students", tags=["Students"])

SUBJECT_LIMITS = {
    ExamType.JAMB: 4,
    ExamType.WAEC: 9,
    ExamType.NECO: 9,
    ExamType.JUNIOR_WAEC: 9,
    ExamType.POST_UTME: 4,
    ExamType.ALL: 9,
}

SUBJECT_MINIMUMS = {
    ExamType.JAMB: 4,
    ExamType.WAEC: 1,
    ExamType.NECO: 1,
    ExamType.JUNIOR_WAEC: 1,
    ExamType.POST_UTME: 4,
    ExamType.ALL: 1,
}


def _norm_level(level: str) -> str:
    return (level or "").strip().upper().replace(" ", "").replace("-", "")


def _is_primary_6(level: str) -> bool:
    n = _norm_level(level)
    return n in ("PRIMARY6", "PRIMARY06", "P6", "PRY6")


def _is_jss_level(level: str) -> bool:
    n = _norm_level(level)
    return n.startswith("JSS")


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
    profile_picture: Optional[str] = None


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
        "exam_type": profile.exam_type.value if profile and profile.exam_type else None,
        "selected_subjects": profile.selected_subjects if profile else [],
        "subject_limit": SUBJECT_LIMITS.get(profile.exam_type, 9) if profile and profile.exam_type else None,
    }


@router.post("/setup-exam")
async def setup_exam(
    payload: ExamSetupRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    exam_type = payload.exam_type
    # JSS1–3 → Junior WAEC CBT (admin uploads JUNIOR_WAEC exams).
    if _is_jss_level(payload.education_level):
        exam_type = ExamType.JUNIOR_WAEC

    # Primary 6 (and below path) → kids app (Common Entrance CBT lives there).
    if _is_primary_6(payload.education_level):
        user_res = await db.execute(select(User).where(User.id == current_user["sub"]))
        user = user_res.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        user.role = UserRole.kind
        kp_res = await db.execute(select(KindProfile).where(KindProfile.user_id == user.id))
        if not kp_res.scalar_one_or_none():
            db.add(
                KindProfile(
                    user_id=user.id,
                    age_group="9-12",
                    grade_level="Primary 6",
                )
            )
        await db.flush()
        access = create_access_token(str(user.id), UserRole.kind.value)
        refresh = create_refresh_token(str(user.id))
        return {
            "message": "Primary 6 uses the Kids app — Common Entrance CBT is there.",
            "redirect": "kind",
            "role": "kind",
            "access_token": access,
            "refresh_token": refresh,
            "setup_complete": True,
            "education_level": payload.education_level,
        }

    limit = SUBJECT_LIMITS.get(exam_type, 9)
    minimum = SUBJECT_MINIMUMS.get(exam_type, 1)
    if len(payload.subjects) > limit:
        raise HTTPException(status_code=400, detail=f"{exam_type.value} allows max {limit} subjects")
    if len(payload.subjects) < minimum:
        raise HTTPException(status_code=400, detail=f"{exam_type.value} requires {minimum} subject(s)")

    # Deduplicate while preserving order
    seen = set()
    subjects = []
    for s in payload.subjects:
        key = s.strip()
        if key and key not in seen:
            seen.add(key)
            subjects.append(key)

    if exam_type == ExamType.JAMB and len(subjects) != 4:
        raise HTTPException(status_code=400, detail="JAMB requires exactly 4 subjects")
    if exam_type == ExamType.POST_UTME and len(subjects) != 4:
        raise HTTPException(status_code=400, detail="POST-UTME requires exactly 4 subjects")

    result = await db.execute(select(StudentProfile).where(StudentProfile.user_id == current_user["sub"]))
    profile = result.scalar_one_or_none()

    if not profile:
        profile = StudentProfile(user_id=current_user["sub"])
        db.add(profile)

    profile.exam_type = exam_type
    profile.selected_subjects = subjects
    profile.education_level = payload.education_level
    await db.flush()

    return {
        "message": "Exam setup complete",
        "exam_type": exam_type.value,
        "subjects": subjects,
        "education_level": payload.education_level,
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
        exam_type=profile.exam_type.value if profile.exam_type else None,
        selected_subjects=profile.selected_subjects or [],
        education_level=profile.education_level,
        has_active_subscription=profile.has_active_subscription,
        setup_complete=bool(
            profile.exam_type
            and profile.selected_subjects
            and len(profile.selected_subjects) >= SUBJECT_MINIMUMS.get(profile.exam_type, 1)
        ),
        profile_picture=user.profile_picture,
    )
