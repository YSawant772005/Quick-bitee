"""Restaurant detail pages, menu filters and promotions.

These tests exercise the *real* filter/sort semantics the web app relies on,
including the rule that nothing (rating, review count, discount) is invented
when the platform has no data for it.
"""

import uuid

from httpx import AsyncClient
from sqlalchemy import select

from app.catalog.ids import stable_id
from app.models.catalog import Category, MenuItemCategory
from app.models.orders import Order, OrderItem

from .conftest import auth, login

CUSTOMER = ("customer@quickbite.dev", "Customer#123")


async def _token(client: AsyncClient) -> str:
    return await login(client, *CUSTOMER)


async def _tag(
    item_ids: list[str],
    slug: str,
    name: str,
    *,
    kind: str = "global",
    restaurant_id: str | None = None,
) -> str:
    """Create (once) a category and link the given dishes to it."""
    from app.db.session import SessionFactory

    category_id = stable_id("category", kind, restaurant_id or "", slug)
    async with SessionFactory() as session:
        async with session.begin():
            if await session.get(Category, category_id) is None:
                session.add(
                    Category(
                        id=category_id,
                        kind=kind,
                        slug=slug,
                        name=name,
                        restaurant_id=restaurant_id,
                    )
                )
                await session.flush()
            for item_id in item_ids:
                await session.merge(
                    MenuItemCategory(
                        menu_item_id=item_id, category_id=category_id
                    )
                )
    return category_id


async def _tag_diet(seeded: dict) -> None:
    """Item 1 and 3 are vegetarian, item 2 is not (real demo taxonomy)."""
    ids = seeded["menu_item_ids"]
    await _tag(ids[:1] + ids[2:], "vegetarian", "Vegetarian")
    await _tag(ids[1:2], "non-vegetarian", "Non-Vegetarian")


async def _place_paid_order(seeded: dict, menu_item_id: str, quantity: int) -> None:
    """A realised order, so popularity data is real (never fabricated)."""
    from app.db.session import SessionFactory

    async with SessionFactory() as session:
        async with session.begin():
            order = Order(
                id=str(uuid.uuid4()),
                customer_id=seeded["users"]["customer@quickbite.dev"],
                restaurant_id=seeded["restaurant_id"],
                status="PAID",
                total_minor=1000 * quantity,
                currency="INR",
                delivery_address="1 Test Street",
                version=1,
            )
            session.add(order)
            await session.flush()
            session.add(
                OrderItem(
                    id=str(uuid.uuid4()),
                    order_id=order.id,
                    menu_item_id=menu_item_id,
                    name_snapshot="Ordered dish",
                    unit_price_minor=1000,
                    quantity=quantity,
                    line_total_minor=1000 * quantity,
                )
            )


async def _add_rated_restaurant(name: str, rating: float, reviews: int) -> str:
    from app.db.session import SessionFactory
    from app.models.catalog import Restaurant

    restaurant_id = str(uuid.uuid4())
    async with SessionFactory() as session:
        async with session.begin():
            session.add(
                Restaurant(
                    id=restaurant_id,
                    name=name,
                    description="Rated demo kitchen",
                    cuisine="Test",
                    image_url="/static/catalog/test.jpg",
                    available=True,
                    address="Delivery-only demo kitchen - no walk-in address",
                    opening_hours="11:00 AM - 11:00 PM, daily",
                    eta_minutes_min=20,
                    eta_minutes_max=35,
                    rating=rating,
                    review_count=reviews,
                )
            )
    return restaurant_id


# ---------------------------------------------------------------------------
# Restaurant detail
# ---------------------------------------------------------------------------


async def test_restaurant_detail_exposes_real_details(client, seeded):
    token = await _token(client)
    await _tag_diet(seeded)
    rid = seeded["restaurant_id"]

    resp = await client.get(f"/api/v1/restaurants/{rid}", headers=auth(token))
    assert resp.status_code == 200, resp.text
    body = resp.json()

    assert body["name"] == "Testaurant"
    assert body["dish_count"] == 3
    assert body["order_count"] == 0
    # Rating data does not exist, so it must stay null rather than be guessed.
    assert body["rating"] is None
    assert body["review_count"] is None
    # Category labels are derived from the dish tags just created.
    assert "Vegetarian" in body["categories"]
    # Demo offers are labelled as such.
    assert body["offers"]
    assert body["eta_minutes_min"] is not None


