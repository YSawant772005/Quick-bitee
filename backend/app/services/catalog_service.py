"""Small read helpers shared by the catalog/order endpoints."""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.catalog import MenuItem


async def item_image_map(session: AsyncSession, menu_item_ids: list[str]) -> dict[str, str]:
    """Map menu-item ids to their current menu image URL.

    Used to render ordered food images on tracking and history screens without
    duplicating image URLs into the order snapshot. Missing items map to "".
    """
    ids = [i for i in menu_item_ids if i]
    if not ids:
        return {}
    rows = (
        await session.execute(
            select(MenuItem.id, MenuItem.image_url).where(MenuItem.id.in_(ids))
        )
    ).all()
    return {item_id: image_url for item_id, image_url in rows}
