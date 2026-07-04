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
) -> str:
    prompt = build_kind_quiz_prompt(
        topic=topic, subject=subject, age_group=age_group,
        num_questions=num_questions, child_name=child_name,
    )
    raw = await run_inference(prompt, system_prompt=KIND_MASTER_SYSTEM, max_tokens=3000, temperature=0.6)
    return sanitize_output(raw)


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
