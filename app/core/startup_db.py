"""Database schema bootstrap — runs on app startup when DATABASE_URL is reachable."""
import logging
import socket

from sqlalchemy import text

from app.core.config import settings
from app.core.database import Base, AsyncSessionLocal, engine
from app.core.seed import seed_database

logger = logging.getLogger(__name__)

_db_initialized = False


def database_ready() -> bool:
    return _db_initialized


async def _run_schema_migrations(conn) -> None:
    await conn.run_sync(Base.metadata.create_all)
    await conn.execute(text(
        "ALTER TABLE cbt_exams ALTER COLUMN created_by DROP NOT NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS is_anonymous BOOLEAN NOT NULL DEFAULT FALSE"
    ))
    await conn.execute(text(
        "ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS visibility VARCHAR(20) NOT NULL DEFAULT 'everyone'"
    ))
    await conn.execute(text(
        "ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS cbt_exam_id UUID NULL"
    ))
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
        "ALTER TABLE cbt_exams ADD COLUMN IF NOT EXISTS year INTEGER NULL"
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
        "ALTER TABLE student_groups ADD COLUMN IF NOT EXISTS is_approved BOOLEAN NOT NULL DEFAULT TRUE"
    ))
    await conn.execute(text(
        "UPDATE student_groups SET is_approved = TRUE WHERE is_approved IS NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS group_id UUID NULL REFERENCES student_groups(id)"
    ))
    await conn.execute(text(
        """
        CREATE TABLE IF NOT EXISTS post_reactions (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            post_id UUID NOT NULL REFERENCES community_posts(id),
            user_id UUID NOT NULL REFERENCES users(id),
            emoji VARCHAR(16) NOT NULL,
            created_at TIMESTAMP DEFAULT NOW(),
            UNIQUE (post_id, user_id)
        )
        """
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
        await conn.execute(text(
            "ALTER TABLE users ALTER COLUMN profile_picture TYPE VARCHAR(1000)"
        ))
    except Exception:
        pass
    try:
        await conn.execute(text("ALTER TYPE examtype ADD VALUE IF NOT EXISTS 'POST_UTME'"))
    except Exception:
        pass
    try:
        await conn.execute(text("ALTER TYPE examtype ADD VALUE IF NOT EXISTS 'JUNIOR_WAEC'"))
    except Exception:
        pass
    try:
        await conn.execute(text("ALTER TYPE userrole ADD VALUE IF NOT EXISTS 'kind'"))
    except Exception:
        pass


async def initialize_database() -> bool:
    """Create tables, run migrations, and seed. Returns False if DATABASE_URL is invalid."""
    global _db_initialized
    try:
        async with engine.begin() as conn:
            await _run_schema_migrations(conn)
        async with AsyncSessionLocal() as db:
            await seed_database(db)
        _db_initialized = True
        logger.info("Database ready (host=%s)", settings.database_host)
        return True
    except (socket.gaierror, OSError, ConnectionRefusedError) as exc:
        logger.error(
            "DATABASE_URL host %r cannot be resolved (%s). "
            "On Render: create or link a PostgreSQL database and set DATABASE_URL "
            "to its Internal Database URL, then redeploy.",
            settings.database_host,
            exc,
        )
        return False
    except Exception as exc:
        logger.error(
            "Database startup failed for host %r: %s",
            settings.database_host,
            exc,
        )
        return False
