from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.exc import DBAPIError, OperationalError
from pydantic import BaseModel
from typing import List, Optional
from uuid import UUID
import asyncio
import logging
from app.core.database import get_db
from app.core.deps import require_student
from app.core.security import create_access_token, create_refresh_token, issue_auth_tokens
from app.core.subjects import AVAILABLE_SUBJECTS
from app.models.user import StudentProfile, ExamType, User, UserRole, KindProfile

router = APIRouter(prefix="/students", tags=["Students"])
log = logging.getLogger(__name__)

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
    ExamType.WAEC: 9,
    ExamType.NECO: 9,
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
    return n == "JSS3"


def _is_common_entrance_level(level: str) -> bool:
    n = _norm_level(level)
    return n in ("COMMONENTRANCE", "COMMON_ENTRANCE", "CE")


class ExamSetupRequest(BaseModel):
    education_level: str  # JSS1, JSS2, SS1, SS2, SS3, JAMB
    # Legacy single-board fields (still accepted)
    exam_type: Optional[ExamType] = None
    subjects: Optional[List[str]] = None
    # Dual-board (SS students can select JAMB + WAEC/NECO)
    enable_jamb: Optional[bool] = None
    enable_ssce: Optional[bool] = None
    jamb_subjects: Optional[List[str]] = None
    ssce_exam_type: Optional[str] = None  # WAEC | NECO
    ssce_subjects: Optional[List[str]] = None


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
    jamb_subjects: List[str] = []
    ssce_subjects: List[str] = []
    ssce_exam_type: Optional[str] = None


def _student_user_id(current_user: dict) -> UUID:
    try:
        return UUID(str(current_user.get("sub") or ""))
    except ValueError:
        raise HTTPException(status_code=401, detail="Invalid session. Log in again.")


def _exam_type_value(exam_type) -> str:
    if exam_type is None:
        return ""
    if hasattr(exam_type, "value"):
        return str(exam_type.value)
    return str(exam_type).replace("ExamType.", "").replace("EXAMTYPE.", "")


async def _get_or_create_profile(db: AsyncSession, user_id: UUID) -> StudentProfile:
    result = await db.execute(select(StudentProfile).where(StudentProfile.user_id == user_id))
    profile = result.scalar_one_or_none()
    if not profile:
        profile = StudentProfile(user_id=user_id, selected_subjects=[])
        db.add(profile)
    return profile


def _profile_boards(profile: StudentProfile) -> dict:
    """Resolve jamb / ssce subject lists with legacy fallback."""
    jamb = list(profile.jamb_subjects or [])
    ssce = list(profile.ssce_subjects or [])
    ssce_board = (profile.ssce_exam_type or "").upper().strip() or None
    if ssce_board and ssce_board not in ("WAEC", "NECO", "JUNIOR_WAEC", "COMMON_ENTRANCE"):
        ssce_board = None

    et = profile.exam_type.value if profile.exam_type else None
    selected = list(profile.selected_subjects or [])

    if not jamb and not ssce and selected and et:
        if et == "JAMB":
            jamb = selected
        elif et in ("WAEC", "NECO"):
            ssce = selected
            ssce_board = et
        elif et == "JUNIOR_WAEC":
            ssce = selected
            ssce_board = "JUNIOR_WAEC"
        elif et == "COMMON_ENTRANCE":
            ssce = selected
            ssce_board = "COMMON_ENTRANCE"
        elif et == "ALL":
            # Old ALL rows: treat subjects as shared until re-setup
            jamb = selected[:4] if len(selected) >= 4 else selected
            ssce = selected
            ssce_board = ssce_board or "WAEC"

    if not ssce_board and ssce:
        ssce_board = "WAEC"
    return {
        "jamb_subjects": jamb,
        "ssce_subjects": ssce,
        "ssce_exam_type": ssce_board,
    }


def _setup_complete(profile: StudentProfile | None) -> bool:
    if not profile:
        return False
    boards = _profile_boards(profile)
    if profile.exam_type == ExamType.JUNIOR_WAEC or _is_jss_level(profile.education_level or ""):
        return bool(boards["ssce_subjects"] or profile.selected_subjects)
    has_jamb = len(boards["jamb_subjects"]) == 4
    has_ssce = len(boards["ssce_subjects"]) >= 1
    if has_jamb or has_ssce:
        return True
    return bool(
        profile.exam_type
        and profile.selected_subjects
        and len(profile.selected_subjects) >= SUBJECT_MINIMUMS.get(profile.exam_type, 1)
    )


