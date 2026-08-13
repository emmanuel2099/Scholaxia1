"""
Marketplace — admin posts products; students browse by category and book.
"""

from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import require_student, require_admin, require_vendor
from app.models.marketplace import (
    MarketplaceProduct,
    MarketplaceBooking,
    MarketplaceCartItem,
    MarketplaceOrder,
    MarketplaceOrderItem,
    VendorWithdrawalRequest,
    MARKETPLACE_CATEGORIES,
)
from app.models.user import User, VendorProfile
from app.services.notification_service import send_admins_notification, send_user_notification
from app.services.media_service import upload_file

router = APIRouter(prefix="/marketplace", tags=["Marketplace"])


def _absolute_image_url(url: Optional[str]) -> Optional[str]:
    """Normalize stored image paths so Flutter / desktop can load them."""
    if not url:
        return None
    value = str(url).strip()
    if not value:
        return None
    if value.startswith("//"):
        return f"https:{value}"
    if value.startswith("http://"):
        return "https://" + value[len("http://") :]
    if value.startswith("https://"):
        return value
    # Relative /media path — leave as-is; clients resolve against API base.
    if value.startswith("/"):
        return value
    return value


def _product_dict(p: MarketplaceProduct) -> dict:
    return {
        "id": str(p.id),
        "title": p.title,
        "description": p.description,
        "category": p.category,
        "price": float(p.price or 0),
        "currency": p.currency or "NGN",
        "image_url": _absolute_image_url(p.image_url),
        "is_available": bool(p.is_available),
        "is_active": bool(getattr(p, "is_active", True)),
        "vendor_id": str(p.vendor_id) if p.vendor_id else None,
        "approval_status": p.approval_status or "approved",
        "source_role": p.source_role or "admin",
        "stock_qty": int(p.stock_qty or 0),
        "created_at": p.created_at.isoformat() if p.created_at else None,
    }


def _booking_dict(b: MarketplaceBooking, product: Optional[MarketplaceProduct] = None) -> dict:
    return {
        "id": str(b.id),
        "product_id": str(b.product_id),
        "product_title": product.title if product else None,
        "product_description": product.description if product else None,
        "product_price": float(product.price) if product else None,
        "user_id": str(b.user_id) if b.user_id else None,
        "full_name": b.full_name,
        "whatsapp": b.whatsapp,
        "phone": b.phone,
        "email": b.email,
        "note": b.note,
        "status": b.status,
        "created_at": b.created_at.isoformat() if b.created_at else None,
    }


async def _require_vendor_kyc(db: AsyncSession, user_id) -> VendorProfile:
    result = await db.execute(select(VendorProfile).where(VendorProfile.user_id == user_id))
    profile = result.scalar_one_or_none()
    if not profile:
        raise HTTPException(status_code=400, detail="Vendor profile not found. Complete registration first.")
    if not profile.is_approved:
        raise HTTPException(
            status_code=403,
            detail="Your vendor account is waiting for admin approval.",
        )
    if not profile.kyc_completed or not (profile.nin or "").strip():
        raise HTTPException(
            status_code=403,
            detail="Complete KYC (NIN + address) before posting products.",
        )
    return profile


@router.get("/categories")
async def list_categories():
    labels = {
        "books": "Books",
        "soft_copy": "Soft copy / PDF",
        "software": "Software",
        "educational_materials": "Educational materials",
        "phones": "Phones",
        "gadgets": "Gadgets",
        "flash_drive": "Flash drive",
        "charger": "Charger",
        "projector": "Projector",
        "desktop_computer": "Desktop computer",
        "bags": "Bags",
        "laptops": "Laptops",
        "other": "Other",
    }
    return {
        "categories": [
            {"id": c, "label": labels.get(c, c.title())} for c in MARKETPLACE_CATEGORIES
        ]
    }


# Legacy demo titles — soft-removed so they no longer appear in the shop.
_LEGACY_SAMPLE_TITLES = (
    "Wireless Earbuds Pro",
    "Used HP Laptop 8GB",
    "Campus Hoodie (M)",
    "Samsung A14 (32GB)",
    "JAMB Past Questions Pack",
)


async def _deactivate_legacy_samples(db: AsyncSession) -> None:
    """Hide old seeded sample products (no images / demo stock)."""
    await db.execute(
        update(MarketplaceProduct)
        .where(MarketplaceProduct.title.in_(_LEGACY_SAMPLE_TITLES))
        .where(MarketplaceProduct.is_active == True)  # noqa: E712
        .values(is_active=False, is_available=False)
    )
    await db.flush()


@router.get("/products")
async def list_products(
    category: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
):
    """Public list of active marketplace products (students browse)."""
    await _deactivate_legacy_samples(db)
    q = select(MarketplaceProduct).where(
        MarketplaceProduct.is_active == True,  # noqa: E712
        MarketplaceProduct.is_available == True,  # noqa: E712
        MarketplaceProduct.approval_status == "approved",
    )
    if category:
        cat = category.strip().lower()
        if cat not in MARKETPLACE_CATEGORIES:
            raise HTTPException(status_code=400, detail="Invalid category")
        q = q.where(MarketplaceProduct.category == cat)
    result = await db.execute(q.order_by(MarketplaceProduct.created_at.desc()))
    products = result.scalars().all()
    # Only show listings from admin or from approved vendors.
    approved_vendor_ids = set()
    vendor_ids = {p.vendor_id for p in products if p.vendor_id}
    if vendor_ids:
        rows = (
            await db.execute(
                select(VendorProfile.user_id).where(
                    VendorProfile.user_id.in_(vendor_ids),
                    VendorProfile.is_approved == True,  # noqa: E712
                )
            )
        ).scalars().all()
        approved_vendor_ids = set(rows)
    out = []
    for p in products:
        if p.vendor_id and p.vendor_id not in approved_vendor_ids:
            continue
        out.append(_product_dict(p))
    return out


