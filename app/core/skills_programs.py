"""Scholaxia Skills Training programs — fees and metadata for enrollment payments."""

from typing import Optional

SKILLS_PROGRAMS: dict[str, dict] = {
    "web-design": {"title": "Web Design", "fee": 250000, "duration": "6 months"},
    "mobile-app": {"title": "Mobile App Development", "fee": 300000, "duration": "9 months"},
    "gsm-repairs": {"title": "Computer / GSM Repairs", "fee": 150000, "duration": "6 months"},
    "graphics": {"title": "Graphics Design", "fee": 70000, "duration": "3 months"},
    "data-analysis": {"title": "Data Analysis", "fee": 100000, "duration": "6 months"},
    "cyber-security": {"title": "Cyber Security", "fee": 150000, "duration": "3 months"},
    "digital-marketing": {"title": "Digital Marketing", "fee": 80000, "duration": "2 months"},
    "scratch-robotics": {"title": "Scratch Coding & Robotics", "fee": 65000, "duration": "3 months"},
}


def get_skill_program(skill_id: str) -> Optional[dict]:
    program = SKILLS_PROGRAMS.get((skill_id or "").strip())
    if not program:
        return None
    return {"id": skill_id, **program}


def skill_plan_key(skill_id: str) -> str:
    return f"skill:{skill_id}"


def is_skill_plan_key(plan_key: str) -> bool:
    return str(plan_key or "").startswith("skill:")


def skill_id_from_plan_key(plan_key: str) -> str:
    return str(plan_key or "").split(":", 1)[-1] if is_skill_plan_key(plan_key) else ""


def first_installment_amount(fee: float) -> float:
    return float(max(1, round(fee / 2)))
