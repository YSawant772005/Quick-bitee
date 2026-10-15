from datetime import date, timedelta
import uuid

from httpx import AsyncClient

from app.domain.events import EVENT_ORDER_CONFIRMED, EVENT_ORDER_CREATED, new_envelope
from workers.common import process_business_event
from workers.delivery_worker import delivery_effect
from workers.payment_worker import payment_effect
from workers.restaurant_worker import restaurant_effect

from .conftest import auth, login, new_idem_key
from .test_workers import _full_pipeline


async def drive_order(order_id: str) -> None:
    """Advance a specific order PENDING -> PAID -> CONFIRMED -> DRIVER_ASSIGNED
    in-process, using exactly the same transitions the background workers apply."""
    created = new_envelope(
        EVENT_ORDER_CREATED, order_id=order_id, order_version=1, correlation_id=str(uuid.uuid4())
    )
    await process_business_event("payment-worker", created, 1, payment_effect)
    paid = new_envelope(
        "order.paid",
        order_id=order_id,
        order_version=2,
        correlation_id=created.correlation_id,
        causation_id=created.event_id,
    )
    await process_business_event("restaurant-worker", paid, 1, restaurant_effect)
    confirmed = new_envelope(
        EVENT_ORDER_CONFIRMED,
        order_id=order_id,
        order_version=3,
        correlation_id=created.correlation_id,
        causation_id=paid.event_id,
    )
    await process_business_event("delivery-worker", confirmed, 1, delivery_effect)


async def _place(client: AsyncClient, seeded, token: str) -> str:
    payload = {
        "restaurant_id": seeded["restaurant_id"],
        "delivery_address": "42 Admin Avenue",
        "items": [{"menu_item_id": seeded["menu_item_ids"][0], "quantity": 1}],
    }
    resp = await client.post(
        "/api/v1/orders",
        json=payload,
        headers={**auth(token), "Idempotency-Key": new_idem_key()},
    )
    assert resp.status_code == 202
    return resp.json()["order_id"]


async def test_admin_orders_requires_admin(client: AsyncClient, seeded):
    token = await login(client, "customer@quickbite.dev", "Customer#123")
    resp = await client.get("/api/v1/admin/orders", headers=auth(token))
    assert resp.status_code == 403


async def test_admin_orders_lists_and_filters(client: AsyncClient, seeded):
    customer = await login(client, "customer@quickbite.dev", "Customer#123")
    await _place(client, seeded, customer)
    await _place(client, seeded, customer)

    admin = await login(client, "admin@quickbite.dev", "Admin#123")
    resp = await client.get("/api/v1/admin/orders", headers=auth(admin))
    assert resp.status_code == 200
    body = resp.json()
    assert body["total"] == 2

    filtered = await client.get(
        "/api/v1/admin/orders",
        params={"status": "PENDING"},
        headers=auth(admin),
    )
    assert filtered.json()["total"] == 2
    filtered_none = await client.get(
        "/api/v1/admin/orders",
        params={"status": "DRIVER_ASSIGNED"},
        headers=auth(admin),
    )
    assert filtered_none.json()["total"] == 0


async def test_admin_orders_pagination(client: AsyncClient, seeded):
    customer = await login(client, "customer@quickbite.dev", "Customer#123")
    for _ in range(3):
        await _place(client, seeded, customer)

    admin = await login(client, "admin@quickbite.dev", "Admin#123")
    page1 = await client.get(
        "/api/v1/admin/orders", params={"page": 1, "page_size": 2}, headers=auth(admin)
    )
    assert page1.status_code == 200
    body = page1.json()
    assert len(body["items"]) == 2
    assert body["total"] == 3
    assert body["page_size"] == 2


async def test_admin_summary_reflects_backlog(client: AsyncClient, seeded):
    customer = await login(client, "customer@quickbite.dev", "Customer#123")
    await _place(client, seeded, customer)

    admin = await login(client, "admin@quickbite.dev", "Admin#123")
    resp = await client.get("/api/v1/admin/summary", headers=auth(admin))
    assert resp.status_code == 200
    body = resp.json()
    assert body["total_orders"] == 1
    assert body["by_status"]["PENDING"] == 1
    assert body["pending_outbox"] >= 1
    assert body["quarantine_count"] >= 0
    assert body["retry_backlog"] >= 0


