import bcrypt
from datetime import datetime, timedelta
from typing import Optional, Union
from jose import JWTError, jwt
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    return bcrypt.checkpw(plain.encode("utf-8"), hashed.encode("utf-8"))


def _role_str(role: Union[str, object]) -> str:
    if isinstance(role, str):
        return role
    return str(getattr(role, "value", role))


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
    user.token_version = int(getattr(user, "token_version", 0) or 0) + 1
    await db.flush()
    sv = int(user.token_version or 0)
    return (
        create_access_token(str(user.id), user.role, session_version=sv),
        create_refresh_token(str(user.id), session_version=sv),
    )
