from uuid import UUID

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import decode_token
from app.models.user import User, TeacherProfile

bearer_scheme = HTTPBearer()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
):
    token = credentials.credentials
    payload = decode_token(token)
    if not payload or payload.get("type") != "access":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    sub = payload.get("sub")
    if not sub:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    if "sv" not in payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session expired. Please sign in again.",
        )

    try:
        user_id = UUID(str(sub))
    except ValueError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    if int(user.token_version or 0) != int(payload.get("sv") or -1):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Logged in on another device. Please sign in again.",
        )

    payload["sub"] = str(user.id)
    payload["_db"] = db
    return payload


async def require_student(current_user: dict = Depends(get_current_user)):
    if current_user.get("role") != "student":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Students only")
    return current_user


async def require_student_or_kind(current_user: dict = Depends(get_current_user)):
    if current_user.get("role") not in ("student", "kind"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Students or kid learners only",
        )
    return current_user


async def require_kind(current_user: dict = Depends(get_current_user)):
    if current_user.get("role") != "kind":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Kind learners only")
    return current_user


async def require_teacher(current_user: dict = Depends(get_current_user)):
    if current_user.get("role") != "teacher":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Teachers only")
    db = current_user.get("_db")
    if db is None:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Database context missing")
    res = await db.execute(select(TeacherProfile).where(TeacherProfile.user_id == current_user["sub"]))
    profile = res.scalar_one_or_none()
    if not profile:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Teacher profile not found")
    if not profile.is_approved:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Teacher account pending admin approval")
    return current_user


async def require_teacher_or_admin(current_user: dict = Depends(get_current_user)):
    if current_user.get("role") not in ("teacher", "admin"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Teachers or admins only",
        )
    if current_user.get("role") == "teacher":
        db = current_user.get("_db")
        if db is None:
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Database context missing")
        res = await db.execute(select(TeacherProfile).where(TeacherProfile.user_id == current_user["sub"]))
        profile = res.scalar_one_or_none()
        if not profile or not profile.is_approved:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Teacher account pending admin approval")
    return current_user


async def require_vendor(current_user: dict = Depends(get_current_user)):
    if current_user.get("role") != "vendor":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Vendors only")
    return current_user


async def require_vendor_or_admin(current_user: dict = Depends(get_current_user)):
    if current_user.get("role") not in ("vendor", "admin"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Vendors or admins only")
    return current_user


async def require_admin(current_user: dict = Depends(get_current_user)):
    if current_user.get("role") != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admins only")
    return current_user


async def require_developer(current_user: dict = Depends(get_current_user)):
    if current_user.get("role") not in ("developer", "admin"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Developer account required")
    return current_user
