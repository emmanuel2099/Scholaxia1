"""ALOC past-questions API (questions.aloc.com.ng) — JAMB / WAEC UTME bank."""

from __future__ import annotations

import asyncio
import time
from typing import Any, Optional

import httpx
from fastapi import HTTPException

from app.core.config import settings

ALOC_JAMB_COMBINED_ID = "aloc:JAMB:combined"

EXAM_TYPE_ALIASES: dict[str, set[str]] = {
    "utme": {"utme", "jamb"},
    "waec": {"waec", "wassce"},
    "neco": {"neco"},
    "post-utme": {"post-utme", "postutme", "post_utme"},
}

EXAM_CONFIG: dict[str, dict] = {
    "JAMB": {
        "aloc_type": "utme",
        "title": "JAMB CBT Practice Exam",
        "duration_minutes": 120,
        "exact_subjects": 4,
        "year_label": "UTME",
    },
    "WAEC": {
        "aloc_type": "waec",
        "title": "WAEC CBT Practice Exam",
        "duration_minutes": 240,
        "exact_subjects": None,
        "min_subjects": 1,
        "year_label": "WAEC",
    },
    "NECO": {
        "aloc_type": "neco",
        "title": "NECO CBT Practice Exam",
        "duration_minutes": 240,
        "exact_subjects": None,
        "min_subjects": 1,
        "year_label": "NECO",
    },
    "POST_UTME": {
        "aloc_type": "post-utme",
        "title": "POST-UTME CBT Practice Exam",
        "duration_minutes": 90,
        "exact_subjects": 4,
        "year_label": "POST-UTME",
    },
}

# UTME years shown in the picker (newest first). ALOC serves 2025+ papers for core subjects.
UTME_PICKER_YEARS = [str(y) for y in range(2025, 2000, -1)]

# Legacy year hints per subject (ALOC catalogue). Picker still shows full UTME_PICKER_YEARS.
ALOC_UTME_YEARS: dict[str, list[str]] = {
    "english": ["2025", "2024", "2023", "2022", "2021", "2010", "2009", "2008", "2007", "2006", "2005", "2004", "2003"],
    "mathematics": ["2025", "2024", "2023", "2022", "2021", "2013", "2009", "2008", "2007", "2006"],
    "biology": ["2025", "2024", "2023", "2022", "2021", "2012", "2011", "2010", "2009", "2008", "2006", "2005", "2004", "2003"],
    "chemistry": ["2025", "2024", "2023", "2022", "2021", "2010", "2006", "2005", "2004", "2003", "2002", "2001"],
    "commerce": ["2016", "2013", "2012", "2011", "2010", "2009", "2008", "2007", "2006", "2005", "2004", "2003", "2002", "2001", "2000"],
    "accounting": ["2016", "2015", "2014", "2013", "2012", "2011", "2010", "2009", "2007", "2006", "2004"],
    "physics": ["2025", "2024", "2023", "2022", "2021", "2012", "2011", "2010", "2009", "2007", "2006"],
    "englishlit": ["2015", "2013", "2012", "2010", "2009", "2008", "2007", "2006"],
    "government": ["2016", "2013", "2012", "2011", "2010", "2009", "2008", "2007", "2006", "2000", "1999"],
    "crk": ["2015", "2013", "2012", "2011", "2010", "2009", "2008", "2007", "2006", "2005"],
    "geography": ["2014", "2013", "2012", "2011", "2010", "2009", "2008", "2007", "2006"],
    "economics": ["2013", "2012", "2011", "2010", "2009", "2008", "2007", "2006", "2005", "2004", "2003", "2001"],
    "irk": ["2012"],
    "civiledu": ["2016", "2015", "2014", "2013", "2012", "2011"],
    "insurance": ["2015", "2014", "5", "4", "3", "2", "1"],
    "currentaffairs": ["2013"],
    "history": ["2013"],
}

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


