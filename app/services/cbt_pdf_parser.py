"""Extract multiple-choice questions from text-based PDF past-question papers.

Designed for the common Nigerian past-question layout:

    1. What is the SI unit of force?
       A. Joule  B. Newton  C. Watt  D. Pascal

with either an inline answer ("Answer: B" / "Ans: B") or an answer-key
section at the end of the document ("ANSWERS: 1. B  2. C ...").

Each extracted question carries a ``confidence`` score (0.0–1.0) plus a list
of ``issues`` so the admin UI can flag anything that needs a human check.
Scanned/image-only PDFs contain no extractable text and are rejected with a
clear error (OCR is out of scope).
"""

from __future__ import annotations

import io
import re
import zipfile
from typing import Any
from xml.etree import ElementTree

# Questions at or below this confidence must be reviewed by the admin and are
# never auto-published.
LOW_CONFIDENCE_THRESHOLD = 0.7

MAX_QUESTION_NUMBER = 5000


class PDFParseError(ValueError):
    """Raised when a PDF cannot be read or contains no usable questions."""


def _extract_pdf_text(content: bytes) -> str:
    try:
        from pypdf import PdfReader
        from pypdf.errors import PdfReadError
    except ImportError as exc:  # pragma: no cover - depends on environment
        raise PDFParseError(
            "PDF import needs the 'pypdf' package on the server. "
            "Install it with: pip install pypdf"
        ) from exc

    try:
        reader = PdfReader(io.BytesIO(content))
        if reader.is_encrypted:
            try:
                reader.decrypt("")
            except Exception as exc:
                raise PDFParseError("This PDF is password-protected. Remove the password and re-upload.") from exc
        pages = [(page.extract_text() or "") for page in reader.pages]
    except PDFParseError:
        raise
    except (PdfReadError, Exception) as exc:
        raise PDFParseError(f"Could not read PDF file: {exc}") from exc

    return "\n".join(pages)


def _extract_docx_text(content: bytes) -> str:
    """Read paragraph and table text from an Office Open XML Word file."""
    try:
        with zipfile.ZipFile(io.BytesIO(content)) as archive:
            document_xml = archive.read("word/document.xml")
    except (zipfile.BadZipFile, KeyError) as exc:
        raise PDFParseError(
            "Could not read this Word file. Upload a valid .docx file; old .doc files "
            "must first be saved as .docx in Microsoft Word."
        ) from exc

    try:
        root = ElementTree.fromstring(document_xml)
    except ElementTree.ParseError as exc:
        raise PDFParseError("Could not read text from this Word document.") from exc

    namespace = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
    lines: list[str] = []
    for paragraph in root.iter(f"{namespace}p"):
        parts: list[str] = []
        for node in paragraph.iter():
            if node.tag == f"{namespace}t" and node.text:
                parts.append(node.text)
            elif node.tag == f"{namespace}tab":
                parts.append("\t")
            elif node.tag == f"{namespace}br":
                parts.append("\n")
        line = "".join(parts).strip()
        if line:
            lines.append(line)
    return "\n".join(lines)


# "1." or "1)" at the start of a line begins a question.
_QUESTION_START = re.compile(r"^[ \t]*(\d{1,4})[.)][ \t]+", re.MULTILINE)

# Inline answer inside a question block, e.g. "Answer: B", "Ans. C", "Answer: C. Cell"
_INLINE_ANSWER = re.compile(
    r"(?im)^[ \t]*(?:answer|ans|correct(?:\s+option)?)\s*[:=.\-]?\s*\(?([A-Da-d])\)?"
    r"(?:\s*[.)]\s*[^\n]*)?[ \t]*$"
)

# Explanation line after the answer, e.g. "➡ The cell is..." or "Explanation: ..."
_EXPLANATION_LINE = re.compile(
    r"(?im)^[ \t]*(?:➡|→|➜|►|>{1,3}|explanation)\s*[:=\-]?\s*.+$"
)

