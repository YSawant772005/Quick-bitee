import asyncio

from httpx import AsyncClient

from .conftest import auth, login, new_idem_key


def _payload(seeded, quantities=None):
    quantities = quantities or [1, 2, 1]
    items = [
        {"menu_item_id": mid, "quantity": q}
        for mid, q in zip(seeded["menu_item_ids"], quantities)
    ]
    return {
        "restaurant_id": seeded["restaurant_id"],
        "delivery_address": "221B Test Lane, Bengaluru 560001",
        "items": items,
    }


async def test_checkout_requires_auth(client: AsyncClient, seeded):
    resp = await client.post("/api/v1/orders", json=_payload(seeded))
    assert resp.status_code == 401


async def test_checkout_requires_idempotency_key(client: AsyncClient, seeded):
    token = await login(client, "customer@quickbite.dev", "Customer#123")
    resp = await client.post("/api/v1/orders", json=_payload(seeded), headers=auth(token))
    assert resp.status_code == 422


async def test_checkout_success_and_server_total(client: AsyncClient, seeded):
    token = await login(client, "customer@quickbite.dev", "Customer#123")
    resp = await client.post(
        "/api/v1/orders",
        json=_payload(seeded, quantities=[1, 2, 1]),
        headers={**auth(token), "Idempotency-Key": new_idem_key()},
    )
    assert resp.status_code == 202
    body = resp.json()
    assert body["status"] == "PENDING"
    # 10000*1 + 25000*2 + 5000*1 = 65000
    assert body["total_minor"] == 65000


async def test_checkout_same_key_replays_same_order(client: AsyncClient, seeded):
    token = await login(client, "customer@quickbite.dev", "Customer#123")
    key = new_idem_key()
    headers = {**auth(token), "Idempotency-Key": key}
    r1 = await client.post("/api/v1/orders", json=_payload(seeded), headers=headers)
    r2 = await client.post("/api/v1/orders", json=_payload(seeded), headers=headers)
    assert r1.status_code == 202
    assert r2.status_code in (200, 201, 202)
    assert r1.json()["order_id"] == r2.json()["order_id"]


async def test_checkout_same_key_different_payload_conflicts(client: AsyncClient, seeded):
    token = await login(client, "customer@quickbite.dev", "Customer#123")
    key = new_idem_key()
    headers = {**auth(token), "Idempotency-Key": key}
    r1 = await client.post("/api/v1/orders", json=_payload(seeded), headers=headers)
    other = _payload(seeded, quantities=[2, 1, 1])
    r2 = await client.post("/api/v1/orders", json=other, headers=headers)
    assert r1.status_code == 202
    assert r2.status_code == 409
    assert r2.json()["code"] == "CONFLICT"


