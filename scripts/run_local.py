"""Local test server for Scholaxia — SAFE: SQLite file DB, never touches production.

Run:  .venv/Scripts/python.exe scripts/run_local.py
Then: http://127.0.0.1:8000/                     (main student site)
      http://127.0.0.1:8000/app/auth.html        (create account / login)
      http://127.0.0.1:8000/school/divine-light/ (school portal, demo school)
      http://127.0.0.1:8000/admin/               (admin UI)

DEBUG=True so POST /api/v1/auth/signup/start returns debug_otp in the response —
the signup screen shows it and you can verify without email.

Stop with Ctrl+C.
"""
import asyncio
import os
import sys
import uuid as uuidmod
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB_FILE = ROOT / "local_dev.db"
if DB_FILE.exists():
    DB_FILE.unlink()  # fresh database every launch

os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{DB_FILE.as_posix()}"
os.environ.setdefault("SECRET_KEY", "local-dev-secret-key-not-for-prod")
os.environ["DEBUG"] = "1"
os.environ.setdefault("SEED_SAMPLE_CBT", "1")  # sample WAEC/NECO/JAMB papers so CBT is testable locally
os.environ["REDIS_URL"] = "redis://localhost:6379/0"  # absent locally → OTP memory fallback

sys.path.insert(0, str(ROOT))

