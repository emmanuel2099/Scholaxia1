"""
Sia — AI Tutor Router
----------------------
All student-facing Sia endpoints.
Sia is the Scholaxia Intelligent Assistant — friendly, adaptive, personalised.
"""

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update, text
from pydantic import BaseModel, Field
from typing import Optional, List
import io, base64

from app.core.database import get_db
from app.core.deps import require_student, require_student_or_kind
from app.models.user import User, StudentProfile
from app.models.sia_note import SiaNote
from app.services.ai_service import (
    get_ai_response,
    sia_explain,
    sia_solve,
    sia_evaluate,
    sia_generate_questions,
    sia_performance_feedback,
    sia_explain_wrong_answer,
    sia_lesson,
    sia_anti_cheat,
    sia_debate,
    sia_study_companion,
    sia_process_pdf,
    sia_language_immersion,
    sia_generate_study_plan,
    sia_cambridge_teach,
    sia_parent_report,
)
from app.ai.recommendation_engine import get_recommendations
from app.ai.weakness_analyzer import get_student_history, get_weak_topics
from app.ai.sia_intelligence import resolve_active_subject
from app.ai.board_parser import extract_board_content
from app.ai.model_backend import run_inference
from app.ai.prompt_builder import build_prompt, detect_language_from_text
from app.ai.safety_filter import sanitize_output
from app.ai.prompt_builder import SUPPORTED_LANGUAGES as ALL_LANGUAGES

router = APIRouter(prefix="/sia", tags=["Sia — AI Tutor"])

SUPPORTED_CURRICULA = ["WAEC", "NECO", "JAMB", "Cambridge", "Nigerian"]


def _validate_language(language: str):
    if language.lower() not in ALL_LANGUAGES:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported language '{language}'. Sia supports {len(ALL_LANGUAGES)}+ languages. Check GET /api/v1/sia/languages for the full list.",
        )

SUPPORTED_LANGUAGES = ["english", "igbo", "yoruba", "hausa", "french", "arabic"]
SUPPORTED_CURRICULA = ["WAEC", "NECO", "JAMB", "Cambridge", "Nigerian"]


# ── Helper: get student name from DB ─────────────────────────────────────────

async def _get_student_name(user_id: str, db: AsyncSession) -> str:
    try:
        result = await db.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()
        if user and user.full_name:
            parts = user.full_name.strip().split()
            if parts:
                return parts[0]
    except Exception:
        try:
            await db.rollback()
        except Exception:
            pass
    return "there"


async def _get_student_level(user_id: str, db: AsyncSession) -> str:
    try:
        row = (
            await db.execute(
                text(
                    "SELECT education_level FROM student_profiles "
                    "WHERE user_id = CAST(:uid AS uuid) LIMIT 1"
                ),
                {"uid": str(user_id)},
            )
        ).mappings().first()
        if row and row.get("education_level"):
            return str(row["education_level"])
    except Exception:
        try:
            await db.rollback()
        except Exception:
            pass
    return "UNKNOWN"


async def _get_student_profile(user_id: str, db: AsyncSession) -> tuple[str, list]:
    try:
        row = (
            await db.execute(
                text(
                    "SELECT education_level, selected_subjects FROM student_profiles "
                    "WHERE user_id = CAST(:uid AS uuid) LIMIT 1"
                ),
                {"uid": str(user_id)},
            )
        ).mappings().first()
        if not row:
            return "UNKNOWN", []
        level = row.get("education_level") or "UNKNOWN"
        raw = row.get("selected_subjects") or []
        try:
            subjects = list(raw)
        except TypeError:
            subjects = []
        return str(level), subjects
    except Exception:
        try:
            await db.rollback()
        except Exception:
            pass
        return "UNKNOWN", []


def _normalize_history(history: Optional[list]) -> Optional[list]:
    """Keep only well-formed chat turns for the model APIs."""
    if not history:
        return None
    out = []
    for msg in history[-24:]:
        if not isinstance(msg, dict):
            continue
        role = str(msg.get("role") or "").strip().lower()
        content = msg.get("content")
        if content is None:
            content = msg.get("text")
        text = str(content or "").strip()
        if not text:
            continue
        if role in ("assistant", "ai", "model", "sia"):
            role = "assistant"
        else:
            role = "user"
        out.append({"role": role, "content": text[:4000]})
    return out or None


def _validate_language(language: str):
    if language.lower() not in SUPPORTED_LANGUAGES:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported language. Choose from: {SUPPORTED_LANGUAGES}",
        )


# ── Mode 1: Ask Sia anything ──────────────────────────────────────────────────

class AskRequest(BaseModel):
    question: str = Field(..., min_length=1, max_length=2000)
    subject: str
    language: str = "english"
    education_level: Optional[str] = None
    conversation_history: Optional[list] = None  # last N messages for context
    tutor_mode: str = "smart"  # smart = ChatGPT-style structured answers with code fences