async def test_checkout_concurrent_same_key_creates_one_order(client: AsyncClient, seeded):
    """Two genuinely concurrent submissions with one Idempotency-Key must
    produce exactly one persisted order and the same order identity.

    Each request runs on its own event loop in a worker thread, so both
    database transactions are really in flight at the same time (an
    `asyncio.gather` on a single loop would serialise them and never reach the
    unique-constraint race the service has to survive).
    """
    from concurrent.futures import ThreadPoolExecutor

    from httpx import ASGITransport, AsyncClient as _Client
    from sqlalchemy import func, select
    from sqlalchemy.pool import NullPool

    from app.db.session import SessionFactory, engine
    from app.main import app
    from app.models.orders import IdempotencyRecord, Order

    token = await login(client, "customer@quickbite.dev", "Customer#123")
    key = new_idem_key()
    headers = {**auth(token), "Idempotency-Key": key}
    payload = _payload(seeded)

    async def submit() -> tuple[int, dict]:
        async with _Client(transport=ASGITransport(app=app), base_url="http://test") as c:
            resp = await c.post("/api/v1/orders", json=payload, headers=headers)
            return resp.status_code, resp.json()

    def submit_in_thread() -> tuple[int, dict]:
        return asyncio.run(submit())

    # Each worker thread runs its own event loop, so the shared asyncpg pool
    # must not hand a connection across loops: use NullPool for the race.
    original_pool = engine.pool
    engine.pool = NullPool(engine.pool._creator)
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(submit_in_thread), pool.submit(submit_in_thread)]
            results = [f.result() for f in futures]
    finally:
        engine.pool = original_pool

    statuses = [status for status, _ in results]
    bodies = [body for _, body in results]
    assert all(s == 202 for s in statuses), statuses
    assert bodies[0]["order_id"] == bodies[1]["order_id"]
    assert bodies[0]["total_minor"] == bodies[1]["total_minor"]

    async with SessionFactory() as session:
        orders = await session.execute(
            select(func.count()).select_from(Order).where(
                Order.customer_id == seeded["users"]["customer@quickbite.dev"]
            )
        )
        records = await session.execute(
            select(func.count()).select_from(IdempotencyRecord).where(
                IdempotencyRecord.customer_id == seeded["users"]["customer@quickbite.dev"],
                IdempotencyRecord.idem_key == key,
            )
        )
        assert orders.scalar_one() == 1, "concurrent checkout persisted more than one order"
        assert records.scalar_one() == 1, "concurrent checkout wrote a duplicate idempotency record"


async def test_checkout_rejects_duplicate_menu_items(client: AsyncClient, seeded):
    token = await login(client, "customer@quickbite.dev", "Customer#123")
    payload = _payload(seeded)
    payload["items"] = [payload["items"][0], payload["items"][0]]
    resp = await client.post(
        "/api/v1/orders",
        json=payload,
        headers={**auth(token), "Idempotency-Key": new_idem_key()},
    )
    assert resp.status_code == 422


async def test_checkout_rejects_mixed_restaurants(client: AsyncClient, seeded):
    token = await login(client, "customer@quickbite.dev", "Customer#123")
    payload = _payload(seeded)
    payload["items"].append({"menu_item_id": "foreign-item", "quantity": 1})
    resp = await client.post(
        "/api/v1/orders",
        json=payload,
        headers={**auth(token), "Idempotency-Key": new_idem_key()},
    )
    assert resp.status_code in (404, 422)


async def test_checkout_admin_role_forbidden(client: AsyncClient, seeded):
    token = await login(client, "admin@quickbite.dev", "Admin#123")
    resp = await client.post(
        "/api/v1/orders",
        json=_payload(seeded),
        headers={**auth(token), "Idempotency-Key": new_idem_key()},
    )
    assert resp.status_code == 403


async def test_order_visible_only_to_owner(client: AsyncClient, seeded):
    token = await login(client, "customer@quickbite.dev", "Customer#123")
    resp = await client.post(
        "/api/v1/orders",
        json=_payload(seeded),
        headers={**auth(token), "Idempotency-Key": new_idem_key()},
    )
    order_id = resp.json()["order_id"]

    other = await login(client, "customer2@quickbite.dev", "Customer#123")
    assert (await client.get(f"/api/v1/orders/{order_id}", headers=auth(other))).status_code == 404

    admin = await login(client, "admin@quickbite.dev", "Admin#123")
    assert (await client.get(f"/api/v1/orders/{order_id}", headers=auth(admin))).status_code == 200


async def test_order_history_records_created(client: AsyncClient, seeded):
    token = await login(client, "customer@quickbite.dev", "Customer#123")
    resp = await client.post(
        "/api/v1/orders",
        json=_payload(seeded),
        headers={**auth(token), "Idempotency-Key": new_idem_key()},
    )
    order_id = resp.json()["order_id"]
    hist = await client.get(f"/api/v1/orders/{order_id}/history", headers=auth(token))
    assert hist.status_code == 200
    entries = hist.json()["items"]
    assert entries[0]["status"] == "PENDING"
    assert entries[0]["version"] == 1
