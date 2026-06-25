from fastapi import FastAPI, WebSocket, Query, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession
from contextlib import asynccontextmanager

from app.core.config import settings
from app.core.database import engine, Base, AsyncSessionLocal, get_db
from app.core.redis import init_redis, close_redis
from app.core.seed import seed_database

from app.routers import auth, students, admin, live_class, cbt, community, ai_tutor, notifications, payments, flutterwave_payments
from app.routers import developer_auth, developer_keys, public_ai_api, reviews_reports, teacher_ai, library, wallet, materials
from app.routers import recommendations
from app.routers import performance
from app.routers import home
from app.routers import kind
from app.routers import profiles
from app.routers import school_groups
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
        # Backfill any existing rows that got NULL before DEFAULT was set
        await conn.execute(text(
            "UPDATE community_posts SET visibility = 'everyone' WHERE visibility IS NULL"
        ))
        await conn.execute(text(
            "UPDATE community_posts SET is_anonymous = FALSE WHERE is_anonymous IS NULL"
        ))
        await conn.execute(text(
            "ALTER TABLE cbt_exams ADD COLUMN IF NOT EXISTS scheduled_start TIMESTAMP NULL"
        ))
        await conn.execute(text(
            "ALTER TABLE cbt_exams ADD COLUMN IF NOT EXISTS scheduled_end TIMESTAMP NULL"
        ))
        await conn.execute(text(
            "ALTER TABLE payments ADD COLUMN IF NOT EXISTS flutterwave_tx_ref VARCHAR(255) NULL"
        ))
        await conn.execute(text(
            "ALTER TABLE payments ADD COLUMN IF NOT EXISTS flutterwave_transaction_id VARCHAR(255) NULL"
        ))
        await conn.execute(text(
            "ALTER TABLE payments ADD COLUMN IF NOT EXISTS live_class_id UUID NULL"
        ))
        await conn.execute(text(
            "ALTER TABLE payments ADD COLUMN IF NOT EXISTS material_id UUID NULL"
        ))
        await conn.execute(text(
            "ALTER TABLE payments ADD COLUMN IF NOT EXISTS live_plan_id VARCHAR(80) NULL"
        ))
        await conn.execute(text(
            "ALTER TABLE student_profiles ADD COLUMN IF NOT EXISTS live_plan_id VARCHAR(80) NULL"
        ))
        await conn.execute(text(
            "ALTER TABLE student_profiles ADD COLUMN IF NOT EXISTS live_plan_expires_at TIMESTAMP NULL"
        ))
        await conn.execute(text(
            "ALTER TABLE student_profiles ADD COLUMN IF NOT EXISTS live_plan_sessions_used INTEGER NOT NULL DEFAULT 0"
        ))
        await conn.execute(text(
            "ALTER TABLE live_session_requests ADD COLUMN IF NOT EXISTS assigned_teacher_id UUID NULL"
        ))
        await conn.execute(text(
            "ALTER TABLE books ADD COLUMN IF NOT EXISTS is_free BOOLEAN NOT NULL DEFAULT TRUE"
        ))
        await conn.execute(text(
            "ALTER TABLE books ADD COLUMN IF NOT EXISTS price DOUBLE PRECISION NOT NULL DEFAULT 0"
        ))
        await conn.execute(text(
            "ALTER TABLE payments ADD COLUMN IF NOT EXISTS book_id UUID NULL"
        ))
        await conn.execute(text(
            """
            CREATE TABLE IF NOT EXISTS school_groups (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                teacher_id UUID NOT NULL REFERENCES users(id),
                school_name VARCHAR(200) NOT NULL,
                name VARCHAR(200) NOT NULL,
                student_ids TEXT NOT NULL DEFAULT '[]',
                created_at TIMESTAMP DEFAULT NOW()
            )
            """
        ))
        await conn.execute(text(
            "ALTER TABLE live_classes ADD COLUMN IF NOT EXISTS visibility VARCHAR(20) NOT NULL DEFAULT 'subject'"
        ))
        await conn.execute(text(
            "ALTER TABLE live_classes ADD COLUMN IF NOT EXISTS join_code VARCHAR(32) NULL"
        ))
        await conn.execute(text(
            "ALTER TABLE live_classes ADD COLUMN IF NOT EXISTS invited_student_ids TEXT NULL"
        ))
        await conn.execute(text(
            "ALTER TABLE live_classes ADD COLUMN IF NOT EXISTS school_group_id UUID NULL"
        ))
        await conn.execute(text(
            """
            CREATE TABLE IF NOT EXISTS kind_profiles (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID UNIQUE NOT NULL REFERENCES users(id),
                age_group VARCHAR(20) NOT NULL DEFAULT '6-8',
                grade_level VARCHAR(50),
                parent_email VARCHAR(255),
                favorite_subjects TEXT[] DEFAULT '{}',
                learning_goals VARCHAR(500),
                preferred_language VARCHAR(30) DEFAULT 'english'
            )
            """
        ))
        try:
            await conn.execute(text("ALTER TYPE examtype ADD VALUE IF NOT EXISTS 'POST_UTME'"))
        except Exception:
            pass
        try:
            await conn.execute(text("ALTER TYPE userrole ADD VALUE IF NOT EXISTS 'kind'"))
        except Exception:
            pass
    await init_redis()
    async with AsyncSessionLocal() as db:
        await seed_database(db)
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

app.include_router(auth.router, prefix="/api/v1")
app.include_router(students.router, prefix="/api/v1")
app.include_router(admin.router, prefix="/api/v1")
app.include_router(live_class.router, prefix="/api/v1")
app.include_router(school_groups.router, prefix="/api/v1")
app.include_router(cbt.router, prefix="/api/v1")
app.include_router(community.router, prefix="/api/v1")
app.include_router(ai_tutor.router, prefix="/api/v1")
app.include_router(notifications.router, prefix="/api/v1")
app.include_router(payments.router, prefix="/api/v1")
app.include_router(flutterwave_payments.router, prefix="/api/v1")
app.include_router(reviews_reports.router, prefix="/api/v1")
app.include_router(teacher_ai.router, prefix="/api/v1")
app.include_router(library.router, prefix="/api/v1")
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
