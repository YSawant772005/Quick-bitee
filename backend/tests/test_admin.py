from httpx import AsyncClient

from .conftest import auth, login, new_idem_key


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