# ── PG→SQLite type shims (same trick as scripts/test_school_cbt.py), applied
#    before models are imported / tables are created. ────────────────────────
from sqlalchemy import CHAR, JSON as _JSON  # noqa: E402
from sqlalchemy.dialects.postgresql import ARRAY, UUID as PG_UUID  # noqa: E402
from sqlalchemy.ext.asyncio import (  # noqa: E402
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.types import TypeDecorator  # noqa: E402


class _GuidAny(TypeDecorator):
    impl = CHAR
    cache_ok = True

    def load_dialect_impl(self, dialect):
        return dialect.type_descriptor(CHAR(36))

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        return value if isinstance(value, str) else str(value)

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        return value if isinstance(value, uuidmod.UUID) else uuidmod.UUID(str(value))


import app.core.database as database  # noqa: E402

database.engine = create_async_engine(
    f"sqlite+aiosqlite:///{DB_FILE.as_posix()}",
    connect_args={"check_same_thread": False, "timeout": 30},
)
database.AsyncSessionLocal = async_sessionmaker(
    database.engine, class_=AsyncSession, expire_on_commit=False
)

import app.core.startup_db as startup_db  # noqa: E402

startup_db.engine = database.engine
startup_db.AsyncSessionLocal = database.AsyncSessionLocal

for _t in database.Base.metadata.tables.values():
    for _c in _t.columns:
        if isinstance(_c.type, ARRAY):
            _c.type = _JSON()
        elif isinstance(_c.type, PG_UUID):
            _c.type = _GuidAny()


async def _create_all():
    from app.core.database import Base

    async with database.engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


def _seed_demo_school():
    """Seed a demo school + admin so the school portal is testable immediately."""

    async def _seed():
        from sqlalchemy import select

        from app.core.security import hash_password
        from app.models.school_campus import SchoolCampus
        from app.models.user import StudentProfile, User, UserRole

        async with database.AsyncSessionLocal() as db:
            existing = (
                await db.execute(select(SchoolCampus).where(SchoolCampus.slug == "divine-light"))
            ).scalar_one_or_none()
            if existing:
                return
            campus = SchoolCampus(
                name="Divine Light College",
                code="DLC",
                slug="divine-light",
                city="Lagos",
                state="LA",
                is_active=True,
                subscription_active=True,
            )
            db.add(campus)
            await db.flush()
            db.add(
                User(
                    email="admin@divine-light.example.com",
                    hashed_password=hash_password("Admin1234!"),
                    full_name="Divine Light Admin",
                    role=UserRole.school_admin,
                    is_verified=True,
                    is_active=True,
                    school_id=campus.id,
                )
            )
            for i, lvl in ((1, "JSS1"), (2, "JSS2"), (3, "SS2")):
                u = User(
                    email=f"stu{i}@divine-light.example.com",
                    hashed_password=hash_password("Student123!"),
                    full_name=f"Test Student {i}",
                    role=UserRole.student,
                    is_verified=True,
                    is_active=True,
                    school_id=campus.id,
                )
                db.add(u)
                await db.flush()
                db.add(
                    StudentProfile(
                        user_id=u.id,
                        education_level=lvl,
                        school_student_id=f"DLC/26/100{i}",
                    )
                )
            await db.commit()

    asyncio.new_event_loop().run_until_complete(_seed())


def _seed_demo_admin():
    """Seed a platform admin so the /admin/ UI is testable immediately."""

    async def _seed():
        from sqlalchemy import select

        from app.core.security import hash_password
        from app.models.user import User, UserRole

        async with database.AsyncSessionLocal() as db:
            existing = (
                await db.execute(select(User).where(User.email == "admin@scholaxiatest.com"))
            ).scalar_one_or_none()
            if existing:
                return
            db.add(
                User(
                    email="admin@scholaxiatest.com",
                    hashed_password=hash_password("AdminPass123!"),
                    full_name="Main Admin (Local)",
                    role=UserRole.admin,
                    is_verified=True,
                    is_active=True,
                )
            )
            await db.commit()

    asyncio.new_event_loop().run_until_complete(_seed())


def _seed_demo_market():
    """Seed the marketplace so the Market page is not empty locally.

    Prefers scripts/demo_market_products.json — a snapshot of the live site's
    approved catalog (titles, prices, images). Falls back to a small built-in
    demo list when the snapshot is missing.
    """

    async def _seed():
        import json

        from sqlalchemy import select

        from app.models.marketplace import MarketplaceProduct

        async with database.AsyncSessionLocal() as db:
            existing = (await db.execute(select(MarketplaceProduct).limit(1))).first()
            if existing:
                return
            snap_path = Path(__file__).resolve().parent / "demo_market_products.json"
            demo = []
            if snap_path.exists():
                try:
                    demo = json.loads(snap_path.read_text(encoding="utf-8"))
                except Exception:
                    demo = []
            if not demo:
                demo = [
                    ("Essential Mathematics for SSCE", "Complete SSCE mathematics textbook with worked examples and past-paper practice.", "books", 3500, 12),
                    ("New General Mathematics Workbook", "Exercise workbook for JSS–SSS, aligned with the Nigerian curriculum.", "educational_materials", 2800, 20),
                    ("SanDisk 32GB Flash Drive", "Reliable USB 3.0 flash drive for school projects and CBT materials.", "flash_drive", 6500, 15),
                    ("HP Laptop Charger", "Original 65W HP laptop charger — fits most HP Pavilion/ProBook models.", "charger", 9000, 8),
                    ("Infinix Smart 8", "Budget smartphone with 6.6\" display, 5000mAh battery — great for online classes.", "phones", 128000, 5),
                    ("School Backpack (Navy)", "Durable water-resistant backpack with laptop compartment.", "bags", 7500, 10),
                    ("Whiteboard Marker Set (4)", "Assorted colours, low-odour dry-erase markers.", "educational_materials", 1200, 30),
                    ("Microsoft Office Study Suite", "Word, Excel & PowerPoint — student licence, digital delivery.", "software", 15000, 25),
                ]
            for item in demo:
                if isinstance(item, dict):
                    title, desc = item["title"], item.get("description")
                    category, price = item.get("category") or "other", float(item.get("price") or 0)
                    stock, image = int(item.get("stock_qty") or 10), item.get("image_url")
                    currency = item.get("currency") or "NGN"
                else:
                    title, desc, category, price, stock = item
                    currency, image = "NGN", None
                db.add(
                    MarketplaceProduct(
                        title=title,
                        description=desc,
                        category=category,
                        price=price,
                        currency=currency,
                        image_url=image,
                        is_available=True,
                        is_free=False,
                        is_active=True,
                        approval_status="approved",
                        source_role="admin",
                        stock_qty=stock,
                    )
                )
            await db.commit()

    asyncio.new_event_loop().run_until_complete(_seed())


async def _noop(*args, **kwargs):
    return None


# Boot-time PG-only migrations are pointless on SQLite — skip them.
for _name in (
    "ensure_school_campus_schema",
    "ensure_school_plans_schema",
    "ensure_ai_token_schema",
    "ensure_cbt_coupon_tables",
    "ensure_videos_table",
    "ensure_community_posts_columns",
    "ensure_live_class_schema",
    "ensure_school_cbt_schema",
    "ensure_model_columns",
):
    setattr(startup_db, _name, _noop)

loop = asyncio.new_event_loop()
loop.run_until_complete(_create_all())
_seed_demo_school()
_seed_demo_admin()
_seed_demo_market()
loop.close()


# _user_from_sql() uses the PG-only "role::text" cast — replace it with an
# ORM lookup so login works on SQLite (behaviour is identical).
import app.routers.auth as auth_router  # noqa: E402
from sqlalchemy import select as _select  # noqa: E402


async def _sqlite_user_lookup(db, email):
    # Duck-typed copy of auth.py's SqlUser with STRING ids: the login path
    # binds user.id/school_id into raw text() SQL, and sqlite3 cannot bind
    # UUID objects (asyncpg on prod can). ORM lookups only — no writes here.
    from app.models.user import User as _User

    try:
        res = await db.execute(
            _select(_User).where(_User.email.ilike((email or "").strip()))
        )
        u = res.scalars().first()
    except Exception:
        return None
    if not u:
        return None

    class _W:
        pass

    w = _W()
    w.id = str(u.id)
    w.email = u.email
    w.full_name = u.full_name
    w.hashed_password = u.hashed_password
    w.role = str(getattr(u, "role", "student") or "student").replace("UserRole.", "").lower()
    w.is_active = bool(u.is_active)
    w.school_id = str(u.school_id) if u.school_id else None
    w.phone = u.phone
    w.profile_picture = u.profile_picture
    w.sub_admin_permissions = getattr(u, "sub_admin_permissions", None)
    w.token_version = int(getattr(u, "token_version", 0) or 0)
    return w


auth_router._user_from_sql = _sqlite_user_lookup


# Safety net: this launcher must never boot against a non-sqlite DB.
assert "sqlite" in os.environ["DATABASE_URL"], "refusing to boot against a non-sqlite DB"

from fastapi import FastAPI  # noqa: E402

from app.main import app  # noqa: E402

# Replace the pg-only /db-check debug endpoint (assumes pg_tables).
app.router.routes = [r for r in app.router.routes if getattr(r, "path", "") != "/db-check"]


@app.get("/db-check")
async def _db_check_local():
    return {"status": "ok", "db": "sqlite (local dev)"}


def main():
    import uvicorn

    print("\n" + "=" * 64)
    port = int(os.environ.get("PORT", "8000"))
    print(f" Scholaxia LOCAL DEV  —  http://127.0.0.1:{port}")
    print(f"   Main site:   http://127.0.0.1:{port}/")
    print(f"   Create acct: http://127.0.0.1:{port}/app/auth.html")
    print(f"   School link: http://127.0.0.1:{port}/school/divine-light/")
    print(f"   Admin UI:    http://127.0.0.1:{port}/admin/")
    print("   DEBUG OTP:   signup response carries debug_otp; the signup")
    print("                screen shows it automatically — no email needed.")
    print("   Demo school admin: admin@divine-light.example.com / Admin1234!")
    print("   Platform admin:    admin@scholaxiatest.com / AdminPass123!  (for /admin/)")
    print("=" * 64 + "\n")
    port = int(os.environ.get("PORT", "8000"))
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="info")


if __name__ == "__main__":
    main()
