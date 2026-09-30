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
                    email="admin@divine-light.test",
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
                    email=f"stu{i}@divine-light.test",
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
loop.close()


# _user_from_sql() uses the PG-only "role::text" cast — replace it with an
# ORM lookup so login works on SQLite (behaviour is identical).
import app.routers.auth as auth_router  # noqa: E402
from sqlalchemy import select as _select  # noqa: E402


async def _sqlite_user_lookup(db, email):
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

    class _W:  # same duck-type as auth.py's SqlUser
        pass

    w = _W()
    w.id = u.id
    w.email = u.email
    w.full_name = u.full_name
    w.hashed_password = u.hashed_password
    w.role = str(getattr(u, "role", "student") or "student").replace("UserRole.", "").lower()
    w.is_active = bool(u.is_active)
    w.school_id = u.school_id
    w.phone = u.phone
    w.profile_picture = u.profile_picture
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
    print(" Scholaxia LOCAL DEV  —  http://127.0.0.1:8000")
    print("   Main site:   http://127.0.0.1:8000/")
    print("   Create acct: http://127.0.0.1:8000/app/auth.html")
    print("   School link: http://127.0.0.1:8000/school/divine-light/")
    print("   Admin UI:    http://127.0.0.1:8000/admin/")
    print("   DEBUG OTP:   signup response carries debug_otp; the signup")
    print("                screen shows it automatically — no email needed.")
    print("   Demo school admin: admin@divine-light.test / Admin1234!")
    print("=" * 64 + "\n")
    uvicorn.run(app, host="127.0.0.1", port=8000, log_level="info")


if __name__ == "__main__":
    main()
