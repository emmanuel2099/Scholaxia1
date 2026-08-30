from pathlib import Path
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, Query, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy.ext.asyncio import AsyncSession

import app.models  # noqa: F401 — register models with Base.metadata
from app.core.config import settings
from app.core.database import engine, get_db
from app.core.redis import init_redis, close_redis
from app.core.startup_db import database_ready, ensure_postgres_enums, initialize_database, probe_database

ADMIN_STATIC_DIR = Path(__file__).resolve().parent.parent / "static" / "admin"
# Prefer static/app (same deploy path as working /admin); fall back to /website.
WEBSITE_STATIC_DIR = Path(__file__).resolve().parent.parent / "static" / "app"
if not WEBSITE_STATIC_DIR.is_dir():
    WEBSITE_STATIC_DIR = Path(__file__).resolve().parent.parent / "website"

from app.routers import auth, students, admin, live_class, cbt, community, ai_tutor, notifications, payments, paystack_payments
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
from app.routers import cbt_coupons, cbt_practice, videos, school_office, schools, external_exams
from app.websockets.live_class_ws import live_class_endpoint


@asynccontextmanager
async def lifespan(app: FastAPI):
    db_ok = await initialize_database()
    try:
        await ensure_postgres_enums()
    except Exception:
        pass
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


# Browser clients (GitHub Pages) call the API with credentials: "omit".
# Wildcard CORS is valid and avoids Origin / preflight edge-cases that surface as
# "Failed to fetch" even when /health works.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
    max_age=86400,
)

app.include_router(app_meta.router, prefix="/api/v1")
app.include_router(auth.router, prefix="/api/v1")
app.include_router(students.router, prefix="/api/v1")
app.include_router(admin.router, prefix="/api/v1")
app.include_router(live_class.router, prefix="/api/v1")
app.include_router(school_groups.router, prefix="/api/v1")
app.include_router(student_groups.router, prefix="/api/v1")
app.include_router(cbt.router, prefix="/api/v1")
app.include_router(cbt_practice.router, prefix="/api/v1")
app.include_router(community.router, prefix="/api/v1")
app.include_router(ai_tutor.router, prefix="/api/v1")
app.include_router(notifications.router, prefix="/api/v1")
app.include_router(payments.router, prefix="/api/v1")
app.include_router(paystack_payments.router, prefix="/api/v1")
app.include_router(paystack_payments.payments_router, prefix="/api/v1")
app.include_router(reviews_reports.router, prefix="/api/v1")
app.include_router(teacher_ai.router, prefix="/api/v1")
app.include_router(library.router, prefix="/api/v1")
app.include_router(marketplace.router, prefix="/api/v1")
app.include_router(marketplace.admin_router, prefix="/api/v1")
app.include_router(marketplace.vendor_router, prefix="/api/v1")
app.include_router(kid_games.router, prefix="/api/v1")
app.include_router(kid_games.admin_router, prefix="/api/v1")
app.include_router(sil.router, prefix="/api/v1")
app.include_router(cbt_coupons.router, prefix="/api/v1")
app.include_router(videos.router, prefix="/api/v1")
app.include_router(school_office.router, prefix="/api/v1")
app.include_router(external_exams.staff_router, prefix="/api/v1")
app.include_router(external_exams.public_router, prefix="/api/v1")
app.include_router(schools.router, prefix="/api/v1")
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
    ready = database_ready() or await probe_database()
    app_dir = WEBSITE_STATIC_DIR if WEBSITE_STATIC_DIR.is_dir() else None
    return {
        "status": "ok" if ready else "degraded",
        "app": settings.APP_NAME,
        "database": "connected" if ready else "unavailable",
        "database_host": settings.database_host,
        "admin_ui": "/admin/" if ADMIN_STATIC_DIR.is_dir() else None,
        "student_ui": "/app/student.html" if app_dir and (app_dir / "student.html").is_file() else None,
        "student_ui_dir": str(app_dir) if app_dir else None,
        "hint": (
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


from fastapi.responses import FileResponse  # noqa: F811 — kept near routes for clarity

# Explicit routes so /app works even if StaticFiles mount order is flaky on Render.
@app.get("/app")
@app.get("/app/")
async def app_home():
    if not WEBSITE_STATIC_DIR.is_dir():
        raise HTTPException(status_code=404, detail="Student app folder missing on this deploy")
    index = WEBSITE_STATIC_DIR / "index.html"
    student = WEBSITE_STATIC_DIR / "student.html"
    target = index if index.is_file() else student
    if not target.is_file():
        raise HTTPException(status_code=404, detail="Student app not packaged on this deploy")
    no_cache = {"Cache-Control": "no-store, no-cache, must-revalidate", "Pragma": "no-cache"}
    return FileResponse(target, headers=no_cache)


@app.get("/app/{asset_path:path}")
async def app_assets(asset_path: str):
    if not WEBSITE_STATIC_DIR.is_dir():
        raise HTTPException(status_code=404, detail="Student app folder missing on this deploy")
    # Prevent path traversal
    safe = Path(asset_path)
    if ".." in safe.parts:
        raise HTTPException(status_code=400, detail="Invalid path")
    full = (WEBSITE_STATIC_DIR / safe).resolve()
    root = WEBSITE_STATIC_DIR.resolve()
    try:
        full.relative_to(root)
    except ValueError:
        raise HTTPException(status_code=404, detail="Not found")
    if not full.is_file():
        raise HTTPException(status_code=404, detail="Not found")
    no_cache = {"Cache-Control": "no-store, no-cache, must-revalidate", "Pragma": "no-cache"}
    return FileResponse(full, headers=no_cache)


# Admin website (same host as API): https://scholaxia1.onrender.com/admin/
if ADMIN_STATIC_DIR.is_dir():
    app.mount(
        "/admin",
        StaticFiles(directory=str(ADMIN_STATIC_DIR), html=True),
        name="admin_ui",
    )