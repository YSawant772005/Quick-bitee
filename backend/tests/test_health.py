from httpx import AsyncClient


async def test_health_live(client: AsyncClient, clean):
    resp = await client.get("/health/live")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


async def test_health_ready(client: AsyncClient, clean):
    resp = await client.get("/health/ready")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ready"
