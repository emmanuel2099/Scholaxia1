"""
Sia AI Service
--------------
Orchestrates the full Sia pipeline with student memory injection.
"""

from app.ai.prompt_builder import (
    build_prompt, build_explain_prompt, build_solve_prompt,
    build_evaluate_prompt, build_generate_questions_prompt,
    build_performance_feedback_prompt, build_wrong_answer_prompt,
    build_lesson_prompt, build_anti_cheat_prompt, build_debate_prompt,
    build_study_companion_prompt, build_pdf_prompt, build_language_immersion_prompt,
    build_study_plan_prompt, build_cambridge_prompt, build_parent_report_prompt,
    build_sia_system_prompt, build_chat_user_prompt,
)
from app.ai.sia_intelligence import (
    analyze_question, build_intelligence_context, extract_recent_topics,
)
from app.ai.model_backend import run_inference
from app.ai.safety_filter import is_educational, sanitize_output
from app.ai.weakness_analyzer import record_interaction, get_weak_topics, get_student_history

SIA_MAX_TOKENS = 8192


async def _run_sia_inference(
    prompt: str,
    system_prompt: str = None,
    conversation_history: list = None,
    temperature: float = 0.50,
) -> str:
    """Run inference with Sia-optimized settings."""
    return await run_inference(
        prompt,
        conversation_history=conversation_history,
        system_prompt=system_prompt,
        max_tokens=SIA_MAX_TOKENS,
        temperature=temperature,
    )


async def _get_memory(student_id: str, subject: str) -> dict:
    """Build student memory profile for prompt injection."""
    try:
        weak = await get_weak_topics(student_id)
        history = await get_student_history(student_id)
        weak_list = weak.get(subject, []) if isinstance(weak, dict) else []
        subjects_seen = {}
        for h in history:
            s = h.get("subject", "")
            subjects_seen[s] = subjects_seen.get(s, 0) + 1
        strong = [s for s, c in subjects_seen.items() if c >= 3 and s != subject]
        return {
            "weak_topics": weak_list,
            "strong_topics": strong[:3],
            "recent_topics": extract_recent_topics(history, subject),
            "learning_style": "adaptive",
            "confidence_score": "building",
        }
    except Exception:
        return {}


async def _prepare_sia_context(
    question: str, subject: str, education_level: str, language: str,
    student_name: str, student_id: str, conversation_history: list = None,
) -> tuple:
    """Build system prompt + analysis for any Sia call."""
    memory = await _get_memory(student_id, subject)
    analysis = analyze_question(question, subject, education_level, conversation_history)
    intel = build_intelligence_context(analysis, memory.get("recent_topics"), education_level)
    system = build_sia_system_prompt(
        student_name=student_name, subject=subject,
        education_level=education_level, language=language,
        student_memory=memory, raw_input=question,
        intelligence_context=intel,
    )
    return system, analysis, memory


async def get_ai_response(question: str, subject: str, education_level: str,
                          language: str, student_id: str, student_name: str = "there",
                          conversation_history: list = None,
                          tutor_mode: str = "smart") -> str:
    safe, reason = is_educational(question)
    if not safe:
        return reason

    system, analysis, _ = await _prepare_sia_context(
        question, subject, education_level, language,
        student_name, student_id, conversation_history,
    )
    prompt = build_chat_user_prompt(
        question=question, student_name=student_name,
        conversation_history=conversation_history,
        education_level=education_level,
        subject=subject,
        tutor_mode=tutor_mode,
    )
    try:
        raw = await _run_sia_inference(
            prompt, system_prompt=system,
            conversation_history=conversation_history,
            temperature=analysis["temperature"],
        )
    except Exception as e:
        if "429" in str(e) or "rate limit" in str(e).lower():
            return f"I'm getting too many requests right now, {student_name}. Please wait a moment and try again."
        raise
    answer = sanitize_output(raw)
    await record_interaction(student_id=student_id, subject=subject, question=question, answer=answer)
    return answer


