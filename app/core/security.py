import bcrypt
from datetime import datetime, timedelta
from typing import Optional, Union
from jose import JWTError, jwt
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings


def hash_password(password: str) -> str:
    raw = (password or "").encode("utf-8")[:72]
    return bcrypt.hashpw(raw, bcrypt.gensalt()).decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    if not plain or not hashed:
        return False
    try:
        raw = plain.encode("utf-8")[:72]
        stored = hashed.encode("utf-8") if isinstance(hashed, str) else hashed
        return bcrypt.checkpw(raw, stored)
    except Exception:
        return False


def _role_str(role: Union[str, object]) -> str:
    if role is None:
        return ""
    if isinstance(role, str):
        s = role
    else:
        s = str(getattr(role, "value", role))
    s = s.strip().lower()
    if s.startswith("userrole."):
        s = s[len("userrole.") :]
    return s


def create_access_token(
    subject: str,
    role: Union[str, object],
    expires_delta: Optional[timedelta] = None,
    session_version: int = 0,
) -> str:
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES))
    payload = {
        "sub": subject,
        "role": _role_str(role),
        "exp": expire,
        "type": "access",
        "sv": int(session_version or 0),
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def create_refresh_token(subject: str, session_version: int = 0) -> str:
    expire = datetime.utcnow() + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    payload = {
        "sub": subject,
        "exp": expire,
        "type": "refresh",
        "sv": int(session_version or 0),
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    except JWTError:
        return {}


async def issue_auth_tokens(db: AsyncSession, user) -> tuple[str, str]:
    """Invalidate other sessions by bumping token_version, then mint new JWTs."""
    current = int(getattr(user, "token_version", 0) or 0)
    sv = current
    if hasattr(user, "_sa_instance_state"):
        try:
            user.token_version = current + 1
            await db.flush()
            sv = int(user.token_version or 0)
        except Exception:
            sv = current
    return (
        create_access_token(str(user.id), getattr(user, "role", "student"), session_version=sv),
        create_refresh_token(str(user.id), session_version=sv),
    )
