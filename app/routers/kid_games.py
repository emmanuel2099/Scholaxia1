"""
Kids educational games — admin questions + public catalog.
"""

from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import require_admin, get_current_user
from app.models.kid_games import KidGameQuestion, KID_GAME_CATALOG

router = APIRouter(prefix="/kind/games", tags=["Kind — Games"])
admin_router = APIRouter(prefix="/admin/kind-games", tags=["Admin — Kind Games"])


def _q_dict(q: KidGameQuestion) -> dict:
    opts = q.options if isinstance(q.options, list) else []
    return {
        "id": str(q.id),
        "game_id": q.game_id,
        "prompt": q.prompt,
        "options": opts,
        "correct_index": int(q.correct_index or 0),
        "speak_word": q.speak_word,
        "is_active": bool(q.is_active),
        "created_at": q.created_at.isoformat() if q.created_at else None,
    }


def _valid_game_id(game_id: str) -> bool:
    return any(g["id"] == game_id for g in KID_GAME_CATALOG)


@router.get("/catalog")
async def games_catalog():
    return {"games": KID_GAME_CATALOG, "session_size": 50, "max_leaf": 10}


@router.get("/{game_id}/questions")
async def list_game_questions(
    game_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Builtin banks live in the app; this returns admin-added questions to merge."""
    if not _valid_game_id(game_id):
        raise HTTPException(status_code=404, detail="Unknown game")
    result = await db.execute(
        select(KidGameQuestion)
        .where(
            KidGameQuestion.game_id == game_id,
            KidGameQuestion.is_active == True,  # noqa: E712
        )
        .order_by(KidGameQuestion.created_at.asc())
    )
    rows = result.scalars().all()
    return {"game_id": game_id, "questions": [_q_dict(q) for q in rows], "count": len(rows)}


# ── Admin ─────────────────────────────────────────────────────────────────────

class KidQuestionCreate(BaseModel):
    game_id: str = Field(..., min_length=2, max_length=80)
    prompt: str = Field(..., min_length=2, max_length=2000)
    options: List[str] = Field(..., min_length=2, max_length=6)
    correct_index: int = Field(..., ge=0)
    speak_word: Optional[str] = Field(None, max_length=255)


class KidQuestionBulkCreate(BaseModel):
    game_id: str
    questions: List[KidQuestionCreate] = Field(..., min_length=1, max_length=100)


@admin_router.get("/catalog")
async def admin_games_catalog(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    # Attach question counts
    counts = {}
    result = await db.execute(
        select(KidGameQuestion.game_id, func.count())
        .where(KidGameQuestion.is_active == True)  # noqa: E712
        .group_by(KidGameQuestion.game_id)
    )
    for gid, n in result.all():
        counts[gid] = n
    games = [{**g, "admin_questions": counts.get(g["id"], 0)} for g in KID_GAME_CATALOG]
    return {"games": games, "session_size": 50}


@admin_router.get("/questions")
async def admin_list_questions(
    game_id: Optional[str] = Query(None),
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    q = select(KidGameQuestion).where(KidGameQuestion.is_active == True)  # noqa: E712
    if game_id:
        q = q.where(KidGameQuestion.game_id == game_id)
    result = await db.execute(q.order_by(KidGameQuestion.created_at.desc()).limit(500))
    return [_q_dict(row) for row in result.scalars().all()]


@admin_router.post("/questions", status_code=201)
async def admin_create_question(
    payload: KidQuestionCreate,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    if not _valid_game_id(payload.game_id):
        raise HTTPException(status_code=400, detail="Unknown game_id")
    opts = [o.strip() for o in payload.options if o and o.strip()]
    if len(opts) < 2:
        raise HTTPException(status_code=400, detail="Need at least 2 options")
    if payload.correct_index < 0 or payload.correct_index >= len(opts):
        raise HTTPException(status_code=400, detail="correct_index out of range")
    row = KidGameQuestion(
        game_id=payload.game_id.strip(),
        prompt=payload.prompt.strip(),
        options=opts,
        correct_index=payload.correct_index,
        speak_word=(payload.speak_word or "").strip() or None,
        created_by=current_user.get("sub"),
    )
    db.add(row)
    await db.flush()
    return _q_dict(row)


@admin_router.post("/questions/bulk", status_code=201)
async def admin_bulk_create(
    payload: KidQuestionBulkCreate,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    if not _valid_game_id(payload.game_id):
        raise HTTPException(status_code=400, detail="Unknown game_id")
    created = []
    for item in payload.questions:
        opts = [o.strip() for o in item.options if o and o.strip()]
        if len(opts) < 2:
            continue
        ci = item.correct_index
        if ci < 0 or ci >= len(opts):
            continue
        row = KidGameQuestion(
            game_id=payload.game_id.strip(),
            prompt=item.prompt.strip(),
            options=opts,
            correct_index=ci,
            speak_word=(item.speak_word or "").strip() or None,
            created_by=current_user.get("sub"),
        )
        db.add(row)
        await db.flush()
        created.append(_q_dict(row))
    return {"created": len(created), "questions": created}


@admin_router.delete("/questions/{question_id}", status_code=200)
async def admin_delete_question(
    question_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(KidGameQuestion).where(KidGameQuestion.id == question_id)
    )
    row = result.scalar_one_or_none()
    if not row:
        raise HTTPException(status_code=404, detail="Question not found")
    row.is_active = False
    await db.flush()
    return {"message": "Question removed"}