@router.get("/status")
async def sia_status():
    """Public check: which AI providers are configured (no secrets)."""
    from app.core.config import settings

    return {
        "ok": True,
        "ai_backend": settings.AI_BACKEND,
        "providers": {
            "deepseek": bool(settings.DEEPSEEK_API_KEY),
            "openai": bool(settings.OPENAI_API_KEY),
            "gemini": bool(settings.GEMINI_API_KEY),
            "groq": bool(settings.GROQ_API_KEY),
        },
        "models": {
            "deepseek": settings.DEEPSEEK_MODEL,
            "openai": settings.OPENAI_MODEL,
            "gemini": settings.GEMINI_MODEL,
            "groq": settings.GROQ_MODEL,
        },
        "voice": {
            "elevenlabs": bool(settings.ELEVENLABS_API_KEY),
            "edge_tts_fallback": True,
        },
    }


@router.post("/ask")
async def ask_sia(
    payload: AskRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Ask Sia any educational question. Returns text + board content."""
    student_name = "there"
    level = "UNKNOWN"
    try:
        _validate_language(payload.language)
        student_name = await _get_student_name(current_user["sub"], db)
        profile_level, profile_subjects = await _get_student_profile(current_user["sub"], db)
        level = payload.education_level or profile_level
        default_subject = (
            profile_subjects[0] if profile_subjects else payload.subject
        )
        active_subject = resolve_active_subject(
            payload.question,
            payload.subject or default_subject,
            profile_subjects,
        )
        history = _normalize_history(payload.conversation_history)

        answer = await get_ai_response(
            question=payload.question,
            subject=active_subject,
            education_level=level,
            language=payload.language,
            student_id=current_user["sub"],
            student_name=student_name,
            conversation_history=history,
            tutor_mode=payload.tutor_mode or "smart",
        )

        if answer.startswith("Sia is temporarily unavailable"):
            # Return 200 with a clear message so the app can show/speak it
            # (raising 503 was shown as a useless "waking up" error).
            return {
                "sia": answer,
                "board": [
                    {"type": "heading", "content": "Sia needs a moment"},
                    {"type": "point", "content": answer[:220]},
                ],
                "student": student_name,
                "level": level,
            }

        try:
            board = extract_board_content(answer)
        except Exception:
            board = []

        return {
            "sia": answer,
            "board": board,
            "student": student_name,
            "level": level,
        }
    except HTTPException:
        raise
    except Exception as e:
        msg = (
            f"I hit a temporary server issue ({type(e).__name__}), {student_name}. "
            "Please try again in a few seconds."
        )
        return {
            "sia": msg,
            "board": [
                {"type": "heading", "content": "Temporary issue"},
                {"type": "point", "content": msg},
            ],
            "student": student_name,
            "level": level,
        }


# ── Mode 2: Explain a concept ─────────────────────────────────────────────────

class ExplainRequest(BaseModel):
    topic: str = Field(..., min_length=2, max_length=500)
    subject: str
    language: str = "english"
    education_level: Optional[str] = None


@router.post("/explain")
async def sia_explain_concept(
    payload: ExplainRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Sia explains a topic: definition → steps → example → worked example → question."""
    _validate_language(payload.language)
    student_name = await _get_student_name(current_user["sub"], db)
    level = payload.education_level or await _get_student_level(current_user["sub"], db)

    answer = await sia_explain(
        topic=payload.topic,
        subject=payload.subject,
        education_level=level,
        language=payload.language,
        student_id=current_user["sub"],
        student_name=student_name,
    )
    return {"sia": answer, "topic": payload.topic}


# ── Mode 3: Solve a problem ───────────────────────────────────────────────────

class SolveRequest(BaseModel):
    question: str = Field(..., min_length=1, max_length=2000)
    subject: str
    language: str = "english"
    education_level: Optional[str] = None


@router.post("/solve")
async def sia_solve_problem(
    payload: SolveRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Sia solves a problem step-by-step without jumping to the final answer."""
    _validate_language(payload.language)
    student_name = await _get_student_name(current_user["sub"], db)
    level = payload.education_level or await _get_student_level(current_user["sub"], db)

    answer = await sia_solve(
        question=payload.question,
        subject=payload.subject,
        education_level=level,
        language=payload.language,
        student_id=current_user["sub"],
        student_name=student_name,
    )
    return {"sia": answer}


# ── Mode 4: Evaluate student answer ──────────────────────────────────────────

class EvaluateRequest(BaseModel):
    question: str
    student_answer: str
    subject: str
    language: str = "english"
    education_level: Optional[str] = None


@router.post("/evaluate")
async def sia_evaluate_answer(
    payload: EvaluateRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    Sia evaluates the student's answer.
    Correct → praise + reinforce + harder question.
    Partial → acknowledge + fix.
    Wrong → encourage + guide.
    """
    _validate_language(payload.language)
    student_name = await _get_student_name(current_user["sub"], db)
    level = payload.education_level or await _get_student_level(current_user["sub"], db)

    answer = await sia_evaluate(
        question=payload.question,
        student_answer=payload.student_answer,
        subject=payload.subject,
        education_level=level,
        language=payload.language,
        student_id=current_user["sub"],
        student_name=student_name,
    )
    return {"sia": answer}


# ── Mode 5: Generate practice questions ──────────────────────────────────────

class GenerateQuestionsRequest(BaseModel):
    topic: str
    subject: str
    number: int = Field(default=5, ge=1, le=20)
    curriculum: str = "WAEC"
    language: str = "english"
    education_level: Optional[str] = None


@router.post("/generate-questions")
async def sia_generate(
    payload: GenerateQuestionsRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Sia generates practice questions — mixed difficulty, exam-style, with answers."""
    _validate_language(payload.language)
    if payload.curriculum not in SUPPORTED_CURRICULA:
        raise HTTPException(status_code=400, detail=f"Curriculum must be one of: {SUPPORTED_CURRICULA}")

    student_name = await _get_student_name(current_user["sub"], db)
    level = payload.education_level or await _get_student_level(current_user["sub"], db)

    answer = await sia_generate_questions(
        topic=payload.topic,
        number=payload.number,
        subject=payload.subject,
        education_level=level,
        language=payload.language,
        student_name=student_name,
        curriculum=payload.curriculum,
    )
    return {"sia": answer, "topic": payload.topic, "count": payload.number}


# ── Mode 6: Performance feedback ─────────────────────────────────────────────

class FeedbackRequest(BaseModel):
    subject: str
    language: str = "english"
    score: Optional[float] = None
    education_level: Optional[str] = None


@router.post("/feedback")
async def sia_feedback(
    payload: FeedbackRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Sia gives personalised feedback based on the student's weak topics."""
    _validate_language(payload.language)
    student_name = await _get_student_name(current_user["sub"], db)
    level = payload.education_level or await _get_student_level(current_user["sub"], db)
    weak = await get_weak_topics(current_user["sub"])

    answer = await sia_performance_feedback(
        weak_topics=weak,
        subject=payload.subject,
        education_level=level,
        language=payload.language,
        student_id=current_user["sub"],
        student_name=student_name,
        score=payload.score,
    )
    return {"sia": answer, "weak_topics": weak}


# ── Mode 7: Explain wrong answer ─────────────────────────────────────────────

class WrongAnswerRequest(BaseModel):
    question: str
    wrong_answer: str
    correct_answer: str
    subject: str
    language: str = "english"
    education_level: Optional[str] = None


@router.post("/explain-wrong")
async def sia_explain_wrong(
    payload: WrongAnswerRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Sia explains why an answer is wrong and re-teaches the concept."""
    student_name = "there"
    try:
        _validate_language(payload.language)
        student_name = await _get_student_name(current_user["sub"], db)
        level = payload.education_level or await _get_student_level(current_user["sub"], db)

        answer = await sia_explain_wrong_answer(
            question=payload.question,
            wrong_answer=payload.wrong_answer,
            correct_answer=payload.correct_answer,
            subject=payload.subject,
            education_level=level,
            language=payload.language,
            student_name=student_name,
            student_id=current_user["sub"],
        )
        return {"sia": answer}
    except HTTPException:
        raise
    except Exception as e:
        return {
            "sia": (
                f"I hit a temporary server issue ({type(e).__name__}), {student_name}. "
                "Please try again in a few seconds."
            ),
        }


# ── Recommendations & History ─────────────────────────────────────────────────

@router.get("/recommendations")
async def get_my_recommendations(
    subject: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Sia recommends books and videos based on weak topics."""
    level = await _get_student_level(current_user["sub"], db)
    return await get_recommendations(
        db=db,
        student_id=current_user["sub"],
        subject=subject,
        education_level=level,
    )


@router.get("/weak-topics")
async def get_my_weak_topics(current_user: dict = Depends(require_student)):
    """Returns the student's identified weak topics per subject."""
    return await get_weak_topics(current_user["sub"])


@router.get("/history")
async def get_my_ai_history(current_user: dict = Depends(require_student)):
    """Returns last 50 Sia interactions for this student."""
    return await get_student_history(current_user["sub"])


# ── Sia identity endpoint ─────────────────────────────────────────────────────

@router.get("/about")
async def about_sia():
    """Returns Sia's public identity."""
    return {
        "name": "Sia",
        "full_name": "Scholaxia Intelligent Assistant",
        "tagline": "Your personal AI study buddy",
        "capabilities": [
            "Explain any concept step-by-step",
            "Solve problems with full working",
            "Evaluate your answers and give feedback",
            "Generate practice questions",
            "Track your weak areas",
            "Give personalised study recommendations",
            "Support 100+ languages including English, Igbo, Yoruba, Hausa, French, Arabic, Spanish, Chinese, Hindi, Swahili, Portuguese, Russian, and more",
            "Adapt to your level: Primary, JSS, SS, JAMB, WAEC, NECO, Cambridge",
        ],
        "powered_by": "Scholaxia",
    }


@router.get("/languages")
async def list_languages():
    """Returns all languages Sia can respond in."""
    from app.ai.prompt_builder import LANGUAGE_INSTRUCTIONS

    grouped = {
        "nigerian": ["english", "igbo", "yoruba", "hausa", "pidgin", "efik", "tiv", "ijaw", "kanuri", "fulfulde"],
        "african": ["swahili", "amharic", "zulu", "xhosa", "shona", "somali", "oromo", "tigrinya",
                    "kinyarwanda", "lingala", "wolof", "twi", "bambara", "moore", "fon", "ewe", "ga",
                    "dagbani", "chichewa", "luganda", "dinka", "nuer", "malagasy", "sesotho", "setswana",
                    "siswati", "ndebele", "venda", "tsonga", "afrikaans", "kabyle"],
        "middle_east_central_asia": ["arabic", "persian", "pashto", "dari", "urdu", "kurdish",
                                      "azerbaijani", "uzbek", "kazakh", "turkmen", "kyrgyz", "tajik"],
        "south_asia": ["hindi", "bengali", "punjabi", "gujarati", "marathi", "tamil", "telugu",
                       "kannada", "malayalam", "sinhala", "nepali", "odia", "assamese"],
        "east_southeast_asia": ["chinese", "cantonese", "japanese", "korean", "vietnamese", "thai",
                                  "burmese", "khmer", "lao", "indonesian", "malay", "tagalog",
                                  "cebuano", "javanese", "sundanese", "mongolian", "tibetan"],
        "europe": ["french", "spanish", "portuguese", "german", "italian", "dutch", "russian",
                   "polish", "ukrainian", "czech", "slovak", "hungarian", "romanian", "bulgarian",
                   "serbian", "croatian", "bosnian", "slovenian", "macedonian", "albanian", "greek",
                   "turkish", "swedish", "norwegian", "danish", "finnish", "icelandic", "estonian",
                   "latvian", "lithuanian", "belarusian", "georgian", "armenian", "welsh", "irish",
                   "catalan", "basque", "galician", "maltese"],
        "americas": ["quechua", "guarani", "nahuatl", "aymara", "haitian_creole"],
        "pacific": ["hawaiian", "samoan", "tongan", "fijian", "maori"],
    }

    return {
        "total": len(ALL_LANGUAGES),
        "languages_by_region": grouped,
        "all_languages": sorted(ALL_LANGUAGES),
    }


# ── Voice: Text-to-Speech ─────────────────────────────────────────────────────

class SpeakRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=5000)
    language: str = "english"


@router.post("/speak")
async def sia_speak(
    payload: SpeakRequest,
    current_user: dict = Depends(require_student_or_kind),
):
    """
    Convert any Sia text response to audio (MP3).

    Flow:
    1. Student receives Sia's text response
    2. Frontend calls this endpoint with that text
    3. Backend returns MP3 audio stream
    4. Frontend plays it — student hears Sia speak

    Voice: warm, calm, medium pace — friendly tutor style.
    Supports ElevenLabs (29 languages) with gTTS fallback (100+ languages).
    """
    from app.services.tts_service import text_to_speech

    _validate_language(payload.language)

    audio_bytes = await text_to_speech(
        text=payload.text,
        language=payload.language,
    )

    if not audio_bytes:
        raise HTTPException(status_code=503, detail="Voice service unavailable. Please read the text response.")

    return StreamingResponse(
        io.BytesIO(audio_bytes),
        media_type="audio/mpeg",
        headers={
            "Content-Disposition": "inline; filename=sia_response.mp3",
            "Cache-Control": "no-store",
        },
    )


@router.post("/ask-voice")
async def ask_sia_voice(
    payload: AskRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    Ask Sia a question and get BOTH text and audio back in one call.

    Returns:
    - text: Sia's full text response
    - audio_url: call POST /sia/speak with the text to get audio
    - student: student's first name
    - level: education level used

    Note: For voice INPUT (student speaks), the frontend uses the device
    microphone + Web Speech API to convert speech to text, then sends
    the text to /sia/ask or /sia/ask-voice.
    """
    _validate_language(payload.language)
    student_name = await _get_student_name(current_user["sub"], db)
    level = payload.education_level or await _get_student_level(current_user["sub"], db)

    text_response = await get_ai_response(
        question=payload.question,
        subject=payload.subject,
        education_level=level,
        language=payload.language,
        student_id=current_user["sub"],
        student_name=student_name,
    )

    return {
        "sia": text_response,
        "student": student_name,
        "level": level,
        "voice_hint": "POST /api/v1/sia/speak with the 'sia' text to hear Sia's voice",
    }


# ── Notes: Save Sia responses as personal notes ───────────────────────────────

class SaveNoteRequest(BaseModel):
    content: str = Field(..., min_length=1)
    title: Optional[str] = None
    question: Optional[str] = None
    subject: Optional[str] = None
    topic: Optional[str] = None
    source_mode: Optional[str] = None   # ask | explain | solve | etc.


class UpdateNoteRequest(BaseModel):
    title: Optional[str] = None
    topic: Optional[str] = None
    is_pinned: Optional[bool] = None


@router.post("/notes", status_code=201)
async def save_note(
    payload: SaveNoteRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    Save a Sia response as a personal note.
    Notes are private — only the student who saved them can see them.
    Student can give it a title, tag it by subject/topic, and pin it.
    """
    note = SiaNote(
        student_id=current_user["sub"],
        content=payload.content,
        title=payload.title or (payload.question[:80] if payload.question else "Sia Note"),
        question=payload.question,
        subject=payload.subject,
        topic=payload.topic,
        source_mode=payload.source_mode,
    )
    db.add(note)
    await db.flush()

    return {
        "note_id": str(note.id),
        "title": note.title,
        "message": "Note saved successfully",
    }


@router.get("/notes")
async def get_my_notes(
    subject: Optional[str] = None,
    pinned_only: bool = False,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Get all of the student's saved Sia notes, newest first."""
    query = select(SiaNote).where(SiaNote.student_id == current_user["sub"])

    if subject:
        query = query.where(SiaNote.subject == subject)
    if pinned_only:
        query = query.where(SiaNote.is_pinned == True)  # noqa: E712

    query = query.order_by(SiaNote.is_pinned.desc(), SiaNote.created_at.desc())
    result = await db.execute(query)
    notes = result.scalars().all()

    return [
        {
            "id": str(n.id),
            "title": n.title,
            "content": n.content,
            "question": n.question,
            "subject": n.subject,
            "topic": n.topic,
            "source_mode": n.source_mode,
            "is_pinned": n.is_pinned,
            "created_at": n.created_at,
        }
        for n in notes
    ]


@router.get("/notes/{note_id}")
async def get_note(
    note_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Get a single note by ID."""
    result = await db.execute(
        select(SiaNote).where(
            SiaNote.id == note_id,
            SiaNote.student_id == current_user["sub"],
        )
    )
    note = result.scalar_one_or_none()
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")

    return {
        "id": str(note.id),
        "title": note.title,
        "content": note.content,
        "question": note.question,
        "subject": note.subject,
        "topic": note.topic,
        "source_mode": note.source_mode,
        "is_pinned": note.is_pinned,
        "created_at": note.created_at,
        "updated_at": note.updated_at,
    }


@router.patch("/notes/{note_id}")
async def update_note(
    note_id: str,
    payload: UpdateNoteRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Update note title, topic, or pin status."""
    result = await db.execute(
        select(SiaNote).where(
            SiaNote.id == note_id,
            SiaNote.student_id == current_user["sub"],
        )
    )
    note = result.scalar_one_or_none()
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")

    if payload.title is not None:
        note.title = payload.title
    if payload.topic is not None:
        note.topic = payload.topic
    if payload.is_pinned is not None:
        note.is_pinned = payload.is_pinned

    await db.flush()
    return {"message": "Note updated", "note_id": note_id}


@router.delete("/notes/{note_id}", status_code=204)
async def delete_note(
    note_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Delete a saved note."""
    result = await db.execute(
        select(SiaNote).where(
            SiaNote.id == note_id,
            SiaNote.student_id == current_user["sub"],
        )
    )
    note = result.scalar_one_or_none()
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")
    await db.delete(note)


# ── Image Analysis — Student sends photo of question/diagram ─────────────────

@router.post("/analyze-image")
async def analyze_image(
    image: UploadFile = File(...),
    question: str = Form(default="Analyze this image and help me understand it"),
    subject: str = Form(default="General"),
    language: str = Form(default="english"),
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    Student uploads a photo of a question, diagram, or problem.
    Sia analyzes it using vision AI and explains/solves it.
    Supports: photos of textbook questions, handwritten problems, diagrams, graphs.
    """
    # Validate file type
    if image.content_type not in ("image/jpeg", "image/png", "image/webp", "image/gif"):
        raise HTTPException(status_code=400, detail="Only JPEG, PNG, WebP, or GIF images are supported.")

    # Read and encode image
    image_bytes = await image.read()
    if len(image_bytes) > 10 * 1024 * 1024:  # 10MB limit
        raise HTTPException(status_code=400, detail="Image too large. Maximum size is 10MB.")

    image_base64 = base64.b64encode(image_bytes).decode("utf-8")

    student_name = await _get_student_name(current_user["sub"], db)
    level = await _get_student_level(current_user["sub"], db)
    lang_instruction = detect_language_from_text(question)

    # Build vision prompt
    vision_prompt = f"""You are Sia, the Scholaxia Intelligent Assistant — an elite AI tutor.

Student Name: {student_name}
Subject: {subject}
Level: {level}
{lang_instruction}

The student has sent you an image. It could be:
- A photo of a textbook question
- A handwritten problem
- A diagram or graph
- A chemistry equation
- A math problem
- Any educational content

Your task:
1. Describe what you see in the image clearly
2. If it's a question or problem — solve it step by step
3. If it's a diagram — explain what it shows and what it means
4. If it's a graph — interpret the data and explain the pattern
5. Connect your explanation to {subject} concepts at {level} level
6. Use Nigerian examples where relevant
7. End with a question to check {student_name}'s understanding

Student's message about the image: {question}

Respond as Sia — warm, clear, educational, and thorough.
"""

    try:
        answer = await run_inference(vision_prompt, image_base64=image_base64)
        answer = sanitize_output(answer)
        board = extract_board_content(answer)

        return {
            "sia": answer,
            "board": board,
            "student": student_name,
            "image_analyzed": True,
        }
    except Exception as e:
        raise HTTPException(
            status_code=503,
            detail="Image analysis temporarily unavailable. Please describe the image in text instead."
        )


# ── Mode 8: Structured Lesson (Classroom Teacher Mode) ───────────────────────

class LessonRequest(BaseModel):
    topic: str = Field(..., min_length=2, max_length=300)
    subject: str
    curriculum: str = "Nigerian"  # Nigerian | Cambridge | British | American | WAEC | JAMB
    language: str = "english"
    education_level: Optional[str] = None
    step: int = Field(default=1, ge=1, le=11)
    previous_response: Optional[str] = None  # student's reply to advance the lesson


@router.post("/lesson")
async def sia_lesson_mode(
    payload: LessonRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    Structured classroom lesson. Sia teaches step-by-step like a real teacher.
    Steps: Greeting → Revision → Objectives → Teach → Questions → Examples
           → Activity → Quiz → Evaluate → Homework → Summary
    Call with step=1 to start. Increment step as student progresses.
    """
    _validate_language(payload.language)
    student_name = await _get_student_name(current_user["sub"], db)
    level = payload.education_level or await _get_student_level(current_user["sub"], db)

    answer = await sia_lesson(
        topic=payload.topic,
        subject=payload.subject,
        education_level=level,
        language=payload.language,
        student_id=current_user["sub"],
        student_name=student_name,
        curriculum=payload.curriculum,
        step=payload.step,
        previous_response=payload.previous_response or "",
    )
    return {
        "sia": answer,
        "topic": payload.topic,
        "step": payload.step,
        "next_step": min(payload.step + 1, 11),
        "is_final_step": payload.step >= 11,
    }


# ── Mode 9: Anti-Cheat / Learning Integrity Check ────────────────────────────

class AntiCheatRequest(BaseModel):
    question: str
    submitted_answer: str
    subject: str


@router.post("/integrity-check")
async def sia_integrity_check(
    payload: AntiCheatRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    Sia checks if a student's answer shows genuine understanding.
    Does NOT accuse — asks follow-up questions to verify comprehension.
    """
    student_name = await _get_student_name(current_user["sub"], db)
    answer = await sia_anti_cheat(
        question=payload.question,
        submitted_answer=payload.submitted_answer,
        subject=payload.subject,
        student_name=student_name,
    )
    return {"sia": answer}


# ── Mode 10: Academic Debate Mode ────────────────────────────────────────────

class DebateRequest(BaseModel):
    topic: str = Field(..., min_length=5, max_length=500)
    student_position: str = Field(..., min_length=5, max_length=1000)
    subject: str
    language: str = "english"


@router.post("/debate")
async def sia_debate_mode(
    payload: DebateRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    Sia debates the student academically to sharpen critical thinking.
    Challenges reasoning with 'Why do you think that?' and 'Can you defend your answer?'
    """
    _validate_language(payload.language)
    student_name = await _get_student_name(current_user["sub"], db)
    answer = await sia_debate(
        topic=payload.topic,
        student_position=payload.student_position,
        subject=payload.subject,
        student_name=student_name,
    )
    return {"sia": answer, "topic": payload.topic}


# ── Mode 11: Language Immersion Teacher ──────────────────────────────────────

SUPPORTED_IMMERSION_LANGUAGES = [
    "yoruba", "igbo", "hausa", "swahili", "zulu", "efik",
    "twi", "wolof", "amharic", "french", "arabic", "pidgin",
]


class LanguageImmersionRequest(BaseModel):
    target_language: str  # the language being learned
    message: str = Field(..., min_length=1, max_length=2000)
    student_level: str = "beginner"  # beginner | intermediate | advanced
    approach: str = "bilingual"      # bilingual | immersion


@router.post("/language-immersion")
async def sia_language_teacher(
    payload: LanguageImmersionRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    Sia as an African Language Immersion Teacher.
    Teaches Yoruba, Igbo, Hausa, Swahili, Zulu, Efik, and more.
    Supports bilingual (English + target) or full immersion mode.
    Diagnoses Igbo-influenced English patterns automatically.
    """
    if payload.target_language.lower() not in SUPPORTED_IMMERSION_LANGUAGES:
        raise HTTPException(
            status_code=400,
            detail=f"Supported languages: {SUPPORTED_IMMERSION_LANGUAGES}",
        )
    if payload.approach not in ("bilingual", "immersion"):
        raise HTTPException(status_code=400, detail="approach must be 'bilingual' or 'immersion'")

    student_name = await _get_student_name(current_user["sub"], db)
    answer = await sia_language_immersion(
        target_language=payload.target_language,
        student_message=payload.message,
        student_name=student_name,
        student_level=payload.student_level,
        approach=payload.approach,
    )
    return {"sia": answer, "target_language": payload.target_language}


# ── Mode 12: PDF / Document Processing ───────────────────────────────────────

PDF_OUTPUT_TYPES = [
    "lesson_notes", "student_summary", "exam_prep",
    "lesson_plan", "practice_questions",
]

SUPPORTED_CURRICULA_LIST = ["Nigerian", "Cambridge", "British", "American", "International"]
SUPPORTED_EXAM_STANDARDS = ["WAEC", "NECO", "JAMB", "Cambridge", "IGCSE", "SAT", "IELTS", "General"]


class PDFProcessRequest(BaseModel):
    pdf_text: str = Field(..., min_length=50, max_length=20000, description="Extracted text from the PDF")
    output_type: str = "lesson_notes"
    subject: str
    curriculum: str = "Nigerian"
    exam_standard: str = "WAEC"
    language: str = "english"
    education_level: Optional[str] = None


@router.post("/process-pdf")
async def sia_pdf_processor(
    payload: PDFProcessRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    Sia transforms PDF/document content into structured learning materials.
    Frontend extracts text from PDF and sends it here.

    Output types:
    - lesson_notes: Structured notes with headings and key points
    - student_summary: Simple summary for the student
    - exam_prep: Exam questions, marking scheme, examiner tips
    - lesson_plan: Professional teacher lesson plan
    - practice_questions: Mixed difficulty practice questions
    """
    if payload.output_type not in PDF_OUTPUT_TYPES:
        raise HTTPException(status_code=400, detail=f"output_type must be one of: {PDF_OUTPUT_TYPES}")
    if payload.curriculum not in SUPPORTED_CURRICULA_LIST:
        raise HTTPException(status_code=400, detail=f"curriculum must be one of: {SUPPORTED_CURRICULA_LIST}")
    if payload.exam_standard not in SUPPORTED_EXAM_STANDARDS:
        raise HTTPException(status_code=400, detail=f"exam_standard must be one of: {SUPPORTED_EXAM_STANDARDS}")
    _validate_language(payload.language)

    student_name = await _get_student_name(current_user["sub"], db)
    level = payload.education_level or await _get_student_level(current_user["sub"], db)

    answer = await sia_process_pdf(
        pdf_content=payload.pdf_text,
        output_type=payload.output_type,
        subject=payload.subject,
        education_level=level,
        curriculum=payload.curriculum,
        exam_standard=payload.exam_standard,
        student_name=student_name,
        language=payload.language,
    )
    return {
        "sia": answer,
        "output_type": payload.output_type,
        "subject": payload.subject,
        "curriculum": payload.curriculum,
    }


# ── Mode 13: Personalized Study Plan ─────────────────────────────────────────

class StudyPlanRequest(BaseModel):
    exam_target: str  # WAEC | JAMB | NECO | Cambridge | IGCSE
    hours_per_day: float = Field(default=2.0, ge=0.5, le=12.0)
    days_until_exam: int = Field(default=90, ge=1, le=365)
    education_level: Optional[str] = None


@router.post("/study-plan")
async def sia_study_plan(
    payload: StudyPlanRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    Sia generates a personalized weekly study plan based on the student's
    weak topics, learning speed, and exam timeline.
    """
    student_name = await _get_student_name(current_user["sub"], db)
    level = payload.education_level or await _get_student_level(current_user["sub"], db)

    answer = await sia_generate_study_plan(
        student_name=student_name,
        level=level,
        exam_target=payload.exam_target,
        student_id=current_user["sub"],
        hours_per_day=payload.hours_per_day,
        days_until_exam=payload.days_until_exam,
    )
    return {"sia": answer, "exam_target": payload.exam_target}


# ── Mode 14: Cambridge Teaching Style ────────────────────────────────────────

class CambridgeRequest(BaseModel):
    topic: str = Field(..., min_length=2, max_length=300)
    subject: str
    education_level: Optional[str] = None


@router.post("/cambridge-teach")
async def sia_cambridge_mode(
    payload: CambridgeRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    Sia teaches using Cambridge methodology: analysis, evaluation, critical thinking,
    scenario questions, and practical applications. No rote memorization.
    """
    student_name = await _get_student_name(current_user["sub"], db)
    level = payload.education_level or await _get_student_level(current_user["sub"], db)

    answer = await sia_cambridge_teach(
        topic=payload.topic,
        subject=payload.subject,
        education_level=level,
        student_id=current_user["sub"],
        student_name=student_name,
    )
    return {"sia": answer, "topic": payload.topic, "style": "cambridge"}


# ── Student Analytics Profile ─────────────────────────────────────────────────

@router.get("/my-profile")
async def get_my_learning_profile(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    Returns the student's full learning profile:
    weak subjects, learning speed, confidence, quiz history,
    streak, total study time, and personalized study plan.
    """
    from app.models.student_analytics import StudentLearningProfile
    result = await db.execute(
        select(StudentLearningProfile).where(
            StudentLearningProfile.student_id == current_user["sub"]
        )
    )
    profile = result.scalar_one_or_none()
    if not profile:
        return {
            "message": "No learning profile yet. Start studying with Sia to build your profile.",
            "weak_subjects": {},
            "strong_subjects": {},
            "learning_speed": "medium",
            "confidence_level": "building",
            "streak_days": 0,
            "total_study_minutes": 0,
            "total_ai_sessions": 0,
        }
    return {
        "weak_subjects": profile.weak_subjects,
        "strong_subjects": profile.strong_subjects,
        "mistake_patterns": profile.mistake_patterns,
        "learning_speed": profile.learning_speed,
        "confidence_level": profile.confidence_level,
        "attention_pattern": profile.attention_pattern,
        "preferred_language": profile.preferred_language,
        "revision_frequency": profile.revision_frequency,
        "total_ai_sessions": profile.total_ai_sessions,
        "total_cbt_sessions": profile.total_cbt_sessions,
        "total_study_minutes": profile.total_study_minutes,
        "streak_days": profile.streak_days,
        "study_plan": profile.study_plan,
        "last_active_at": profile.last_active_at,
    }


# ── Parent Intelligence Dashboard ────────────────────────────────────────────

@router.get("/parent-report/{student_id}")
async def get_parent_report(
    student_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    Generates a parent-readable intelligence report for a student.
    Students can only access their own report (share with parent).
    Shows: attention level, weak subjects, learning consistency,
    emotional learning pattern, and progress.
    """
    # Students can only view their own report
    if current_user["sub"] != student_id:
        raise HTTPException(status_code=403, detail="You can only view your own report")

    from app.models.student_analytics import StudentLearningProfile
    result = await db.execute(
        select(StudentLearningProfile).where(
            StudentLearningProfile.student_id == student_id
        )
    )
    profile = result.scalar_one_or_none()

    student_name = await _get_student_name(student_id, db)
    level = await _get_student_level(student_id, db)

    if not profile:
        return {
            "message": "Not enough data yet. The student needs to study more with Sia to generate a report.",
            "student": student_name,
        }

    # Compute average quiz score from history
    quiz_history = profile.quiz_history or []
    avg_score = (
        sum(q.get("score", 0) for q in quiz_history) / len(quiz_history)
        if quiz_history else 0.0
    )

    report = await sia_parent_report(
        student_name=student_name,
        level=level,
        profile_data={
            "total_ai_sessions": profile.total_ai_sessions,
            "total_study_minutes": profile.total_study_minutes,
            "streak_days": profile.streak_days,
            "weak_subjects": profile.weak_subjects,
            "strong_subjects": profile.strong_subjects,
            "avg_score": avg_score,
            "learning_speed": profile.learning_speed,
            "confidence_level": profile.confidence_level,
            "attention_pattern": profile.attention_pattern,
            "last_active": str(profile.last_active_at) if profile.last_active_at else "Unknown",
        },
    )
    return {
        "sia_report": report,
        "student": student_name,
        "raw_data": {
            "streak_days": profile.streak_days,
            "total_sessions": profile.total_ai_sessions,
            "total_study_minutes": profile.total_study_minutes,
            "weak_subjects": profile.weak_subjects,
            "confidence_level": profile.confidence_level,
            "learning_speed": profile.learning_speed,
        },
    }


# ── Study Companion: Inactivity Nudge ────────────────────────────────────────

class StudyCompanionRequest(BaseModel):
    last_subject: Optional[str] = None
    last_topic: Optional[str] = None
    days_inactive: int = Field(default=1, ge=1, le=365)


@router.post("/nudge")
async def sia_nudge(
    payload: StudyCompanionRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """
    Sia sends a warm, personalized nudge to an inactive student.
    Suggests revision, recommends practice, continues unfinished lessons.
    """
    student_name = await _get_student_name(current_user["sub"], db)
    answer = await sia_study_companion(
        student_name=student_name,
        last_subject=payload.last_subject or "",
        last_topic=payload.last_topic or "",
        days_inactive=payload.days_inactive,
    )
    return {"sia": answer}
