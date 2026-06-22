"""ALOC past-questions API (questions.aloc.com.ng) — JAMB / WAEC UTME bank."""

from __future__ import annotations

from typing import Any, Optional

import httpx
from fastapi import HTTPException

from app.core.config import settings

ALOC_JAMB_COMBINED_ID = "aloc:JAMB:combined"

SUBJECT_TO_ALOC: dict[str, str] = {
    "english language": "english",
    "english": "english",
    "mathematics": "mathematics",
    "math": "mathematics",
    "biology": "biology",
    "chemistry": "chemistry",
    "physics": "physics",
    "government": "government",
    "economics": "economics",
    "commerce": "commerce",
    "accounting": "accounting",
    "geography": "geography",
    "literature-in-english": "englishlit",
    "literature in english": "englishlit",
    "english literature": "englishlit",
    "englishlit": "englishlit",
    "crk": "crk",
    "christian religious knowledge": "crk",
    "irk": "irk",
    "islamic religious knowledge": "irk",
    "civic education": "civiledu",
    "insurance": "insurance",
    "current affairs": "currentaffairs",
    "history": "history",
}


def aloc_configured() -> bool:
    return bool((settings.ALOC_ACCESS_TOKEN or "").strip())


def profile_subject_to_aloc(name: str) -> Optional[str]:
    key = (name or "").strip().lower()
    if key in SUBJECT_TO_ALOC:
        return SUBJECT_TO_ALOC[key]
    compact = key.replace("-", " ").replace("_", " ")
    if compact in SUBJECT_TO_ALOC:
        return SUBJECT_TO_ALOC[compact]
    for label, slug in SUBJECT_TO_ALOC.items():
        if label in compact or compact in label:
            return slug
    return None


def order_jamb_subjects(subjects: list[str]) -> list[str]:
    ordered = list(subjects)
    eng_idx = next(
        (i for i, s in enumerate(ordered) if "english" in (s or "").lower()),
        -1,
    )
    if eng_idx > 0:
        eng = ordered.pop(eng_idx)
        ordered.insert(0, eng)
    return ordered


def jamb_question_limit(aloc_slug: str) -> int:
    return 60 if aloc_slug == "english" else 40


def jamb_total_questions(matched_subjects: list[str]) -> int:
    total = 0
    for subject in matched_subjects:
        slug = profile_subject_to_aloc(subject)
        if slug:
            total += jamb_question_limit(slug)
    return total


def _normalize_answer(answer: Any, options: dict[str, str]) -> str:
    raw = str(answer or "A").strip().upper()
    if raw in {"A", "B", "C", "D", "E"}:
        return raw
    for letter, text in options.items():
        if text and str(text).strip().upper() == raw:
            return letter.upper()
    return "A"


def convert_aloc_question(item: dict, index: int, subject_label: str) -> dict:
    options = item.get("option") or {}
    opts = {
        "A": options.get("a") or "",
        "B": options.get("b") or "",
        "C": options.get("c") or "",
        "D": options.get("d") or "",
    }
    correct = _normalize_answer(item.get("answer"), opts)
    year = item.get("examyear")
    topic = subject_label
    if year:
        topic = f"{subject_label} ({year})"
    return {
        "id": f"aloc-q-{index}",
        "question_text": item.get("question") or "",
        "option_a": opts["A"],
        "option_b": opts["B"],
        "option_c": opts["C"],
        "option_d": opts["D"],
        "correct_option": correct,
        "explanation": item.get("solution") or "",
        "topic": topic,
        "image_url": item.get("image") or "",
        "exam_year": year,
    }


async def fetch_aloc_questions(
    aloc_subject: str,
    limit: int,
    *,
    exam_type: str = "utme",
    year: Optional[str] = None,
) -> list[dict]:
    token = (settings.ALOC_ACCESS_TOKEN or "").strip()
    if not token:
        raise HTTPException(status_code=503, detail="ALOC access token is not configured on the server")

    base = (settings.ALOC_BASE_URL or "https://questions.aloc.com.ng").rstrip("/")
    url = f"{base}/api/v2/m/{limit}"
    params: dict[str, str] = {"subject": aloc_subject, "type": exam_type}
    if year:
        params["year"] = year

    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "AccessToken": token,
    }

    try:
        async with httpx.AsyncClient(timeout=90.0) as client:
            resp = await client.get(url, params=params, headers=headers)
            payload = resp.json()
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"ALOC request failed: {exc}") from exc

    if resp.status_code != 200:
        detail = payload.get("error") if isinstance(payload, dict) else str(payload)
        raise HTTPException(status_code=502, detail=detail or "ALOC returned an error")

    data = payload.get("data") if isinstance(payload, dict) else None
    if not isinstance(data, list):
        return []
    return data


def split_jamb_profile_subjects(subjects: list[str]) -> tuple[list[str], list[str]]:
    ordered = order_jamb_subjects(subjects)
    matched: list[str] = []
    missing: list[str] = []
    for subject in ordered:
        if profile_subject_to_aloc(subject):
            matched.append(subject)
        else:
            missing.append(subject)
    return matched, missing


async def build_jamb_combined_exam(
    subjects: list[str],
    *,
    year: Optional[str] = None,
    fetch: bool = True,
) -> dict:
    if len(subjects) != 4:
        raise HTTPException(status_code=400, detail="JAMB requires exactly 4 subjects in profile")

    matched, missing = split_jamb_profile_subjects(subjects)
    if not matched:
        raise HTTPException(
            status_code=400,
            detail="None of your subjects are supported by ALOC. Update subjects in Profile.",
        )

    questions: list[dict] = []
    sections: list[dict] = []
    failed: list[str] = []

    if fetch:
        for subject in matched:
            slug = profile_subject_to_aloc(subject)
            assert slug
            limit = jamb_question_limit(slug)
            try:
                raw = await fetch_aloc_questions(slug, limit, exam_type="utme", year=year)
            except HTTPException:
                failed.append(subject)
                continue
            if not raw:
                failed.append(subject)
                continue
            start = len(questions)
            slice_items = raw[:limit]
            for i, item in enumerate(slice_items):
                questions.append(convert_aloc_question(item, start + i, subject))
            sections.append({"subject": subject, "start": start, "count": len(slice_items)})

        missing = missing + failed
        matched = [s for s in matched if s not in failed]

    total = jamb_total_questions(matched) if not fetch else len(questions)
    year_note = f" · UTME {year}" if year else " · mixed UTME years"

    return {
        "id": ALOC_JAMB_COMBINED_ID,
        "title": "JAMB CBT Practice Exam",
        "subject": " · ".join(matched),
        "exam_type": "JAMB",
        "duration_minutes": 120,
        "total_questions": total,
        "is_portal": True,
        "is_combined": True,
        "is_aloc": True,
        "subjects": matched,
        "missing_subjects": missing,
        "source": "ALOC Past Questions",
        "questions": questions,
        "sections": sections,
        "meta": (
            " · ".join(matched)
            + f" · {total} questions · 2 hrs · ALOC Past Questions{year_note}"
        ),
    }