async def test_restaurant_detail_unknown_returns_404(client, seeded):
    token = await _token(client)
    resp = await client.get("/api/v1/restaurants/nope", headers=auth(token))
    assert resp.status_code == 404
    assert resp.json()["code"] == "NOT_FOUND"


async def test_restaurant_detail_requires_auth(client, seeded):
    resp = await client.get(f"/api/v1/restaurants/{seeded['restaurant_id']}")
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Menu filters and sorting
# ---------------------------------------------------------------------------


async def test_menu_filters_combine(client, seeded):
    token = await _token(client)
    await _tag_diet(seeded)
    rid = seeded["restaurant_id"]
    url = f"/api/v1/restaurants/{rid}/menu"

    veg = await client.get(url, params={"food_type": "veg"}, headers=auth(token))
    assert veg.json()["total"] == 2
    assert {i["name"] for i in veg.json()["items"]} == {"Item 1", "Item 3"}

    non_veg = await client.get(
        url, params={"food_type": "non_veg"}, headers=auth(token)
    )
    assert {i["name"] for i in non_veg.json()["items"]} == {"Item 2"}

    # search + food_type + sort all narrow/order the same result set.
    combined = await client.get(
        url,
        params={"search": "Item", "food_type": "veg", "sort": "price_desc"},
        headers=auth(token),
    )
    assert [i["name"] for i in combined.json()["items"]] == ["Item 1", "Item 3"]

    only_three = await client.get(
        url, params={"search": "Item 3", "food_type": "veg"}, headers=auth(token)
    )
    assert [i["name"] for i in only_three.json()["items"]] == ["Item 3"]


async def test_menu_unknown_filter_reports_no_matches(client, seeded):
    token = await _token(client)
    resp = await client.get(
        f"/api/v1/restaurants/{seeded['restaurant_id']}/menu",
        params={"search": "does-not-exist"},
        headers=auth(token),
    )
    assert resp.status_code == 200
    assert resp.json()["total"] == 0
    assert resp.json()["items"] == []


async def test_menu_filters_by_category_tag(client, seeded):
    token = await _token(client)
    rid = seeded["restaurant_id"]
    section_id = await _tag(
        [seeded["menu_item_ids"][1]],
        "mains",
        "Mains",
        kind="menu",
        restaurant_id=rid,
    )
    assert section_id

    resp = await client.get(
        f"/api/v1/restaurants/{rid}/menu",
        params={"category": "mains"},
        headers=auth(token),
    )
    assert [i["name"] for i in resp.json()["items"]] == ["Item 2"]
    # Tags travel with every item so the client can render chips.
    assert resp.json()["items"][0]["tags"][0]["kind"] == "menu"
    assert resp.json()["items"][0]["is_veg"] is None


async def test_menu_sort_price_ascending(client, seeded):
    token = await _token(client)
    resp = await client.get(
        f"/api/v1/restaurants/{seeded['restaurant_id']}/menu",
        params={"sort": "price_asc"},
        headers=auth(token),
    )
    prices = [i["price_minor"] for i in resp.json()["items"]]
    assert prices == sorted(prices)


async def test_menu_popular_sort_uses_real_orders(client, seeded):
    token = await _token(client)
    await _place_paid_order(seeded, seeded["menu_item_ids"][2], 5)

    resp = await client.get(
        f"/api/v1/restaurants/{seeded['restaurant_id']}/menu",
        params={"sort": "popular"},
        headers=auth(token),
    )
    assert resp.json()["items"][0]["name"] == "Item 3"
    assert resp.json()["items"][0]["order_count"] == 5

    detail = await client.get(
        f"/api/v1/restaurants/{seeded['restaurant_id']}", headers=auth(token)
    )
    assert detail.json()["order_count"] == 5


# ---------------------------------------------------------------------------
# Restaurant discovery sorting
# ---------------------------------------------------------------------------


