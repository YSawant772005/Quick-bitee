from pydantic import BaseModel


class CategoryTagOut(BaseModel):
    """A category label attached to a dish.

    ``kind`` is ``"menu"`` for the restaurant's own menu section and
    ``"global"`` for cross-restaurant taxonomy (cuisine, diet, topic), so the
    client can tell a section header from a discovery tag.
    """

    slug: str
    name: str
    kind: str = "global"


class RestaurantOut(BaseModel):
    """Catalogue listing/detail payload for one restaurant.

    ``rating`` / ``review_count`` are ``None`` while the platform has no review
    data — clients must hide them rather than render placeholders. Popularity
    fields are real: ``order_count`` counts realised orders (paid/confirmed/
    delivered) and ``dish_count`` counts published menu items.

    ``categories`` are the restaurant's most common global food tags (real
    data) and ``offers`` the labels of configured promotions naming it.
    """

    id: str
    name: str
    description: str
    cuisine: str
    image_url: str
    available: bool
    address: str = ""
    opening_hours: str = ""
    eta_minutes_min: int | None = None
    eta_minutes_max: int | None = None
    rating: float | None = None
    review_count: int | None = None
    order_count: int = 0
    dish_count: int = 0
    categories: list[str] = []
    offers: list[str] = []

    model_config = {"from_attributes": True}


class MenuItemOut(BaseModel):
    """One dish.

    ``tags`` carries the dish's categories (menu section + global tags) so the
    client can offer category filters and derive the veg/non-veg indicator
    without extra requests. ``is_veg`` is ``None`` when the dish carries no
    diet tag (nothing may be assumed). ``order_count`` is realised units sold
    and feeds the "top ordered" quick filter; 0 means never ordered.
    """

    id: str
    restaurant_id: str
    name: str
    description: str
    price_minor: int
    currency: str
    image_url: str
    available: bool
    is_veg: bool | None = None
    tags: list[CategoryTagOut] = []
    order_count: int = 0

    model_config = {"from_attributes": True}


class DishOut(MenuItemOut):
    """A menu item enriched with its restaurant name for dish-first browsing.

    ``order_count`` is the number of units of this dish that appear on
    successful orders; it is 0 when the dish has never been ordered and is used
    only for the "popular" sort. It is real data, never a placeholder.
    """

    restaurant_name: str = ""


class PromoBannerOut(BaseModel):
    """One homepage/promotions banner.

    ``badge`` is ``"Demo offer"`` for promotions that only exist in the
    development catalogue; ``None`` for genuine discovery banners. ``cta`` is a
    structured target ({"type": "restaurant", ...}) and ``target`` the same
    thing as an in-app route for clients that prefer strings.
    """

    id: str
    title: str
    subtitle: str
    image_url: str
    cta_label: str
    target: str
    cta: dict = {}
    accent: str | None = None
    badge: str | None = None
    restaurant_id: str | None = None
    is_demo: bool = False


class OfferOut(BaseModel):
    """One entry of the offers page.

    ``disclosure`` states in plain text that the promotion applies no discount
    at checkout; clients must render it rather than imply a real price cut.
    """

    id: str
    title: str
    description: str = ""
    kind: str = "general"
    image_url: str = ""
    cta_label: str = ""
    target: str = "/offers"
    cta: dict = {}
    accent: str | None = None
    badge: str | None = None
    disclosure: str | None = None
    is_demo: bool = False


class PromotionsOut(BaseModel):
    """Everything the storefront needs to render promotions in one payload."""

    banners: list[PromoBannerOut] = []
    offers: list[OfferOut] = []
