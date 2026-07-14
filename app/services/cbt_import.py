"""Parse uploaded CBT files (JSON / CSV) into exam payloads for the database."""

from __future__ import annotations

import csv
import io
import json
from typing import Any

VALID_EXAM_TYPES = {"JAMB", "WAEC", "NECO", "SCHOOL", "POST_UTME", "COMMON_ENTRANCE", "CE"}
VALID_OPTIONS = {"A", "B", "C", "D"}


def _norm_key(key: str) -> str:
    return key.strip().lower().replace(" ", "_").replace("-", "_")


def _pick(data: dict[str, Any], *keys: str, default: Any = None) -> Any:
    if not isinstance(data, dict):
        return default
    normalized = {_norm_key(k): v for k, v in data.items()}
    for key in keys:
        val = normalized.get(_norm_key(key))
        if val is not None and str(val).strip() != "":
            return val
    return default


def _normalize_answer(raw: Any, line_hint: str = "") -> str:
    ans = str(raw or "").strip().upper()
    mapping = {
        "1": "A",
        "2": "B",
        "3": "C",
        "4": "D",
        "OPTION_A": "A",
        "OPTION_B": "B",
        "OPTION_C": "C",
        "OPTION_D": "D",
        "A.": "A",
        "B.": "B",
        "C.": "C",
        "D.": "D",
    }
    ans = mapping.get(ans, ans)
    if len(ans) == 1 and ans in VALID_OPTIONS:
        return ans
    raise ValueError(
        f"{line_hint}correct_option must be A, B, C, or D (got {raw!r})"
    )


def normalize_question(raw: dict[str, Any], line_no: int = 0) -> dict[str, Any]:
    hint = f"Row {line_no}: " if line_no else "Question: "
    qtext = str(_pick(raw, "question_text", "question", "text", "q") or "").strip()
    if not qtext:
        raise ValueError(f"{hint}missing question text")

    option_a = str(_pick(raw, "option_a", "a", "optiona") or "").strip()
    option_b = str(_pick(raw, "option_b", "b", "optionb") or "").strip()
    option_c = str(_pick(raw, "option_c", "c", "optionc") or "").strip()
    option_d = str(_pick(raw, "option_d", "d", "optiond") or "").strip()
    if not all([option_a, option_b, option_c, option_d]):
        raise ValueError(f"{hint}all four options (A–D) are required")

    item: dict[str, Any] = {
        "question_text": qtext,
        "option_a": option_a,
        "option_b": option_b,
        "option_c": option_c,
        "option_d": option_d,
        "correct_option": _normalize_answer(
            _pick(raw, "correct_option", "answer", "correct", "correct_answer"),
            hint,
        ),
    }
    for field, keys in (
        ("explanation", ("explanation", "explain", "solution")),
        ("topic", ("topic", "subject_topic")),
        ("image_url", ("image_url", "image", "diagram_url")),
    ):
        val = _pick(raw, *keys)
        if val is not None and str(val).strip():
            item[field] = str(val).strip()
    return item


