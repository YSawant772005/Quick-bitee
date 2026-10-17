# 7. Backend Routing and Persistence

## Purpose

- This document explains how the FastAPI backend is organised.
- It shows how an HTTP request becomes database work and JSON back.
- It covers the models (tables) and the request/response schemas.

## Files involved

- `backend/app/main.py` — creates the app and includes the router.
- `backend/app/api/v1/__init__.py` — the top-level `/api/v1` router.
- `backend/app/api/v1/*.py` — one file per area: `auth`, `restaurants`, `promotions`, `orders`, `notifications`, `admin`.
- `backend/app/api/dependencies.py` — shared dependencies: auth check and pagination.
- `backend/app/schemas/` — Pydantic models for JSON shapes.
- `backend/app/models/` — SQLAlchemy models for tables.
- `backend/app/db/session.py` — gives each request a database session.

## How it works

1. `main.py` calls `app.include_router(api_router)`.
2. `api_router` has the prefix `/api/v1` and includes each area's router.
3. Each route function declares its inputs: path parameters, query parameters, a Pydantic body, and `Depends(...)` dependencies.
4. FastAPI validates all inputs and returns `422` if they are wrong.
5. Route functions call a service when the logic is complex, or query the database directly for simple reads.
6. The route returns a Pydantic model, which FastAPI converts to JSON.
7. Errors raised as `AppError` subclasses become JSON responses with a `code` and `message`.

## Routing map

`backend/app/api/v1/__init__.py`:

```python
api_router = APIRouter(prefix="/api/v1")
api_router.include_router(auth.router)
api_router.include_router(restaurants.router)
api_router.include_router(promotions.router)
api_router.include_router(orders.router)
api_router.include_router(notifications.router)
api_router.include_router(admin.router)
```

| File | Prefix | Endpoints |
|---|---|---|
| `auth.py` | `/auth` | `POST /login`, `GET /me` |
| `restaurants.py` | (none) | `GET /restaurants`, `/restaurants/{id}`, `/restaurants/{id}/menu`, `/dishes` |
| `promotions.py` | (none) | `GET /promotions` |
| `orders.py` | (none) | `POST /orders`, `GET /orders`, `/orders/{id}`, `/orders/{id}/history`, `/orders/{id}/notifications` |
| `notifications.py` | (none) | `GET /notifications` |
| `admin.py` | `/admin` | orders, summary, analytics, restaurants, menu-items, customers, deliveries |

There are also two routes defined directly in `main.py`: `GET /health/live` and `GET /health/ready`.

## Dependencies

`backend/app/api/dependencies.py`:

```python
async def get_current_user(
    token: str | None = Depends(oauth2_scheme),
    session: AsyncSession = Depends(get_session),
) -> User:
    if not token:
        raise UnauthorizedError("Authentication token is required.")
    claims = decode_access_token(token)
    user_id = claims.get("sub")
    ...
    user = (await session.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if user is None:
        raise UnauthorizedError("Account no longer exists.")
    return user
```

- `Depends(get_current_user)` is a reusable guard. Add it to any route to require login.
- `require_admin` builds on it and also checks the role.
- `get_session` gives each request its own database session, closed automatically afterwards.

## The database models

| Model file | Table | What it stores |
|---|---|---|
| `models/users.py` | `users` | Email, hashed password, role. |
| `models/catalog.py` | `restaurants` | Name, cuisine, availability, details. |
| `models/catalog.py` | `menu_items` | Dish name, price, image, availability. |
| `models/catalog.py` | `categories` | Menu sections and global tags. |
| `models/catalog.py` | `menu_item_categories` | Which dish has which category. |
| `models/orders.py` | `orders` | Status, total, address, version. |
| `models/orders.py` | `order_items` | A frozen snapshot of each ordered dish. |
| `models/orders.py` | `order_status_history` | One row per status change. |
| `models/orders.py` | `simulated_payments` | Fake payment result. |
| `models/orders.py` | `driver_assignments` | Fake driver for an order. |
| `models/orders.py` | `notifications` | Notification feed entries. |
| `models/orders.py` | `idempotency_records` | Replays for safe retries. |
| `models/messaging.py` | `outbox_events` | Events waiting to be published. |
| `models/messaging.py` | `processed_events` | Dedupe markers per consumer. |
| `models/messaging.py` | `retry_jobs` | Durable retry schedule. |
| `models/messaging.py` | `quarantine_records` | Events that can never be processed. |

### The `Order` model

`backend/app/models/orders.py`:

```python
class Order(UUIDMixin, TimestampMixin, Base):
    __tablename__ = "orders"

    customer_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    restaurant_id: Mapped[str] = mapped_column(ForeignKey("restaurants.id"))
    status: Mapped[str] = mapped_column(String(30), default="PENDING", index=True)
    total_minor: Mapped[int] = mapped_column(Integer)
    currency: Mapped[str] = mapped_column(CHAR(3), default="INR")
    delivery_address: Mapped[str] = mapped_column(Text)
    version: Mapped[int] = mapped_column(Integer, default=1)
    failure_reason: Mapped[str | None] = mapped_column(String(500), nullable=True)
```

- `version` counts how many times the order changed. Workers use it to detect stale events.
- `total_minor` stores money in the smallest unit (paise), so there are no rounding problems.

## Schemas (JSON shapes)

- Request bodies and responses are Pydantic models in `backend/app/schemas/`.
- `OrderCreateRequest` describes the checkout body.
- `OrderAcceptedResponse` describes the `202` response.
- `Paginated[T]` in `schemas/common.py` is the shared list envelope: `{items, page, page_size, total}`.
- FastAPI uses `response_model=...` to filter the response to exactly these fields.

## Error handling

`backend/app/main.py` registers three exception handlers:

- `AppError` → returns the defined status code with `{code, message, details, request_id}`.
- `RequestValidationError` → returns `422` with `code: "INVALID_REQUEST"` and the field errors.
- Any other `Exception` → returns `500` with `code: "INTERNAL_ERROR"`.

The status codes come from `backend/app/core/errors.py`:

| Class | HTTP status | Meaning |
|---|---|---|
| `UnauthorizedError` | 401 | Not signed in or bad token. |
| `ForbiddenError` | 403 | Signed in but not allowed. |
| `NotFoundError` | 404 | Missing resource. |
| `ConflictError` | 409 | Conflicts with existing state. |
| `InvalidRequestError` | 422 | Invalid data. |

## Data flow

- **Enters a route:** path/query parameters, a JSON body, and a header token.
- **The route does:** validate → check auth → call a service or query the database → return a schema.
- **The database:** reads or writes rows inside a session transaction.
- **Leaves the route:** a JSON response, or an error JSON with `code`, `message`, `details`, `request_id`.

## Example

- The Orders page calls `GET /api/v1/orders`.
- `list_orders` in `orders.py` counts the customer's orders, loads a page ordered by `created_at` descending, and enriches each row with restaurant name and item summary.
- It returns `Paginated[OrderListItemOut]`, which FastAPI serialises to JSON.

## What to remember

- Every endpoint lives under `/api/v1` and is grouped by area in `backend/app/api/v1/`.
- `Depends(get_current_user)` requires login; `Depends(require_admin)` requires the admin role.
- SQLAlchemy models map to tables; Pydantic schemas define the JSON.
- All errors come back in the same shape with a `code`, `message`, `details`, and `request_id`.
- Money is stored as an integer number of minor units.

## Builds on

- 2. Project Structure
- 3. Application Startup
- 4. Request and Data Flow
