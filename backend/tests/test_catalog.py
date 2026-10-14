from httpx import AsyncClient

from .conftest import auth, login


async def test_restaurants_requires_auth(client: AsyncClient, seeded):
    resp = await client.get("/api/v1/restaurants")
    assert resp.status_code == 401


async def test_restaurants_listed(client: AsyncClient, seeded):
    token = await login(client, "customer@quickbite.dev", "Customer#123")
    resp = await client.get("/api/v1/restaurants", headers=auth(token))
    assert resp.status_code == 200
    body = resp.json()
    assert body["total"] >= 1
    names = [r["name"] for r in body["items"]]
    assert "Testaurant" in names


async def test_restaurants_pagination(client: AsyncClient, seeded):
    token = await login(client, "customer@quickbite.dev", "Customer#123")
    resp = await client.get(
        "/api/v1/restaurants", params={"page": 1, "page_size": 1}, headers=auth(token)
    )
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["items"]) == 1
    assert body["page_size"] == 1


async def test_menu_items(client: AsyncClient, seeded):
    token = await login(client, "customer@quickbite.dev", "Customer#123")
    rid = seeded["restaurant_id"]
    resp = await client.get(f"/api/v1/restaurants/{rid}/menu", headers=auth(token))
    assert resp.status_code == 200
    body = resp.json()
    assert body["total"] == 3
    prices = {i["price_minor"] for i in body["items"]}
    assert prices == {10000, 25000, 5000}


async def test_menu_unknown_restaurant_404(client: AsyncClient, seeded):
    token = await login(client, "customer@quickbite.dev", "Customer#123")
    resp = await client.get("/api/v1/restaurants/does-not-exist/menu", headers=auth(token))
    assert resp.status_code == 404
    assert resp.json()["code"] == "NOT_FOUND"
