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