@router.get("/products/{product_id}")
async def get_product(product_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(MarketplaceProduct).where(
            MarketplaceProduct.id == product_id,
            MarketplaceProduct.is_active == True,  # noqa: E712
        )
    )
    product = result.scalar_one_or_none()
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    return _product_dict(product)


class BookProductRequest(BaseModel):
    full_name: str = Field(..., min_length=2, max_length=255)
    whatsapp: str = Field(..., min_length=7, max_length=40)
    phone: str = Field(..., min_length=7, max_length=40)
    email: EmailStr
    note: Optional[str] = Field(None, max_length=1000)


@router.post("/products/{product_id}/book", status_code=201)
async def book_product(
    product_id: str,
    payload: BookProductRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Student books a product — vendor (and admin) are notified. Payment is arranged in chat."""
    result = await db.execute(
        select(MarketplaceProduct).where(
            MarketplaceProduct.id == product_id,
            MarketplaceProduct.is_active == True,  # noqa: E712
            MarketplaceProduct.is_available == True,  # noqa: E712
        )
    )
    product = result.scalar_one_or_none()
    if not product:
        raise HTTPException(status_code=404, detail="Product not available")

    booking = MarketplaceBooking(
        product_id=product.id,
        user_id=current_user["sub"],
        full_name=payload.full_name.strip(),
        whatsapp=payload.whatsapp.strip(),
        phone=payload.phone.strip(),
        email=str(payload.email).strip().lower(),
        note=(payload.note or "").strip() or None,
        status="pending",
    )
    db.add(booking)
    await db.flush()

    price_label = f"₦{product.price:,.0f}" if product.price else "Price on request"
    notif_body = (
        f"{booking.full_name} wants {product.title} ({price_label}). "
        f"WhatsApp: {booking.whatsapp} · Phone: {booking.phone} · {booking.email}"
    )
    notif_data = {
        "type": "marketplace_booking",
        "booking_id": str(booking.id),
        "product_id": str(product.id),
        "whatsapp": booking.whatsapp,
        "phone": booking.phone,
        "email": booking.email,
    }
    if product.vendor_id:
        await send_user_notification(
            db,
            str(product.vendor_id),
            title=f"New booking: {product.title}",
            body=notif_body,
            notification_type="marketplace_booking",
            data=notif_data,
        )
    await send_admins_notification(
        db,
        title=f"Marketplace booking: {product.title}",
        body=notif_body,
        notification_type="announcement",
        data=notif_data,
    )

    return {
        "message": "Booking submitted. The vendor will review your request and arrange payment in chat.",
        "booking": _booking_dict(booking, product),
    }


@router.get("/bookings/mine")
async def my_bookings(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MarketplaceBooking)
        .where(MarketplaceBooking.user_id == current_user["sub"])
        .order_by(MarketplaceBooking.created_at.desc())
    )
    bookings = result.scalars().all()
    out = []
    for b in bookings:
        p_res = await db.execute(
            select(MarketplaceProduct).where(MarketplaceProduct.id == b.product_id)
        )
        out.append(_booking_dict(b, p_res.scalar_one_or_none()))
    return out


# ── Admin ─────────────────────────────────────────────────────────────────────

class ProductCreate(BaseModel):
    title: str = Field(..., min_length=2, max_length=255)
    description: Optional[str] = None
    category: str = "gadgets"
    price: float = 0
    currency: str = "NGN"
    image_url: Optional[str] = None
    is_available: bool = True
    stock_qty: int = 0


class ProductUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    category: Optional[str] = None
    price: Optional[float] = None
    image_url: Optional[str] = None
    is_available: Optional[bool] = None
    is_active: Optional[bool] = None
    stock_qty: Optional[int] = None


admin_router = APIRouter(prefix="/admin/marketplace", tags=["Admin — Marketplace"])

_MP_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}


@admin_router.post("/upload-image")
async def admin_upload_product_image(
    file: UploadFile = File(...),
    current_user: dict = Depends(require_admin),
):
    """Upload a product photo for the marketplace."""
    content_type = (file.content_type or "").split(";")[0].strip().lower()
    name = (file.filename or "").lower()
    if content_type not in _MP_IMAGE_TYPES and not name.endswith(
        (".jpg", ".jpeg", ".png", ".webp", ".gif")
    ):
        raise HTTPException(status_code=400, detail="Use JPEG, PNG, WebP, or GIF.")
    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="Empty image file.")
    if len(content) > 6 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Image too large (max 6MB).")
    try:
        result = upload_file(content, "marketplace")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Upload failed: {e}")
    image_url = _absolute_image_url(result.get("secure_url") or result.get("url"))
    if not image_url:
        raise HTTPException(status_code=500, detail="Upload succeeded but no image URL returned.")
    return {"image_url": image_url, "secure_url": image_url}


@admin_router.post("/products", status_code=201)
async def admin_create_product(
    payload: ProductCreate,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    cat = (payload.category or "gadgets").strip().lower()
    if cat not in MARKETPLACE_CATEGORIES:
        raise HTTPException(
            status_code=400,
            detail=f"category must be one of {', '.join(MARKETPLACE_CATEGORIES)}",
        )
    image_url = _absolute_image_url(payload.image_url)
    if not image_url:
        raise HTTPException(status_code=400, detail="Product image is required.")
    if not (
        image_url.startswith("https://")
        or image_url.startswith("http://")
        or image_url.startswith("/")
    ):
        raise HTTPException(
            status_code=400,
            detail="image_url must be an http(s) URL or uploaded media path.",
        )
    product = MarketplaceProduct(
        title=payload.title.strip(),
        description=(payload.description or "").strip() or None,
        category=cat,
        price=max(float(payload.price or 0), 0),
        currency=(payload.currency or "NGN").upper(),
        image_url=image_url,
        is_available=payload.is_available,
        stock_qty=max(int(payload.stock_qty or 0), 0),
        approval_status="approved",
        source_role="admin",
        created_by=current_user["sub"],
    )
    db.add(product)
    await db.flush()
    return _product_dict(product)


@admin_router.get("/products")
async def admin_list_products(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    await _deactivate_legacy_samples(db)
    result = await db.execute(
        select(MarketplaceProduct)
        .where(MarketplaceProduct.is_active == True)  # noqa: E712
        .order_by(MarketplaceProduct.created_at.desc())
    )
    return [_product_dict(p) | {"is_active": p.is_active} for p in result.scalars().all()]


@admin_router.patch("/products/{product_id}")
async def admin_update_product(
    product_id: str,
    payload: ProductUpdate,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MarketplaceProduct).where(MarketplaceProduct.id == product_id)
    )
    product = result.scalar_one_or_none()
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    if payload.title is not None:
        product.title = payload.title.strip()
    if payload.description is not None:
        product.description = payload.description.strip() or None
    if payload.category is not None:
        cat = payload.category.strip().lower()
        if cat not in MARKETPLACE_CATEGORIES:
            raise HTTPException(status_code=400, detail="Invalid category")
        product.category = cat
    if payload.price is not None:
        product.price = max(float(payload.price), 0)
    if payload.image_url is not None:
        product.image_url = _absolute_image_url(payload.image_url)
    if payload.is_available is not None:
        product.is_available = payload.is_available
    if payload.is_active is not None:
        product.is_active = payload.is_active
    if payload.stock_qty is not None:
        product.stock_qty = max(int(payload.stock_qty), 0)
    await db.flush()
    return _product_dict(product) | {"is_active": product.is_active}


@admin_router.delete("/products/{product_id}")
async def admin_delete_product(
    product_id: str,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MarketplaceProduct).where(MarketplaceProduct.id == product_id)
    )
    product = result.scalar_one_or_none()
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    product.is_active = False
    product.is_available = False
    await db.flush()
    return {"message": "Product removed"}


@admin_router.get("/bookings")
async def admin_list_bookings(
    status: Optional[str] = Query(None),
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    q = select(MarketplaceBooking).order_by(MarketplaceBooking.created_at.desc())
    if status:
        q = q.where(MarketplaceBooking.status == status.strip().lower())
    result = await db.execute(q.limit(200))
    bookings = result.scalars().all()
    out = []
    for b in bookings:
        p_res = await db.execute(
            select(MarketplaceProduct).where(MarketplaceProduct.id == b.product_id)
        )
        out.append(_booking_dict(b, p_res.scalar_one_or_none()))
    return out


@admin_router.patch("/bookings/{booking_id}/status")
async def admin_update_booking_status(
    booking_id: str,
    status: str = Query(..., description="pending | contacted | closed"),
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    st = status.strip().lower()
    if st not in ("pending", "contacted", "closed"):
        raise HTTPException(status_code=400, detail="Invalid status")
    result = await db.execute(
        select(MarketplaceBooking).where(MarketplaceBooking.id == booking_id)
    )
    booking = result.scalar_one_or_none()
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found")
    booking.status = st
    await db.flush()
    p_res = await db.execute(
        select(MarketplaceProduct).where(MarketplaceProduct.id == booking.product_id)
    )
    return _booking_dict(booking, p_res.scalar_one_or_none())


# ── Vendor self-service marketplace ───────────────────────────────────────────

vendor_router = APIRouter(prefix="/vendor/marketplace", tags=["Vendor — Marketplace"])


@vendor_router.get("/status")
async def vendor_account_status(
    current_user: dict = Depends(require_vendor),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(VendorProfile, User)
        .join(User, User.id == VendorProfile.user_id)
        .where(VendorProfile.user_id == current_user["sub"])
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Vendor profile not found")
    profile, user = row
    return {
        "full_name": user.full_name,
        "email": user.email,
        "phone": user.phone,
        "business_name": profile.business_name,
        "location": profile.location,
        "address": profile.address,
        "whatsapp": profile.whatsapp,
        "is_approved": bool(profile.is_approved),
        "kyc_completed": bool(profile.kyc_completed and (profile.nin or "").strip()),
        "can_list_products": bool(
            profile.is_approved and profile.kyc_completed and (profile.nin or "").strip()
        ),
    }


class VendorKycRequest(BaseModel):
    full_name: str = Field(..., min_length=2, max_length=255)
    location: str = Field(..., min_length=2, max_length=255)
    address: str = Field(..., min_length=5, max_length=500)
    nin: str = Field(..., min_length=11, max_length=11)


@vendor_router.get("/kyc")
async def vendor_get_kyc(
    current_user: dict = Depends(require_vendor),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(VendorProfile, User)
        .join(User, User.id == VendorProfile.user_id)
        .where(VendorProfile.user_id == current_user["sub"])
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Vendor profile not found")
    profile, user = row
    return {
        "full_name": user.full_name,
        "business_name": profile.business_name,
        "location": profile.location,
        "address": profile.address,
        "nin": profile.nin,
        "kyc_completed": bool(profile.kyc_completed and (profile.nin or "").strip()),
        "phone": user.phone,
        "email": user.email,
    }


@vendor_router.post("/kyc")
async def vendor_submit_kyc(
    payload: VendorKycRequest,
    current_user: dict = Depends(require_vendor),
    db: AsyncSession = Depends(get_db),
):
    nin = "".join(ch for ch in payload.nin.strip() if ch.isdigit())
    if len(nin) != 11:
        raise HTTPException(status_code=400, detail="NIN must be 11 digits")
    result = await db.execute(
        select(VendorProfile, User)
        .join(User, User.id == VendorProfile.user_id)
        .where(VendorProfile.user_id == current_user["sub"])
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Vendor profile not found")
    profile, user = row
    user.full_name = payload.full_name.strip()
    profile.location = payload.location.strip()
    profile.address = payload.address.strip()
    profile.nin = nin
    profile.kyc_completed = True
    await db.flush()
    return {
        "message": "KYC saved. You can now post products.",
        "kyc_completed": True,
    }


@vendor_router.get("/bookings")
async def vendor_bookings(
    current_user: dict = Depends(require_vendor),
    db: AsyncSession = Depends(get_db),
):
    """Bookings for this vendor's products — shown on the Requests page."""
    rows = (
        await db.execute(
            select(MarketplaceBooking, MarketplaceProduct)
            .join(MarketplaceProduct, MarketplaceProduct.id == MarketplaceBooking.product_id)
            .where(MarketplaceProduct.vendor_id == current_user["sub"])
            .order_by(MarketplaceBooking.created_at.desc())
        )
    ).all()
    out = []
    for booking, product in rows:
        out.append(
            {
                "kind": "booking",
                "booking_id": str(booking.id),
                "order_item_id": None,
                "order_id": str(booking.id),
                "buyer_name": booking.full_name,
                "buyer_email": booking.email,
                "buyer_whatsapp": booking.whatsapp,
                "buyer_phone": booking.phone,
                "contact_phone": booking.phone,
                "product_title": product.title if product else None,
                "product_description": product.description if product else None,
                "quantity": 1,
                "unit_price": float(product.price or 0) if product else 0,
                "tracking_status": booking.status,
                "tracking_note": booking.note,
                "delivery_address": None,
                "note": booking.note,
                "created_at": booking.created_at.isoformat() if booking.created_at else None,
            }
        )
    return out


@vendor_router.patch("/bookings/{booking_id}/status")
async def vendor_update_booking_status(
    booking_id: str,
    status: str = Query(...),
    current_user: dict = Depends(require_vendor),
    db: AsyncSession = Depends(get_db),
):
    """Approve → running (fulfillment starts). Reject closes the request."""
    allowed = {"pending", "running", "rejected", "closed", "approved"}
    new_status = status.strip().lower()
    if new_status == "approved":
        new_status = "running"
    if new_status not in allowed:
        raise HTTPException(status_code=400, detail="Invalid status")
    result = await db.execute(
        select(MarketplaceBooking, MarketplaceProduct)
        .join(MarketplaceProduct, MarketplaceProduct.id == MarketplaceBooking.product_id)
        .where(
            MarketplaceBooking.id == booking_id,
            MarketplaceProduct.vendor_id == current_user["sub"],
        )
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Booking not found")
    booking, product = row
    booking.status = new_status
    await db.flush()
    if booking.user_id and new_status == "running":
        await send_user_notification(
            db,
            str(booking.user_id),
            title=f"Booking approved: {product.title}",
            body=(
                f"Your request for {product.title} was approved and is now running. "
                "The vendor will contact you to arrange payment in chat."
            ),
            notification_type="marketplace_booking",
            data={
                "type": "marketplace_booking",
                "booking_id": str(booking.id),
                "status": new_status,
            },
        )
    return {
        "message": "Booking updated",
        "booking_id": str(booking.id),
        "status": booking.status,
    }


@vendor_router.post("/upload-image")
async def vendor_upload_product_image(
    file: UploadFile = File(...),
    current_user: dict = Depends(require_vendor),
):
    """Upload a product photo for the vendor marketplace listing."""
    content_type = (file.content_type or "").split(";")[0].strip().lower()
    name = (file.filename or "").lower()
    if content_type not in _MP_IMAGE_TYPES and not name.endswith(
        (".jpg", ".jpeg", ".png", ".webp", ".gif")
    ):
        raise HTTPException(status_code=400, detail="Use JPEG, PNG, WebP, or GIF.")
    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="Empty image file.")
    if len(content) > 6 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Image too large (max 6MB).")
    try:
        result = upload_file(content, "marketplace")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Upload failed: {e}")
    image_url = _absolute_image_url(result.get("secure_url") or result.get("url"))
    if not image_url:
        raise HTTPException(status_code=500, detail="Upload succeeded but no image URL returned.")
    return {"image_url": image_url, "secure_url": image_url}


@vendor_router.post("/products", status_code=201)
async def vendor_create_product(
    payload: ProductCreate,
    current_user: dict = Depends(require_vendor),
    db: AsyncSession = Depends(get_db),
):
    await _require_vendor_kyc(db, current_user["sub"])
    cat = (payload.category or "gadgets").strip().lower()
    if cat not in MARKETPLACE_CATEGORIES:
        raise HTTPException(status_code=400, detail="Invalid category")
    image_url = _absolute_image_url(payload.image_url)
    if not image_url:
        raise HTTPException(status_code=400, detail="Product image is required.")
    product = MarketplaceProduct(
        title=payload.title.strip(),
        description=(payload.description or "").strip() or None,
        category=cat,
        price=max(float(payload.price or 0), 0),
        currency=(payload.currency or "NGN").upper(),
        image_url=image_url,
        is_available=payload.is_available,
        stock_qty=max(int(payload.stock_qty or 0), 0),
        approval_status="approved",
        source_role="vendor",
        vendor_id=current_user["sub"],
        created_by=current_user["sub"],
    )
    db.add(product)
    await db.flush()
    return _product_dict(product)


@vendor_router.get("/products")
async def vendor_list_products(
    current_user: dict = Depends(require_vendor),
    db: AsyncSession = Depends(get_db),
):
    # Hide soft-deleted products so Remove stays gone after refresh.
    result = await db.execute(
        select(MarketplaceProduct)
        .where(
            MarketplaceProduct.vendor_id == current_user["sub"],
            MarketplaceProduct.is_active == True,  # noqa: E712
        )
        .order_by(MarketplaceProduct.created_at.desc())
    )
    return [_product_dict(p) | {"is_active": p.is_active} for p in result.scalars().all()]


@vendor_router.patch("/products/{product_id}")
async def vendor_update_product(
    product_id: str,
    payload: ProductUpdate,
    current_user: dict = Depends(require_vendor),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MarketplaceProduct).where(
            MarketplaceProduct.id == product_id,
            MarketplaceProduct.vendor_id == current_user["sub"],
        )
    )
    product = result.scalar_one_or_none()
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    if payload.title is not None:
        product.title = payload.title.strip()
    if payload.description is not None:
        product.description = payload.description.strip() or None
    if payload.category is not None:
        cat = payload.category.strip().lower()
        if cat not in MARKETPLACE_CATEGORIES:
            raise HTTPException(status_code=400, detail="Invalid category")
        product.category = cat
    if payload.price is not None:
        product.price = max(float(payload.price), 0)
    if payload.image_url is not None:
        product.image_url = _absolute_image_url(payload.image_url)
    if payload.is_available is not None:
        product.is_available = payload.is_available
    if payload.is_active is not None:
        product.is_active = payload.is_active
    if payload.stock_qty is not None:
        product.stock_qty = max(int(payload.stock_qty), 0)
    await db.flush()
    await db.commit()
    await db.refresh(product)
    return _product_dict(product) | {"is_active": product.is_active}