def normalize_exam(raw: dict[str, Any], defaults: dict[str, Any] | None = None) -> dict[str, Any]:
    defaults = defaults or {}
    title = str(
        _pick(raw, "title", "name", "exam_title") or defaults.get("title") or ""
    ).strip()
    subject = str(
        _pick(raw, "subject", "exam_subject") or defaults.get("subject") or ""
    ).strip()
    exam_type = str(
        _pick(raw, "exam_type", "type", "board") or defaults.get("exam_type") or "JAMB"
    ).strip().upper().replace(" ", "_").replace("-", "_")
    if exam_type in ("CE", "COMMONENTRANCE"):
        exam_type = "COMMON_ENTRANCE"
    if not title:
        raise ValueError("Exam title is required")
    if not subject:
        raise ValueError(f"Exam '{title}': subject is required")
    if exam_type not in VALID_EXAM_TYPES:
        raise ValueError(
            f"Exam '{title}': exam_type must be one of {', '.join(sorted(VALID_EXAM_TYPES))}"
        )

    year_raw = _pick(raw, "year", "exam_year", "session")
    if year_raw is None:
        year_raw = defaults.get("year")
    year: int | None = None
    if year_raw is not None and str(year_raw).strip() != "":
        try:
            year = int(str(year_raw).strip()[:4])
        except (TypeError, ValueError) as exc:
            raise ValueError(f"Exam '{title}': year must be a number like 2019") from exc
        if year < 1990 or year > 2100:
            raise ValueError(f"Exam '{title}': year must be between 1990 and 2100")

    duration = _pick(raw, "duration_minutes", "duration", "time_minutes")
    if duration is None:
        duration = defaults.get("duration_minutes", 30)
    try:
        duration_minutes = int(duration)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"Exam '{title}': duration_minutes must be a number") from exc
    if duration_minutes < 5 or duration_minutes > 300:
        raise ValueError(f"Exam '{title}': duration_minutes must be between 5 and 300")

    questions_raw = _pick(raw, "questions", "items", "qs")
    if not isinstance(questions_raw, list) or not questions_raw:
        raise ValueError(f"Exam '{title}': at least one question is required")

    questions = [
        normalize_question(q if isinstance(q, dict) else {}, i + 1)
        for i, q in enumerate(questions_raw)
    ]

    is_published = _pick(raw, "is_published", "published")
    if is_published is None:
        is_published = defaults.get("is_published", True)
    if isinstance(is_published, str):
        is_published = is_published.strip().lower() in {"1", "true", "yes", "y"}

    out: dict[str, Any] = {
        "title": title,
        "subject": subject,
        "exam_type": exam_type,
        "duration_minutes": duration_minutes,
        "is_published": bool(is_published),
        "is_school_exam": bool(_pick(raw, "is_school_exam") or defaults.get("is_school_exam")),
        "questions": questions,
    }
    if year is not None:
        out["year"] = year
    return out


def parse_json_import(content: bytes, defaults: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    try:
        data = json.loads(content.decode("utf-8-sig"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON: {exc.msg}") from exc

    if isinstance(data, list):
        return [normalize_exam(item, defaults) for item in data if isinstance(item, dict)]
    if isinstance(data, dict):
        exams = data.get("exams")
        if isinstance(exams, list):
            return [normalize_exam(item, defaults) for item in exams if isinstance(item, dict)]
        if _pick(data, "questions", "items", "qs"):
            return [normalize_exam(data, defaults)]
    raise ValueError(
        "JSON must be one exam object, { \"exams\": [ ... ] }, or [ ... ]"
    )


def parse_csv_import(content: bytes, defaults: dict[str, Any]) -> list[dict[str, Any]]:
    if not defaults.get("title") or not defaults.get("subject"):
        raise ValueError("CSV upload needs title and subject (in the file or upload form)")

    text = content.decode("utf-8-sig")
    reader = csv.DictReader(io.StringIO(text))
    if not reader.fieldnames:
        raise ValueError("CSV must include a header row")

    questions: list[dict[str, Any]] = []
    for row_no, row in enumerate(reader, start=2):
        if not row or not any(str(v or "").strip() for v in row.values()):
            continue
        questions.append(normalize_question(row, row_no))

    if not questions:
        raise ValueError("CSV file has no question rows")

    return [normalize_exam({"questions": questions}, defaults)]


def parse_cbt_file(
    filename: str,
    content: bytes,
    defaults: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    if not content:
        raise ValueError("Uploaded file is empty")

    name = (filename or "").lower()
    if name.endswith(".json"):
        return parse_json_import(content, defaults)
    if name.endswith(".csv"):
        return parse_csv_import(content, defaults or {})

    try:
        return parse_json_import(content, defaults)
    except (json.JSONDecodeError, ValueError):
        if defaults and defaults.get("title") and defaults.get("subject"):
            return parse_csv_import(content, defaults)
        raise ValueError("Unsupported file. Upload a .json or .csv CBT file.") from None


CBT_IMPORT_TEMPLATE: dict[str, Any] = {
    "title": "JAMB Physics Mock 1",
    "subject": "Physics",
    "year": 2019,
    "exam_type": "JAMB",
    "duration_minutes": 60,
    "is_published": True,
    "questions": [
        {
            "question_text": "What is the SI unit of force?",
            "option_a": "Joule",
            "option_b": "Newton",
            "option_c": "Watt",
            "option_d": "Pascal",
            "correct_option": "B",
            "explanation": "Force is measured in Newtons (N).",
            "topic": "Mechanics",
        },
        {
            "question_text": "Which law states F = ma?",
            "option_a": "Newton's first law",
            "option_b": "Newton's second law",
            "option_c": "Newton's third law",
            "option_d": "Ohm's law",
            "correct_option": "B",
            "explanation": "Newton's second law: force equals mass times acceleration.",
            "topic": "Mechanics",
        },
    ],
}
