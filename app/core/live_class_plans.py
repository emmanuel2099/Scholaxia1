"""Scholaxia One-on-One Live Class monthly plans."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class LiveClassPlan:
    id: str
    category: str
    name: str
    price: float
    sessions: int
    session_minutes: int
    max_subjects: int
    features: tuple[str, ...]
    education_levels: tuple[str, ...]
    exam_types: tuple[str, ...]


LIVE_CLASS_PLANS: tuple[LiveClassPlan, ...] = (
    LiveClassPlan(
        id="nursery_standard",
        category="Nursery",
        name="Nursery Standard",
        price=45000,
        sessions=8,
        session_minutes=45,
        max_subjects=2,
        features=(
            "Homework assistance",
            "Learning activities",
            "Monthly progress report",
            "Parent feedback session",
        ),
        education_levels=("NURSERY", "KG", "PRE-NURSERY", "NURSERY 1", "NURSERY 2"),
        exam_types=(),
    ),
    LiveClassPlan(
        id="nursery_premium",
        category="Nursery",
        name="Nursery Premium",
        price=65000,
        sessions=12,
        session_minutes=45,
        max_subjects=4,
        features=(
            "Homework assistance",
            "Learning activities",
            "Weekly assessments",
            "Monthly progress report",
            "Parent feedback session",
        ),
        education_levels=("NURSERY", "KG", "PRE-NURSERY", "NURSERY 1", "NURSERY 2"),
        exam_types=(),
    ),
    LiveClassPlan(
        id="primary_standard",
        category="Primary School",
        name="Primary Standard",
        price=55000,
        sessions=8,
        session_minutes=60,
        max_subjects=3,
        features=(
            "Homework support",
            "Weekly practice exercises",
            "Monthly progress report",
            "Performance tracking",
        ),
        education_levels=tuple(f"PRIMARY {i}" for i in range(1, 7))
        + tuple(f"PRY{i}" for i in range(1, 7))
        + ("PRIMARY",),
        exam_types=(),
    ),
    LiveClassPlan(
        id="primary_premium",
        category="Primary School",
        name="Primary Premium",
        price=80000,
        sessions=12,
        session_minutes=60,
        max_subjects=5,
        features=(
            "Homework support",
            "Weekly assessments",
            "Personalized study plan",
            "Monthly progress report",
            "Performance tracking",
        ),
        education_levels=tuple(f"PRIMARY {i}" for i in range(1, 7))
        + tuple(f"PRY{i}" for i in range(1, 7))
        + ("PRIMARY",),
        exam_types=(),
    ),
    LiveClassPlan(
        id="primary_elite",
        category="Primary School",
        name="Primary Elite",
        price=70000,
        sessions=16,
        session_minutes=60,
        max_subjects=99,
        features=(
            "Homework & assignment support",
            "Weekly tests",
            "Personalized study plan",
            "Dedicated academic coach",
            "Monthly parent consultation",
        ),
        education_levels=tuple(f"PRIMARY {i}" for i in range(1, 7))
        + tuple(f"PRY{i}" for i in range(1, 7))
        + ("PRIMARY",),
        exam_types=(),
    ),
    LiveClassPlan(
        id="secondary_standard",
        category="High School (JSS & SSS)",
        name="High Standard",
        price=50000,
        sessions=8,
        session_minutes=60,
        max_subjects=3,
        features=(
            "Assignment support",
            "Topic-based assessments",
            "Monthly progress report",
            "Performance analytics",
        ),
        education_levels=tuple(f"JSS{i}" for i in range(1, 4))
        + tuple(f"SS{i}" for i in range(1, 4))
        + ("JSS", "SSS", "SECONDARY"),
        exam_types=(),
    ),
    LiveClassPlan(
        id="secondary_premium",
        category="High School (JSS & SSS)",
        name="Secondary Premium",
        price=60000,
        sessions=12,
        session_minutes=60,
        max_subjects=6,
        features=(
            "Assignment support",
            "Weekly assessments",
            "Personalized study plan",
            "Monthly progress report",
            "Performance analytics",
        ),
        education_levels=tuple(f"JSS{i}" for i in range(1, 4))
        + tuple(f"SS{i}" for i in range(1, 4))
        + ("JSS", "SSS", "SECONDARY"),
        exam_types=(),
    ),
    LiveClassPlan(
        id="secondary_elite",
        category="High School (JSS & SSS)",
        name="Secondary Elite",
        price=80000,
        sessions=16,
        session_minutes=60,
        max_subjects=99,
        features=(
            "Assignment & project support",
            "Weekly tests",
            "CBT practice",
            "Personalized study plan",
            "Dedicated academic mentor",
            "Parent consultation",
        ),
        education_levels=tuple(f"JSS{i}" for i in range(1, 4))
        + tuple(f"SS{i}" for i in range(1, 4))
        + ("JSS", "SSS", "SECONDARY"),
        exam_types=(),
    ),
    LiveClassPlan(
        id="exam_intensive",
        category="Exam Preparation",
        name="Exam Intensive",
        price=80000,
        sessions=18,
        session_minutes=90,
        max_subjects=4,
        features=(
            "JAMB prep classes",
            "Past question practice",
            "Mock tests",
            "Exam strategies",
            "Performance reports",
        ),
        education_levels=("JAMB", "UTME", "WAEC", "NECO", "IGCSE"),
        exam_types=("JAMB", "WAEC", "NECO", "POST_UTME"),
    ),
    LiveClassPlan(
        id="exam_mastery",
        category="Exam Preparation",
        name="Exam Mastery",
        price=100000,
        sessions=25,
        session_minutes=120,
        max_subjects=8,
        features=(
            "Intensive revision",
            "Unlimited past questions",
            "Weekly mock CBT exams",
            "Exam strategy sessions",
            "Dedicated academic mentor",
            "Detailed performance reports",
        ),
        education_levels=("JAMB", "UTME", "WAEC", "NECO", "IGCSE"),
        exam_types=("JAMB", "WAEC", "NECO", "POST_UTME"),
    ),
)

_PLAN_MAP = {p.id: p for p in LIVE_CLASS_PLANS}


def get_plan(plan_id: str) -> Optional[LiveClassPlan]:
    return _PLAN_MAP.get(plan_id)


def plan_to_dict(plan: LiveClassPlan) -> dict:
    return {
        "id": plan.id,
        "category": plan.category,
        "name": plan.name,
        "price": plan.price,
        "currency": "NGN",
        "sessions": plan.sessions,
        "session_minutes": plan.session_minutes,
        "max_subjects": plan.max_subjects if plan.max_subjects < 99 else "All core subjects",
        "features": list(plan.features),
        "billing": "monthly",
    }


def all_plans_dict() -> list[dict]:
    return [plan_to_dict(p) for p in LIVE_CLASS_PLANS]


def _norm(value: Optional[str]) -> str:
    return (value or "").strip().upper().replace("-", " ").replace("_", " ")


def suggest_plan_ids(
    education_level: Optional[str] = None,
    exam_type: Optional[str] = None,
) -> list[str]:
    level = _norm(education_level)
    exam = _norm(exam_type).replace("POST UTME", "POST_UTME")

    if exam in {"JAMB", "WAEC", "NECO", "POST_UTME", "IGCSE"}:
        return ["exam_intensive", "exam_mastery"]

    if any(x in level for x in ("NURSERY", "KG", "PRE NURSERY")):
        return ["nursery_standard", "nursery_premium"]

    if "PRIMARY" in level or level.startswith("PRY"):
        return ["primary_standard", "primary_premium", "primary_elite"]

    if level.startswith("JSS") or level.startswith("SS") or "SECONDARY" in level:
        return ["secondary_standard", "secondary_premium", "secondary_elite"]

    return [p.id for p in LIVE_CLASS_PLANS]
