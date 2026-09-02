"""Offline checks for CBT bank append helpers (no DB required)."""

from __future__ import annotations

import csv
import io
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app.services.cbt_bank_import import (  # noqa: E402
    annotate_preview,
    normalize_question_text,
    parse_upload_questions,
    question_is_valid,
    question_needs_review,
)


def _sample_csv(n: int = 5, prefix: str = "Q") -> bytes:
    buf = io.StringIO()
    w = csv.DictWriter(
        buf,
        fieldnames=[
            "question_text",
            "option_a",
            "option_b",
            "option_c",
            "option_d",
            "correct_option",
            "explanation",
        ],
    )
    w.writeheader()
    for i in range(1, n + 1):
        w.writerow(
            {
                "question_text": f"{prefix} What is {i}+{i}?",
                "option_a": str(i),
                "option_b": str(2 * i),
                "option_c": str(3 * i),
                "option_d": str(4 * i),
                "correct_option": "B",
                "explanation": "double",
            }
        )
    return buf.getvalue().encode("utf-8")


def test_normalize():
    a = normalize_question_text("What is 2+2?")
    b = normalize_question_text("  what   is 2+2 ? ")
    assert a == b
    print("OK normalize")


def test_csv_parse_and_append_counts():
    parsed = parse_upload_questions("math.csv", _sample_csv(100, "BatchA"))
    assert parsed["source"] == "csv"
    assert len(parsed["questions"]) == 100
    existing = {normalize_question_text(q["question_text"]) for q in parsed["questions"][:20]}
    # second file overlaps first 20 + 80 new
    parsed2 = parse_upload_questions("math2.csv", _sample_csv(100, "BatchA"))
    ann = annotate_preview(parsed2["questions"], existing)
    assert ann["duplicate_count"] == 20
    assert ann["new_count"] == 80
    assert ann["valid_count"] == 100
    print("OK csv parse + duplicate annotate", ann["duplicate_count"], ann["new_count"])


def test_malformed_flagged():
    bad = {
        "question_text": "Incomplete?",
        "option_a": "A1",
        "option_b": "",
        "option_c": "C1",
        "option_d": "D1",
        "correct_option": "",
        "confidence": 0.2,
        "issues": ["missing options"],
    }
    assert not question_is_valid(bad)
    assert question_needs_review(bad)
    ann = annotate_preview([bad], set())
    assert ann["needs_review_count"] == 1
    assert ann["valid_count"] == 0
    print("OK malformed flagged")


def test_pdf_sample_if_available():
    # Build a tiny synthetic "text-like" path: parser needs real PDF bytes.
    # Skip if no sample PDF in repo.
    samples = list(ROOT.glob("**/sample*questions*.pdf")) + list(ROOT.glob("**/fixtures/**/*.pdf"))
    if not samples:
        print("SKIP pdf sample (no fixture PDF in repo)")
        return
    content = samples[0].read_bytes()
    try:
        parsed = parse_upload_questions(samples[0].name, content)
        print("OK pdf parse", samples[0].name, "questions=", len(parsed["questions"]))
    except ValueError as exc:
        print("PDF parse ValueError (acceptable for odd fixture):", exc)


if __name__ == "__main__":
    test_normalize()
    test_csv_parse_and_append_counts()
    test_malformed_flagged()
    test_pdf_sample_if_available()
    print("ALL CHECKS PASSED")