# Safety: if answer/explanation still trails an option, cut it off.
_OPTION_TRAILING_JUNK = re.compile(
    r"(?is)\s*(?:(?:answer|ans|correct(?:\s+option)?)\s*[:=.\-].*|"
    r"(?:➡|→|➜|►)\s*.*)$"
)

# Heading that starts an answer-key section.
_ANSWER_KEY_HEADING = re.compile(
    r"^[ \t]*(?:answer\s*key|answers|answer\s*sheet|marking\s*scheme)\b.*$",
    re.IGNORECASE | re.MULTILINE,
)

# "12. B" / "12) C" / "12 - D" / "12: A" pairs inside an answer key.
_ANSWER_PAIR = re.compile(r"\b(\d{1,4})\s*[.):\-]?\s*([A-Da-d])\b")


def _find_option_positions(block: str) -> list[tuple[str, int, int]]:
    """Locate option markers A–D in order. Returns (letter, marker_start, text_start)."""
    positions: list[tuple[str, int, int]] = []
    search_from = 0
    for letter in ("A", "B", "C", "D"):
        pattern = re.compile(
            r"(?:(?<=\s)|(?<=^))\(?([" + letter + letter.lower() + r"])[.)]\s*",
        )
        match = pattern.search(block, search_from)
        if not match:
            break
        positions.append((letter, match.start(), match.end()))
        search_from = match.end()
    return positions


