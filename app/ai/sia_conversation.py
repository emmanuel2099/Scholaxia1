"""
Sia Conversation Intelligence
-----------------------------
Topic stickiness, follow-up detection, and thread continuity
for student Sia, Teacher AI, and Sia Kind.
"""

from app.ai.prompt_builder import classify_input

_SUBJECT_HINTS = [
    "mathematics", "math", "maths", "physics", "chemistry", "biology",
    "english", "economics", "government", "algebra", "geometry",
]

TOPIC_CHANGE_SIGNALS = [
    "new topic", "change topic", "different topic", "something else",
    "another subject", "switch to", "move on to", "let's talk about",
    "lets talk about", "forget that", "stop that", "instead teach",
    "now teach me", "i want to learn about", "can we do", "different subject",
    "talk about something", "another thing",
]

FOLLOW_UP_SIGNALS = [
    "why", "how come", "what about", "and then", "continue", "go on",
    "explain more", "more detail", "i don't understand", "i dont understand",
    "not clear", "say again", "another example", "next step", "what next",
    "so meaning", "meaning", "huh", "okay so", "ok so", "tell me more",
    "what do you mean", "can you clarify", "still confused", "i'm lost",
]

SHORT_ACKS = {
    "yes", "no", "yeah", "yep", "nope", "ok", "okay", "sure", "correct",
    "wrong", "true", "false", "maybe", "alright", "cool", "nice", "thanks",
}


def _msg_role(msg) -> str:
    if not isinstance(msg, dict):
        return "user"
    role = (msg.get("role") or "").lower()
    if role in ("assistant", "model", "ai", "sia"):
        return "assistant"
    return "user"


def extract_active_topic(history: list, current_question: str) -> str:
    """Best guess at what the conversation is currently about."""
    candidates = []
    for msg in history or []:
        if _msg_role(msg) != "user":
            continue
        content = (msg.get("content") or "").strip()
        if len(content) < 6:
            continue
        kind = classify_input(content, has_history=True)
        if kind in ("greeting", "casual") and len(content) < 30:
            continue
        candidates.append(content[:140])

    if candidates:
        return candidates[-1]
    return (current_question or "")[:140]


def detect_topic_change(question: str, active_topic: str) -> bool:
    q = (question or "").lower().strip()
    if any(sig in q for sig in TOPIC_CHANGE_SIGNALS):
        return True

    if not active_topic:
        return False

    at = active_topic.lower()
    if any(v in q for v in ("teach me", "help me with", "explain", "i want to learn")):
        for hint in _SUBJECT_HINTS:
            if len(hint) < 4:
                continue
            if hint in q and hint not in at:
                return True
    return False


def is_follow_up(question: str, history: list) -> bool:
    if not history:
        return False

    q = (question or "").lower().strip().rstrip("?.!")
    if q in SHORT_ACKS:
        return True

    kind = classify_input(question, has_history=True)
    if kind in ("answer", "conversation_turn"):
        return True

    if len(q) < 70 and any(sig in q for sig in FOLLOW_UP_SIGNALS):
        return True

    return len(q) < 25 and "?" not in question


def analyze_conversation(question: str, history: list = None) -> dict:
    history = history or []
    active_topic = extract_active_topic(history, question)
    topic_changed = bool(history) and detect_topic_change(question, active_topic)
    follow_up = is_follow_up(question, history) and not topic_changed

    return {
        "active_topic": active_topic,
        "topic_changed": topic_changed,
        "is_follow_up": follow_up,
        "has_thread": len(history) >= 2,
        "thread_mode": (
            "follow_up" if follow_up
            else "topic_change" if topic_changed
            else "continue" if active_topic and history
            else "fresh"
        ),
    }


def build_conversation_intel(
    question: str,
    history: list = None,
    audience: str = "student",
) -> str:
    """Prompt block injected into system prompt for all three AIs."""
    conv = analyze_conversation(question, history)
    if not conv["has_thread"]:
        return ""

    lines = [
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
        "CONVERSATION THREAD (mandatory)",
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    ]

    if conv["thread_mode"] == "follow_up":
        lines.append(
            f'You are MID-DISCUSSION on: "{conv["active_topic"]}"\n'
            "The latest message is a follow-up or answer to YOU.\n"
            "RULES:\n"
            "- STAY on this exact topic — do NOT start a new lesson or repeat introductions.\n"
            "- Continue from your last explanation (next step, deeper point, or evaluate their answer).\n"
            "- If they answered your check question: say if correct/wrong, then go one step deeper.\n"
            "- Do NOT jump to a different subject unless they clearly asked to."
        )
    elif conv["thread_mode"] == "topic_change":
        lines.append(
            "The user is switching to a new topic. Briefly acknowledge, then teach the new request.\n"
            "Do not drag the old topic into the new answer."
        )
    else:
        lines.append(
            f'Active discussion topic: "{conv["active_topic"]}"\n'
            "Build on what was already said. Do not reset or repeat the opening explanation."
        )

    if audience == "teacher":
        lines.append(
            "Teacher thread: refine the SAME lesson plan, quiz, or document in progress. "
            "Only produce a brand-new structure if they explicitly ask for one."
        )
    elif audience == "kind":
        lines.append(
            "Child thread: stay on the same story, game, or lesson. "
            "Use simple words. Do not confuse them by jumping topics."
        )
    else:
        lines.append(
            "Student thread: think like a tutor in an ongoing lesson — "
            "one topic at a time until the student changes it."
        )

    return "\n".join(lines)