async def test_restaurant_rating_sort_keeps_unrated_last(client, seeded):
    token = await _token(client)
    await _add_rated_restaurant("Zeta Rated", 4.6, 320)

    resp = await client.get(
        "/api/v1/restaurants", params={"sort": "rating"}, headers=auth(token)
    )
    names = [r["name"] for r in resp.json()["items"]]
    assert names[0] == "Zeta Rated"
    assert names[-1] == "Testaurant"
    # The rating itself is real data, echoed as-is.
    assert resp.json()["items"][0]["rating"] == 4.6
    assert resp.json()["items"][0]["review_count"] == 320


async def test_restaurant_popularity_sort_and_category_filter(client, seeded):
    token = await _token(client)
    await _tag([seeded["menu_item_ids"][0]], "biryani", "Biryani")
    await _place_paid_order(seeded, seeded["menu_item_ids"][0], 7)

    popular = await client.get(
        "/api/v1/restaurants", params={"sort": "popular"}, headers=auth(token)
    )
    assert popular.json()["items"][0]["name"] == "Testaurant"
    assert popular.json()["items"][0]["order_count"] == 7

    by_category = await client.get(
        "/api/v1/restaurants", params={"category": "biryani"}, headers=auth(token)
    )
    assert [r["name"] for r in by_category.json()["items"]] == ["Testaurant"]

    # A restaurant with no matching dish is not returned.
    empty = await client.get(
        "/api/v1/restaurants", params={"category": "desserts"}, headers=auth(token)
    )
    assert empty.json()["total"] == 0


async def test_restaurant_food_type_filter(client, seeded):
    token = await _token(client)
    await _tag_diet(seeded)

    veg = await client.get(
        "/api/v1/restaurants", params={"food_type": "veg"}, headers=auth(token)
    )
    assert [r["name"] for r in veg.json()["items"]] == ["Testaurant"]

    non_veg = await client.get(
        "/api/v1/restaurants", params={"food_type": "non_veg"}, headers=auth(token)
    )
    assert [r["name"] for r in non_veg.json()["items"]] == ["Testaurant"]


# ---------------------------------------------------------------------------
# Dish-first browsing
# ---------------------------------------------------------------------------


async def test_dishes_expose_tags_and_food_type_filter(client, seeded):
    token = await _token(client)
    await _tag_diet(seeded)

    veg = await client.get(
        "/api/v1/dishes", params={"food_type": "veg"}, headers=auth(token)
    )
    items = veg.json()["items"]
    assert {d["name"] for d in items} == {"Item 1", "Item 3"}
    assert all(d["is_veg"] is True for d in items)
    assert all(d["restaurant_name"] == "Testaurant" for d in items)
    assert all(
        any(t["name"] == "Vegetarian" for t in d["tags"]) for d in items
    )


# ---------------------------------------------------------------------------
# Promotions
# ---------------------------------------------------------------------------


async def test_promotions_are_labelled_demo_and_never_claim_discounts(
    client, seeded
):
    token = await _token(client)
    resp = await client.get("/api/v1/promotions", headers=auth(token))
    assert resp.status_code == 200
    body = resp.json()

    assert body["banners"], "demo banners should be served in development"
    assert body["offers"], "demo offers should be served in development"
    assert all(b["is_demo"] and b["badge"] == "Demo offer" for b in body["banners"])
    assert all(o["is_demo"] and o["badge"] == "Demo offer" for o in body["offers"])
    # Every offer states plainly that no discount is applied at checkout.
    assert all("no discount" in (o["disclosure"] or "").lower() for o in body["offers"])
    # CTAs always point at something real and browsable.
    assert all(b["target"] for b in body["banners"])
    assert all(b["cta"].get("type") for b in body["banners"])


async def test_promotions_empty_in_production(client, seeded, monkeypatch):
    from app import promotions

    monkeypatch.setattr(promotions.settings, "APP_ENV", "production")
    token = await _token(client)

    resp = await client.get("/api/v1/promotions", headers=auth(token))
    assert resp.json() == {"banners": [], "offers": []}

    # Restaurant payloads must not advertise offers that do not exist either.
    detail = await client.get(
        f"/api/v1/restaurants/{seeded['restaurant_id']}", headers=auth(token)
    )
    assert detail.json()["offers"] == []


async def test_promotions_requires_auth(client, seeded):
    resp = await client.get("/api/v1/promotions")
    assert resp.status_code == 401
