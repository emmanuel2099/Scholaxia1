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
    MARKETPLACE_CATEGORIES,
)
from app.models.user import User
from app.services.notification_service import send_admins_notification
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


@vendor_router.post("/products", status_code=201)
async def vendor_create_product(
    payload: ProductCreate,
    current_user: dict = Depends(require_vendor),
    db: AsyncSession = Depends(get_db),
):
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
    result = await db.execute(
        select(MarketplaceProduct)
        .where(MarketplaceProduct.vendor_id == current_user["sub"])
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
    return _product_dict(product) | {"is_active": product.is_active}


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
        status="processing",
    )
    db.add(order)
    await db.flush()
    for cart_item, product in rows:
        qty = max(1, int(cart_item.quantity or 1))
        unit = float(product.price or 0)
        total += qty * unit
        db.add(
            MarketplaceOrderItem(
                order_id=order.id,
                product_id=product.id,
                vendor_id=product.vendor_id,
                quantity=qty,
                unit_price=unit,
                tracking_status="processing",
            )
        )
        await db.delete(cart_item)
    order.total_amount = total
    await db.flush()
    return {"message": "Checkout created", "order_id": str(order.id), "total_amount": total, "status": order.status}


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
                        "product_id": str(item.product_id),
                        "product_title": product.title if product else None,
                        "quantity": int(item.quantity or 1),
                        "unit_price": float(item.unit_price or 0),
                        "tracking_status": item.tracking_status,
                        "tracking_note": item.tracking_note,
                    }
                    for item, product in item_rows
                ],
            }
        )
    return out


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
        }
        for item, order, product, buyer in rows
    ]


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
