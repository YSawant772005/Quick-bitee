# 11. Catalogue and Search Workflow

## Purpose

- This document explains how a customer finds food.
- It covers the Home screen, the Explore (search) screen, and the menu screen.
- It explains the backend query filters and sorting.

## Files involved

Frontend:

- `frontend/lib/features/home/home_screen.dart` — restaurant discovery, promo carousel, popular dishes.
- `frontend/lib/features/explore/explore_screen.dart` — search, filters, sorting.
- `frontend/lib/features/menu/menu_screen.dart` — one restaurant's menu.
- `frontend/lib/features/offers/offers_screen.dart` — demo promotions.
- `frontend/lib/core/api_client.dart` — `restaurants`, `allRestaurants`, `menu`, `allMenu`, `dishes`, `allDishes`, `promotions`.

Backend:

- `backend/app/api/v1/restaurants.py` — `list_restaurants`, `get_restaurant`, `list_menu`, `list_dishes`.
- `backend/app/api/v1/promotions.py` — `GET /promotions`.
- `backend/app/promotions.py` — the demo promotion data.
- `backend/app/models/catalog.py` — `Restaurant`, `MenuItem`, `Category`, `MenuItemCategory`.

## How it works

### Home screen

1. On load, `home_screen.dart` calls `api.allRestaurants()` and `api.promotions()`.
2. It shows a promo carousel, a category strip, and restaurant cards.
3. Another call uses `api.dishes(sort: 'popular')` for the popular-dishes carousel.
4. If promotions fail, it falls back to an empty `Promotions`, because promotions are not essential.

### Explore screen

1. The user types in the search box or taps a chip.
2. `_reload()` calls `api.allRestaurants(...)` with `search`, `category`, `foodType`, and `sort`.
3. In dish view it calls `api.dishes(...)` with the same filters.
4. It loads all pages so no result is dropped, then applies the "open only" filter locally.

### Menu screen

1. Opening `/restaurant/:id` reads the id from the route.
2. The screen calls `api.restaurantDetail(id)` and `api.allMenu(id)`.
3. Add-to-cart uses `cartProvider.add(item)`, which blocks mixing restaurants.

### Backend query

1. `list_restaurants` builds a list of filters.
2. It always requires `Restaurant.available.is_(True)`.
3. `search` matches the restaurant name.
4. `category` matches the cuisine **or** any global category tag on the restaurant's dishes.
5. `food_type` filters by the vegetarian / non-vegetarian global tag.
6. Sorting: `popular` uses real units sold; `rating`, `eta`, `newest`, and `name` are the others.

`backend/app/api/v1/restaurants.py`:

```python
@router.get("/restaurants", response_model=Paginated[RestaurantOut])
async def list_restaurants(
    search: str | None = Query(default=None, max_length=120),
    category: str | None = Query(default=None, max_length=60),
    food_type: str | None = Query(default=None, pattern=FOOD_TYPE_PATTERN),
    sort: str = Query(default="name", pattern=RESTAURANT_SORT_PATTERN),
    params: PageParams = Depends(page_params),
    session: AsyncSession = Depends(get_session),
    current_user: User = Depends(get_current_user),
) -> Paginated[RestaurantOut]:
```

- Every filter is optional.
- `Query(pattern=...)` rejects invalid values automatically, so `sort=banana` returns `422`.
- `current_user = Depends(get_current_user)` means browsing requires a signed-in user.

### Real popularity, not fake numbers

```python
SALES_STATUSES = ("PAID", "CONFIRMED", "DRIVER_ASSIGNED")
```

- "Popular" counts only orders that were actually paid and confirmed.
- A pending or failed order never counts.
- Restaurants with no rating data sort last instead of showing an invented score.

### Enrichment

- `_enrich_restaurants(...)` adds dish count, real order count, up to three category labels, and configured demo offers.
- `_enrich_menu_items(...)` adds category tags, a veg/non-veg indicator only when the data says so, and the real order count.
- These use batch queries to avoid the "N+1 query" problem (one query per row).

### Promotions

- `backend/app/promotions.py` serves clearly-labelled demo banners and offers.
- They are only exposed outside production (`settings.demo_promotions_enabled`).
- Every promotion carries `is_demo` so the client can show a "Demo offer" badge.
- They never claim a discount that checkout does not apply.

## Data flow

- **Enters `GET /restaurants`:** query parameters `search`, `category`, `food_type`, `sort`, `page`, `page_size`.
- **The database reads:** `restaurants`, plus joined counts from `menu_items`, `order_items`, `orders`, `categories`, `menu_item_categories`.
- **Leaves the endpoint:** `{items, page, page_size, total}` where each item is a `RestaurantOut`.
- **Enters `GET /dishes`:** similar filters plus `restaurant_id`.
- **Leaves `GET /dishes`:** `DishOut` items with `restaurant_name`, `tags`, `is_veg`, and `order_count`.
- **The app does:** parses JSON into `Restaurant`, `MenuItem`, or `Dish` and renders cards.

## Example

- The user opens Explore and types "biryani".
- The app calls `GET /api/v1/dishes?page=1&page_size=100&sort=popular&search=biryani`.
- The backend matches the word against dish names and restaurant names, counts real units sold, and joins the restaurant name.
- The screen shows matching dishes from every restaurant, most popular first.
- If the user also picks `food_type=veg`, the query keeps only dishes tagged `vegetarian`.

## What to remember

- The catalogue is served by `backend/app/api/v1/restaurants.py` under `/restaurants` and `/dishes`.
- Filters are optional query parameters validated by FastAPI patterns.
- "Popular" and order counts come from real paid orders, never invented values.
- The frontend loads all pages (`allRestaurants`, `allMenu`, `allDishes`) so nothing is silently dropped.
- Promotions are clearly-labelled demos that apply no real discount.

## Builds on

- 2. Project Structure
- 5. Frontend Routing and State
- 6. API Communication
- 7. Backend Routing and Persistence