async def sia_explain(topic: str, subject: str, education_level: str,
                      language: str, student_id: str, student_name: str) -> str:
    safe, reason = is_educational(topic)
    if not safe:
        return reason
    memory = await _get_memory(student_id, subject)
    system, analysis, _ = await _prepare_sia_context(
        topic, subject, education_level, language, student_name, student_id,
    )
    prompt = build_explain_prompt(topic=topic, subject=subject, education_level=education_level,
                                  language=language, student_name=student_name, student_memory=memory)
    return sanitize_output(await _run_sia_inference(
        prompt, system_prompt=system, temperature=analysis["temperature"],
    ))


async def sia_solve(question: str, subject: str, education_level: str,
                    language: str, student_id: str, student_name: str) -> str:
    safe, reason = is_educational(question)
    if not safe:
        return reason
    memory = await _get_memory(student_id, subject)
    system, analysis, _ = await _prepare_sia_context(
        question, subject, education_level, language, student_name, student_id,
    )
    prompt = build_solve_prompt(question=question, subject=subject, education_level=education_level,
                                language=language, student_name=student_name, student_memory=memory)
    try:
        raw = await _run_sia_inference(
            prompt, system_prompt=system, temperature=analysis["temperature"],
        )
    except Exception as e:
        if "429" in str(e) or "rate limit" in str(e).lower():
            return f"Too many requests right now, {student_name}. Please wait a moment and try again."
        raise
    answer = sanitize_output(raw)
    await record_interaction(student_id=student_id, subject=subject, question=question, answer=answer)
    return answer


async def sia_evaluate(question: str, student_answer: str, subject: str,
                       education_level: str, language: str, student_id: str, student_name: str) -> str:
    memory = await _get_memory(student_id, subject)
    prompt = build_evaluate_prompt(question=question, student_answer=student_answer, subject=subject,
                                   education_level=education_level, language=language,
                                   student_name=student_name, student_memory=memory)
    return sanitize_output(await _run_sia_inference(prompt))


async def sia_generate_questions(topic: str, number: int, subject: str, education_level: str,
                                  language: str, student_name: str, curriculum: str = "WAEC",
                                  student_id: str = "") -> str:
    memory = await _get_memory(student_id, subject) if student_id else {}
    prompt = build_generate_questions_prompt(topic=topic, number=number, subject=subject,
                                             education_level=education_level, language=language,
                                             student_name=student_name, curriculum=curriculum,
                                             student_memory=memory)
    return sanitize_output(await _run_sia_inference(prompt))


async def sia_performance_feedback(weak_topics: list, subject: str, education_level: str,
                                    language: str, student_id: str, student_name: str,
                                    score: float = None) -> str:
    memory = await _get_memory(student_id, subject)
    prompt = build_performance_feedback_prompt(weak_topics=weak_topics, subject=subject,
                                               education_level=education_level, language=language,
                                               student_name=student_name, score=score,
                                               student_memory=memory)
    return sanitize_output(await _run_sia_inference(prompt))


async def sia_explain_wrong_answer(question: str, wrong_answer: str, correct_answer: str,
                                    subject: str, education_level: str, language: str,
                                    student_name: str, student_id: str = "") -> str:
    memory = await _get_memory(student_id, subject) if student_id else {}
    prompt = build_wrong_answer_prompt(question=question, wrong_answer=wrong_answer,
                                       correct_answer=correct_answer, subject=subject,
                                       education_level=education_level, language=language,
                                       student_name=student_name, student_memory=memory)
    return sanitize_output(await _run_sia_inference(prompt))


async def sia_lesson(topic: str, subject: str, education_level: str, language: str,
                     student_id: str, student_name: str, curriculum: str,
                     step: int = 1, previous_response: str = "") -> str:
    memory = await _get_memory(student_id, subject)
    prompt = build_lesson_prompt(
        topic=topic, subject=subject, education_level=education_level,
        language=language, student_name=student_name, curriculum=curriculum,
        step=step, previous_response=previous_response, student_memory=memory,
    )
    return sanitize_output(await _run_sia_inference(prompt))