async def test_admin_summary_analytics_fields(client: AsyncClient, seeded):
    customer = await login(client, "customer@quickbite.dev", "Customer#123")
    await _place(client, seeded, customer)

    admin = await login(client, "admin@quickbite.dev", "Admin#123")
    body = (await client.get("/api/v1/admin/summary", headers=auth(admin))).json()
    assert body["active_customers"] == 1
    # A freshly placed (still PENDING) order is not counted as revenue yet.
    assert body["total_revenue_minor"] == 0
    assert body["avg_order_value_minor"] == 0
    assert len(body["revenue_by_day"]) == 14
    assert isinstance(body["top_dishes"], list)


async def test_order_items_and_list_include_food_images(client: AsyncClient, seeded):
    customer = await login(client, "customer@quickbite.dev", "Customer#123")
    order_id = await _place(client, seeded, customer)

    detail = (
        await client.get(f"/api/v1/orders/{order_id}", headers=auth(customer))
    ).json()
    assert detail["items"][0]["image_url"] == "/static/catalog/item.jpg"

    listing = (await client.get("/api/v1/orders", headers=auth(customer))).json()
    assert listing["items"][0]["thumbnail_url"] == "/static/catalog/item.jpg"


# ---------------------------------------------------------------------------
# New admin console endpoints
# ---------------------------------------------------------------------------

NEW_ADMIN_PATHS = (
    "/api/v1/admin/analytics",
    "/api/v1/admin/restaurants",
    "/api/v1/admin/menu-items",
    "/api/v1/admin/customers",
    "/api/v1/admin/deliveries",
)


async def test_new_admin_endpoints_require_admin(client: AsyncClient, seeded):
    customer = await login(client, "customer@quickbite.dev", "Customer#123")
    for path in NEW_ADMIN_PATHS:
        resp = await client.get(path, headers=auth(customer))
        assert resp.status_code == 403, f"{path} should be admin-only"

    resp = await client.patch(
        "/api/v1/admin/menu-items/whatever",
        json={"available": False},
        headers=auth(customer),
    )
    assert resp.status_code == 403


async def test_summary_date_range_scopes_metrics_and_compares(client: AsyncClient, seeded):
    customer = await login(client, "customer@quickbite.dev", "Customer#123")
    await _place(client, seeded, customer)
    admin = await login(client, "admin@quickbite.dev", "Admin#123")

    today = date.today().isoformat()
    body = (
        await client.get(
            "/api/v1/admin/summary",
            params={"date_from": today, "date_to": today},
            headers=auth(admin),
        )
    ).json()

    assert body["date_from"] == today
    assert body["date_to"] == today
    assert body["total_orders"] == 1
    assert body["active_customers"] == 1

    comparison = body["comparison"]
    assert comparison is not None
    assert comparison["date_from"] == today
    assert comparison["orders"]["current"] == 1
    # The previous period is yesterday, which has no orders: the percentage must
    # be null rather than a fabricated figure.
    assert comparison["orders"]["previous"] == 0
    assert comparison["orders"]["change_pct"] is None
    assert comparison["revenue_minor"]["change_pct"] is None


async def test_summary_range_excludes_orders_outside_period(client: AsyncClient, seeded):
    customer = await login(client, "customer@quickbite.dev", "Customer#123")
    await _place(client, seeded, customer)
    admin = await login(client, "admin@quickbite.dev", "Admin#123")

    yesterday = (date.today() - timedelta(days=1)).isoformat()
    body = (
        await client.get(
            "/api/v1/admin/summary",
            params={"date_from": yesterday, "date_to": yesterday},
            headers=auth(admin),
        )
    ).json()

    assert body["total_orders"] == 0
    assert body["active_customers"] == 0
    assert body["total_revenue_minor"] == 0
    assert body["avg_order_value_minor"] == 0
    assert body["top_dishes"] == []
    assert body["top_restaurants"] == []
    # One empty bucket for the requested day, so the chart still renders.
    assert len(body["revenue_by_day"]) == 1
    assert body["revenue_by_day"][0]["orders"] == 0


