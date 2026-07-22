"""Scholaxia Skills Training programs — fees and metadata for enrollment payments."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional

from app.core.datetime_utils import naive_utc_now

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

SKILL_ENTITLEMENT_TYPE = "skill_program"


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
    raw = str(plan_key or "")
    if not is_skill_plan_key(raw):
        return ""
    # skill:web-design or skill:web-design:half2
    parts = raw.split(":")
    return parts[1] if len(parts) >= 2 else ""


def first_installment_amount(fee: float) -> float:
    return float(max(1, round(fee / 2)))


def remaining_installment_amount(fee: float) -> float:
    fee = float(fee)
    return float(max(1, round(fee - first_installment_amount(fee))))


def payment_amount_for_mode(fee: float, payment_mode: str, installment: int = 1) -> float:
    mode = (payment_mode or "half").strip().lower()
    fee = float(fee)
    if mode == "once":
        return fee
    if int(installment or 1) >= 2:
        return remaining_installment_amount(fee)
    return first_installment_amount(fee)


def parse_duration_months(duration: str) -> int:
    text = (duration or "").lower()
    digits = "".join(ch for ch in text if ch.isdigit())
    try:
        months = int(digits) if digits else 3
    except ValueError:
        months = 3
    return max(1, months)


def skill_program_end(start: datetime | None, duration: str) -> datetime:
    base = start or naive_utc_now()
    return base + timedelta(days=30 * parse_duration_months(duration))


def skill_midpoint_due(start: datetime | None, duration: str) -> datetime:
    """When half-payment balance is due (program midpoint)."""
    base = start or naive_utc_now()
    months = parse_duration_months(duration)
    return base + timedelta(days=max(14, 15 * months))
