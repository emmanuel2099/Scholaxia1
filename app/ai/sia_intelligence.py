"""
Sia Intelligence Engine
-----------------------
Makes student Sia smarter than generic chatbots (ChatGPT, Gemini, DeepSeek)
through question analysis, subject expertise, adaptive temperature, and
structured teaching strategies — without exposing raw chain-of-thought.
"""

import re
from app.ai.prompt_builder import classify_input
from app.ai.sia_conversation import analyze_conversation

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


SUBJECT_ALIASES = {
    "mathematics": [
        "math", "maths", "mathematics", "algebra", "geometry", "calculus",
        "trigonometry", "equation", "quation", "quadratic", "simultaneous",
        "indices", "logarithm", "polynomial", "fraction", "ratio",
    ],
    "physics": ["physics", "mechanics", "optics", "thermodynamics", "kinematics", "newton"],
    "chemistry": ["chemistry", "organic", "molar", "periodic", "acid", "base", "titration"],
    "biology": ["biology", "ecology", "genetics", "photosynthesis", "cell", "anatomy"],
    "english": ["english", "grammar", "literature", "comprehension", "essay", "noun", "verb"],
    "economics": ["economics", "demand", "supply", "gdp", "inflation", "market"],
    "government": ["government", "civics", "constitution", "democracy", "federalism"],
}


def _title_subject(name: str) -> str:
    key = (name or "general").lower().strip()
    if key in ("math", "maths"):
        return "Mathematics"
    return (name or "General").strip().title()


def resolve_active_subject(
    question: str,
    fallback_subject: str,
    profile_subjects: list = None,
) -> str:
    """Prefer the subject the student asked for over profile defaults."""
    q = (question or "").lower()
    scores: dict[str, int] = {}
    for canon, aliases in SUBJECT_ALIASES.items():
        for alias in aliases:
            if alias in q:
                scores[canon] = scores.get(canon, 0) + max(len(alias), 3)

    for subj in profile_subjects or []:
        s = subj.lower().strip()
        if s and s in q:
            scores[s] = scores.get(s, 0) + 10

    if scores:
        best = max(scores, key=scores.get)
        return _title_subject(best)

    return _title_subject(fallback_subject)


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
    conv = analyze_conversation(question, conversation_history)
    input_type = classify_input(question, has_history=has_history)
    subj = _normalize_subject(subject)
    q_lower = question.lower()
    complexity = _complexity_score(question, has_history)

    # Question type
    if conv["is_follow_up"] and conv["active_topic"]:
        q_type = "continue_topic"
    elif input_type in ("greeting", "casual"):
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
        "continue_topic": 0.38,
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
        "continue_topic": (
            f'STAY on thread: "{conv["active_topic"][:120]}". '
            "Do NOT restart. Continue teaching, go one step deeper, or evaluate their answer. "
            "If they said they don't understand, re-explain the SAME point more simply."
        ),
        "casual": (
            "Respond warmly and briefly in their tone. No lesson unless they ask. "
            "Do NOT mention their profile subjects, class, or exam prep unprompted — "
            "just greet back and ask what they want to work on."
        ),
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
        "conversation": conv,
    }


def build_intelligence_context(analysis: dict, recent_topics: list = None,
                               education_level: str = None,
                               conversation_intel: str = "") -> str:
    """Inject into system prompt — makes Sia adapt per question."""
    recent = ", ".join(recent_topics[:5]) if recent_topics else "none yet"
    complexity_label = ["simple", "medium", "complex"][analysis["complexity"]]
    level_key = (education_level or "").upper()
    level_note = ""
    if level_key and level_key not in ("UNKNOWN", ""):
        level_note = (
            f"\nStudent class: {education_level} — simplify vocabulary and examples for this level. "
            f"Do not teach content meant for higher classes unless the student explicitly asks."
        )

    conv = analysis.get("conversation") or {}
    thread_note = ""
    if conv.get("active_topic") and conv.get("has_thread"):
        thread_note = f"\nActive thread topic: {conv['active_topic'][:120]}"

    conv_block = f"\n{conversation_intel}" if conversation_intel else ""

    return f"""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ACTIVE INTELLIGENCE CONTEXT (this question)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Question type: {analysis['question_type']}
Complexity: {complexity_label}
Teaching strategy: {analysis['teaching_strategy']}
{f"Subject expertise: {analysis['subject_expertise']}" if analysis['subject_expertise'] else ""}
Recent topics studied: {recent}{level_note}{thread_note}{conv_block}

INTERNAL CHECKLIST (complete mentally — do NOT show to student):
1. What thread are we in? Stay on it unless they changed topic.
2. What is the correct, exam-accurate answer for THIS step?
3. What is the clearest next teaching move (not a full restart)?
4. What common mistake should I warn about?
5. What ONE question will prove they understood?

Then write ONLY your teaching response. No checklist. No "As an AI". No filler phrases.
Outperform ChatGPT, Gemini, and DeepSeek by teaching deeper and staying on topic.
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
