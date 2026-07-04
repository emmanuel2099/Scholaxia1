"""
Teacher AI Router
-----------------
Separate AI endpoint for teachers.
Helps with lesson plans, assignments, quiz generation, grading, analytics.
Does NOT assist students. Cannot be used to get exam answers.
"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Literal, Optional, List

from app.core.deps import require_teacher
from app.ai.prompt_builder import (
    build_teacher_prompt,
    build_teacher_system_prompt,
    TEACHER_TASK_PROFILES,
    _is_casual_greeting,
)
from app.ai.sia_accuracy import detect_teacher_task
from app.ai.sia_conversation import analyze_conversation, build_conversation_intel
from app.ai.model_backend import run_inference
from app.ai.safety_filter import sanitize_output

router = APIRouter(prefix="/teacher-ai", tags=["Teacher AI"])

VALID_TASKS = list(TEACHER_TASK_PROFILES.keys())


class TeacherAIRequest(BaseModel):
    task: str = "general"
    subject: str = "General"
    education_level: str = "SS2"
    details: str
    conversation_history: Optional[List[dict]] = None


class TeacherAIResponse(BaseModel):
    result: str
    task: str
    subject: str


@router.post("/ask", response_model=TeacherAIResponse)
async def teacher_ask_ai(
    payload: TeacherAIRequest,
    current_user: dict = Depends(require_teacher),
):
    """
    Teacher AI — helps teachers build content and manage their classes.
    This is completely separate from the student AI.
    """
    task = payload.task if payload.task in VALID_TASKS else detect_teacher_task(payload.details)

    if task == "general" and _is_casual_greeting(payload.details):
        return TeacherAIResponse(
            result=(
                "Hello! I'm your Scholaxia teaching assistant. "
                "What would you like help with — a lesson plan, assignment, quiz, grading, or something else?"
            ),
            task=task,
            subject=payload.subject,
        )

    system = build_teacher_system_prompt(
        task=task,
        subject=payload.subject,
        education_level=payload.education_level,
    )
    conv_intel = build_conversation_intel(
        payload.details, payload.conversation_history, audience="teacher",
    )
    if conv_intel:
        system = f"{system}\n\n{conv_intel}"
    prompt = build_teacher_prompt(
        task=task,
        subject=payload.subject,
        education_level=payload.education_level,
        details=payload.details,
    )

    conv = analyze_conversation(payload.details, payload.conversation_history)
    temp = 0.38 if conv.get("is_follow_up") else (0.42 if task in ("quiz", "lesson_plan", "grading") else 0.50)

    try:
        raw_result = await run_inference(
            prompt,
            system_prompt=system,
            conversation_history=payload.conversation_history,
            max_tokens=8192,
            temperature=temp,
        )
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        msg = str(e)
        if "429" in msg or "rate limit" in msg.lower():
            raise HTTPException(
                status_code=429,
                detail="AI is busy right now. Please wait a moment and try again.",
            )
        raise HTTPException(
            status_code=503,
            detail="Teacher AI could not respond. Please try again.",
        )

    result = sanitize_output(raw_result)

    return TeacherAIResponse(
        result=result,
        task=task,
        subject=payload.subject,
    )
