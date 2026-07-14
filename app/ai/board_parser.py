"""
Board Parser — Voice Classroom Only
-------------------------------------
Extracts rich structured content from Sia's response for the voice classroom board.
Produces: headings, steps, formulas, equations, worked examples, diagram hints.
NOT used in the text chat — chat shows full text response.
"""

import re
from typing import TypedDict


class BoardItem(TypedDict):
    type: str   # heading | step | formula | point | equation | example | diagram_hint
    content: str


def extract_board_content(sia_response: str) -> list[BoardItem]:
    """
    Parse Sia's response and extract items for the classroom board.
    Prioritises: equations, worked examples, formulas, key steps.
    Returns max 15 items.
    """
    board = []
    lines = sia_response.split("\n")
    step_num = 0

    for line in lines:
        line = line.strip()
        if not line:
            continue

        # Remove markdown bold markers for display
        clean = re.sub(r"\*\*(.*?)\*\*", r"\1", line)

        # ── Equations and formulas ────────────────────────
        # Lines with math operators and = sign
        if re.search(r"[=]\s*[\d\w]", clean) and re.search(r"[\d\w]\s*[+\-×÷*/^]", clean):
            board.append({"type": "equation", "content": clean})
            continue

        # Lines that look like formulas (F = ma, E = mc², v = u + at)
        if re.match(r"^[A-Za-z]\s*=\s*", clean) and len(clean) < 80:
            board.append({"type": "formula", "content": clean})
            continue

        # ── Numbered steps ────────────────────────────────
        if re.match(r"^\d+\.\s+", clean):
            step_num += 1
            content = re.sub(r"^\d+\.\s+", "", clean)
            board.append({"type": "step", "content": content})
            continue

        # ── Worked example lines ──────────────────────────
        if any(clean.lower().startswith(w) for w in
               ["step ", "given:", "find:", "solution:", "working:", "answer:", "therefore:",
                "so,", "thus,", "hence,", "substituting", "let ", "let's"]):
            board.append({"type": "example", "content": clean})
            continue

        # ── Headings ──────────────────────────────────────
        if clean and (
            re.match(r"^\*\*(.+)\*\*:?$", line)
            or (clean.endswith(":") and len(clean) < 50 and clean[0].isupper())
        ):
            content = clean.rstrip(":")
            board.append({"type": "heading", "content": content})
            continue

        # ── Bullet points ─────────────────────────────────
        if line.startswith(("- ", "• ", "* ")):
            content = clean[2:].strip()
            if content:
                board.append({"type": "point", "content": content})
            continue

        # ── Diagram hints ─────────────────────────────────
        if any(word in clean.lower() for word in
               ["diagram", "figure", "imagine", "picture", "draw", "sketch",
                "triangle", "circuit", "wave", "cell", "force", "arrow"]):
            board.append({"type": "diagram_hint", "content": clean})
            continue

        # ── Key labeled lines (Definition:, Example:, etc.) ──
        if re.match(r"^(Definition|Example|Key point|Formula|Note|Remember|Exam tip|Try this):", clean, re.IGNORECASE):
            label_match = re.match(r"^(\w[\w ]+):\s*(.*)", clean)
            if label_match:
                label = label_match.group(1)
                content = label_match.group(2)
                if label.lower() in ("definition", "formula", "key point", "remember"):
                    board.append({"type": "heading", "content": f"{label}: {content}"})
                elif label.lower() in ("example", "try this"):
                    board.append({"type": "example", "content": f"{label}: {content}"})
                else:
                    board.append({"type": "point", "content": f"{label}: {content}"})
            continue

    # Deduplicate and limit
    seen = set()
    unique = []
    for item in board:
        key = item["content"][:60]
        if key not in seen:
            seen.add(key)
            unique.append(item)

    return unique[:15]
