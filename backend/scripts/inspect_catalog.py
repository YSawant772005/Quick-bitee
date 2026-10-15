import asyncio
import os

from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

URL = os.environ.get(
    "DATABASE_URL",
    "postgresql+asyncpg://quickbite:quickbite@127.0.0.1:55432/quickbite",
)


async def main() -> None:
    engine = create_async_engine(URL)
    async with engine.connect() as conn:
        tables = (
            await conn.execute(
                text(
                    "select tablename from pg_tables "
                    "where schemaname='public' order by 1"
                )
            )
        ).all()
        print("tables:", [r[0] for r in tables])

        for table in ("categories", "menu_item_categories"):
            cols = (
                await conn.execute(
                    text(
                        "select column_name from information_schema.columns "
                        "where table_name = :t order by ordinal_position"
                    ),
                    {"t": table},
                )
            ).all()
            print(f"{table} cols:", [r[0] for r in cols])

        idx = (
            await conn.execute(
                text(
                    "select indexname, indexdef from pg_indexes "
                    "where tablename = 'categories' order by 1"
                )
            )
        ).all()
        for name, definition in idx:
            print("idx:", name, "|", definition)

        for table in ("users", "restaurants", "menu_items", "orders", "order_items"):
            n = (
                await conn.execute(text(f"select count(*) from {table}"))
            ).scalar_one()
            print(f"{table:16} {n}")

    await engine.dispose()


asyncio.run(main())
