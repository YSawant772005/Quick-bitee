"""Shared pytest fixtures. Tests run against the real PostgreSQL + RabbitMQ
services (started via docker compose). A dedicated `quickbite_test` database
is created and migrated once per session; each test gets a clean schema."""

import os

os.environ["DATABASE_URL"] = "postgresql+asyncpg://quickbite:quickbite@localhost:55432/quickbite_test"
os.environ["AMQP_URL"] = "amqp://quickbite:quickbite@localhost:5672/"
os.environ["PAYMENT_FAILURE_MODE"] = "none"
os.environ["RESTAURANT_FAILURE_MODE"] = "none"
os.environ["DELIVERY_FAILURE_MODE"] = "none"
os.environ["NOTIFICATION_FAILURE_MODE"] = "none"
os.environ["WORKER_CRASH_POINT"] = "none"
os.environ["RETRY_DELAYS_SECONDS"] = "1,1,1"
os.environ["SIM_PAYMENT_DELAY_SECONDS"] = "0.01"
os.environ["SIM_RESTAURANT_DELAY_SECONDS"] = "0.01"
os.environ["SIM_DELIVERY_DELAY_SECONDS"] = "0.01"
os.environ["SIM_NOTIFICATION_DELAY_SECONDS"] = "0.01"

import asyncio
import uuid
from collections.abc import AsyncIterator

import asyncpg
import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

TEST_DB = "quickbite_test"

ALL_TABLES = [
    "simulated_payments",
    "order_status_history",
    "order_items",
    "notifications",
    "idempotency_records",
    "driver_assignments",
    "orders",
    "menu_items",
    "restaurants",
    "users",
    "processed_events",
    "outbox_events",
    "retry_jobs",
    "quarantine_records",
]


@pytest.fixture(scope="session")
def anyio_backend() -> str:
    return "asyncio"


@pytest.fixture(scope="session")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


async def _ensure_database() -> None:
    conn = await asyncpg.connect(
        host="localhost", port=55432, user="quickbite", password="quickbite", database="postgres"
    )
    try:
        exists = await conn.fetchval("SELECT 1 FROM pg_database WHERE datname = $1", TEST_DB)
        if not exists:
            await conn.execute(f'CREATE DATABASE "{TEST_DB}"')
    finally:
        await conn.close()


async def _migrate() -> None:
    from alembic import command
    from alembic.config import Config

    cfg = Config(os.path.join(os.path.dirname(__file__), "..", "alembic.ini"))
    cfg.set_main_option("script_location", os.path.join(os.path.dirname(__file__), "..", "alembic"))
    cfg.set_main_option("sqlalchemy.url", os.environ["DATABASE_URL"])
    await asyncio.to_thread(command.upgrade, cfg, "head")


async def _truncate() -> None:
    from sqlalchemy import text

    from app.db.session import engine

    async with engine.begin() as conn:
        for table in ALL_TABLES:
            await conn.execute(text(f'TRUNCATE TABLE "{table}" CASCADE'))


@pytest_asyncio.fixture(scope="session")
async def prepared() -> AsyncIterator[None]:
    await _ensure_database()
    await _migrate()
    yield
    from sqlalchemy.ext.asyncio import close_all_sessions

    await close_all_sessions()
    from app.db.session import engine

    await engine.dispose()


@pytest_asyncio.fixture()
async def clean(prepared) -> AsyncIterator[None]:
    await _truncate()
    yield
    await _truncate()


@pytest_asyncio.fixture(scope="session")
async def client(prepared) -> AsyncIterator[AsyncClient]:
    from app.main import app

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c


async def _seed() -> dict:
    from app.core.security import hash_password
    from app.db.session import SessionFactory
    from app.models.catalog import MenuItem, Restaurant
    from app.models.users import User

    ids: dict = {"users": {}, "restaurant_id": None, "menu_item_ids": []}
    async with SessionFactory() as session:
        async with session.begin():
            for email, role, pw in [
                ("customer@quickbite.dev", "customer", "Customer#123"),
                ("customer2@quickbite.dev", "customer", "Customer#123"),
                ("admin@quickbite.dev", "admin", "Admin#123"),
            ]:
                user = User(email=email, password_hash=hash_password(pw), role=role)
                session.add(user)
                await session.flush()
                ids["users"][email] = user.id
            restaurant = Restaurant(
                name="Testaurant",
                description="Test restaurant",
                cuisine="test",
                image_url="/static/catalog/test.jpg",
                available=True,
            )
            session.add(restaurant)
            await session.flush()
            ids["restaurant_id"] = restaurant.id
            for i, price in enumerate([10000, 25000, 5000]):
                item = MenuItem(
                    restaurant_id=restaurant.id,
                    name=f"Item {i + 1}",
                    description="tasty",
                    price_minor=price,
                    currency="INR",
                    image_url="/static/catalog/item.jpg",
                    available=True,
                )
                session.add(item)
                await session.flush()
                ids["menu_item_ids"].append(item.id)
    return ids


@pytest_asyncio.fixture()
async def seeded(client, clean) -> AsyncIterator[dict]:
    data = await _seed()
    yield data


async def login(client: AsyncClient, email: str, password: str) -> str:
    resp = await client.post("/api/v1/auth/login", json={"email": email, "password": password})
    assert resp.status_code == 200, resp.text
    return resp.json()["access_token"]


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def new_idem_key() -> str:
    return uuid.uuid4().hex[:32]
