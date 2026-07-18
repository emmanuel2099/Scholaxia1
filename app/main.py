from fastapi import FastAPI, WebSocket, Query, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession
from contextlib import asynccontextmanager

import app.models  # noqa: F401 — register models with Base.metadata
from app.core.config import settings
from app.core.database import engine, get_db
from app.core.redis import init_redis, close_redis
from app.core.startup_db import database_ready, initialize_database

from app.routers import auth, students, admin, live_class, cbt, community, ai_tutor, notifications, payments, flutterwave_payments
from app.routers import developer_auth, developer_keys, public_ai_api, reviews_reports, teacher_ai, library, wallet, materials
from app.routers import recommendations
from app.routers import performance
from app.routers import home
from app.routers import kind
from app.routers import profiles
from app.routers import school_groups, student_groups
from app.routers import app_meta
from app.routers import marketplace
from app.routers import kid_games
from app.routers import sil
from app.websockets.live_class_ws import live_class_endpoint


@asynccontextmanager
async def lifespan(app: FastAPI):
    db_ok = await initialize_database()
    try:
        await init_redis()
    except Exception:
        pass
    if db_ok:
        from app.services.live_class_scheduler import start_live_class_scheduler
        start_live_class_scheduler()
    yield
    await close_redis()
    await engine.dispose()


app = FastAPI(
    title="Scholaxia API — Powered by Sia",
    description="Scholaxia educational ecosystem. Student AI tutor: Sia (Scholaxia Intelligent Assistant)",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(app_meta.router, prefix="/api/v1")
app.include_router(auth.router, prefix="/api/v1")
app.include_router(students.router, prefix="/api/v1")
app.include_router(admin.router, prefix="/api/v1")
app.include_router(live_class.router, prefix="/api/v1")
app.include_router(school_groups.router, prefix="/api/v1")
app.include_router(student_groups.router, prefix="/api/v1")
app.include_router(cbt.router, prefix="/api/v1")
app.include_router(community.router, prefix="/api/v1")
app.include_router(ai_tutor.router, prefix="/api/v1")
app.include_router(notifications.router, prefix="/api/v1")
app.include_router(payments.router, prefix="/api/v1")
app.include_router(flutterwave_payments.router, prefix="/api/v1")
app.include_router(reviews_reports.router, prefix="/api/v1")
app.include_router(teacher_ai.router, prefix="/api/v1")
app.include_router(library.router, prefix="/api/v1")
app.include_router(marketplace.router, prefix="/api/v1")
app.include_router(marketplace.admin_router, prefix="/api/v1")
app.include_router(kid_games.router, prefix="/api/v1")
app.include_router(kid_games.admin_router, prefix="/api/v1")
app.include_router(sil.router, prefix="/api/v1")
app.include_router(materials.router, prefix="/api/v1")
app.include_router(wallet.router, prefix="/api/v1")
app.include_router(recommendations.router, prefix="/api/v1")
app.include_router(home.router, prefix="/api/v1")
app.include_router(kind.router, prefix="/api/v1")
app.include_router(performance.router, prefix="/api/v1")
app.include_router(developer_auth.router, prefix="/api/v1")
app.include_router(developer_keys.router, prefix="/api/v1")
app.include_router(public_ai_api.router, prefix="/api")
app.include_router(profiles.router, prefix="/api/v1")


@app.websocket("/ws/live-class/{room_id}")
async def live_class_ws(
    websocket: WebSocket,
    room_id: str,
    user_id: str = Query(...),
    role: str = Query(...),
    display_name: str = Query(""),
):
    await live_class_endpoint(websocket, room_id, user_id, role, display_name or "")


@app.get("/health")
async def health():
    ready = database_ready()
    return {
        "status": "ok" if ready else "degraded",
        "app": settings.APP_NAME,
        "database": "connected" if ready else "unavailable",
        "database_host": settings.database_host,
        "fix": (
            None
            if ready
            else "On Render: link a live PostgreSQL database and set DATABASE_URL to its Internal Database URL."
        ),
    }


@app.get("/db-check")
async def db_check(db: AsyncSession = Depends(get_db)):
    """Check DB tables — remove after debugging."""
    from sqlalchemy import text
    try:
        result = await db.execute(text("SELECT tablename FROM pg_tables WHERE schemaname='public'"))
        tables = sorted([row[0] for row in result.fetchall()])
        return {"status": "ok", "tables": tables, "count": len(tables)}
    except Exception as e:
        return {"status": "error", "detail": str(e)}


@app.get("/debug-posts")
async def debug_posts(db: AsyncSession = Depends(get_db)):
    """Temporary debug endpoint — remove after diagnosis."""
    try:
        from sqlalchemy import text
        result = await db.execute(text(
            "SELECT id, visibility, is_anonymous FROM community_posts LIMIT 3"
        ))
        rows = [dict(r._mapping) for r in result.fetchall()]
        return {"status": "ok", "sample_rows": rows}
    except Exception as e:
        import traceback
        return {"status": "error", "detail": str(e), "trace": traceback.format_exc()}


@app.get("/debug-sia")
async def debug_sia(db: AsyncSession = Depends(get_db)):
    """Debug endpoint to test Sia directly."""
    try:
        from app.ai.prompt_builder import build_explain_prompt
        prompt = build_explain_prompt("photosynthesis", "Biology", "SS1", "english", "Test")
        return {"status": "prompt_ok", "length": len(prompt)}
    except Exception as e:
        import traceback
        return {"status": "error", "detail": str(e), "trace": traceback.format_exc()}