async def test_summary_rejects_inverted_or_bad_range(client: AsyncClient, seeded):
    admin = await login(client, "admin@quickbite.dev", "Admin#123")
    today = date.today().isoformat()
    yesterday = (date.today() - timedelta(days=1)).isoformat()

    inverted = await client.get(
        "/api/v1/admin/summary",
        params={"date_from": today, "date_to": yesterday},
        headers=auth(admin),
    )
    assert inverted.status_code == 422

    malformed = await client.get(
        "/api/v1/admin/summary",
        params={"date_from": "not-a-date"},
        headers=auth(admin),
    )
    assert malformed.status_code == 422

    bad_granularity = await client.get(
        "/api/v1/admin/summary", params={"granularity": "hour"}, headers=auth(admin)
    )
    assert bad_granularity.status_code == 422


async def test_summary_week_granularity_buckets_daily_rows(client: AsyncClient, seeded):
    customer = await login(client, "customer@quickbite.dev", "Customer#123")
    await _place(client, seeded, customer)
    admin = await login(client, "admin@quickbite.dev", "Admin#123")

    today = date.today().isoformat()
    body = (
        await client.get(
            "/api/v1/admin/summary",
            params={
                "date_from": today,
                "date_to": today,
                "granularity": "week",
            },
            headers=auth(admin),
        )
    ).json()

    assert body["granularity"] == "week"
    assert len(body["revenue_by_day"]) == 1
    # Week buckets are labelled by the Monday of their week.
    monday = (date.today() - timedelta(days=date.today().weekday())).isoformat()
    assert body["revenue_by_day"][0]["date"] == monday


async def test_admin_orders_return_customer_email_and_respect_dates(
    client: AsyncClient, seeded
):
    customer = await login(client, "customer@quickbite.dev", "Customer#123")
    await _place(client, seeded, customer)
    admin = await login(client, "admin@quickbite.dev", "Admin#123")

    body = (
        await client.get("/api/v1/admin/orders", headers=auth(admin))
    ).json()
    assert body["items"][0]["customer_email"] == "customer@quickbite.dev"
    assert body["items"][0]["payment_status"] in (None, "SUCCESS", "FAILED")
    assert body["items"][0]["restaurant_name"] == "Testaurant"
    assert body["items"][0]["item_count"] == 1

    tomorrow = (date.today() + timedelta(days=1)).isoformat()
    outside = (
        await client.get(
            "/api/v1/admin/orders",
            params={"date_from": tomorrow, "date_to": tomorrow},
            headers=auth(admin),
        )
    ).json()
    assert outside["total"] == 0


async def test_admin_orders_sort_by_total(client: AsyncClient, seeded):
    customer = await login(client, "customer@quickbite.dev", "Customer#123")
    await _place(client, seeded, customer)  # quantity 1 of Item 1 = 10000
    await client.post(
        "/api/v1/orders",
        json={
            "restaurant_id": seeded["restaurant_id"],
            "delivery_address": "2 Sort Street",
            "items": [{"menu_item_id": seeded["menu_item_ids"][1], "quantity": 2}],
        },
        headers={**auth(customer), "Idempotency-Key": new_idem_key()},
    )
    admin = await login(client, "admin@quickbite.dev", "Admin#123")

    desc = (
        await client.get(
            "/api/v1/admin/orders", params={"sort": "total_desc"}, headers=auth(admin)
        )
    ).json()
    assert desc["items"][0]["total_minor"] >= desc["items"][1]["total_minor"]

    asc = (
        await client.get(
            "/api/v1/admin/orders", params={"sort": "total_asc"}, headers=auth(admin)
        )
    ).json()
    assert asc["items"][0]["total_minor"] <= asc["items"][1]["total_minor"]

    bad = await client.get(
        "/api/v1/admin/orders", params={"sort": "nope"}, headers=auth(admin)
    )
    assert bad.status_code == 422


