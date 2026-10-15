"""Idempotent bulk upsert of the expanded catalogue into the dev database.

* Deterministic UUIDv5 keys (stable across runs) so re-runs update instead of
  inserting duplicates.
* Never drops / truncates / resets – only upserts.
* Preserves all existing orders (208) and order_items (215) with their FKs.
* Reports created / updated / skipped / failed counts.
* Dev DB only – aborts if it detects a non-local PostgreSQL host.
"""

from __future__ import annotations

import argparse
import sys
import uuid
from dataclasses import dataclass
from pathlib import Path

import httpx
from sqlalchemy import select, text
from sqlalchemy.dialects.postgresql import insert as pg_insert

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.catalog.build import build_catalogue  # noqa: E402
from app.catalog import taxonomy  # noqa: E402
from app.db.base import UUIDMixin  # noqa: E402
from app.db.session import engine  # noqa: E402
from app.models.catalog import Category, MenuItem, Restaurant, MenuItemCategory  # noqa: E402

NAMESPACE = uuid.UUID("6fa459ea-ee8a-3ca4-894e-db77e160355e")  # fixed namespace


def stable_id(*parts: str) -> str:
    """Deterministic UUIDv5 from a stable string key."""
    return str(uuid.uuid5(NAMESPACE, "|".join(parts)))


@dataclass
class Stats:
    restaurants_created: int = 0
    restaurants_updated: int = 0
    categories_created: int = 0
    categories_updated: int = 0
    dishes_created: int = 0
    dishes_updated: int = 0
    dishes_skipped: int = 0
    failed: list[str] = None

    def __post_init__(self):
        if self.failed is None:
            self.failed = []


def dev_db_only(engine) -> bool:
    """Return True only for local dev databases."""
    try:
        with engine.connect() as conn:
            row = conn.execute(text("select inet_server_addr(), inet_server_port()")).first()
            if row is None:
                return False
            host, port = row
            return host in ("127.0.0.1", "::1", "localhost", None) and port == 55432
    except Exception:
        # If we can't query server info, fall back to URL check
        try:
            from app.core.config import settings
            return "localhost:55432" in settings.DATABASE_URL or "127.0.0.1:55432" in settings.DATABASE_URL
        except Exception:
            return False


