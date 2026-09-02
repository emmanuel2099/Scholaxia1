"""Append questions into an existing CBT practice bank (never replace)."""

from __future__ import annotations

import re
import uuid
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cbt import CBTExam, CBTQuestion
from app.services.cbt_access import normalize_board
from app.services.cbt_import import normalize_exam_type, parse_cbt_file

LOW_CONFIDENCE_THRESHOLD = 0.55


def normalize_question_text(text: str | None) -> str:
    """Loose fingerprint for duplicate detection (ignore case/punct/whitespace)."""
    t = (text or "").lower().strip()
    t = re.sub(r"\s+", " ", t)
    t = re.sub(r"[^\w\s]", "", t)
    return t


def _subject_match(a: str, b: str) -> bool:
    return re.sub(r"\s+", " ", (a or "").strip().lower()) == re.sub(
        r"\s+", " ", (b or "").strip().lower()
    )


def question_is_valid(q: dict[str, Any]) -> bool:
    text = (q.get("question_text") or "").strip()
    opts = [
        (q.get("option_a") or "").strip(),
        (q.get("option_b") or "").strip(),
        (q.get("option_c") or "").strip(),
        (q.get("option_d") or "").strip(),
    ]
    ans = (q.get("correct_option") or "").strip().upper()
    return bool(text and all(opts) and ans in {"A", "B", "C", "D"})


def question_needs_review(q: dict[str, Any]) -> bool:
    if not question_is_valid(q):
        return True
    conf = q.get("confidence")
    if conf is not None and float(conf) < LOW_CONFIDENCE_THRESHOLD:
        return True
    if q.get("issues"):
        return True
    return False


async def existing_question_norms(
    db: AsyncSession, exam_type: str, subject: str
) -> set[str]:
    board = normalize_board(normalize_exam_type(exam_type))
    exams = (
        await db.execute(
            select(CBTExam).where(
                CBTExam.is_school_exam.is_(False),
                CBTExam.paper_kind == "cbt_practice",
            )
        )
    ).scalars().all()
    norms: set[str] = set()
    for ex in exams:
        if normalize_board(ex.exam_type) != board:
            continue
        if not _subject_match(ex.subject, subject):
            continue
        rows = (
            await db.execute(select(CBTQuestion.question_text).where(CBTQuestion.exam_id == ex.id))
        ).scalars().all()
        for text in rows:
            n = normalize_question_text(text)
            if n:
                norms.add(n)
    return norms


async def count_bank_questions(db: AsyncSession, exam_type: str, subject: str) -> int:
    board = normalize_board(normalize_exam_type(exam_type))
    exams = (
        await db.execute(
            select(CBTExam).where(
                CBTExam.is_school_exam.is_(False),
                CBTExam.paper_kind == "cbt_practice",
            )
        )
    ).scalars().all()
    total = 0
    for ex in exams:
        if normalize_board(ex.exam_type) != board:
            continue
        if not _subject_match(ex.subject, subject):
            continue
        n = (
            await db.execute(
                select(func.count()).select_from(CBTQuestion).where(CBTQuestion.exam_id == ex.id)
            )
        ).scalar() or 0
        total += int(n)
    return total


async def get_or_create_bank_exam(
    db: AsyncSession,
    *,
    exam_type: str,
    subject: str,
    created_by: str | uuid.UUID | None,
    duration_minutes: int = 60,
) -> CBTExam:
    """Pick the canonical Question Bank exam for append, or create one. Never clears old rows."""
    board = normalize_board(normalize_exam_type(exam_type))
    subject = (subject or "").strip()
    canonical_title = f"{board} {subject} Question Bank"

    exams = (
        await db.execute(
            select(CBTExam).where(
                CBTExam.is_school_exam.is_(False),
                CBTExam.paper_kind == "cbt_practice",
            )
        )
    ).scalars().all()
    candidates: list[CBTExam] = []
    for ex in exams:
        if normalize_board(ex.exam_type) != board:
            continue
        if not _subject_match(ex.subject, subject):
            continue
        candidates.append(ex)

    for ex in candidates:
        if (ex.title or "").strip().lower() == canonical_title.lower():
            return ex

    if candidates:
        # Append into the largest existing set so we grow one bank, not scatter.
        best = candidates[0]
        best_n = -1
        for ex in candidates:
            n = (
                await db.execute(
                    select(func.count())
                    .select_from(CBTQuestion)
                    .where(CBTQuestion.exam_id == ex.id)
                )
            ).scalar() or 0
            if int(n) > best_n:
                best_n = int(n)
                best = ex
        return best

    creator = None
    if created_by:
        try:
            creator = uuid.UUID(str(created_by))
        except (TypeError, ValueError):
            creator = None

    exam = CBTExam(
        title=canonical_title,
        subject=subject,
        exam_type=board,
        year=None,
        duration_minutes=max(5, int(duration_minutes or 60)),
        total_questions=0,
        created_by=creator,
        is_published=True,
        is_school_exam=False,
        paper_kind="cbt_practice",
    )
    db.add(exam)
    await db.flush()
    return exam


