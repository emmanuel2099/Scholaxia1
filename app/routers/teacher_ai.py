"""
Teacher AI Router
-----------------
Separate AI endpoint for teachers.
Helps with lesson plans, assignments, quiz generation, grading, analytics.
Does NOT assist students. Cannot be used to get exam answers.
"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Literal

from app.core.deps import require_teacher
from app.ai.prompt_builder import build_teacher_prompt, TEACHER_TASK_PROFILES, _is_casual_greeting
from app.ai.model_backend import run_inference
from app.ai.safety_filter import sanitize_output

router = APIRouter(prefix="/teacher-ai", tags=["Teacher AI"])

VALID_TASKS = list(TEACHER_TASK_PROFILES.keys())


class TeacherAIRequest(BaseModel):
    task: str           # lesson_plan | assignment | quiz | grading | analytics | general
    subject: str
    education_level: str  # JSS1 ... SS3, JAMB, WAEC, NECO
    details: str        # teacher's specific request/description


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
    if payload.task not in VALID_TASKS:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid task. Choose from: {VALID_TASKS}",
        )

    if payload.task == "general" and _is_casual_greeting(payload.details):
        return TeacherAIResponse(
            result=(
                "Hello! I'm your Scholaxia teaching assistant. "
                "What would you like help with — a lesson idea, assignment, quiz, grading, or something else?"
            ),
            task=payload.task,
            subject=payload.subject,
        )

    prompt = build_teacher_prompt(
        task=payload.task,
        subject=payload.subject,
        education_level=payload.education_level,
        details=payload.details,
    )

    raw_result = await run_inference(prompt)
    result = sanitize_output(raw_result)

    return TeacherAIResponse(
        result=result,
        task=payload.task,
        subject=payload.subject,
    )