async def seed(dry_run: bool = False) -> Stats:
    stats = Stats()
    catalogue = build_catalogue()

    if not dev_db_only(engine):
        raise RuntimeError("Seeder only runs against local dev DB (127.0.0.1:55432)")

    # Load image manifest
    manifest_path = Path(__file__).resolve().parents[1] / "app" / "static" / "catalog" / "manifest.json"
    image_manifest: dict[str, str] = {}
    if manifest_path.exists():
        import json
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
        for ft, entry in data.get("assets", {}).items():
            image_manifest[ft] = entry["file"]
    catalog_dir = Path(__file__).resolve().parents[1] / "app" / "static" / "catalog"

    from sqlalchemy.ext.asyncio import AsyncSession

    async with AsyncSession(engine) as session:
        # -----------------------------------------------------------
        # 1. Restaurants
        # -----------------------------------------------------------
        for built in catalogue.restaurants:
            rid = stable_id("restaurant", built.key)
            stmt = pg_insert(Restaurant).values(
                id=rid,
                name=built.name,
                description=built.description,
                cuisine=built.cuisine,
                image_url=f"/static/catalog/{built.cover_food_type}.jpg",
                available=True,
            ).on_conflict_do_update(
                index_elements=["name"],  # unique constraint is on name
                set_=dict(
                    description=built.description,
                    cuisine=built.cuisine,
                    image_url=f"/static/catalog/{built.cover_food_type}.jpg",
                    available=True,
                ),
            )
            await session.execute(stmt)

            # check if row existed before
            existing = await session.scalar(
                select(Restaurant).where(Restaurant.name == built.name)
            )
            if existing is None:
                stats.restaurants_created += 1
            else:
                stats.restaurants_updated += 1
                # Use the existing restaurant's ID for sections/dishes
                rid = existing.id

            # -------------------------------------------------------
            # 2. Menu categories (per-restaurant) — one bulk upsert
            # -------------------------------------------------------
            cat_rows = [
                dict(
                    id=stable_id("category", built.key, section.slug),
                    restaurant_id=rid,
                    name=section.title,
                    kind="menu",
                    slug=section.slug,
                    sort_order=idx,
                )
                for idx, section in enumerate(built.sections)
            ]
            before_cat_ids = set(
                (
                    await session.execute(
                        select(Category.id).where(
                            Category.id.in_([c["id"] for c in cat_rows])
                        )
                    )
                ).scalars()
            )
            stats.categories_created += sum(1 for c in cat_rows if c["id"] not in before_cat_ids)
            stats.categories_updated += sum(1 for c in cat_rows if c["id"] in before_cat_ids)
            if cat_rows:
                cat_insert = pg_insert(Category)
                await session.execute(
                    cat_insert.values(cat_rows).on_conflict_do_update(
                        index_elements=["id"],
                        set_=dict(
                            name=cat_insert.excluded.name,
                            slug=cat_insert.excluded.slug,
                            sort_order=cat_insert.excluded.sort_order,
                        ),
                    )
                )

            # ---------------------------------------------------
            # 3. Menu items (dishes) in this section — bulk upsert
            # ---------------------------------------------------
            for section in built.sections:
                cat_id = stable_id("category", built.key, section.slug)
                dish_rows = []
                link_rows = []
                for dish in section.dishes:
                    did = stable_id("dish", built.key, section.slug, dish.name)

                    # Resolve actual image filename from manifest (falls back to food_type.jpg)
                    img_file = image_manifest.get(dish.food_type, f"{dish.food_type}.jpg")

                    # Verify the image exists
                    if not (catalog_dir / img_file).exists():
                        stats.failed.append(f"image missing for {dish.name} ({dish.food_type} -> {img_file})")
                        stats.dishes_skipped += 1
                        continue
                    dish_rows.append(
                        dict(
                            id=did,
                            restaurant_id=rid,
                            name=dish.name,
                            description=dish.description,
                            price_minor=dish.price_minor,
                            currency="INR",
                            image_url=f"/static/catalog/{img_file}",
                            available=True,
                        )
                    )
                    # Link dish to its menu section category
                    link_rows.append(dict(menu_item_id=did, category_id=cat_id))
                if not dish_rows:
                    continue
                before_dish_ids = set(
                    (
                        await session.execute(
                            select(MenuItem.id).where(
                                MenuItem.id.in_([d["id"] for d in dish_rows])
                            )
                        )
                    ).scalars()
                )
                stats.dishes_created += sum(1 for d in dish_rows if d["id"] not in before_dish_ids)
                stats.dishes_updated += sum(1 for d in dish_rows if d["id"] in before_dish_ids)
                if dish_rows:
                    dish_insert = pg_insert(MenuItem)
                    await session.execute(
                        dish_insert.values(dish_rows).on_conflict_do_update(
                            index_elements=["id"],
                            set_=dict(
                                name=dish_insert.excluded.name,
                            description=dish_insert.excluded.description,
                            price_minor=dish_insert.excluded.price_minor,
                            image_url=dish_insert.excluded.image_url,
                            available=True,
                        ),
                    )
                )
                if link_rows:
                    link_insert = pg_insert(MenuItemCategory)
                    await session.execute(
                        link_insert.values(link_rows).on_conflict_do_nothing(
                            index_elements=["menu_item_id", "category_id"]
                        )
                    )

            if dry_run:
                await session.rollback()
            else:
                await session.commit()

    # -----------------------------------------------------------
    # 4. Global categories and dish -> global category links
    # -----------------------------------------------------------
    async with AsyncSession(engine) as session:
        # Create global categories
        for slug, name, description, thumb, sort_order in taxonomy.GLOBAL_CATEGORIES:
            gc_id = stable_id("category", "global", slug)
            gc_stmt = pg_insert(Category).values(
                id=gc_id,
                restaurant_id=None,
                name=name,
                kind="global",
                slug=slug,
                description=description,
                image_url=f"/static/catalog/{thumb}.jpg",
                sort_order=sort_order,
            ).on_conflict_do_update(
                index_elements=["id"],
                set_=dict(
                    name=name,
                    description=description,
                    image_url=f"/static/catalog/{thumb}.jpg",
                    sort_order=sort_order,
                ),
            )
            await session.execute(gc_stmt)

        # Link dishes to global categories based on dish tags.
        # Insert links per restaurant in batches so one slow statement can't
        # stall the run. A link is queued only when its dish row really exists
        # in the DB right now (verified by SELECT), which keeps the FK
        # satisfied even after a rollback in dry-run mode.
        existing_dish_ids: set[str] = set(
            (await session.execute(select(MenuItem.id))).scalars()
        )
        for built in catalogue.restaurants:
            global_links: list[dict] = []
            for dish in built.all_dishes:
                section_slug = next(s.slug for s in built.sections if dish in s.dishes)
                did = stable_id("dish", built.key, section_slug, dish.name)
                if did not in existing_dish_ids:
                    continue
                for tag in set(dish.tags):
                    if tag in taxonomy.GLOBAL_CATEGORY_SLUGS:
                        global_links.append(
                            dict(
                                menu_item_id=did,
                                category_id=stable_id("category", "global", tag),
                            )
                        )
            link_all = pg_insert(MenuItemCategory)
            for i in range(0, len(global_links), 2000):
                chunk = global_links[i : i + 2000]
                await session.execute(
                    link_all.values(chunk).on_conflict_do_nothing(
                        index_elements=["menu_item_id", "category_id"]
                    )
                )
            if dry_run:
                await session.rollback()
            else:
                await session.commit()

    return stats


async def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="simulate without committing")
    args = parser.parse_args()

    try:
        stats = await seed(dry_run=args.dry_run)
    except Exception as e:
        print(f"SEED FAILED: {e}", file=sys.stderr)
        return 1

    print("SEED SUMMARY")
    print(f"  restaurants:  created={stats.restaurants_created}  updated={stats.restaurants_updated}")
    print(f"  categories:   created={stats.categories_created}  updated={stats.categories_updated}")
    print(f"  dishes:       created={stats.dishes_created}  updated={stats.dishes_updated}  skipped={stats.dishes_skipped}")
    if stats.failed:
        print(f"  failed:       {len(stats.failed)}")
        for f in stats.failed[:20]:
            print(f"    - {f}")
    return 0 if not stats.failed else 1


if __name__ == "__main__":
    import asyncio
    raise SystemExit(asyncio.run(main()))