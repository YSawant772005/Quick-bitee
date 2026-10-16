"""Promotional banners and offers.

QuickBitee stores no offers/promotions of its own, so this module serves
explicitly-labelled *demo* promotions — and only outside production (see
``settings.demo_promotions_enabled``). Nothing here ever claims a discount
that checkout does not apply: every banner and offer carries ``is_demo`` so
the client can badge it ("Demo offer") and print the disclosure text.

The catalogue deliberately links to real, browsable content (a restaurant,
a cuisine/category listing, the offers page) instead of dead ends.
"""

from __future__ import annotations

from typing import Any

from app.core.config import settings

#: Accent hex colours used by the web carousel (brand-compatible).
TEAL = "#0F766E"
BLUE = "#1D4ED8"
AMBER = "#B45309"
_ROSE = "#BE123C"
_PURPLE = "#6D28D9"

#: Shown verbatim next to every demo promotion.
DEMO_BADGE = "Demo offer"
DEMO_DISCLOSURE = (
    "Demo promotion - it links to real browsing pages but applies no "
    "discount at checkout."
)


def _banner(
    slug: str,
    title: str,
    subtitle: str,
    image: str,
    accent: str,
    cta_label: str,
    cta: dict[str, Any],
    target: str,
) -> dict[str, Any]:
    return {
        "id": slug,
        "title": title,
        "subtitle": subtitle,
        "image_url": image,
        "accent": accent,
        "cta_label": cta_label,
        "cta": cta,
        "target": target,
        "badge": DEMO_BADGE,
        "is_demo": True,
    }


def demo_banners() -> list[dict[str, Any]]:
    """Homepage carousel slides (development/demo only)."""
    if not settings.demo_promotions_enabled:
        return []
    return [
        _banner(
            slug="welcome",
            title="QuickBitee, delivered fast",
            subtitle="Hot meals from local kitchens, at your door in minutes.",
            image="/static/catalog/rest-biryani.jpg",
            accent=TEAL,
            cta_label="Browse restaurants",
            cta={"type": "restaurant_list"},
            target="/explore",
        ),
        _banner(
            slug="burgers",
            title="Stack it high",
            subtitle="Juicy burgers and sides from kitchens near you.",
            image="/static/catalog/rest-burger.jpg",
            accent=AMBER,
            cta_label="See burger dishes",
            cta={"type": "query", "query": "burger", "view": "dishes"},
            target="/explore?q=burger&view=dishes",
        ),
        _banner(
            slug="vegetarian",
            title="Fresh vegetarian picks",
            subtitle="Meat-free favourites across every cuisine.",
            image="/static/catalog/rest-punjabi.jpg",
            accent=TEAL,
            cta_label="Explore vegetarian",
            cta={
                "type": "category",
                "category": "vegetarian",
                "food_type": "veg",
                "view": "dishes",
            },
            target="/explore?category=vegetarian&food_type=veg&view=dishes",
        ),
        _banner(
            slug="asian",
            title="Asian flavours, one tap away",
            subtitle="Noodles, curries and stir-fries from kitchens that cook them.",
            image="/static/catalog/rest-asian.jpg",
            accent=BLUE,
            cta_label="Browse noodle dishes",
            cta={"type": "query", "query": "noodles", "view": "dishes"},
            target="/explore?q=noodles&view=dishes",
        ),
        _banner(
            slug="fast",
            title="Under 30 minutes",
            subtitle="Quick bites, sorted by the fastest kitchens on QuickBitee.",
            image="/static/catalog/rest-biryani.jpg",
            accent=_ROSE,
            cta_label="Sort restaurants by ETA",
            cta={"type": "restaurant_list", "sort": "eta"},
            target="/explore?sort=eta",
        ),
        _banner(
            slug="top-rated",
            title="Loved by customers",
            subtitle="Popular dishes, ranked by real order counts.",
            image="/static/catalog/rest-burger.jpg",
            accent=_PURPLE,
            cta_label="See popular dishes",
            cta={"type": "restaurant_list", "sort": "popular", "view": "dishes"},
            target="/explore?sort=popular&view=dishes",
        ),
    ]


def demo_offers() -> list[dict[str, Any]]:
    """Entries for the offers page (development/demo only)."""
    if not settings.demo_promotions_enabled:
        return []
    common = {
        "badge": DEMO_BADGE,
        "is_demo": True,
        "disclosure": DEMO_DISCLOSURE,
    }
    return [
        {
            **common,
            "id": "free-delivery",
            "title": "Free delivery week",
            "description": (
                "Demo offer with no delivery fee advertised. Real delivery "
                "charges, if any, are calculated at checkout."
            ),
            "kind": "delivery",
            "image_url": "/static/catalog/rest-punjabi.jpg",
            "accent": TEAL,
            "cta_label": "Browse restaurants",
            "cta": {"type": "restaurant_list"},
            "target": "/explore",
        },
        {
            **common,
            "id": "new-kitchens",
            "title": "Discover new kitchens",
            "description": (
                "Demo spotlight that opens the restaurant list sorted by "
                "rating. No discount is applied at checkout."
            ),
            "kind": "spotlight",
            "image_url": "/static/catalog/rest-asian.jpg",
            "accent": BLUE,
            "cta_label": "Browse by rating",
            "cta": {"type": "restaurant_list", "sort": "rating"},
            "target": "/explore?sort=rating",
        },
        {
            **common,
            "id": "veg",
            "title": "Vegetarian favourites",
            "description": (
                "Demo offer page for vegetarian dishes. "
                "No discount is applied at checkout."
            ),
            "kind": "category",
            "image_url": "/static/catalog/rest-burger.jpg",
            "accent": AMBER,
            "cta_label": "Explore vegetarian",
            "cta": {
                "type": "category",
                "category": "vegetarian",
                "food_type": "veg",
                "view": "dishes",
            },
            "target": "/explore?category=vegetarian&food_type=veg&view=dishes",
        },
    ]


def offers_for_restaurant(_restaurant_id: str) -> list[dict[str, Any]]:
    """Demo offers surfaced on a restaurant detail page."""
    if not settings.demo_promotions_enabled:
        return []
    return [
        {
            "id": "free-delivery",
            "title": "Free delivery week",
            "badge": DEMO_BADGE,
            "is_demo": True,
            "disclosure": DEMO_DISCLOSURE,
            "cta": {"type": "offers"},
            "target": "/offers",
        },
        {
            "id": "new-kitchens",
            "title": "Discover new kitchens",
            "badge": DEMO_BADGE,
            "is_demo": True,
            "disclosure": DEMO_DISCLOSURE,
            "cta": {"type": "offers"},
            "target": "/offers",
        },
    ]