def normalize_exam_type(value: Optional[str]) -> str:
    raw = (value or "JAMB").strip().upper().replace("-", "_")
    if raw in {"POSTUTME", "POST_UTME"}:
        return "POST_UTME"
    if raw in EXAM_CONFIG:
        return raw
    return "JAMB"


def aloc_combined_id(exam_type: str) -> str:
    return f"aloc:{normalize_exam_type(exam_type)}:combined"


def aloc_type_for_exam(exam_type: str) -> str:
    cfg = EXAM_CONFIG.get(normalize_exam_type(exam_type), EXAM_CONFIG["JAMB"])
    return cfg["aloc_type"]


def jamb_question_limit(aloc_slug: str) -> int:
    return 60 if aloc_slug == "english" else 40


def question_limit_for_exam(exam_type: str, aloc_slug: str) -> int:
    if normalize_exam_type(exam_type) == "JAMB":
        return jamb_question_limit(aloc_slug)
    return 40


def total_questions_for_subjects(exam_type: str, matched_subjects: list[str]) -> int:
    total = 0
    for subject in matched_subjects:
        slug = profile_subject_to_aloc(subject)
        if slug:
            total += question_limit_for_exam(exam_type, slug)
    return total


def _normalize_year(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def _question_matches_year(item: dict, year: str, exam_type: str = "utme") -> bool:
    if not year:
        return True
    qyear = _normalize_year(item.get("examyear"))
    if qyear != _normalize_year(year):
        return False
    qtype = str(item.get("examtype") or "").strip().lower()
    if not qtype:
        return True
    want = (exam_type or "utme").strip().lower()
    aliases = EXAM_TYPE_ALIASES.get(want, {want})
    return qtype in aliases or qtype in {"", want}


def _filter_questions_by_year(items: list[dict], year: str, exam_type: str = "utme") -> list[dict]:
    if not year:
        return items
    return [q for q in items if _question_matches_year(q, year, exam_type)]


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


def jamb_year_catalog(subjects: list[str]) -> dict:
    """Years for the UI picker — full 2025→2001 list plus per-subject catalogue hints."""
    by_subject: dict[str, list[str]] = {}
    slug_year_sets: list[set[str]] = []

    for subject in order_jamb_subjects(subjects):
        slug = profile_subject_to_aloc(subject)
        if not slug:
            continue
        catalogue = set(ALOC_UTME_YEARS.get(slug, [])) | set(UTME_PICKER_YEARS)
        ordered = [y for y in UTME_PICKER_YEARS if y in catalogue]
        by_subject[subject] = ordered
        slug_year_sets.append(catalogue)

    all_years = list(UTME_PICKER_YEARS)

    common_years: list[str] = []
    if slug_year_sets:
        common_years = [y for y in UTME_PICKER_YEARS if all(y in s for s in slug_year_sets)]

    return {
        "by_subject": by_subject,
        "all_years": all_years,
        "common_years": common_years,
    }


async def _fetch_aloc_batch(
    client: httpx.AsyncClient,
    *,
    base: str,
    token: str,
    aloc_subject: str,
    limit: int,
    exam_type: str,
    year: Optional[str],
) -> tuple[list[dict], bool]:
    """Fetch one ALOC batch. Returns (questions, used_fallback)."""
    cap = min(max(int(limit), 1), 120)
    url = f"{base}/api/v2/m/{cap}"
    params: dict[str, str] = {"subject": aloc_subject, "type": exam_type}
    year_norm = _normalize_year(year)
    if year_norm:
        params["year"] = year_norm

    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "AccessToken": token,
    }

    resp = await client.get(url, params=params, headers=headers)
    payload = resp.json()

    if resp.status_code != 200:
        detail = payload.get("error") if isinstance(payload, dict) else str(payload)
        if isinstance(payload, dict) and payload.get("message"):
            detail = payload.get("message")
        raise HTTPException(status_code=502, detail=detail or "ALOC returned an error")

    data = payload.get("data") if isinstance(payload, dict) else None
    if not isinstance(data, list):
        return [], False

    used_fallback = False
    if year_norm and isinstance(payload, dict):
        msg = str(payload.get("message") or "").lower()
        if "could not find" in msg:
            used_fallback = True
            data = []

    if year_norm:
        data = _filter_questions_by_year(data, year_norm, exam_type)
        if used_fallback:
            return [], True
        return data, False

    if exam_type:
        aliases = EXAM_TYPE_ALIASES.get(exam_type.strip().lower(), {exam_type.lower()})
        data = [
            q for q in data
            if str(q.get("examtype") or "").strip().lower() in aliases | {"", "utme", "jamb", "waec", "wassce", "neco", "post-utme"}
        ]
    return data, False


