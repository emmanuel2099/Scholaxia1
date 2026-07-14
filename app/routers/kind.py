"""
Kind (young learner) API + Sia Kind AI.
Role: student | teacher | kind
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel, Field, EmailStr
from typing import Optional, List

from app.core.database import get_db
from app.core.deps import require_kind, get_current_user
from app.models.user import User, KindProfile
from app.ai.kind_prompt_builder import KIND_SUBJECTS, AGE_GROUPS
from app.ai.board_parser import extract_board_content
from app.services.kind_ai_service import kind_chat, kind_lesson, kind_quiz, kind_homework_help

router = APIRouter(tags=["Kind — Young Learners"])


# ── Profile schemas ───────────────────────────────────────────────────────────

class KindProfileUpdate(BaseModel):
    age_group: Optional[str] = None
    grade_level: Optional[str] = None
    parent_email: Optional[EmailStr] = None
    favorite_subjects: Optional[List[str]] = None
    learning_goals: Optional[str] = None
    preferred_language: Optional[str] = None


class KindChatRequest(BaseModel):
    question: str = Field(..., min_length=1, max_length=2000)
    subject: str = "General"
    language: str = "english"
    conversation_history: Optional[list] = None


class KindLessonRequest(BaseModel):
    topic: str = Field(..., min_length=1, max_length=500)
    subject: str = "General"
    language: str = "english"


class KindQuizRequest(BaseModel):
    topic: str = Field(..., min_length=1, max_length=300)
    subject: str = "General"
    num_questions: int = Field(default=5, ge=3, le=10)


class KindHomeworkRequest(BaseModel):
    question: str = Field(..., min_length=1, max_length=2000)
    subject: str = "General"
    child_attempt: Optional[str] = None


async def _get_kind_profile(user_id: str, db: AsyncSession) -> KindProfile:
    result = await db.execute(select(KindProfile).where(KindProfile.user_id == user_id))
    profile = result.scalar_one_or_none()
    if not profile:
        raise HTTPException(status_code=404, detail="Kind profile not found")
    return profile


async def _get_child_name(user_id: str, db: AsyncSession) -> str:
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if user and user.full_name:
        parts = user.full_name.strip().split()
        if parts:
            return parts[0]
    return "friend"


def _profile_dict(profile: KindProfile, user: User) -> dict:
    return {
        "user_id": str(user.id),
        "full_name": user.full_name,
        "email": user.email,
        "role": "kind",
        "age_group": profile.age_group,
        "grade_level": profile.grade_level,
        "parent_email": profile.parent_email,
        "favorite_subjects": profile.favorite_subjects or [],
        "learning_goals": profile.learning_goals,
        "preferred_language": profile.preferred_language,
        "profile_picture": user.profile_picture,
    }


# ── Profile ───────────────────────────────────────────────────────────────────

@router.get("/kind/me")
async def get_kind_profile(
    current_user: dict = Depends(require_kind),
    db: AsyncSession = Depends(get_db),
):
    """GET /api/v1/kind/me — young learner profile."""
    user_res = await db.execute(select(User).where(User.id == current_user["sub"]))
    user = user_res.scalar_one_or_none()
    profile = await _get_kind_profile(current_user["sub"], db)
    return _profile_dict(profile, user)


@router.patch("/kind/profile")
async def update_kind_profile(
    payload: KindProfileUpdate,
    current_user: dict = Depends(require_kind),
    db: AsyncSession = Depends(get_db),
):
    """PATCH /api/v1/kind/profile"""
    profile = await _get_kind_profile(current_user["sub"], db)
    if payload.age_group:
        if payload.age_group not in AGE_GROUPS:
            raise HTTPException(status_code=400, detail=f"age_group must be one of {AGE_GROUPS}")
        profile.age_group = payload.age_group
    if payload.grade_level is not None:
        profile.grade_level = payload.grade_level
    if payload.parent_email is not None:
        profile.parent_email = payload.parent_email
    if payload.favorite_subjects is not None:
        profile.favorite_subjects = payload.favorite_subjects
    if payload.learning_goals is not None:
        profile.learning_goals = payload.learning_goals
    if payload.preferred_language is not None:
        profile.preferred_language = payload.preferred_language
    await db.flush()

    user_res = await db.execute(select(User).where(User.id == current_user["sub"]))
    user = user_res.scalar_one()
    return _profile_dict(profile, user)


@router.get("/kind/subjects")
async def kind_subjects():
    """Kid-friendly subject list."""
    return {"subjects": KIND_SUBJECTS, "age_groups": AGE_GROUPS}


# ── Sia Kind AI (enhanced intelligence) ───────────────────────────────────────

@router.post("/kind/sia/chat")
async def sia_kind_chat(
    payload: KindChatRequest,
    current_user: dict = Depends(require_kind),
    db: AsyncSession = Depends(get_db),
):
    """
    POST /api/v1/kind/sia/chat
    Sia Kind — advanced teaching AI for children.
  Uses multi-model fallback (Gemini → OpenAI → DeepSeek → Groq).
    """
    try:
        profile = await _get_kind_profile(current_user["sub"], db)
        name = await _get_child_name(current_user["sub"], db)
        answer = await kind_chat(
            question=payload.question,
            subject=payload.subject,
            user_id=current_user["sub"],
            child_name=name,
            age_group=profile.age_group,
            grade_level=profile.grade_level,
            language=payload.language or profile.preferred_language,
            learning_goals=profile.learning_goals,
            favorite_subjects=profile.favorite_subjects,
            conversation_history=payload.conversation_history,
        )
        try:
            board = extract_board_content(answer)
        except Exception:
            board = []
        return {
            "sia_kind": answer,
            "board": board,
            "subject": payload.subject,
            "age_group": profile.age_group,
            "engine": "sia-kind-multi-model",
        }
    except HTTPException:
        raise
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        raise HTTPException(
            status_code=503,
            detail=f"Sia Kind could not respond right now. Please try again. ({type(e).__name__})",
        ) from e


@router.post("/kind/sia/learn")
async def sia_kind_lesson(
    payload: KindLessonRequest,
    current_user: dict = Depends(require_kind),
    db: AsyncSession = Depends(get_db),
):
    """Structured mini-lesson with hook, teach, example, practice."""
    profile = await _get_kind_profile(current_user["sub"], db)
    name = await _get_child_name(current_user["sub"], db)
    answer = await kind_lesson(
        topic=payload.topic,
        subject=payload.subject,
        user_id=current_user["sub"],
        child_name=name,
        age_group=profile.age_group,
        grade_level=profile.grade_level,
        language=payload.language or profile.preferred_language,
    )
    return {"sia_kind": answer, "topic": payload.topic, "subject": payload.subject}


@router.post("/kind/sia/quiz")
async def sia_kind_quiz(
    payload: KindQuizRequest,
    current_user: dict = Depends(require_kind),
    db: AsyncSession = Depends(get_db),
):
    """Fun age-appropriate interactive quiz for Learn & Play."""
    profile = await _get_kind_profile(current_user["sub"], db)
    name = await _get_child_name(current_user["sub"], db)
    result = await kind_quiz(
        topic=payload.topic,
        subject=payload.subject,
        child_name=name,
        age_group=profile.age_group,
        num_questions=payload.num_questions,
    )
    return {
        "sia_kind": result.get("sia_kind") or result.get("intro") or "",
        "intro": result.get("intro") or "",
        "questions": result.get("questions") or [],
        "topic": payload.topic,
        "num_questions": result.get("num_questions") or payload.num_questions,
    }


@router.post("/kind/sia/homework")
async def sia_kind_homework(
    payload: KindHomeworkRequest,
    current_user: dict = Depends(require_kind),
    db: AsyncSession = Depends(get_db),
):
    """Homework help — guides with hints, does NOT give answers directly."""
    profile = await _get_kind_profile(current_user["sub"], db)
    name = await _get_child_name(current_user["sub"], db)
    answer = await kind_homework_help(
        question=payload.question,
        subject=payload.subject,
        user_id=current_user["sub"],
        child_name=name,
        age_group=profile.age_group,
        child_attempt=payload.child_attempt,
    )
    return {"sia_kind": answer, "subject": payload.subject}


# ── Roles overview ────────────────────────────────────────────────────────────

@router.get("/roles")
async def list_platform_roles():
    """
    GET /api/v1/roles
    Describes student, teacher, and kind account types.
    """
    return {
        "roles": [
            {
                "id": "student",
                "name": "Student",
                "description": "Secondary school & exam prep (JAMB, WAEC, NECO)",
                "signup": "POST /api/v1/auth/student/signup",
                "ai": "POST /api/v1/sia/ask",
                "features": ["CBT practice", "School exams", "Community", "Live classes", "Sia tutor"],
            },
            {
                "id": "teacher",
                "name": "Teacher",
                "description": "Create classes, school exams, and manage students",
                "signup": "POST /api/v1/admin/teachers (admin creates account)",
                "ai": "POST /api/v1/teacher-ai/*",
                "features": ["Live classes", "School CBT scheduling", "Assignments", "Class management"],
            },
            {
                "id": "kind",
                "name": "Kind (Young Learner)",
                "description": "Kids & primary learners ages 3–12 with Sia Kind AI",
                "signup": "POST /api/v1/auth/kind/signup",
                "ai": "POST /api/v1/kind/sia/chat",
                "features": [
                    "Sia Kind — advanced child-safe AI",
                    "Mini-lessons", "Fun quizzes", "Homework hints",
                    "Age-adaptive teaching (3-5, 6-8, 9-12)",
                ],
            },
        ]
    }