def parse_upload_questions(filename: str, content: bytes) -> dict[str, Any]:
    """Parse PDF/DOCX/CSV/JSON into a flat question list (no DB writes)."""
    from app.services.cbt_pdf_parser import (
        LOW_CONFIDENCE_THRESHOLD as PDF_LOW,
        PDFParseError,
        parse_docx_questions,
        parse_pdf_questions,
    )

    name = (filename or "").lower()
    is_pdf = name.endswith(".pdf") or (content[:5] == b"%PDF-")
    is_docx = name.endswith(".docx")

    if is_pdf or is_docx:
        try:
            result = parse_docx_questions(content) if is_docx else parse_pdf_questions(content)
        except PDFParseError as exc:
            raise ValueError(str(exc)) from exc
        questions = result.get("questions") or []
        warnings = list(result.get("warnings") or [])
        if not questions:
            warnings.append(
                "Some questions could not be detected. Please review them before importing."
            )
        return {
            "source": "docx" if is_docx else "pdf",
            "questions": questions,
            "warnings": warnings,
            "answer_key_found": bool(result.get("answer_key_found")),
            "low_confidence_threshold": PDF_LOW,
        }

    defaults = {"title": "Bank Preview", "subject": "Preview", "year": 2000}
    exams = parse_cbt_file(filename or "upload.csv", content, defaults)
    questions: list[dict[str, Any]] = []
    for exam in exams:
        for i, q in enumerate(exam.get("questions") or [], start=1):
            questions.append({**q, "number": i, "confidence": 1.0, "issues": []})
    return {
        "source": "json" if name.endswith(".json") else "csv",
        "questions": questions,
        "warnings": [],
        "answer_key_found": True,
        "low_confidence_threshold": LOW_CONFIDENCE_THRESHOLD,
    }


def annotate_preview(
    questions: list[dict[str, Any]], existing_norms: set[str]
) -> dict[str, Any]:
    annotated: list[dict[str, Any]] = []
    valid = 0
    needs_review = 0
    duplicates = 0
    for i, raw in enumerate(questions, start=1):
        q = dict(raw)
        q.setdefault("number", i)
        norm = normalize_question_text(q.get("question_text"))
        is_dup = bool(norm and norm in existing_norms)
        q["is_duplicate"] = is_dup
        q["normalized_text"] = norm
        review = question_needs_review(
            {**q, "issues": [x for x in (q.get("issues") or []) if "duplicate" not in x.lower()]}
        )
        if is_dup:
            duplicates += 1
            issues = list(q.get("issues") or [])
            if "Possible duplicate of an existing bank question" not in issues:
                issues.append("Possible duplicate of an existing bank question")
            q["issues"] = issues
        ok = question_is_valid(q) and not review
        q["is_valid"] = ok
        q["needs_review"] = review
        if ok:
            valid += 1
        if review:
            needs_review += 1
        annotated.append(q)

    new_count = sum(1 for q in annotated if q.get("is_valid") and not q.get("is_duplicate"))
    return {
        "questions": annotated,
        "total_questions": len(annotated),
        "valid_count": valid,
        "needs_review_count": needs_review,
        "duplicate_count": duplicates,
        "new_count": new_count,
    }


async def append_questions_to_bank(
    db: AsyncSession,
    *,
    exam_type: str,
    subject: str,
    created_by: str | uuid.UUID | None,
    duration_minutes: int,
    questions: list[dict[str, Any]],
    import_mode: str = "new_only",
) -> dict[str, Any]:
    """
    APPEND questions to the bank for exam+subject.
    Never deletes or replaces existing questions.
    import_mode: new_only | all
    """
    subject = (subject or "").strip()
    if not subject:
        raise ValueError("Subject is required before importing")
    if not questions:
        raise ValueError("No questions to import")

    before = await count_bank_questions(db, exam_type, subject)
    existing = await existing_question_norms(db, exam_type, subject)
    exam = await get_or_create_bank_exam(
        db,
        exam_type=exam_type,
        subject=subject,
        created_by=created_by,
        duration_minutes=duration_minutes,
    )

    mode = (import_mode or "new_only").strip().lower()
    inserted = 0
    skipped_dup = 0
    skipped_invalid = 0

    for raw in questions:
        if not question_is_valid(raw):
            skipped_invalid += 1
            continue
        norm = normalize_question_text(raw.get("question_text"))
        if mode != "all" and norm and norm in existing:
            skipped_dup += 1
            continue
        db.add(
            CBTQuestion(
                exam_id=exam.id,
                question_text=(raw.get("question_text") or "").strip(),
                option_a=(raw.get("option_a") or "").strip(),
                option_b=(raw.get("option_b") or "").strip(),
                option_c=(raw.get("option_c") or "").strip(),
                option_d=(raw.get("option_d") or "").strip(),
                correct_option=(raw.get("correct_option") or "").strip().upper(),
                explanation=(raw.get("explanation") or None),
                topic=(raw.get("topic") or None),
                image_url=(raw.get("image_url") or None),
            )
        )
        inserted += 1
        if norm:
            existing.add(norm)

    # Refresh total_questions on the target exam only (sum of its rows).
    new_exam_count = (
        await db.execute(
            select(func.count()).select_from(CBTQuestion).where(CBTQuestion.exam_id == exam.id)
        )
    ).scalar() or 0
    exam.total_questions = int(new_exam_count)
    if not exam.is_published:
        exam.is_published = True
    await db.flush()

    after = await count_bank_questions(db, exam_type, subject)
    return {
        "exam_id": str(exam.id),
        "exam_title": exam.title,
        "exam_type": normalize_board(exam.exam_type),
        "subject": exam.subject,
        "inserted_count": inserted,
        "skipped_duplicate_count": skipped_dup,
        "skipped_invalid_count": skipped_invalid,
        "bank_count_before": before,
        "bank_count_after": after,
        "import_mode": mode,
    }
