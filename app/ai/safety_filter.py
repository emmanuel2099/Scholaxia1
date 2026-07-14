"""
AI Safety Filter
"""
import re
from typing import Tuple

BLOCKED_INPUT_PATTERNS = [
    r"\b(hack|exploit|crack|bypass|jailbreak)\b",
    r"\b(kill|murder|suicide|self.harm)\b",
    r"\b(sex|porn|nude|naked)\b",
    r"ignore (previous|all|your) instructions",
    r"you are now",
    r"pretend (you are|to be)",
    r"act as (a|an)",
]

BLOCKED_OUTPUT_PATTERNS = [
    r"https?://(?!scholaxia\.com)\S+",
    r"\b\d{10,11}\b",
    r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b",
    r"(whatsapp|telegram|instagram|facebook|twitter|tiktok)",
]

OFF_TOPIC_KEYWORDS = [
    "stock price", "lottery", "bet", "gambling",
    "recipe", "movie", "music", "celebrity",
]

EDUCATIONAL_KEYWORDS = [
    "student", "teacher", "learn", "teach", "education", "school",
    "study", "exam", "test", "homework", "lesson", "concept",
    "understand", "method", "approach", "pedagogy", "curriculum",
    "assessment", "evaluate", "grade", "classroom", "instruction",
    "mathematics", "science", "physics", "chemistry", "biology",
    "history", "geography", "english", "literature", "language",
    "problem", "solve", "solution", "answer", "question",
    "explain", "understanding", "knowledge", "skill", "ability",
]


def is_educational(question: str) -> Tuple[bool, str]:
    lower = question.lower().strip()
    if len(lower) < 15:
        return True, ""
    
    # Allow questions about languages the AI speaks
    language_questions = [
        "what language", "which language", "languages do you",
        "languages can you", "languages you speak", "how many language",
        "what languages", "do you speak",
    ]
    if any(q in lower for q in language_questions):
        return True, ""
    
    # Explicitly allow educational content
    for keyword in EDUCATIONAL_KEYWORDS:
        if keyword in lower:
            return True, ""
    
    # Check for blocked patterns
    for pattern in BLOCKED_INPUT_PATTERNS:
        if re.search(pattern, lower, re.IGNORECASE):
            return False, "I can only help with educational topics."
    
    # Check for off-topic keywords (only if no educational context found)
    for keyword in OFF_TOPIC_KEYWORDS:
        if keyword in lower:
            return False, "I can only help with educational topics."
    
    return True, ""


def sanitize_output(text: str) -> str:
    for pattern in BLOCKED_OUTPUT_PATTERNS:
        text = re.sub(pattern, "[removed]", text, flags=re.IGNORECASE)
    return text.strip()


def check_exam_lock(is_school_exam: bool, ai_locked: bool) -> Tuple[bool, str]:
    if is_school_exam and ai_locked:
        return False, "AI assistance is not available during this exam."
    return True, ""