@vendor_router.delete("/products/{product_id}")
async def vendor_delete_product(
    product_id: str,
    current_user: dict = Depends(require_vendor),
    db: AsyncSession = Depends(get_db),
):
    """Soft-delete: product leaves vendor list and public market immediately."""
    result = await db.execute(
        select(MarketplaceProduct).where(
            MarketplaceProduct.id == product_id,
            MarketplaceProduct.vendor_id == current_user["sub"],
        )
    )
    product = result.scalar_one_or_none()
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    product.is_active = False
    product.is_available = False
    product.stock_qty = 0
    await db.flush()
    await db.commit()
    return {"message": "Product removed", "id": str(product.id)}


class CartAddRequest(BaseModel):
    product_id: str
    quantity: int = 1


@router.post("/cart/add")
async def add_to_cart(
    payload: CartAddRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    if payload.quantity <= 0:
        raise HTTPException(status_code=400, detail="Quantity must be at least 1")
    result = await db.execute(
        select(MarketplaceProduct).where(
            MarketplaceProduct.id == payload.product_id,
            MarketplaceProduct.is_active == True,  # noqa: E712
            MarketplaceProduct.is_available == True,  # noqa: E712
            MarketplaceProduct.approval_status == "approved",
        )
    )
    product = result.scalar_one_or_none()
    if not product:
        raise HTTPException(status_code=404, detail="Product not available")
    existing = await db.execute(
        select(MarketplaceCartItem).where(
            MarketplaceCartItem.user_id == current_user["sub"],
            MarketplaceCartItem.product_id == payload.product_id,
        )
    )
    item = existing.scalar_one_or_none()
    if item:
        item.quantity = max(1, int(item.quantity or 1) + int(payload.quantity))
    else:
        db.add(
            MarketplaceCartItem(
                user_id=current_user["sub"],
                product_id=payload.product_id,
                quantity=max(1, int(payload.quantity)),
            )
        )
    await db.flush()
    return {"message": "Added to cart"}


@router.get("/cart")
async def my_cart(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    rows = (
        await db.execute(
            select(MarketplaceCartItem, MarketplaceProduct)
            .join(MarketplaceProduct, MarketplaceProduct.id == MarketplaceCartItem.product_id)
            .where(MarketplaceCartItem.user_id == current_user["sub"])
            .order_by(MarketplaceCartItem.created_at.desc())
        )
    ).all()
    items = []
    total = 0.0
    for cart_item, product in rows:
        line_total = float(product.price or 0) * int(cart_item.quantity or 1)
        total += line_total
        items.append(
            {
                "id": str(cart_item.id),
                "product": _product_dict(product),
                "quantity": int(cart_item.quantity or 1),
                "line_total": line_total,
            }
        )
    return {"items": items, "total_amount": total, "currency": "NGN"}


@router.delete("/cart/{cart_item_id}")
async def remove_cart_item(
    cart_item_id: str,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MarketplaceCartItem).where(
            MarketplaceCartItem.id == cart_item_id,
            MarketplaceCartItem.user_id == current_user["sub"],
        )
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Cart item not found")
    await db.delete(item)
    await db.flush()
    return {"message": "Removed from cart"}


class CheckoutRequest(BaseModel):
    delivery_address: str
    contact_phone: str


@router.post("/checkout")
async def checkout_cart(
    payload: CheckoutRequest,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    rows = (
        await db.execute(
            select(MarketplaceCartItem, MarketplaceProduct)
            .join(MarketplaceProduct, MarketplaceProduct.id == MarketplaceCartItem.product_id)
            .where(MarketplaceCartItem.user_id == current_user["sub"])
        )
    ).all()
    if not rows:
        raise HTTPException(status_code=400, detail="Cart is empty")
    total = 0.0
    order = MarketplaceOrder(
        user_id=current_user["sub"],
        delivery_address=payload.delivery_address.strip(),
        contact_phone=payload.contact_phone.strip(),
        status="pending_payment",
    )
    db.add(order)
    await db.flush()
    for cart_item, product in rows:
        qty = max(1, int(cart_item.quantity or 1))
        unit = float(product.price or 0)
        if unit <= 0:
            raise HTTPException(
                status_code=400,
                detail=f'"{product.title}" has no checkout price. Remove it from cart.',
            )
        total += qty * unit
        db.add(
            MarketplaceOrderItem(
                order_id=order.id,
                product_id=product.id,
                vendor_id=product.vendor_id,
                quantity=qty,
                unit_price=unit,
                tracking_status="pending_payment",
            )
        )
        await db.delete(cart_item)
    order.total_amount = total
    await db.flush()
    return {
        "message": "Checkout created. Complete payment to confirm the order.",
        "order_id": str(order.id),
        "total_amount": total,
        "status": order.status,
        "currency": order.currency or "NGN",
    }


@router.get("/orders/mine")
async def my_orders(
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    orders = (
        await db.execute(
            select(MarketplaceOrder)
            .where(MarketplaceOrder.user_id == current_user["sub"])
            .order_by(MarketplaceOrder.created_at.desc())
        )
    ).scalars().all()
    out = []
    for order in orders:
        item_rows = (
            await db.execute(
                select(MarketplaceOrderItem, MarketplaceProduct)
                .join(MarketplaceProduct, MarketplaceProduct.id == MarketplaceOrderItem.product_id)
                .where(MarketplaceOrderItem.order_id == order.id)
            )
        ).all()
        out.append(
            {
                "id": str(order.id),
                "status": order.status,
                "total_amount": float(order.total_amount or 0),
                "currency": order.currency,
                "delivery_address": order.delivery_address,
                "contact_phone": order.contact_phone,
                "created_at": order.created_at.isoformat() if order.created_at else None,
                "items": [
                    {
                        "id": str(item.id),
                        "order_item_id": str(item.id),
                        "product_id": str(item.product_id),
                        "product_title": product.title if product else None,
                        "quantity": int(item.quantity or 1),
                        "unit_price": float(item.unit_price or 0),
                        "tracking_status": item.tracking_status,
                        "tracking_note": item.tracking_note,
                        "escrow_status": getattr(item, "escrow_status", None) or "none",
                        "buyer_confirmed": bool(getattr(item, "buyer_confirmed", False)),
                        "platform_fee": float(getattr(item, "platform_fee", 0) or 0),
                        "vendor_net": float(getattr(item, "vendor_net", 0) or 0),
                    }
                    for item, product in item_rows
                ],
            }
        )
    return out


class ConfirmDeliveryBody(BaseModel):
    note: Optional[str] = Field(None, max_length=500)


@router.post("/orders/items/{order_item_id}/confirm-delivery")
async def buyer_confirm_delivery(
    order_item_id: str,
    payload: ConfirmDeliveryBody = None,
    current_user: dict = Depends(require_student),
    db: AsyncSession = Depends(get_db),
):
    """Buyer confirms product received OK → escrow becomes withdrawable; admin notified."""
    payload = payload or ConfirmDeliveryBody()
    row = (
        await db.execute(
            select(MarketplaceOrderItem, MarketplaceOrder, MarketplaceProduct)
            .join(MarketplaceOrder, MarketplaceOrder.id == MarketplaceOrderItem.order_id)
            .join(MarketplaceProduct, MarketplaceProduct.id == MarketplaceOrderItem.product_id)
            .where(MarketplaceOrderItem.id == order_item_id)
        )
    ).first()
    if not row:
        raise HTTPException(status_code=404, detail="Order item not found")
    item, order, product = row
    if str(order.user_id) != str(current_user["sub"]):
        raise HTTPException(status_code=403, detail="Not your order")
    if (order.status or "").lower() not in (
        "paid",
        "processing",
        "shipped",
        "delivered",
        "buyer_confirmed",
    ):
        raise HTTPException(status_code=400, detail="Order is not paid yet")
    if item.buyer_confirmed or (item.escrow_status or "") == "available":
        return {
            "message": "Already confirmed",
            "order_item_id": str(item.id),
            "escrow_status": item.escrow_status,
            "buyer_confirmed": True,
        }
    if (item.tracking_status or "").lower() in ("pending_payment", "pending"):
        raise HTTPException(status_code=400, detail="Payment not completed for this item")

    gross = float(item.unit_price or 0) * max(1, int(item.quantity or 1))
    if not float(getattr(item, "vendor_net", 0) or 0):
        fee = round(gross * 0.10)
        item.platform_fee = fee
        item.vendor_net = max(0.0, round(gross - fee, 2))

    item.buyer_confirmed = True
    item.buyer_confirmed_at = datetime.utcnow()
    item.escrow_status = "available"
    item.tracking_status = "buyer_confirmed"
    note = (payload.note or "").strip()
    item.tracking_note = note or "Buyer confirmed product received and OK"
    order.status = "buyer_confirmed"
    await db.flush()

    title = product.title if product else "your product"
    try:
        if item.vendor_id:
            await send_user_notification(
                db,
                user_id=str(item.vendor_id),
                title="Buyer confirmed delivery",
                body=(
                    f'Buyer confirmed "{title}" is OK. '
                    f"₦{float(item.vendor_net or 0):,.0f} is now available to withdraw."
                ),
                notification_type="marketplace_buyer_confirm",
                data={"order_item_id": str(item.id), "order_id": str(order.id)},
            )
        await send_admins_notification(
            db,
            title="Buyer confirmed marketplace delivery",
            body=(
                f'Order item {item.id} ("{title}") confirmed OK. '
                f"Vendor may request payout of ₦{float(item.vendor_net or 0):,.0f}."
            ),
            notification_type="marketplace_buyer_confirm",
            data={
                "order_item_id": str(item.id),
                "order_id": str(order.id),
                "vendor_id": str(item.vendor_id) if item.vendor_id else None,
            },
        )
    except Exception:
        pass

    return {
        "message": "Delivery confirmed. Vendor can now request payout; admin has been notified.",
        "order_item_id": str(item.id),
        "escrow_status": "available",
        "buyer_confirmed": True,
        "vendor_net": float(item.vendor_net or 0),
    }


@vendor_router.get("/orders")
async def vendor_orders(
    current_user: dict = Depends(require_vendor),
    db: AsyncSession = Depends(get_db),
):
    rows = (
        await db.execute(
            select(MarketplaceOrderItem, MarketplaceOrder, MarketplaceProduct, User)
            .join(MarketplaceOrder, MarketplaceOrder.id == MarketplaceOrderItem.order_id)
            .join(MarketplaceProduct, MarketplaceProduct.id == MarketplaceOrderItem.product_id)
            .join(User, User.id == MarketplaceOrder.user_id)
            .where(MarketplaceOrderItem.vendor_id == current_user["sub"])
            .order_by(MarketplaceOrder.created_at.desc())
        )
    ).all()
    return [
        {
            "order_item_id": str(item.id),
            "order_id": str(order.id),
            "buyer_name": buyer.full_name,
            "buyer_email": buyer.email,
            "product_title": product.title if product else None,
            "quantity": int(item.quantity or 1),
            "unit_price": float(item.unit_price or 0),
            "tracking_status": item.tracking_status,
            "tracking_note": item.tracking_note,
            "delivery_address": order.delivery_address,
            "contact_phone": order.contact_phone,
            "created_at": order.created_at.isoformat() if order.created_at else None,
            "escrow_status": getattr(item, "escrow_status", None) or "none",
            "buyer_confirmed": bool(getattr(item, "buyer_confirmed", False)),
            "buyer_confirmed_at": (
                item.buyer_confirmed_at.isoformat()
                if getattr(item, "buyer_confirmed_at", None)
                else None
            ),
            "platform_fee": float(getattr(item, "platform_fee", 0) or 0),
            "vendor_net": float(getattr(item, "vendor_net", 0) or 0),
            "vendor_amount": float(getattr(item, "vendor_net", 0) or 0),
            "payment_status": order.status,
            "status": item.tracking_status or order.status,
        }
        for item, order, product, buyer in rows
    ]


async def _vendor_escrow_totals(db: AsyncSession, vendor_id) -> dict:
    items = (
        await db.execute(
            select(MarketplaceOrderItem).where(MarketplaceOrderItem.vendor_id == vendor_id)
        )
    ).scalars().all()
    held = 0.0
    available = 0.0
    for item in items:
        net = float(getattr(item, "vendor_net", 0) or 0)
        if not net:
            gross = float(item.unit_price or 0) * max(1, int(item.quantity or 1))
            net = max(0.0, round(gross * 0.9, 2))
        status = (getattr(item, "escrow_status", None) or "").lower()
        track = (item.tracking_status or "").lower()
        if status == "withdrawn":
            continue
        if status == "available" or getattr(item, "buyer_confirmed", False):
            available += net
        elif status == "held" or track in (
            "held_escrow",
            "processing",
            "paid",
            "shipped",
            "delivered",
        ):
            if track not in ("pending_payment", "pending", "cancelled"):
                held += net
    pending_rows = (
        await db.execute(
            select(VendorWithdrawalRequest).where(
                VendorWithdrawalRequest.vendor_id == vendor_id,
                VendorWithdrawalRequest.status.in_(["pending", "approved"]),
            )
        )
    ).scalars().all()
    pending = sum(float(w.amount or 0) for w in pending_rows)
    withdrawable = max(0.0, round(available - pending, 2))
    return {
        "held": round(held, 2),
        "available": round(available, 2),
        "pending_withdrawals": round(pending, 2),
        "withdrawable": withdrawable,
        "currency": "NGN",
        "platform_fee_percent": 10,
    }


@vendor_router.get("/escrow")
async def vendor_escrow_balance(
    current_user: dict = Depends(require_vendor),
    db: AsyncSession = Depends(get_db),
):
    return await _vendor_escrow_totals(db, current_user["sub"])


class VendorWithdrawBody(BaseModel):
    amount: float = Field(..., gt=0)
    bank_name: str = Field(..., min_length=2, max_length=255)
    account_number: str = Field(..., min_length=6, max_length=40)
    account_name: str = Field(..., min_length=2, max_length=255)


@vendor_router.post("/withdraw")
async def vendor_request_withdraw(
    payload: VendorWithdrawBody,
    current_user: dict = Depends(require_vendor),
    db: AsyncSession = Depends(get_db),
):
    totals = await _vendor_escrow_totals(db, current_user["sub"])
    if payload.amount > totals["withdrawable"] + 0.01:
        raise HTTPException(
            status_code=400,
            detail=f"Insufficient withdrawable balance. Available: ₦{totals['withdrawable']:,.2f}",
        )
    existing = (
        await db.execute(
            select(VendorWithdrawalRequest).where(
                VendorWithdrawalRequest.vendor_id == current_user["sub"],
                VendorWithdrawalRequest.status == "pending",
            )
        )
    ).scalar_one_or_none()
    if existing:
        raise HTTPException(
            status_code=400,
            detail="You already have a pending withdrawal. Wait for admin to process it.",
        )
    wd = VendorWithdrawalRequest(
        vendor_id=current_user["sub"],
        amount=round(float(payload.amount), 2),
        bank_name=payload.bank_name.strip(),
        account_number=payload.account_number.strip().replace(" ", ""),
        account_name=payload.account_name.strip(),
        status="pending",
    )
    db.add(wd)
    await db.flush()
    try:
        await send_admins_notification(
            db,
            title="Vendor withdrawal request",
            body=(
                f"Vendor requested ₦{wd.amount:,.2f} → {wd.bank_name} "
                f"{wd.account_number} ({wd.account_name})."
            ),
            notification_type="vendor_withdrawal",
            data={"withdrawal_id": str(wd.id), "vendor_id": str(current_user["sub"])},
        )
    except Exception:
        pass
    return {
        "message": "Withdrawal request sent to admin",
        "withdrawal_id": str(wd.id),
        "amount": wd.amount,
        "status": wd.status,
    }


@vendor_router.get("/withdrawals")
async def vendor_list_withdrawals(
    current_user: dict = Depends(require_vendor),
    db: AsyncSession = Depends(get_db),
):
    rows = (
        await db.execute(
            select(VendorWithdrawalRequest)
            .where(VendorWithdrawalRequest.vendor_id == current_user["sub"])
            .order_by(VendorWithdrawalRequest.requested_at.desc())
        )
    ).scalars().all()
    return [
        {
            "id": str(w.id),
            "amount": float(w.amount or 0),
            "bank_name": w.bank_name,
            "account_number": w.account_number,
            "account_name": w.account_name,
            "status": w.status,
            "admin_note": w.admin_note,
            "requested_at": w.requested_at.isoformat() if w.requested_at else None,
            "processed_at": w.processed_at.isoformat() if w.processed_at else None,
        }
        for w in rows
    ]


class AdminVendorWithdrawBody(BaseModel):
    status: str = Field(..., pattern="^(approved|rejected|paid)$")
    admin_note: Optional[str] = None


@admin_router.get("/withdrawals")
async def admin_list_vendor_withdrawals(
    status: Optional[str] = Query(None),
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    q = select(VendorWithdrawalRequest, User).join(
        User, User.id == VendorWithdrawalRequest.vendor_id
    )
    if status:
        q = q.where(VendorWithdrawalRequest.status == status.strip().lower())
    q = q.order_by(VendorWithdrawalRequest.requested_at.desc())
    rows = (await db.execute(q)).all()
    return [
        {
            "id": str(w.id),
            "vendor_id": str(w.vendor_id),
            "vendor_name": user.full_name,
            "vendor_email": user.email,
            "amount": float(w.amount or 0),
            "bank_name": w.bank_name,
            "account_number": w.account_number,
            "account_name": w.account_name,
            "status": w.status,
            "admin_note": w.admin_note,
            "requested_at": w.requested_at.isoformat() if w.requested_at else None,
            "processed_at": w.processed_at.isoformat() if w.processed_at else None,
        }
        for w, user in rows
    ]


@admin_router.patch("/withdrawals/{withdrawal_id}")
async def admin_process_vendor_withdrawal(
    withdrawal_id: str,
    payload: AdminVendorWithdrawBody,
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(VendorWithdrawalRequest).where(VendorWithdrawalRequest.id == withdrawal_id)
    )
    wd = result.scalar_one_or_none()
    if not wd:
        raise HTTPException(status_code=404, detail="Withdrawal not found")
    if (wd.status or "").lower() == "paid":
        raise HTTPException(status_code=400, detail="Already paid")
    new_status = payload.status.strip().lower()
    wd.status = new_status
    wd.admin_note = (payload.admin_note or "").strip() or None
    wd.processed_at = datetime.utcnow()
    wd.processed_by = current_user["sub"]

    if new_status == "paid":
        remaining = float(wd.amount or 0)
        items = (
            await db.execute(
                select(MarketplaceOrderItem)
                .where(
                    MarketplaceOrderItem.vendor_id == wd.vendor_id,
                    MarketplaceOrderItem.escrow_status == "available",
                )
                .order_by(MarketplaceOrderItem.id.asc())
            )
        ).scalars().all()
        for item in items:
            if remaining <= 0:
                break
            net = float(item.vendor_net or 0)
            if net <= 0:
                continue
            item.escrow_status = "withdrawn"
            item.tracking_note = ((item.tracking_note or "") + " · Payout sent by admin").strip(" ·")
            remaining -= net

    await db.flush()
    try:
        msg = {
            "approved": "Your withdrawal was approved and will be paid soon.",
            "rejected": f"Your withdrawal was rejected. {wd.admin_note or ''}",
            "paid": f"₦{float(wd.amount or 0):,.0f} has been sent to your bank account.",
        }.get(new_status, "Withdrawal updated")
        await send_user_notification(
            db,
            user_id=str(wd.vendor_id),
            title="Withdrawal update",
            body=msg,
            notification_type="vendor_withdrawal",
            data={"withdrawal_id": str(wd.id), "status": new_status},
        )
    except Exception:
        pass
    return {"message": "Withdrawal updated", "withdrawal_id": str(wd.id), "status": wd.status}


@vendor_router.patch("/orders/{order_item_id}/tracking")
async def vendor_update_tracking(
    order_item_id: str,
    tracking_status: str = Query(...),
    tracking_note: Optional[str] = Query(None),
    current_user: dict = Depends(require_vendor),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MarketplaceOrderItem).where(
            MarketplaceOrderItem.id == order_item_id,
            MarketplaceOrderItem.vendor_id == current_user["sub"],
        )
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Order item not found")
    item.tracking_status = tracking_status.strip().lower()
    item.tracking_note = (tracking_note or "").strip() or None
    await db.flush()
    return {"message": "Tracking updated", "order_item_id": order_item_id, "tracking_status": item.tracking_status}


@vendor_router.delete("/orders/{order_item_id}")
async def vendor_delete_order_item(
    order_item_id: str,
    current_user: dict = Depends(require_vendor),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MarketplaceOrderItem).where(
            MarketplaceOrderItem.id == order_item_id,
            MarketplaceOrderItem.vendor_id == current_user["sub"],
        )
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Order item not found")
    order_id = item.order_id
    await db.delete(item)
    await db.flush()
    remaining = (
        await db.execute(
            select(MarketplaceOrderItem).where(MarketplaceOrderItem.order_id == order_id)
        )
    ).scalars().all()
    if not remaining:
        order_res = await db.execute(select(MarketplaceOrder).where(MarketplaceOrder.id == order_id))
        order = order_res.scalar_one_or_none()
        if order:
            await db.delete(order)
            await db.flush()
    return {"message": "Order deleted", "order_item_id": order_item_id}
