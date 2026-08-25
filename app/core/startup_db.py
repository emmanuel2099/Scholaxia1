"""Database schema bootstrap — runs on app startup when DATABASE_URL is reachable."""
import asyncio
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


async def ensure_school_campus_schema() -> None:
    """Add school_campuses columns that create_all skips on existing tables.

    Runs in its own transaction so a failed bulk migration does not block this.
    """
    stmts = (
        "ALTER TABLE school_campuses ADD COLUMN IF NOT EXISTS subscription_active BOOLEAN NOT NULL DEFAULT FALSE",
        "ALTER TABLE school_campuses ADD COLUMN IF NOT EXISTS subscription_plan VARCHAR(80) NULL",
    )
    for stmt in stmts:
        try:
            async with engine.begin() as conn:
                await conn.execute(text(stmt))
        except Exception as exc:
            logger.warning("school_campus schema skipped: %s (%s)", stmt, exc)


async def ensure_postgres_enums() -> None:
    """Commit each new enum label in its own transaction so it can be used immediately."""
    from app.models.user import ExamType, UserRole

    labels = [f"ALTER TYPE userrole ADD VALUE IF NOT EXISTS '{e.value}'" for e in UserRole]
    labels += [f"ALTER TYPE examtype ADD VALUE IF NOT EXISTS '{e.value}'" for e in ExamType]
    for stmt in labels:
        try:
            async with engine.begin() as conn:
                await conn.execute(text(stmt))
        except Exception as exc:
            logger.warning("enum migrate skipped: %s (%s)", stmt, exc)


async def probe_database() -> bool:
    """Live ping. Startup may have failed while Postgres later became reachable."""
    global _db_initialized
    try:
        async with engine.connect() as conn:
            await asyncio.wait_for(conn.execute(text("SELECT 1")), timeout=5)
        _db_initialized = True
        return True
    except Exception as exc:
        logger.warning("Database probe failed for host %r: %s", settings.database_host, exc)
        return False


