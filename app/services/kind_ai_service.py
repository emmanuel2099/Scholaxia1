"""
Sia Kind AI Service — enhanced inference for young learners.
Uses custom system prompt + multi-model fallback for maximum intelligence.
"""

from app.ai.kind_prompt_builder import (
    KIND_MASTER_SYSTEM,
    build_kind_chat_prompt,
    build_kind_lesson_prompt,
    build_kind_quiz_prompt,
    build_kind_homework_prompt,
)
from app.ai.model_backend import run_inference
from app.ai.safety_filter import is_educational, sanitize_output
from app.ai.sia_conversation import analyze_conversation, build_conversation_intel
from app.ai.weakness_analyzer import record_interaction


async def kind_chat(
    question: str,
    subject: str,
    user_id: str,
    child_name: str,
    age_group: str = "6-8",
    grade_level: str = None,
    language: str = "english",
    learning_goals: str = None,
    favorite_subjects: list = None,
    conversation_history: list = None,
) -> str:
    safe, reason = is_educational(question)
    if not safe:
        return reason

    prompt = build_kind_chat_prompt(
        question=question,
        subject=subject,
        age_group=age_group,
        grade_level=grade_level,
        child_name=child_name,
        language=language,
        learning_goals=learning_goals,
        favorite_subjects=favorite_subjects,
    )
    conv_intel = build_conversation_intel(question, conversation_history, audience="kind")
    conv = analyze_conversation(question, conversation_history)
    system = KIND_MASTER_SYSTEM
    if conv_intel:
        system = f"{system}\n\n{conv_intel}"
    temp = 0.38 if conv.get("is_follow_up") else 0.45
    try:
        raw = await run_inference(
            prompt,
            conversation_history=conversation_history,
            system_prompt=system,
            max_tokens=4096,
            temperature=temp,
        )
    except RuntimeError as e:
        return f"Sia Kind needs a moment — {str(e)[:100]}. Try again soon!"
    except Exception:
        return (
            f"Sorry {child_name}, I couldn't answer that properly. "
            "Can you ask again in different words?"
        )
    answer = sanitize_output(raw)
    await record_interaction(student_id=user_id, subject=subject, question=question, answer=answer)
    return answer


async def kind_lesson(
    topic: str,
    subject: str,
    user_id: str,
    child_name: str,
    age_group: str = "6-8",
    grade_level: str = None,
    language: str = "english",
) -> str:
    prompt = build_kind_lesson_prompt(
        topic=topic, subject=subject, age_group=age_group,
        grade_level=grade_level, child_name=child_name, language=language,
    )
    raw = await run_inference(prompt, system_prompt=KIND_MASTER_SYSTEM, max_tokens=4096, temperature=0.5)
    answer = sanitize_output(raw)
    await record_interaction(student_id=user_id, subject=subject, question=f"Lesson: {topic}", answer=answer)
    return answer


async def kind_quiz(
    topic: str,
    subject: str,
    child_name: str,
    age_group: str = "6-8",
    num_questions: int = 5,
) -> dict:
    """Return structured quiz for the interactive Kids Learn & Play UI."""
    import json
    import re

    prompt = build_kind_quiz_prompt(
        topic=topic, subject=subject, age_group=age_group,
        num_questions=num_questions, child_name=child_name,
    )
    raw = await run_inference(
        prompt, system_prompt=KIND_MASTER_SYSTEM, max_tokens=3000, temperature=0.5
    )
    text = sanitize_output(raw or "")

    questions: list[dict] = []
    intro = ""

    # Prefer JSON payload from the model.
    json_block = text
    fence = re.search(r"```(?:json)?\s*([\s\S]*?)```", text, re.I)
    if fence:
        json_block = fence.group(1).strip()
    else:
        start = text.find("{")
        end = text.rfind("}")
        if start >= 0 and end > start:
            json_block = text[start : end + 1]

    try:
        data = json.loads(json_block)
        intro = str(data.get("intro") or "").strip()
        raw_qs = data.get("questions") or []
        if isinstance(raw_qs, list):
            for i, q in enumerate(raw_qs):
                if not isinstance(q, dict):
                    continue
                opts = q.get("options") or {}
                if isinstance(opts, list) and len(opts) >= 4:
                    opts = {
                        "A": str(opts[0]),
                        "B": str(opts[1]),
                        "C": str(opts[2]),
                        "D": str(opts[3]),
                    }
                if not isinstance(opts, dict):
                    continue
                option_map = {
                    "A": str(opts.get("A") or opts.get("a") or "").strip(),
                    "B": str(opts.get("B") or opts.get("b") or "").strip(),
                    "C": str(opts.get("C") or opts.get("c") or "").strip(),
                    "D": str(opts.get("D") or opts.get("d") or "").strip(),
                }
                if not all(option_map.values()):
                    continue
                correct = str(q.get("correct") or "A").strip().upper()[:1]
                if correct not in option_map:
                    correct = "A"
                questions.append(
                    {
                        "id": str(q.get("id") or i + 1),
                        "question": str(q.get("question") or q.get("prompt") or "").strip(),
                        "options": option_map,
                        "correct": correct,
                    }
                )
    except Exception:
        questions = []

    # Fallback: parse classic Q1 / A) B) C) D) text quizzes.
    if not questions:
        blocks = re.split(r"(?=\n?\s*Q\d+[\.\)\:])", text)
        for block in blocks:
            qm = re.search(
                r"Q(\d+)[\.\)\:]\s*(.+?)(?=\n\s*[A-D][\.\)])",
                block,
                re.S | re.I,
            )
            if not qm:
                continue
            opts = {}
            for letter in "ABCD":
                om = re.search(
                    rf"{letter}[\.\)]\s*(.+?)(?=\n\s*[A-D][\.\)]|\n\s*Q\d+|\Z)",
                    block,
                    re.S | re.I,
                )
                if om:
                    opts[letter] = om.group(1).strip()
            if len(opts) >= 2:
                questions.append(
                    {
                        "id": qm.group(1),
                        "question": qm.group(2).strip(),
                        "options": {
                            "A": opts.get("A", ""),
                            "B": opts.get("B", ""),
                            "C": opts.get("C", ""),
                            "D": opts.get("D", ""),
                        },
                        "correct": "",  # unknown — app will ask Sia to check
                    }
                )

    if not intro and questions:
        intro = f"Hi {child_name}! Tap an answer for each question. Good luck!"

    return {
        "intro": intro or text,
        "questions": questions,
        "sia_kind": text,
        "topic": topic,
        "num_questions": len(questions) or num_questions,
    }



async def kind_homework_help(
    question: str,
    subject: str,
    user_id: str,
    child_name: str,
    age_group: str = "6-8",
    child_attempt: str = None,
) -> str:
    prompt = build_kind_homework_prompt(
        question=question, subject=subject, age_group=age_group,
        child_name=child_name, child_attempt=child_attempt,
    )
    raw = await run_inference(prompt, system_prompt=KIND_MASTER_SYSTEM, max_tokens=2048, temperature=0.45)
    answer = sanitize_output(raw)
    await record_interaction(student_id=user_id, subject=subject, question=question, answer=answer)
    return answer
