"""
Marketplace — admin posts products; students browse by category and book.
"""

from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import require_student, require_admin, get_current_user
from app.models.marketplace import MarketplaceProduct, MarketplaceBooking, MARKETPLACE_CATEGORIES
from app.models.user import User
from app.services.notification_service import send_admins_notification

router = APIRouter(prefix="/marketplace", tags=["Marketplace"])


def _product_dict(p: MarketplaceProduct) -> dict:
    return {
        "id": str(p.id),
        "title": p.title,
        "description": p.description,
        "category": p.category,
        "price": float(p.price or 0),
        "currency": p.currency or "NGN",
        "image_url": p.image_url,
        "is_available": bool(p.is_available),
        "created_at": p.created_at.isoformat() if p.created_at else None,
    }


def _booking_dict(b: MarketplaceBooking, product: Optional[MarketplaceProduct] = None) -> dict:
    return {
        "id": str(b.id),
        "product_id": str(b.product_id),
        "product_title": product.title if product else None,
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


@router.get("/categories")
async def list_categories():
    labels = {
        "gadgets": "Gadgets",
        "laptops": "Laptops",
        "clothes": "Clothes",
        "phones": "Phones",
        "books": "Books",
        "other": "Other",
    }
    return {
        "categories": [
            {"id": c, "label": labels.get(c, c.title())} for c in MARKETPLACE_CATEGORIES
        ]
    }


_SAMPLE_PRODUCTS = [
    {
        "title": "Wireless Earbuds Pro",
        "description": "Bluetooth earbuds with case — great for lectures. Tap Book and Scholaxia will chat with you.",
        "category": "gadgets",
        "price": 18500,
    },
    {
        "title": "Used HP Laptop 8GB",
        "description": "Reliable student laptop for CBT practice and Zoom classes.",
        "category": "laptops",
        "price": 175000,
    },
    {
        "title": "Campus Hoodie (M)",
        "description": "Soft cotton hoodie — Scholaxia purple. Limited stock for testing.",
        "category": "clothes",
        "price": 12000,
    },
    {
        "title": "Samsung A14 (32GB)",
        "description": "Clean condition phone for classes and community chat.",
        "category": "phones",
        "price": 95000,
    },
    {
        "title": "JAMB Past Questions Pack",
        "description": "Printed past questions set for practice at home.",
        "category": "books",
        "price": 3500,
    },
]


async def _ensure_sample_products(db: AsyncSession) -> None:
    """Seed sample sellable items when the marketplace is empty (for testing)."""
    count_res = await db.execute(select(MarketplaceProduct.id).limit(1))
    if count_res.scalar_one_or_none() is not None:
        return
    for item in _SAMPLE_PRODUCTS:
        db.add(
            MarketplaceProduct(
                title=item["title"],
                description=item["description"],
                category=item["category"],
                price=float(item["price"]),
                currency="NGN",
                is_available=True,
                is_active=True,
            )
        )
    await db.flush()


@router.get("/products")
async def list_products(
    category: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
):
    """Public list of active marketplace products (students browse)."""
    await _ensure_sample_products(db)
    q = select(MarketplaceProduct).where(
        MarketplaceProduct.is_active == True,  # noqa: E712
        MarketplaceProduct.is_available == True,  # noqa: E712
    )
    if category:
        cat = category.strip().lower()
        if cat not in MARKETPLACE_CATEGORIES:
            raise HTTPException(status_code=400, detail="Invalid category")
        q = q.where(MarketplaceProduct.category == cat)
    result = await db.execute(q.order_by(MarketplaceProduct.created_at.desc()))
    return [_product_dict(p) for p in result.scalars().all()]


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
    """Student books a product — admin is notified to chat/follow up."""
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
    await send_admins_notification(
        db,
        title=f"Marketplace booking: {product.title}",
        body=(
            f"{booking.full_name} wants {product.title} ({price_label}). "
            f"WhatsApp: {booking.whatsapp} · Phone: {booking.phone} · {booking.email}"
        ),
        notification_type="announcement",
        data={
            "type": "marketplace_booking",
            "booking_id": str(booking.id),
            "product_id": str(product.id),
            "whatsapp": booking.whatsapp,
            "phone": booking.phone,
            "email": booking.email,
        },
    )

    return {
        "message": "Booking submitted. Scholaxia will contact you on WhatsApp / phone.",
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


class ProductUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    category: Optional[str] = None
    price: Optional[float] = None
    image_url: Optional[str] = None
    is_available: Optional[bool] = None
    is_active: Optional[bool] = None


admin_router = APIRouter(prefix="/admin/marketplace", tags=["Admin — Marketplace"])


@admin_router.post("/seed-samples", status_code=201)
async def admin_seed_sample_products(
    current_user: dict = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Post sample sellable products for testing (admin only). Skips titles that already exist."""
    created = []
    for item in _SAMPLE_PRODUCTS:
        dup = await db.execute(
            select(MarketplaceProduct).where(MarketplaceProduct.title == item["title"])
        )
        if dup.scalar_one_or_none() is not None:
            continue
        product = MarketplaceProduct(
            title=item["title"],
            description=item["description"],
            category=item["category"],
            price=float(item["price"]),
            currency="NGN",
            is_available=True,
            is_active=True,
            created_by=current_user["sub"],
        )
        db.add(product)
        await db.flush()
        created.append(_product_dict(product))

    return {
        "message": f"Added {len(created)} sample product(s)."
        if created
        else "Sample products already exist.",
        "added": len(created),
        "products": created,
    }


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
    product = MarketplaceProduct(
        title=payload.title.strip(),
        description=(payload.description or "").strip() or None,
        category=cat,
        price=max(float(payload.price or 0), 0),
        currency=(payload.currency or "NGN").upper(),
        image_url=(payload.image_url or "").strip() or None,
        is_available=payload.is_available,
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
    result = await db.execute(
        select(MarketplaceProduct).order_by(MarketplaceProduct.created_at.desc())
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
        product.image_url = payload.image_url.strip() or None
    if payload.is_available is not None:
        product.is_available = payload.is_available
    if payload.is_active is not None:
        product.is_active = payload.is_active
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