async def _run_schema_migrations(conn) -> None:
    await conn.run_sync(Base.metadata.create_all)
    await conn.execute(text(
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(40) NULL"
    ))
    try:
        await conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS ix_users_phone ON users (phone)"
        ))
    except Exception:
        pass
    await conn.execute(text(
        "ALTER TABLE cbt_exams ALTER COLUMN created_by DROP NOT NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE cbt_exams ADD COLUMN IF NOT EXISTS paper_kind VARCHAR(32) NOT NULL DEFAULT 'cbt_practice'"
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
        "ALTER TABLE cbt_exams ADD COLUMN IF NOT EXISTS assigned_student_ids JSON NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE cbt_exams ADD COLUMN IF NOT EXISTS notes_url VARCHAR(500) NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE cbt_exams ADD COLUMN IF NOT EXISTS notes_title VARCHAR(255) NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE student_profiles ADD COLUMN IF NOT EXISTS jamb_subjects VARCHAR[] NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE student_profiles ADD COLUMN IF NOT EXISTS ssce_subjects VARCHAR[] NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE student_profiles ADD COLUMN IF NOT EXISTS ssce_exam_type VARCHAR(20) NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE live_classes ADD COLUMN IF NOT EXISTS academic_class VARCHAR(40) NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE live_classes ADD COLUMN IF NOT EXISTS school_id UUID NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE marketplace_products ADD COLUMN IF NOT EXISTS is_free BOOLEAN NOT NULL DEFAULT FALSE"
    ))
    await conn.execute(text(
        "ALTER TABLE teacher_profiles ADD COLUMN IF NOT EXISTS academic_classes VARCHAR[] NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE teacher_profiles ADD COLUMN IF NOT EXISTS school_id UUID NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS school_id UUID NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE school_exam_candidates ADD COLUMN IF NOT EXISTS school_id UUID NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE student_profiles ADD COLUMN IF NOT EXISTS school_student_id VARCHAR(40) NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE school_campuses ADD COLUMN IF NOT EXISTS subscription_active BOOLEAN NOT NULL DEFAULT FALSE"
    ))
    await conn.execute(text(
        "ALTER TABLE school_campuses ADD COLUMN IF NOT EXISTS subscription_plan VARCHAR(80) NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE external_exams ADD COLUMN IF NOT EXISTS allowed_classes JSON NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE external_exam_attempts ADD COLUMN IF NOT EXISTS student_user_id UUID NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE external_exam_attempts ALTER COLUMN candidate_id DROP NOT NULL"
    ))
    try:
        await conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS ix_school_exam_candidates_candidate_id ON school_exam_candidates (candidate_id)"
        ))
    except Exception:
        pass
    await conn.execute(text(
        "ALTER TABLE cbt_exams ADD COLUMN IF NOT EXISTS school_id UUID NULL"
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
        "ALTER TABLE student_entitlements ADD COLUMN IF NOT EXISTS details JSON NULL"
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
        "ALTER TABLE student_profiles ADD COLUMN IF NOT EXISTS community_channel_id UUID NULL"
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
        "ALTER TABLE books ADD COLUMN IF NOT EXISTS category VARCHAR(80) NOT NULL DEFAULT 'Books'"
    ))
    await conn.execute(text(
        "ALTER TABLE books ADD COLUMN IF NOT EXISTS education_level VARCHAR(80) NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE books ADD COLUMN IF NOT EXISTS term VARCHAR(40) NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE books ADD COLUMN IF NOT EXISTS scheme_week INTEGER NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE books ADD COLUMN IF NOT EXISTS scheme_topic VARCHAR(255) NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE books ADD COLUMN IF NOT EXISTS library_target VARCHAR(20) NOT NULL DEFAULT 'student'"
    ))
    await conn.execute(text(
        "ALTER TABLE books ADD COLUMN IF NOT EXISTS is_downloadable BOOLEAN NOT NULL DEFAULT FALSE"
    ))
    await conn.execute(text(
        "ALTER TABLE books ADD COLUMN IF NOT EXISTS allow_copy BOOLEAN NOT NULL DEFAULT FALSE"
    ))
    await conn.execute(text(
        "ALTER TABLE books ADD COLUMN IF NOT EXISTS allow_screenshot BOOLEAN NOT NULL DEFAULT FALSE"
    ))
    await conn.execute(text(
        "ALTER TABLE books ADD COLUMN IF NOT EXISTS allow_print BOOLEAN NOT NULL DEFAULT FALSE"
    ))
    await conn.execute(text(
        "ALTER TABLE payments ADD COLUMN IF NOT EXISTS book_id UUID NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE payments ADD COLUMN IF NOT EXISTS provider VARCHAR(30) NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE payments ADD COLUMN IF NOT EXISTS provider_reference VARCHAR(255) NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE payments ADD COLUMN IF NOT EXISTS provider_transaction_id VARCHAR(255) NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE payments ADD COLUMN IF NOT EXISTS product_type VARCHAR(40) NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE payments ADD COLUMN IF NOT EXISTS product_id VARCHAR(120) NULL"
    ))
    try:
        await conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS ux_payments_provider_reference "
            "ON payments (provider_reference) WHERE provider_reference IS NOT NULL"
        ))
    except Exception:
        pass
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
        "ALTER TABLE student_groups ADD COLUMN IF NOT EXISTS image_url VARCHAR(1000)"
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
    await conn.execute(text(
        """
        CREATE TABLE IF NOT EXISTS vendor_profiles (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID UNIQUE NOT NULL REFERENCES users(id),
            business_name VARCHAR(255) NOT NULL,
            location VARCHAR(255),
            categories TEXT[] DEFAULT '{}',
            is_approved BOOLEAN NOT NULL DEFAULT FALSE
        )
        """
    ))
    await conn.execute(text(
        "ALTER TABLE vendor_profiles ADD COLUMN IF NOT EXISTS address VARCHAR(500) NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE vendor_profiles ADD COLUMN IF NOT EXISTS whatsapp VARCHAR(40) NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE vendor_profiles ADD COLUMN IF NOT EXISTS nin VARCHAR(20) NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE vendor_profiles ADD COLUMN IF NOT EXISTS kyc_completed BOOLEAN NOT NULL DEFAULT FALSE"
    ))
    await conn.execute(text(
        "ALTER TABLE teacher_profiles ADD COLUMN IF NOT EXISTS location VARCHAR(255) NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE teacher_profiles ADD COLUMN IF NOT EXISTS is_approved BOOLEAN NOT NULL DEFAULT FALSE"
    ))
    await conn.execute(text(
        "ALTER TABLE marketplace_products ADD COLUMN IF NOT EXISTS vendor_id UUID NULL"
    ))
    await conn.execute(text(
        "ALTER TABLE marketplace_products ADD COLUMN IF NOT EXISTS approval_status VARCHAR(20) NOT NULL DEFAULT 'approved'"
    ))
    await conn.execute(text(
        "ALTER TABLE marketplace_products ADD COLUMN IF NOT EXISTS source_role VARCHAR(20) NOT NULL DEFAULT 'admin'"
    ))
    await conn.execute(text(
        "ALTER TABLE marketplace_products ADD COLUMN IF NOT EXISTS stock_qty INTEGER NOT NULL DEFAULT 0"
    ))
    await conn.execute(text(
        "ALTER TABLE marketplace_products ADD COLUMN IF NOT EXISTS is_available BOOLEAN NOT NULL DEFAULT TRUE"
    ))
    await conn.execute(text(
        "ALTER TABLE marketplace_products ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE"
    ))
    await conn.execute(text(
        """
        CREATE TABLE IF NOT EXISTS marketplace_cart_items (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL REFERENCES users(id),
            product_id UUID NOT NULL REFERENCES marketplace_products(id),
            quantity INTEGER NOT NULL DEFAULT 1,
            created_at TIMESTAMP DEFAULT NOW()
        )
        """
    ))
    await conn.execute(text(
        """
        CREATE TABLE IF NOT EXISTS marketplace_orders (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL REFERENCES users(id),
            total_amount DOUBLE PRECISION NOT NULL DEFAULT 0,
            currency VARCHAR(10) NOT NULL DEFAULT 'NGN',
            status VARCHAR(30) NOT NULL DEFAULT 'pending_payment',
            delivery_address VARCHAR(500),
            contact_phone VARCHAR(40),
            created_at TIMESTAMP DEFAULT NOW()
        )
        """
    ))
    await conn.execute(text(
        """
        CREATE TABLE IF NOT EXISTS marketplace_order_items (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            order_id UUID NOT NULL REFERENCES marketplace_orders(id),
            product_id UUID NOT NULL REFERENCES marketplace_products(id),
            vendor_id UUID NULL REFERENCES users(id),
            quantity INTEGER NOT NULL DEFAULT 1,
            unit_price DOUBLE PRECISION NOT NULL DEFAULT 0,
            tracking_status VARCHAR(40) NOT NULL DEFAULT 'pending',
            tracking_note VARCHAR(500)
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
        await conn.execute(text(
            "ALTER TABLE marketplace_products ALTER COLUMN image_url TYPE VARCHAR(1000)"
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
    try:
        await conn.execute(text("ALTER TYPE userrole ADD VALUE IF NOT EXISTS 'vendor'"))
    except Exception:
        pass
    try:
        await conn.execute(text("ALTER TYPE userrole ADD VALUE IF NOT EXISTS 'school_admin'"))
    except Exception:
        pass
    try:
        await conn.execute(text(
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS token_version INTEGER NOT NULL DEFAULT 0"
        ))
    except Exception:
        pass
    try:
        await conn.execute(text(
            "ALTER TABLE sil_anticheat_events ADD COLUMN IF NOT EXISTS severity INTEGER NOT NULL DEFAULT 1"
        ))
    except Exception:
        pass
    # Marketplace escrow / vendor payouts
    for stmt in (
        "ALTER TABLE marketplace_order_items ADD COLUMN IF NOT EXISTS platform_fee DOUBLE PRECISION NOT NULL DEFAULT 0",
        "ALTER TABLE marketplace_order_items ADD COLUMN IF NOT EXISTS vendor_net DOUBLE PRECISION NOT NULL DEFAULT 0",
        "ALTER TABLE marketplace_order_items ADD COLUMN IF NOT EXISTS escrow_status VARCHAR(30) NOT NULL DEFAULT 'none'",
        "ALTER TABLE marketplace_order_items ADD COLUMN IF NOT EXISTS buyer_confirmed BOOLEAN NOT NULL DEFAULT FALSE",
        "ALTER TABLE marketplace_order_items ADD COLUMN IF NOT EXISTS buyer_confirmed_at TIMESTAMP NULL",
        """
        CREATE TABLE IF NOT EXISTS vendor_withdrawal_requests (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            vendor_id UUID NOT NULL REFERENCES users(id),
            amount DOUBLE PRECISION NOT NULL,
            bank_name VARCHAR(255) NOT NULL,
            account_number VARCHAR(40) NOT NULL,
            account_name VARCHAR(255) NOT NULL,
            status VARCHAR(30) NOT NULL DEFAULT 'pending',
            admin_note TEXT NULL,
            requested_at TIMESTAMP DEFAULT NOW(),
            processed_at TIMESTAMP NULL,
            processed_by UUID NULL REFERENCES users(id)
        )
        """,
    ):
        try:
            await conn.execute(text(stmt))
        except Exception:
            pass


async def ensure_cbt_coupon_tables() -> None:
    """Make sure CBT coupon tables exist (create_all can miss them on older deploys)."""
    stmts = (
        """
        CREATE TABLE IF NOT EXISTS cbt_coupons (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            code VARCHAR(40) NOT NULL UNIQUE,
            package_id VARCHAR(80) NOT NULL,
            max_uses INTEGER DEFAULT 1,
            used_count INTEGER DEFAULT 0,
            is_active BOOLEAN DEFAULT TRUE,
            note TEXT NULL,
            expires_at TIMESTAMP NULL,
            created_by UUID NULL REFERENCES users(id),
            created_at TIMESTAMP DEFAULT NOW()
        )
        """,
        "CREATE INDEX IF NOT EXISTS ix_cbt_coupons_code ON cbt_coupons (code)",
        "CREATE INDEX IF NOT EXISTS ix_cbt_coupons_package_id ON cbt_coupons (package_id)",
        """
        CREATE TABLE IF NOT EXISTS cbt_coupon_redemptions (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            coupon_id UUID NOT NULL REFERENCES cbt_coupons(id),
            student_id UUID NOT NULL REFERENCES users(id),
            created_at TIMESTAMP DEFAULT NOW()
        )
        """,
        "CREATE INDEX IF NOT EXISTS ix_cbt_coupon_redemptions_coupon_id ON cbt_coupon_redemptions (coupon_id)",
        "CREATE INDEX IF NOT EXISTS ix_cbt_coupon_redemptions_student_id ON cbt_coupon_redemptions (student_id)",
    )
    try:
        async with engine.begin() as conn:
            for stmt in stmts:
                try:
                    await conn.execute(text(stmt))
                except Exception as exc:
                    logger.warning("cbt coupon schema stmt skipped: %s", exc)
    except Exception as exc:
        logger.warning("cbt coupon schema skipped: %s", exc)


async def ensure_videos_table() -> None:
    """Ensure video tutorials table exists for admin publish + student watch."""
    stmts = (
        """
        CREATE TABLE IF NOT EXISTS videos (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            title VARCHAR(255) NOT NULL,
            subject VARCHAR(100) NOT NULL,
            exam_type VARCHAR(20) NULL,
            video_url VARCHAR(500) NOT NULL,
            thumbnail_url VARCHAR(500) NULL,
            duration_seconds INTEGER NULL,
            uploaded_by UUID NULL REFERENCES users(id),
            created_at TIMESTAMP DEFAULT NOW()
        )
        """,
        "CREATE INDEX IF NOT EXISTS ix_videos_subject ON videos (subject)",
        "CREATE INDEX IF NOT EXISTS ix_videos_created_at ON videos (created_at)",
    )
    try:
        async with engine.begin() as conn:
            for stmt in stmts:
                try:
                    await conn.execute(text(stmt))
                except Exception as exc:
                    logger.warning("videos schema stmt skipped: %s", exc)
    except Exception as exc:
        logger.warning("ensure_videos_table failed: %s", exc)


async def initialize_database() -> bool:
    """Create tables, run migrations, and seed. Returns False if DATABASE_URL is invalid."""
    global _db_initialized
    try:
        async with engine.begin() as conn:
            await _run_schema_migrations(conn)
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
            "Database schema migration failed for host %r: %s",
            settings.database_host,
            exc,
        )
    try:
        await ensure_school_campus_schema()
    except Exception as exc:
        logger.warning("ensure_school_campus_schema: %s", exc)
    try:
        await ensure_cbt_coupon_tables()
    except Exception as exc:
        logger.warning("ensure_cbt_coupon_tables: %s", exc)
    try:
        await ensure_videos_table()
    except Exception as exc:
        logger.warning("ensure_videos_table: %s", exc)
    try:
        from app.services.cbt_access import ensure_student_entitlements_schema
        await ensure_student_entitlements_schema()
    except Exception as exc:
        logger.warning("ensure_student_entitlements_schema: %s", exc)
    try:
        from app.services.cbt_engine import ensure_cbt_settings_schema
        await ensure_cbt_settings_schema()
    except Exception as exc:
        logger.warning("ensure_cbt_settings_schema: %s", exc)
    try:
        await ensure_postgres_enums()
        _db_initialized = True
    except Exception as exc:
        logger.error(
            "Database startup failed for host %r: %s",
            settings.database_host,
            exc,
        )
        return False
    try:
        async with AsyncSessionLocal() as db:
            await seed_database(db)
    except Exception as exc:
        logger.error("Database seed failed (login can still work): %s", exc)
    logger.info("Database ready (host=%s)", settings.database_host)
    return True
