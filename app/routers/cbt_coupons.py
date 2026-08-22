from datetime import timedelta
import re
import secrets
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.cbt_packages import get_cbt_package, all_cbt_packages_dict
from app.core.database import get_db
from app.core.datetime_utils import naive_utc_now
from app.core.deps import require_admin, require_student_or_kind
from app.models.cbt_coupon import CbtCoupon, CbtCouponRedemption
from app.services.cbt_access import grant_cbt_package

router = APIRouter(tags=["CBT coupons"])


def _new_code() -> str:
    return "SX-" + secrets.token_hex(4).upper()


def _normalize_code(raw: str) -> str:
    """Strip spaces and normalize to uppercase SX-XXXX style."""
    code = re.sub(r"\s+", "", (raw or "").strip().upper())
    return code.replace("–", "-").replace("—", "-")


def _as_uuid(value) -> uuid.UUID:
    if isinstance(value, uuid.UUID):
        return value
    try:
        return uuid.UUID(str(value))
    except (TypeError, ValueError) as exc:
        raise HTTPException(status_code=400, detail="Invalid account id") from exc


def _coupon_dict(row: CbtCoupon) -> dict:
    return {
        "id": str(row.id),
        "code": row.code,
        "package_id": row.package_id,
        "max_uses": row.max_uses,
        "used_count": row.used_count,
        "is_active": row.is_active,
        "note": row.note,
        "expires_at": row.expires_at.isoformat() if row.expires_at else None,
        "created_at": row.created_at.isoformat() if row.created_at else None,
    }


class GenerateCouponRequest(BaseModel):
    package_id: str
    count: int = Field(1, ge=1, le=50)
    max_uses: int = Field(1, ge=1, le=10000)
    note: Optional[str] = None
    days_valid: Optional[int] = Field(None, ge=1, le=730)


class RedeemCouponRequest(BaseModel):
    code: str = Field(..., min_length=4, max_length=40)


@router.get("/admin/cbt-coupons")
async def list_coupons(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    rows = (
        await db.execute(select(CbtCoupon).order_by(CbtCoupon.created_at.desc()).limit(200))
    ).scalars().all()
    return {"coupons": [_coupon_dict(r) for r in rows], "packages": all_cbt_packages_dict()}


@router.post("/admin/cbt-coupons", status_code=201)
async def generate_coupons(
    payload: GenerateCouponRequest,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    if not get_cbt_package(payload.package_id):
        raise HTTPException(status_code=400, detail="Unknown CBT package")
    expires = None
    if payload.days_valid:
        expires = naive_utc_now() + timedelta(days=payload.days_valid)
    created_by = None
    try:
        created_by = _as_uuid(current_user["sub"])
    except HTTPException:
        created_by = None
    created = []
    for _ in range(payload.count):
        row = CbtCoupon(
            code=_new_code(),
            package_id=payload.package_id.strip().lower(),
            max_uses=payload.max_uses,
            note=payload.note,
            expires_at=expires,
            created_by=created_by,
        )
        db.add(row)
        await db.flush()
        created.append(_coupon_dict(row))
    return {"coupons": created}


@router.post("/admin/cbt-coupons/{coupon_id}/deactivate")
async def deactivate_coupon(
    coupon_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    row = (await db.execute(select(CbtCoupon).where(CbtCoupon.id == coupon_id))).scalar_one_or_none()
    if not row:
        raise HTTPException(status_code=404, detail="Coupon not found")
    row.is_active = False
    await db.flush()
    return _coupon_dict(row)


@router.post("/cbt/coupons/redeem")
async def redeem_coupon(
    payload: RedeemCouponRequest,
    current_user: dict = Depends(require_student_or_kind),
    db: AsyncSession = Depends(get_db),
):
    code = _normalize_code(payload.code)
    if len(code) < 4:
        raise HTTPException(status_code=400, detail="Enter a valid coupon code")

    row = (
        await db.execute(
            select(CbtCoupon).where(func.upper(func.trim(CbtCoupon.code)) == code)
        )
    ).scalar_one_or_none()
    if not row:
        compact = code.replace("-", "")
        rows = (await db.execute(select(CbtCoupon).where(CbtCoupon.is_active.is_(True)))).scalars().all()
        for candidate in rows:
            if _normalize_code(candidate.code).replace("-", "") == compact:
                row = candidate
                break
    if not row or not row.is_active:
        raise HTTPException(status_code=400, detail="Invalid coupon code")
    now = naive_utc_now()
    if row.expires_at and row.expires_at < now:
        raise HTTPException(status_code=400, detail="This coupon has expired")
    if int(row.used_count or 0) >= int(row.max_uses or 1):
        raise HTTPException(status_code=400, detail="This coupon has already been used up")

    student_id = _as_uuid(current_user["sub"])
    already = (
        await db.execute(
            select(CbtCouponRedemption).where(
                CbtCouponRedemption.coupon_id == row.id,
                CbtCouponRedemption.student_id == student_id,
            )
        )
    ).scalar_one_or_none()
    if already:
        try:
            await grant_cbt_package(db, str(student_id), row.package_id)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        await db.flush()
        return {
            "ok": True,
            "package_id": row.package_id,
            "message": "Coupon already applied. CBT access refreshed.",
        }

    try:
        await grant_cbt_package(db, str(student_id), row.package_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    db.add(CbtCouponRedemption(coupon_id=row.id, student_id=student_id))
    row.used_count = int(row.used_count or 0) + 1
    await db.flush()
    return {
        "ok": True,
        "package_id": row.package_id,
        "message": "CBT access unlocked with coupon.",
    }
