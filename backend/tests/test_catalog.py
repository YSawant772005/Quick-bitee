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


async def test_dishes_requires_auth(client: AsyncClient, seeded):
    resp = await client.get("/api/v1/dishes")
    assert resp.status_code == 401


async def test_dishes_lists_items_with_restaurant_name(client: AsyncClient, seeded):
    token = await login(client, "customer@quickbite.dev", "Customer#123")
    resp = await client.get("/api/v1/dishes", headers=auth(token))
    assert resp.status_code == 200
    body = resp.json()
    assert body["total"] == 3
    names = {d["name"] for d in body["items"]}
    assert names == {"Item 1", "Item 2", "Item 3"}
    assert all(d["restaurant_name"] == "Testaurant" for d in body["items"])
    assert all(d["order_count"] == 0 for d in body["items"])


async def test_dishes_search_matches_item_and_restaurant(client: AsyncClient, seeded):
    token = await login(client, "customer@quickbite.dev", "Customer#123")
    by_item = await client.get("/api/v1/dishes", params={"search": "Item 2"}, headers=auth(token))
    assert by_item.json()["total"] == 1
    by_restaurant = await client.get(
        "/api/v1/dishes", params={"search": "Testaurant"}, headers=auth(token)
    )
    assert by_restaurant.json()["total"] == 3