_ALOC_RESPONSE_CACHE: dict[str, tuple[float, list[dict]]] = {}
_ALOC_CACHE_TTL_SEC = 600


def _aloc_cache_key(aloc_subject: str, exam_type: str, year: Optional[str], limit: int) -> str:
    return f"{aloc_subject}:{exam_type}:{_normalize_year(year)}:{limit}"


def _aloc_cache_get(key: str) -> Optional[list[dict]]:
    entry = _ALOC_RESPONSE_CACHE.get(key)
    if not entry:
        return None
    ts, data = entry
    if time.time() - ts > _ALOC_CACHE_TTL_SEC:
        _ALOC_RESPONSE_CACHE.pop(key, None)
        return None
    return data


def _aloc_cache_set(key: str, data: list[dict]) -> None:
    _ALOC_RESPONSE_CACHE[key] = (time.time(), data)


async def fetch_aloc_questions(
    aloc_subject: str,
    limit: int,
    *,
    exam_type: str = "utme",
    year: Optional[str] = None,
    client: Optional[httpx.AsyncClient] = None,
) -> list[dict]:
    token = (settings.ALOC_ACCESS_TOKEN or "").strip()
    if not token:
        raise HTTPException(status_code=503, detail="ALOC access token is not configured on the server")

    base = (settings.ALOC_BASE_URL or "https://questions.aloc.com.ng").rstrip("/")
    year_norm = _normalize_year(year)
    want = max(int(limit), 1)
    cache_key = _aloc_cache_key(aloc_subject, exam_type, year_norm or None, want)
    cached = _aloc_cache_get(cache_key)
    if cached is not None:
        return cached[:want]

    collected: list[dict] = []
    seen_ids: set[Any] = set()
    max_attempts = 1 if year_norm else (2 if want > 40 else 1)
    own_client = client is None

    try:
        if own_client:
            client = httpx.AsyncClient(timeout=28.0)
        assert client is not None
        attempts = 0
        while len(collected) < want and attempts < max_attempts:
            batch, _ = await _fetch_aloc_batch(
                client,
                base=base,
                token=token,
                aloc_subject=aloc_subject,
                limit=want - len(collected),
                exam_type=exam_type,
                year=year_norm or None,
            )
            if not batch:
                break
            for item in batch:
                qid = item.get("id")
                if qid in seen_ids:
                    continue
                seen_ids.add(qid)
                collected.append(item)
                if len(collected) >= want:
                    break
            attempts += 1
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"ALOC request failed: {exc}") from exc
    finally:
        if own_client and client is not None:
            await client.aclose()

    if year_norm:
        collected = _filter_questions_by_year(collected, year_norm, exam_type)

    result = collected[:want]
    if result:
        _aloc_cache_set(cache_key, result)
    return result


def split_profile_subjects(subjects: list[str]) -> tuple[list[str], list[str]]:
    ordered = order_jamb_subjects(subjects)
    matched: list[str] = []
    missing: list[str] = []
    for subject in ordered:
        if profile_subject_to_aloc(subject):
            matched.append(subject)
        else:
            missing.append(subject)
    return matched, missing


