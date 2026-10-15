from pydantic import BaseModel


class RestaurantOut(BaseModel):
    id: str
    name: str
    description: str
    cuisine: str
    image_url: str
    available: bool

    model_config = {"from_attributes": True}


class MenuItemOut(BaseModel):
    id: str
    restaurant_id: str
    name: str
    description: str
    price_minor: int
    currency: str
    image_url: str
    available: bool

    model_config = {"from_attributes": True}


class DishOut(MenuItemOut):
    """A menu item enriched with its restaurant name for dish-first browsing.

    ``order_count`` is the number of units of this dish that appear on
    successful orders; it is 0 when the dish has never been ordered and is used
    only for the "popular" sort. It is real data, never a placeholder.
    """

    restaurant_name: str = ""
    order_count: int = 0