async def test_admin_order_detail_has_customer_payment_and_timeline(
    client: AsyncClient, seeded
):
    customer = await login(client, "customer@quickbite.dev", "Customer#123")
    order_id = await _place(client, seeded, customer)
    admin = await login(client, "admin@quickbite.dev", "Admin#123")

    pending = (
        await client.get(f"/api/v1/admin/orders/{order_id}", headers=auth(admin))
    ).json()
    assert pending["status"] == "PENDING"
    assert pending["customer_email"] == "customer@quickbite.dev"
    assert pending["restaurant_name"] == "Testaurant"
    assert pending["delivery_address"] == "42 Admin Avenue"
    assert pending["payment_status"] is None
    assert pending["items"][0]["image_url"] == "/static/catalog/item.jpg"
    assert pending["items"][0]["unit_price_minor"] == 10000
    assert pending["total_minor"] == 10000
    assert pending["timeline"], "the fulfilment timeline must not be empty"

    await drive_order(order_id)
    done = (await client.get(f"/api/v1/admin/orders/{order_id}", headers=auth(admin))).json()
    assert done["status"] == "DRIVER_ASSIGNED"
    assert done["payment_status"] == "SUCCESS"
    assert done["driver"]["driver_name"]
    # The timeline is ordered by version and ends on the current status.
    versions = [entry["version"] for entry in done["timeline"]]
    assert versions == sorted(versions)
    assert len(set(versions)) == len(versions)
    assert done["timeline"][0]["status"] == "PENDING"
    assert done["timeline"][-1]["status"] == "DRIVER_ASSIGNED"

    missing = await client.get(
        f"/api/v1/admin/orders/{'0' * 8}", headers=auth(admin)
    )
    assert missing.status_code == 404


async def test_summary_revenue_counts_paid_and_ignores_pending(
    client: AsyncClient, seeded
):
    customer = await login(client, "customer@quickbite.dev", "Customer#123")
    await _place(client, seeded, customer)
    admin = await login(client, "admin@quickbite.dev", "Admin#123")

    before = (
        await client.get("/api/v1/admin/summary", headers=auth(admin))
    ).json()
    assert before["total_orders"] == 1
    assert before["total_revenue_minor"] == 0
    assert before["successful_orders"] == 0

    await _full_pipeline(client, seeded)

    after = (
        await client.get("/api/v1/admin/summary", headers=auth(admin))
    ).json()
    # Two orders now (one placed here, one inside the pipeline helper).
    assert after["successful_orders"] >= 1
    assert after["total_revenue_minor"] > 0
    assert after["avg_order_value_minor"] > 0
    assert after["by_status"]["DRIVER_ASSIGNED"] >= 1
    assert after["active_deliveries"] >= 1


async def test_admin_restaurants_list_and_toggle_availability(
    client: AsyncClient, seeded
):
    admin = await login(client, "admin@quickbite.dev", "Admin#123")

    listing = (
        await client.get("/api/v1/admin/restaurants", headers=auth(admin))
    ).json()
    assert listing["total"] == 1
    restaurant = listing["items"][0]
    assert restaurant["name"] == "Testaurant"
    assert restaurant["available"] is True
    assert restaurant["menu_item_count"] == 3
    assert restaurant["available_item_count"] == 3

    toggled = await client.patch(
        f"/api/v1/admin/restaurants/{restaurant['id']}",
        json={"available": False},
        headers=auth(admin),
    )
    assert toggled.status_code == 200
    assert toggled.json()["available"] is False

    # The public catalogue must no longer show the closed restaurant.
    customer = await login(client, "customer@quickbite.dev", "Customer#123")
    public = (await client.get("/api/v1/restaurants", headers=auth(customer))).json()
    assert public["total"] == 0

    # Only admins may manage it.
    forbidden = await client.patch(
        f"/api/v1/admin/restaurants/{restaurant['id']}",
        json={"available": True},
        headers=auth(customer),
    )
    assert forbidden.status_code == 403

    missing = await client.patch(
        "/api/v1/admin/restaurants/does-not-exist",
        json={"available": True},
        headers=auth(admin),
    )
    assert missing.status_code == 404