@router.get("/subjects")
async def list_available_subjects():
    """Subjects students can pick during exam setup."""
    from app.core.subjects import COMMON_ENTRANCE_SUBJECTS
    try:
        subjects = list(AVAILABLE_SUBJECTS)
    except Exception:
        subjects = []
    if not subjects:
        subjects = [
            "Mathematics", "English Language", "Biology", "Chemistry", "Physics",
            "Economics", "Government", "Geography", "Literature in English",
        ]
    return {
        "subjects": subjects,
        "common_entrance_subjects": list(COMMON_ENTRANCE_SUBJECTS),
    }


@router.get("/setup-status")
async def setup_status(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Returns whether the student has completed exam type + subject selection."""
    uid = _student_user_id(current_user)
    result = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == uid)
    )
    profile = result.scalar_one_or_none()
    boards = _profile_boards(profile) if profile else {
        "jamb_subjects": [], "ssce_subjects": [], "ssce_exam_type": None
    }
    return {
        "setup_complete": _setup_complete(profile),
        "exam_type": profile.exam_type.value if profile and profile.exam_type else None,
        "selected_subjects": profile.selected_subjects if profile else [],
        "jamb_subjects": boards["jamb_subjects"],
        "ssce_subjects": boards["ssce_subjects"],
        "ssce_exam_type": boards["ssce_exam_type"],
        "subject_limit": SUBJECT_LIMITS.get(profile.exam_type, 9) if profile and profile.exam_type else None,
    }


@router.post("/setup-exam")
async def setup_exam(
    payload: ExamSetupRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    last_exc: Exception | None = None
    for attempt in range(3):
        try:
            return await _setup_exam_impl(payload, current_user, db)
        except HTTPException:
            raise
        except (OperationalError, DBAPIError) as exc:
            last_exc = exc
            log.warning("setup-exam db retry %s for user %s: %s", attempt + 1, current_user.get("sub"), exc)
            try:
                await db.rollback()
            except Exception:
                pass
            if attempt < 2:
                await asyncio.sleep(0.6 * (attempt + 1))
                continue
        except Exception as exc:
            last_exc = exc
            log.exception("setup-exam failed for user %s", current_user.get("sub"))
            break
    detail = "Could not save exam setup right now. Your subjects were not lost — tap Save again in a minute."
    if last_exc and isinstance(last_exc, (OperationalError, DBAPIError)):
        detail = "Database is waking up — wait 30 seconds and tap Save again."
    raise HTTPException(status_code=500, detail=detail)


def _uniq(items: List[str] | None) -> List[str]:
    seen = set()
    out: List[str] = []
    for s in items or []:
        key = (s or "").strip()
        if key and key not in seen:
            seen.add(key)
            out.append(key)
    return out


async def _setup_exam_impl(
    payload: ExamSetupRequest,
    current_user: dict,
    db: AsyncSession,
):
    user_id = _student_user_id(current_user)
    # Common Entrance — 3 fixed subjects, taken together like JAMB.
    if _is_common_entrance_level(payload.education_level):
        from app.core.subjects import COMMON_ENTRANCE_SUBJECTS
        subjects = _uniq(payload.ssce_subjects or payload.subjects or [])
        if not subjects:
            subjects = list(COMMON_ENTRANCE_SUBJECTS)
        if len(subjects) != 3:
            raise HTTPException(
                status_code=400,
                detail="Common Entrance requires exactly 3 subjects: Mathematics/Quantitative Reasoning, English Language/Verbal Reasoning, and General Knowledge",
            )
        profile = await _get_or_create_profile(db, user_id)
        profile.exam_type = ExamType.WAEC
        profile.selected_subjects = subjects
        profile.jamb_subjects = []
        profile.ssce_subjects = subjects
        profile.ssce_exam_type = "COMMON_ENTRANCE"
        profile.education_level = payload.education_level
        await db.flush()
        return {
            "message": "Exam setup complete",
            "exam_type": "COMMON_ENTRANCE",
            "subjects": subjects,
            "jamb_subjects": [],
            "ssce_subjects": subjects,
            "ssce_exam_type": "COMMON_ENTRANCE",
            "education_level": payload.education_level,
            "setup_complete": True,
        }

    # JSS3 → Junior WAEC CBT (admin uploads JUNIOR_WAEC exams).
    if _is_jss_level(payload.education_level):
        exam_type = ExamType.JUNIOR_WAEC
        subjects = _uniq(payload.ssce_subjects or payload.subjects or [])
        if not subjects:
            raise HTTPException(status_code=400, detail="Select at least one subject for Junior WAEC")
        if len(subjects) > 9:
            raise HTTPException(status_code=400, detail="Junior WAEC allows max 9 subjects")
        profile = await _get_or_create_profile(db, user_id)
        profile.exam_type = exam_type
        profile.selected_subjects = subjects
        profile.jamb_subjects = []
        profile.ssce_subjects = subjects
        profile.ssce_exam_type = "JUNIOR_WAEC"
        profile.education_level = payload.education_level
        await db.flush()
        return {
            "message": "Exam setup complete",
            "exam_type": exam_type.value,
            "subjects": subjects,
            "jamb_subjects": [],
            "ssce_subjects": subjects,
            "ssce_exam_type": "JUNIOR_WAEC",
            "education_level": payload.education_level,
            "setup_complete": True,
        }

    # Primary 6 (and below path) → kids app (Common Entrance CBT lives there).
    if _is_primary_6(payload.education_level):
        user_res = await db.execute(select(User).where(User.id == user_id))
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
        access, refresh = await issue_auth_tokens(db, user)
        return {
            "message": "Primary 6 uses the Kids app — Common Entrance CBT is there.",
            "redirect": "kind",
            "role": "kind",
            "access_token": access,
            "refresh_token": refresh,
            "setup_complete": True,
            "education_level": payload.education_level,
        }

    # Dual-board setup (SS / JAMB prep)
    use_dual = (
        payload.enable_jamb is not None
        or payload.enable_ssce is not None
        or payload.jamb_subjects is not None
        or payload.ssce_subjects is not None
    )

    if use_dual:
        enable_jamb = bool(payload.enable_jamb) or bool(payload.jamb_subjects)
        enable_ssce = bool(payload.enable_ssce) or bool(payload.ssce_subjects)
        if not enable_jamb and not enable_ssce:
            # Fall back to legacy fields if dual flags empty
            if payload.exam_type and payload.subjects:
                use_dual = False
            else:
                raise HTTPException(
                    status_code=400,
                    detail="Select JAMB and/or WAEC/NECO, then choose subjects for each.",
                )

    if use_dual:
        jamb = _uniq(payload.jamb_subjects) if enable_jamb else []
        ssce = _uniq(payload.ssce_subjects) if enable_ssce else []
        ssce_board = (payload.ssce_exam_type or "WAEC").upper().strip()
        if enable_ssce and ssce_board not in ("WAEC", "NECO", "COMMON_ENTRANCE"):
            raise HTTPException(status_code=400, detail="SSCE board must be WAEC, NECO, or COMMON_ENTRANCE")
        if enable_jamb and len(jamb) != 4:
            raise HTTPException(status_code=400, detail="JAMB requires exactly 4 subjects")
        if enable_ssce and len(ssce) != 9:
            raise HTTPException(status_code=400, detail="WAEC/NECO requires exactly 9 subjects")

        if enable_jamb and enable_ssce:
            exam_type = ExamType.ALL
        elif enable_jamb:
            exam_type = ExamType.JAMB
            ssce_board = None
        else:
            exam_type = ExamType.WAEC if ssce_board == "WAEC" else ExamType.NECO

        # Union for legacy consumers
        merged = _uniq([*jamb, *ssce])

        profile = await _get_or_create_profile(db, user_id)
        profile.exam_type = exam_type
        profile.selected_subjects = merged
        profile.jamb_subjects = jamb or None
        profile.ssce_subjects = ssce or None
        profile.ssce_exam_type = ssce_board if enable_ssce else None
        profile.education_level = payload.education_level
        await db.flush()
        return {
            "message": "Exam setup complete",
            "exam_type": exam_type.value,
            "subjects": merged,
            "jamb_subjects": jamb,
            "ssce_subjects": ssce,
            "ssce_exam_type": ssce_board if enable_ssce else None,
            "education_level": payload.education_level,
            "setup_complete": True,
        }

    # Legacy single-board path
    if not payload.exam_type or payload.subjects is None:
        raise HTTPException(status_code=400, detail="exam_type and subjects are required")
    exam_type = payload.exam_type
    limit = SUBJECT_LIMITS.get(exam_type, 9)
    minimum = SUBJECT_MINIMUMS.get(exam_type, 1)
    subjects = _uniq(payload.subjects)
    if len(subjects) > limit:
        raise HTTPException(status_code=400, detail=f"{exam_type.value} allows max {limit} subjects")
    if len(subjects) < minimum:
        raise HTTPException(status_code=400, detail=f"{exam_type.value} requires {minimum} subject(s)")
    if exam_type == ExamType.JAMB and len(subjects) != 4:
        raise HTTPException(status_code=400, detail="JAMB requires exactly 4 subjects")
    if exam_type in (ExamType.WAEC, ExamType.NECO) and len(subjects) != 9:
        raise HTTPException(status_code=400, detail="WAEC/NECO requires exactly 9 subjects")
    if exam_type == ExamType.POST_UTME and len(subjects) != 4:
        raise HTTPException(status_code=400, detail="POST-UTME requires exactly 4 subjects")

    profile = await _get_or_create_profile(db, user_id)

    profile.exam_type = exam_type
    profile.selected_subjects = subjects
    profile.education_level = payload.education_level
    if exam_type == ExamType.JAMB:
        profile.jamb_subjects = subjects
        profile.ssce_subjects = None
        profile.ssce_exam_type = None
    elif exam_type in (ExamType.WAEC, ExamType.NECO):
        profile.jamb_subjects = None
        profile.ssce_subjects = subjects
        profile.ssce_exam_type = exam_type.value
    elif exam_type == ExamType.JUNIOR_WAEC:
        profile.jamb_subjects = None
        profile.ssce_subjects = subjects
        profile.ssce_exam_type = "JUNIOR_WAEC"
    await db.flush()

    return {
        "message": "Exam setup complete",
        "exam_type": exam_type.value,
        "subjects": subjects,
        "jamb_subjects": profile.jamb_subjects or [],
        "ssce_subjects": profile.ssce_subjects or [],
        "ssce_exam_type": profile.ssce_exam_type,
        "education_level": payload.education_level,
        "setup_complete": True,
    }


@router.get("/me", response_model=ProfileResponse)
async def get_my_profile(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    try:
        uid = _student_user_id(current_user)
        result = await db.execute(
            select(User).where(User.id == uid)
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

        boards = _profile_boards(profile)
        exam_type = None
        if profile.exam_type is not None:
            exam_type = (
                profile.exam_type.value
                if hasattr(profile.exam_type, "value")
                else str(profile.exam_type)
            )
            exam_type = exam_type.replace("ExamType.", "").replace("EXAMTYPE.", "")
        return ProfileResponse(
            user_id=str(user.id),
            full_name=str(user.full_name or "Student"),
            email=str(user.email or ""),
            exam_type=exam_type,
            selected_subjects=list(profile.selected_subjects or []),
            education_level=profile.education_level,
            has_active_subscription=bool(getattr(profile, "has_active_subscription", False)),
            setup_complete=_setup_complete(profile),
            profile_picture=user.profile_picture,
            jamb_subjects=list(boards.get("jamb_subjects") or []),
            ssce_subjects=list(boards.get("ssce_subjects") or []),
            ssce_exam_type=boards.get("ssce_exam_type"),
        )
    except HTTPException:
        raise
    except Exception:
        import logging
        logging.getLogger(__name__).exception("students/me failed for %s", current_user.get("sub"))
        # Never 500 the profile page — return a safe empty profile so the app can still save subjects.
        return ProfileResponse(
            user_id=str(current_user.get("sub") or ""),
            full_name="Student",
            email="",
            exam_type=None,
            selected_subjects=[],
            education_level=None,
            has_active_subscription=False,
            setup_complete=False,
            profile_picture=None,
            jamb_subjects=[],
            ssce_subjects=[],
            ssce_exam_type=None,
        )
