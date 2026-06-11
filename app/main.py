from fastapi import FastAPI, WebSocket, Query, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession
from contextlib import asynccontextmanager

from app.core.config import settings
from app.core.database import engine, Base, AsyncSessionLocal, get_db
from app.core.redis import init_redis, close_redis
from app.core.seed import seed_database

from app.routers import auth, students, admin, live_class, cbt, community, ai_tutor, notifications, payments
from app.routers import developer_auth, developer_keys, public_ai_api, reviews_reports, teacher_ai, library, wallet
from app.routers import recommendations
from app.routers import performance
from app.routers import profiles
from app.websockets.live_class_ws import live_class_endpoint


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        from sqlalchemy import text
        # Fix: ensure created_by is nullable (schema drift correction)
        await conn.execute(text(
            "ALTER TABLE cbt_exams ALTER COLUMN created_by DROP NOT NULL"
        ))
        # Add new community_posts columns if they don't exist yet
        await conn.execute(text(
            "ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS is_anonymous BOOLEAN NOT NULL DEFAULT FALSE"
        ))
        await conn.execute(text(
            "ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS visibility VARCHAR(20) NOT NULL DEFAULT 'everyone'"
        ))
        await conn.execute(text(
            "ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS cbt_exam_id UUID NULL"
        ))
    await init_redis()
    async with AsyncSessionLocal() as db:
        await seed_database(db)
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

app.include_router(auth.router, prefix="/api/v1")
app.include_router(students.router, prefix="/api/v1")
app.include_router(admin.router, prefix="/api/v1")
app.include_router(live_class.router, prefix="/api/v1")
app.include_router(cbt.router, prefix="/api/v1")
app.include_router(community.router, prefix="/api/v1")
app.include_router(ai_tutor.router, prefix="/api/v1")
app.include_router(notifications.router, prefix="/api/v1")
app.include_router(payments.router, prefix="/api/v1")
app.include_router(reviews_reports.router, prefix="/api/v1")
app.include_router(teacher_ai.router, prefix="/api/v1")
app.include_router(library.router, prefix="/api/v1")
app.include_router(wallet.router, prefix="/api/v1")
app.include_router(recommendations.router, prefix="/api/v1")
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
):
    await live_class_endpoint(websocket, room_id, user_id, role)


@app.get("/health")
async def health():
    return {"status": "ok", "app": settings.APP_NAME}


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


@app.post("/debug-sia")
async def debug_sia(db: AsyncSession = Depends(get_db)):
    """Debug endpoint to test Sia directly."""
    try:
        from app.ai.prompt_builder import build_explain_prompt
        prompt = build_explain_prompt("photosynthesis", "Biology", "SS1", "english", "Test")
        return {"status": "prompt_ok", "length": len(prompt)}
    except Exception as e:
        import traceback
        return {"status": "error", "detail": str(e), "trace": traceback.format_exc()}
