"""Scholaxia annual CBT practice packages (server-side price catalog).

Prices are authoritative here — clients must never send amounts.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class CbtPackage:
    id: str
    name: str
    price: float  # NGN
    duration_days: int
    boards: tuple[str, ...]
    audience: str  # student | kind
    features: tuple[str, ...]


CBT_PACKAGES: tuple[CbtPackage, ...] = (
    CbtPackage(
        id="jamb",
        name="JAMB CBT",
        price=3000,
        duration_days=365,
        boards=("JAMB",),
        audience="student",
        features=("Full JAMB CBT package (all selected subjects)", "Randomized questions from bank", "Sia AI with active package"),
    ),
    CbtPackage(
        id="waec",
        name="WAEC CBT",
        price=3000,
        duration_days=365,
        boards=("WAEC",),
        audience="student",
        features=("WAEC subject practice from your registered subjects", "Randomized questions", "Sia AI with active package"),
    ),
    CbtPackage(
        id="neco",
        name="NECO CBT",
        price=2500,
        duration_days=365,
        boards=("NECO",),
        audience="student",
        features=("NECO subject practice from your registered subjects", "Randomized questions", "Sia AI with active package"),
    ),
    CbtPackage(
        id="all",
        name="ALL (JAMB + WAEC + NECO)",
        price=7000,
        duration_days=365,
        boards=("JAMB", "WAEC", "NECO"),
        audience="student",
        features=("Unlock every senior CBT exam type", "Randomized questions", "Sia AI with active package"),
    ),
    # Keep legacy combo ids so old coupons/payments still resolve
    CbtPackage(
        id="jamb_waec",
        name="JAMB & WAEC",
        price=5000,
        duration_days=365,
        boards=("JAMB", "WAEC"),
        audience="student",
        features=("JAMB + WAEC CBT", "Sia AI with active package"),
    ),
    CbtPackage(
        id="jamb_waec_neco",
        name="JAMB, WAEC & NECO",
        price=7000,
        duration_days=365,
        boards=("JAMB", "WAEC", "NECO"),
        audience="student",
        features=("All senior exam boards", "Sia AI with active package"),
    ),
    CbtPackage(
        id="junior_waec",
        name="Junior WAEC",
        price=3000,
        duration_days=365,
        boards=("JUNIOR_WAEC",),
        audience="student",
        features=("Junior WAEC / BECE practice", "Sia AI with active package"),
    ),
    CbtPackage(
        id="common_entrance",
        name="Common Entrance",
        price=2000,
        duration_days=365,
        boards=("COMMON_ENTRANCE",),
        audience="kind",
        features=("Primary 6 Common Entrance practice", "Kid-safe CBT access"),
    ),
)

_PACKAGE_MAP = {p.id: p for p in CBT_PACKAGES}


def get_cbt_package(package_id: str) -> Optional[CbtPackage]:
    return _PACKAGE_MAP.get((package_id or "").strip().lower())


def cbt_package_to_dict(package: CbtPackage) -> dict:
    return {
        "id": package.id,
        "name": package.name,
        "price": package.price,
        "currency": "NGN",
        "duration_days": package.duration_days,
        "boards": list(package.boards),
        "audience": package.audience,
        "billing": "annual",
        "includes_sia_ai": True,
        "features": list(package.features),
    }


def all_cbt_packages_dict() -> list[dict]:
    return [cbt_package_to_dict(p) for p in CBT_PACKAGES]


def all_cbt_packages() -> list[dict]:
  return all_cbt_packages_dict()
