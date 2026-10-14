from httpx import AsyncClient

from .conftest import auth, login


async def test_login_success(client: AsyncClient, seeded):
    resp = await client.post(
        "/api/v1/auth/login",
        json={"email": "customer@quickbite.dev", "password": "Customer#123"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["access_token"]
    assert body["user"]["role"] == "customer"


async def test_login_wrong_password(client: AsyncClient, seeded):
    resp = await client.post(
        "/api/v1/auth/login",
        json={"email": "customer@quickbite.dev", "password": "wrong"},
    )
    assert resp.status_code == 401
    assert resp.json()["code"] == "UNAUTHENTICATED"


async def test_login_unknown_user(client: AsyncClient, seeded):
    resp = await client.post(
        "/api/v1/auth/login",
        json={"email": "ghost@quickbite.dev", "password": "Customer#123"},
    )
    assert resp.status_code == 401


async def test_me_requires_token(client: AsyncClient, seeded):
    resp = await client.get("/api/v1/auth/me")
    assert resp.status_code == 401


async def test_me_returns_profile(client: AsyncClient, seeded):
    token = await login(client, "admin@quickbite.dev", "Admin#123")
    resp = await client.get("/api/v1/auth/me", headers=auth(token))
    assert resp.status_code == 200
    assert resp.json()["email"] == "admin@quickbite.dev"
    assert resp.json()["role"] == "admin"


async def test_me_rejects_garbage_token(client: AsyncClient, seeded):
    resp = await client.get("/api/v1/auth/me", headers=auth("not-a-token"))
    assert resp.status_code == 401