async def test_admin_menu_items_list_and_edit(client: AsyncClient, seeded):
    admin = await login(client, "admin@quickbite.dev", "Admin#123")

    listing = (await client.get("/api/v1/admin/menu-items", headers=auth(admin))).json()
    assert listing["total"] == 3
    item = listing["items"][0]
    assert item["restaurant_name"] == "Testaurant"
    assert item["units_sold"] == 0
    assert item["available"] is True

    edited = await client.patch(
        f"/api/v1/admin/menu-items/{item['id']}",
        json={"price_minor": 123456, "available": False},
        headers=auth(admin),
    )
    assert edited.status_code == 200
    body = edited.json()
    assert body["price_minor"] == 123456
    assert body["available"] is False

    filtered = (
        await client.get(
            "/api/v1/admin/menu-items",
            params={"available": "false"},
            headers=auth(admin),
        )
    ).json()
    assert filtered["total"] == 1

    searched = (
        await client.get(
            "/api/v1/admin/menu-items",
            params={"search": "Item 2"},
            headers=auth(admin),
        )
    ).json()
    assert searched["total"] == 1

    bad_price = await client.patch(
        f"/api/v1/admin/menu-items/{item['id']}",
        json={"price_minor": -5},
        headers=auth(admin),
    )
    assert bad_price.status_code == 422


async def test_admin_customers_aggregation(client: AsyncClient, seeded):
    customer = await login(client, "customer@quickbite.dev", "Customer#123")
    await _place(client, seeded, customer)
    admin = await login(client, "admin@quickbite.dev", "Admin#123")

    body = (await client.get("/api/v1/admin/customers", headers=auth(admin))).json()
    # Only role=customer accounts are listed; the admin is excluded.
    assert body["total"] == 2
    target = next(i for i in body["items"] if i["email"] == "customer@quickbite.dev")
    assert target["total_orders"] == 1
    assert target["active_orders"] == 1
    assert target["successful_orders"] == 0
    assert target["last_order_at"] is not None
    assert target["total_spent_minor"] == 0

    searched = (
        await client.get(
            "/api/v1/admin/customers",
            params={"search": "customer2"},
            headers=auth(admin),
        )
    ).json()
    assert searched["total"] == 1
    assert searched["items"][0]["total_orders"] == 0


async def test_admin_deliveries_show_real_assignments(client: AsyncClient, seeded):
    admin = await login(client, "admin@quickbite.dev", "Admin#123")
    empty = (await client.get("/api/v1/admin/deliveries", headers=auth(admin))).json()
    assert empty["total"] == 0

    await _full_pipeline(client, seeded)

    body = (await client.get("/api/v1/admin/deliveries", headers=auth(admin))).json()
    assert body["total"] == 1
    delivery = body["items"][0]
    assert delivery["order_status"] == "DRIVER_ASSIGNED"
    assert delivery["driver_name"]
    assert delivery["restaurant_name"] == "Testaurant"
    assert delivery["delivery_address"]


async def test_admin_analytics_buckets(client: AsyncClient, seeded):
    customer = await login(client, "customer@quickbite.dev", "Customer#123")
    await _place(client, seeded, customer)
    admin = await login(client, "admin@quickbite.dev", "Admin#123")

    body = (await client.get("/api/v1/admin/analytics", headers=auth(admin))).json()
    assert body["total_orders"] == 1
    assert body["orders_by_status"]["PENDING"] == 1
    assert len(body["orders_by_weekday"]) >= 1
    assert len(body["orders_by_hour"]) >= 1
    assert body["avg_items_per_order"] > 0
    assert isinstance(body["revenue_by_restaurant"], list)
    # Zero-revenue buckets are not revenue: a pending order is not a sale.
    assert body["total_revenue_minor"] == 0
    assert body["failed_orders"] == 0
    assert body["successful_orders"] == 0

    future_from = (date.today() + timedelta(days=3)).isoformat()
    future_to = (date.today() + timedelta(days=4)).isoformat()
    empty = (
        await client.get(
            "/api/v1/admin/analytics",
            params={"date_from": future_from, "date_to": future_to},
            headers=auth(admin),
        )
    ).json()
    assert empty["total_orders"] == 0
    assert empty["orders_by_weekday"] == []
    assert empty["orders_by_status"] == {}
