"""
Sia Intelligence Engine
-----------------------
Makes student Sia smarter than generic chatbots (ChatGPT, Gemini, DeepSeek)
through question analysis, subject expertise, adaptive temperature, and
structured teaching strategies — without exposing raw chain-of-thought.
"""

import re
from app.ai.prompt_builder import classify_input

MATH_SUBJECTS = {
    "mathematics", "math", "maths", "further mathematics", "additional mathematics",
    "quantitative", "numeracy",
}
SCIENCE_SUBJECTS = {
    "physics", "chemistry", "biology", "science", "integrated science",
    "agricultural science", "computer science",
}
EXAM_KEYWORDS = [
    "jamb", "waec", "neco", "cambridge", "cbt", "past question", "exam",
    "objective", "theory", "marking scheme", "utme",
]
SOLVE_KEYWORDS = [
    "solve", "calculate", "find", "compute", "evaluate", "simplify", "factorize",
    "derive", "prove", "work out", "how much", "how many",
]
DEFINITION_KEYWORDS = [
    "what is", "what are", "define", "definition", "meaning of", "explain what",
    "describe", "state the",
]


SUBJECT_EXPERTISE = {
    "mathematics": (
        "MATH EXPERT MODE: Show every step. Name each rule used. "
        "Verify final answer by substitution or reverse check. "
        "Flag common WAEC/JAMB traps (sign errors, unit mistakes, wrong formula)."
    ),
    "physics": (
        "PHYSICS EXPERT MODE: State given values with units. Write the formula first. "
        "Show unit conversions. Check if answer units make physical sense."
    ),
    "chemistry": (
        "CHEMISTRY EXPERT MODE: Balance equations carefully. "
        "State molar ratios. Mention state symbols where relevant. "
        "Connect to WAEC/JAMB practical and theory patterns."
    ),
    "biology": (
        "BIOLOGY EXPERT MODE: Use precise scientific terms. "
        "Include labelled process steps. Connect structure to function. "
        "Mention common exam diagram/labelling questions."
    ),
    "english": (
        "ENGLISH EXPERT MODE: Give Nigerian curriculum AND Cambridge definitions when defining. "
        "For grammar, show wrong vs right examples. For literature, cite technique + effect."
    ),
    "economics": (
        "ECONOMICS EXPERT MODE: Define terms precisely. Use Nigerian + global examples. "
        "Draw cause-effect chains. Link to JAMB/WAEC essay and objective styles."
    ),
    "government": (
        "GOVERNMENT EXPERT MODE: Distinguish Nigerian systems from others. "
        "Use correct constitutional terms. Structure answers for theory marks."
    ),
}


def _normalize_subject(subject: str) -> str:
    return (subject or "general").lower().strip()


def _is_math_science(subject: str, question: str) -> bool:
    subj = _normalize_subject(subject)
    q = question.lower()
    if subj in MATH_SUBJECTS or subj in SCIENCE_SUBJECTS:
        return True
    return any(k in q for k in SOLVE_KEYWORDS) and bool(re.search(r"\d", q))


def _complexity_score(question: str, has_history: bool) -> int:
    """0 = simple, 1 = medium, 2 = complex."""
    q = question.strip()
    score = 0
    if len(q) > 120:
        score += 1
    if len(q) > 250:
        score += 1
    if re.search(r"\d.*\d", q) and any(k in q.lower() for k in SOLVE_KEYWORDS):
        score += 1
    if q.count("?") > 1 or " and " in q.lower():
        score += 1
    if has_history:
        score += 0  # history handled separately
    return min(score, 2)