def _validate_subjects_for_exam(exam_type: str, subjects: list[str]) -> None:
    exam = normalize_exam_type(exam_type)
    cfg = EXAM_CONFIG[exam]
    exact = cfg.get("exact_subjects")
    if exact is not None and len(subjects) != exact:
        label = exam.replace("_", "-")
        raise HTTPException(status_code=400, detail=f"{label} requires exactly {exact} subjects in profile")
    minimum = cfg.get("min_subjects", 1)
    if len(subjects) < minimum:
        raise HTTPException(status_code=400, detail=f"{exam} requires at least {minimum} subject(s) in profile")


async def build_combined_exam(
    exam_type: str,
    subjects: list[str],
    *,
    year: Optional[str] = None,
    fetch: bool = True,
) -> dict:
    exam = normalize_exam_type(exam_type)
    cfg = EXAM_CONFIG[exam]
    _validate_subjects_for_exam(exam, subjects)

    matched, missing = split_profile_subjects(subjects)
    if not matched:
        raise HTTPException(
            status_code=400,
            detail="None of your subjects are supported by ALOC. Update subjects in Profile.",
        )

    aloc_type = cfg["aloc_type"]
    questions: list[dict] = []
    sections: list[dict] = []
    failed: list[str] = []

    if fetch:
        async with httpx.AsyncClient(timeout=28.0) as http_client:

            async def load_subject(subject: str) -> tuple[str, list[dict]]:
                try:
                    slug = profile_subject_to_aloc(subject)
                    assert slug
                    limit = question_limit_for_exam(exam, slug)
                    raw = await fetch_aloc_questions(
                        slug, limit, exam_type=aloc_type, year=year, client=http_client
                    )
                    return subject, raw[:limit]
                except Exception:
                    return subject, []

            results = await asyncio.gather(
                *[load_subject(subject) for subject in matched],
                return_exceptions=True,
            )
        for result in results:
            if isinstance(result, Exception):
                failed.append(str(result))
                continue
            subject, slice_items = result
            if not slice_items:
                failed.append(subject)
                continue
            start = len(questions)
            for i, item in enumerate(slice_items):
                questions.append(convert_aloc_question(item, start + i, subject))
            sections.append({"subject": subject, "start": start, "count": len(slice_items)})

        missing = missing + [s for s in matched if s not in [sec["subject"] for sec in sections]]
        matched = [sec["subject"] for sec in sections]

        year_label = cfg["year_label"]
        if year and not questions:
            raise HTTPException(
                status_code=400,
                detail=f"No {year_label} {year} papers found for your subjects. Try another year or Any year.",
            )

    total = total_questions_for_subjects(exam, matched) if not fetch else len(questions)
    year_catalog = jamb_year_catalog(matched)
    year_note = f" · {cfg['year_label']} {year}" if year else f" · mixed {cfg['year_label']} years"

    return {
        "id": aloc_combined_id(exam),
        "title": cfg["title"],
        "subject": " · ".join(matched),
        "exam_type": exam,
        "duration_minutes": cfg["duration_minutes"],
        "total_questions": total,
        "is_portal": True,
        "is_combined": True,
        "is_aloc": True,
        "subjects": matched,
        "missing_subjects": missing,
        "source": "ALOC Past Questions",
        "years_by_subject": year_catalog["by_subject"],
        "available_years": year_catalog["all_years"],
        "common_years": year_catalog["common_years"],
        "selected_year": year or "",
        "questions": questions,
        "sections": sections,
        "meta": (
            " · ".join(matched)
            + f" · {total} questions · {cfg['duration_minutes']} min · ALOC Past Questions{year_note}"
        ),
    }


async def build_jamb_combined_exam(
    subjects: list[str],
    *,
    year: Optional[str] = None,
    fetch: bool = True,
) -> dict:
    return await build_combined_exam("JAMB", subjects, year=year, fetch=fetch)