async def sia_anti_cheat(question: str, submitted_answer: str,
                          subject: str, student_name: str) -> str:
    prompt = build_anti_cheat_prompt(
        question=question, submitted_answer=submitted_answer,
        subject=subject, student_name=student_name,
    )
    return sanitize_output(await _run_sia_inference(prompt))


async def sia_debate(topic: str, student_position: str,
                     subject: str, student_name: str) -> str:
    prompt = build_debate_prompt(
        topic=topic, student_position=student_position,
        subject=subject, student_name=student_name,
    )
    return sanitize_output(await _run_sia_inference(prompt))


async def sia_study_companion(student_name: str, last_subject: str,
                               last_topic: str, days_inactive: int) -> str:
    prompt = build_study_companion_prompt(
        student_name=student_name, last_subject=last_subject,
        last_topic=last_topic, days_inactive=days_inactive,
    )
    return sanitize_output(await _run_sia_inference(prompt))


async def sia_process_pdf(pdf_content: str, output_type: str, subject: str,
                           education_level: str, curriculum: str, exam_standard: str,
                           student_name: str, language: str = "english") -> str:
    prompt = build_pdf_prompt(
        pdf_content=pdf_content, output_type=output_type, subject=subject,
        education_level=education_level, curriculum=curriculum,
        exam_standard=exam_standard, student_name=student_name, language=language,
    )
    return sanitize_output(await _run_sia_inference(prompt))


async def sia_language_immersion(target_language: str, student_message: str,
                                  student_name: str, student_level: str = "beginner",
                                  approach: str = "bilingual") -> str:
    prompt = build_language_immersion_prompt(
        target_language=target_language, student_message=student_message,
        student_name=student_name, student_level=student_level, approach=approach,
    )
    return sanitize_output(await _run_sia_inference(prompt))


async def sia_generate_study_plan(student_name: str, level: str, exam_target: str,
                                   student_id: str, hours_per_day: float,
                                   days_until_exam: int) -> str:
    weak = await get_weak_topics(student_id)
    memory = await _get_memory(student_id, "")
    strong = {s: [] for s in memory.get("strong_topics", [])}
    prompt = build_study_plan_prompt(
        student_name=student_name, level=level, exam_target=exam_target,
        weak_subjects=weak if isinstance(weak, dict) else {},
        strong_subjects=strong, learning_speed=memory.get("learning_style", "medium"),
        hours_per_day=hours_per_day, days_until_exam=days_until_exam,
    )
    return sanitize_output(await _run_sia_inference(prompt))


async def sia_cambridge_teach(topic: str, subject: str, education_level: str,
                               student_id: str, student_name: str) -> str:
    prompt = build_cambridge_prompt(
        topic=topic, subject=subject,
        education_level=education_level, student_name=student_name,
    )
    return sanitize_output(await _run_sia_inference(prompt))


async def sia_parent_report(student_name: str, level: str, profile_data: dict) -> str:
    prompt = build_parent_report_prompt(
        student_name=student_name,
        level=level,
        total_sessions=profile_data.get("total_ai_sessions", 0),
        total_minutes=profile_data.get("total_study_minutes", 0),
        streak_days=profile_data.get("streak_days", 0),
        weak_subjects=profile_data.get("weak_subjects", {}),
        strong_subjects=profile_data.get("strong_subjects", {}),
        avg_score=profile_data.get("avg_score", 0.0),
        learning_speed=profile_data.get("learning_speed", "medium"),
        confidence_level=profile_data.get("confidence_level", "building"),
        attention_pattern=profile_data.get("attention_pattern", "normal"),
        last_active=profile_data.get("last_active", "Unknown"),
    )
    return sanitize_output(await _run_sia_inference(prompt))