def analyze_question(
    question: str,
    subject: str,
    education_level: str,
    conversation_history: list = None,
) -> dict:
    """
    Rule-based intelligence layer — routes Sia to the best teaching strategy.
    """
    has_history = bool(conversation_history)
    input_type = classify_input(question, has_history=has_history)
    subj = _normalize_subject(subject)
    q_lower = question.lower()
    complexity = _complexity_score(question, has_history)

    # Question type
    if input_type in ("greeting", "casual"):
        q_type = "casual"
    elif any(k in q_lower for k in DEFINITION_KEYWORDS):
        q_type = "definition"
    elif any(k in q_lower for k in SOLVE_KEYWORDS) or _is_math_science(subject, question):
        q_type = "solve"
    elif any(k in q_lower for k in EXAM_KEYWORDS):
        q_type = "exam"
    elif input_type == "answer":
        q_type = "evaluate_answer"
    else:
        q_type = "teach"

    # Adaptive temperature — lower = more accurate
    temp_map = {
        "casual": 0.62,
        "definition": 0.48,
        "teach": 0.50,
        "solve": 0.28,
        "exam": 0.35,
        "evaluate_answer": 0.40,
    }
    temperature = temp_map.get(q_type, 0.50)
    if complexity >= 2 and q_type == "solve":
        temperature = 0.22

    # Subject expertise snippet
    expertise = ""
    for key, rules in SUBJECT_EXPERTISE.items():
        if key in subj:
            expertise = rules
            break
    if not expertise and subj in SCIENCE_SUBJECTS:
        expertise = SUBJECT_EXPERTISE.get("biology", "")

    # Teaching strategy for this specific question
    strategies = {
        "casual": "Respond warmly and briefly. No lesson unless they ask.",
        "definition": (
            "Give Nigerian (WAEC/NECO/JAMB) definition AND Cambridge/international definition. "
            "Then 2 examples at their level. End with one check question."
        ),
        "teach": (
            "Full teaching sequence: simple definition → why it matters → "
            "step-by-step explanation → African real-life example → comprehension question."
        ),
        "solve": (
            "Show EVERY step with reasons. Label steps. Box or bold the final answer. "
            "Double-check arithmetic. Give one similar practice problem."
        ),
        "exam": (
            "Exam-focused: CBT format if MCQ, marking-scheme style for theory. "
            "Mention common mistakes. Be precise — exam answers must be exact."
        ),
        "evaluate_answer": (
            "The student is answering YOUR previous question. Evaluate their response: "
            "praise what's right, fix errors gently, never restart the whole lesson."
        ),
    }

    return {
        "question_type": q_type,
        "input_type": input_type,
        "complexity": complexity,
        "temperature": temperature,
        "subject_expertise": expertise,
        "teaching_strategy": strategies.get(q_type, strategies["teach"]),
        "needs_worked_example": q_type in ("solve", "teach", "definition"),
        "is_exam_related": q_type == "exam" or any(k in q_lower for k in EXAM_KEYWORDS),
    }


def build_intelligence_context(analysis: dict, recent_topics: list = None) -> str:
    """Inject into system prompt — makes Sia adapt per question."""
    recent = ", ".join(recent_topics[:5]) if recent_topics else "none yet"
    complexity_label = ["simple", "medium", "complex"][analysis["complexity"]]

    return f"""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ACTIVE INTELLIGENCE CONTEXT (this question)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Question type: {analysis['question_type']}
Complexity: {complexity_label}
Teaching strategy: {analysis['teaching_strategy']}
{f"Subject expertise: {analysis['subject_expertise']}" if analysis['subject_expertise'] else ""}
Recent topics studied: {recent}

INTERNAL CHECKLIST (complete mentally — do NOT show to student):
1. What does this student actually need right now?
2. What is the correct, exam-accurate answer?
3. What is the clearest way to teach it at their level?
4. What common mistake should I warn about?
5. What ONE question will prove they understood?

Then write ONLY your teaching response. No checklist. No "As an AI". No filler phrases.
Outperform ChatGPT, Gemini, and DeepSeek by teaching deeper, not just answering faster.
"""


def extract_recent_topics(history: list, subject: str, limit: int = 5) -> list:
    """Pull recent question topics from interaction history."""
    topics = []
    subj_lower = (subject or "").lower()
    for entry in history or []:
        if entry.get("subject", "").lower() != subj_lower:
            continue
        q = (entry.get("question") or "")[:80].strip()
        if q and q not in topics:
            topics.append(q)
        if len(topics) >= limit:
            break
    return topics