def _clean_text(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def _clean_option_text(text: str) -> str:
    cleaned = _OPTION_TRAILING_JUNK.sub("", text)
    cleaned = _clean_text(cleaned)
    # Drop a leftover ". Cell" style fragment if answer text leaked in.
    cleaned = re.sub(r"\s*[.]\s*[A-Za-z][A-Za-z0-9 +\-/]{0,40}$", "", cleaned).strip()
    return cleaned


def _strip_answer_and_explanation(block: str) -> tuple[str, str, str]:
    """Remove answer/explanation lines from a question block.

    Returns (cleaned_block, correct_option_letter, explanation_text).
    """
    inline_answer = ""

    ans_match = _INLINE_ANSWER.search(block)
    if ans_match:
        inline_answer = ans_match.group(1).upper()
        block = block[: ans_match.start()] + block[ans_match.end():]

    expl_parts: list[str] = []
    for match in list(_EXPLANATION_LINE.finditer(block))[::-1]:
        part = _clean_text(
            re.sub(
                r"^(?:➡|→|➜|►|>{1,3}|explanation)\s*[:=\-]?\s*",
                "",
                match.group(0),
                flags=re.I,
            )
        )
        if part:
            expl_parts.insert(0, part)
        block = block[: match.start()] + block[match.end():]

    return block, inline_answer, " ".join(expl_parts).strip()


def _parse_question_block(number: int, block: str) -> dict[str, Any]:
    issues: list[str] = []
    confidence = 1.0

    block, inline_answer, explanation = _strip_answer_and_explanation(block)

    options = {"A": "", "B": "", "C": "", "D": ""}
    positions = _find_option_positions(block)

    if positions:
        question_text = _clean_text(block[: positions[0][1]])
        for idx, (letter, _start, text_start) in enumerate(positions):
            end = positions[idx + 1][1] if idx + 1 < len(positions) else len(block)
            options[letter] = _clean_option_text(block[text_start:end])
    else:
        question_text = _clean_text(block)

    missing = [letter for letter, value in options.items() if not value]
    if missing:
        issues.append(f"Options {', '.join(missing)} not detected — fill them in manually")
        confidence -= 0.5

    if len(question_text) < 5:
        issues.append("Question text looks incomplete")
        confidence -= 0.4
    if len(question_text) > 1500:
        issues.append("Question text is unusually long — may include stray page content")
        confidence -= 0.2

    return {
        "number": number,
        "question_text": question_text,
        "option_a": options["A"],
        "option_b": options["B"],
        "option_c": options["C"],
        "option_d": options["D"],
        "correct_option": inline_answer,
        "explanation": explanation or None,
        "confidence": confidence,
        "issues": issues,
    }


def _parse_answer_key(key_text: str) -> dict[int, str]:
    answers: dict[int, str] = {}
    for num_str, letter in _ANSWER_PAIR.findall(key_text):
        num = int(num_str)
        if 1 <= num <= MAX_QUESTION_NUMBER and num not in answers:
            answers[num] = letter.upper()
    return answers


def _parse_questions_from_text(text: str, source_label: str) -> dict[str, Any]:
    """Extract questions + answer key from document text."""
    if len(_clean_text(text)) < 40:
        if source_label == "PDF":
            raise PDFParseError(
                "No readable text found in this PDF. It is probably a scanned/image "
                "PDF — OCR is not supported. Re-export the paper as a text PDF, or "
                "use the JSON/CSV template instead."
            )
        raise PDFParseError(
            f"No readable text was found in this {source_label} file. "
            "Check the document or use the JSON/CSV template instead."
        )

    warnings: list[str] = []

    # Split off the answer-key section (if any) before parsing questions.
    key_match = _ANSWER_KEY_HEADING.search(text)
    answer_key: dict[int, str] = {}
    question_text_region = text
    if key_match:
        answer_key = _parse_answer_key(text[key_match.end():])
        if answer_key:
            question_text_region = text[: key_match.start()]
        else:
            warnings.append("Found an 'Answers' heading but could not read any answer pairs from it.")

    starts = list(_QUESTION_START.finditer(question_text_region))
    if not starts:
        raise PDFParseError(
            f"No numbered questions (like '1.' or '1)') were found in this {source_label} file. "
            "Check the file, or use the JSON/CSV template instead."
        )

    questions: list[dict[str, Any]] = []
    for idx, match in enumerate(starts):
        number = int(match.group(1))
        if number > MAX_QUESTION_NUMBER:
            continue
        end = starts[idx + 1].start() if idx + 1 < len(starts) else len(question_text_region)
        block = question_text_region[match.end():end]
        parsed = _parse_question_block(number, block)

        key_answer = answer_key.get(number, "")
        if parsed["correct_option"] and key_answer and parsed["correct_option"] != key_answer:
            parsed["issues"].append(
                f"Inline answer ({parsed['correct_option']}) conflicts with answer key ({key_answer})"
            )
            parsed["confidence"] -= 0.3
            parsed["correct_option"] = key_answer
        elif key_answer:
            parsed["correct_option"] = key_answer

        if not parsed["correct_option"]:
            parsed["issues"].append("No correct answer detected — pick one before saving")
            parsed["confidence"] -= 0.4

        parsed["confidence"] = round(max(0.0, min(1.0, parsed["confidence"])), 2)
        questions.append(parsed)

    # Detect duplicate / out-of-order numbering which usually means the layout
    # confused the parser.
    numbers = [q["number"] for q in questions]
    if len(set(numbers)) != len(numbers):
        warnings.append("Duplicate question numbers detected — check the extracted questions carefully.")
    expected = list(range(numbers[0], numbers[0] + len(numbers))) if numbers else []
    if numbers != expected:
        warnings.append("Question numbering has gaps or jumps — some questions may be missing or merged.")

    if not answer_key and not any(q["correct_option"] for q in questions):
        warnings.append(
            f"No answer key was found in the {source_label} file. "
            "Set the correct option for every question before saving."
        )

    return {
        "questions": questions,
        "answer_key_found": bool(answer_key),
        "warnings": warnings,
    }


def parse_pdf_questions(content: bytes) -> dict[str, Any]:
    """Extract questions + answer key from a PDF. Returns a preview payload.

    Result shape::

        {
          "questions": [ {number, question_text, option_a..d, correct_option,
                          confidence, issues}, ... ],
          "answer_key_found": bool,
          "warnings": [str, ...],
        }
    """
    return _parse_questions_from_text(_extract_pdf_text(content), "PDF")


def parse_docx_questions(content: bytes) -> dict[str, Any]:
    """Extract questions + answer key from a modern Word (.docx) document."""
    return _parse_questions_from_text(_extract_docx_text(content), "Word")
