# 12. Admin Dashboard Workflow

## Purpose

- This document explains the admin console.
- It shows which endpoints power each admin screen.
- It explains the reporting rules (what counts as revenue, how periods work).

## Files involved

Frontend:

- `frontend/lib/features/admin/admin_shell.dart` — sidebar, header, and the route list.
- `frontend/lib/features/admin/overview_page.dart` — summary metrics.
- `frontend/lib/features/admin/orders_page.dart` and `order_detail_page.dart` — order list and detail.
- `frontend/lib/features/admin/restaurants_page.dart`, `menu_page.dart` — catalogue management.
- `frontend/lib/features/admin/customers_page.dart`, `deliveries_page.dart`.
- `frontend/lib/features/admin/analytics_page.dart`, `settings_page.dart`.
- `frontend/lib/state/admin_range_controller.dart` — the shared date-range filter.
- `frontend/lib/core/api_client.dart` — the `admin*` methods.

Backend:

- `backend/app/api/v1/admin.py` — every admin endpoint, all behind `require_admin`.

## How it works

### Access control

1. The router redirect sends non-admins away from any `/admin...` path.
2. Every admin endpoint uses `admin: User = Depends(require_admin)`.
3. So even a direct API call by a customer returns `403`.

### The admin shell

`frontend/lib/features/admin/admin_shell.dart` defines the sidebar:

- Overview `/admin`, Orders `/admin/orders`, Restaurants `/admin/restaurants`, Menu Management `/admin/menu`, Customers `/admin/customers`, Deliveries `/admin/deliveries`, Analytics `/admin/analytics`, Settings `/admin/settings`.
- `adminShowsDateRange(...)` returns true only for Overview and Analytics, so the date picker only appears where it matters.

### The Overview screen

1. It calls `api.adminSummary(dateFrom, dateTo, granularity)`.
2. The backend returns status counts, revenue, order counts, active customers, average order value, and an attention list.
3. If a period is set, it also returns a comparison with the previous equal-length period.

`backend/app/api/v1/admin.py`:

```python
@router.get("/summary", response_model=AdminSummaryOut)
async def admin_summary(
    date_from: str | None = Query(default=None),
    date_to: str | None = Query(default=None),
    granularity: str = Query(default="day", pattern="^(day|week|month)$"),
    session: AsyncSession = Depends(get_session),
    admin: User = Depends(require_admin),
) -> AdminSummaryOut:
    start, end = _period_bounds(date_from, date_to)
    period_filters = _created_filters(start, end)
    ...
    total_revenue = (
        await session.execute(
            select(func.coalesce(func.sum(Order.total_minor), 0)).where(
                Order.status.in_(SALES_STATUSES), *period_filters
            )
        )
    ).scalar_one()
```

- `SALES_STATUSES` is `PAID`, `CONFIRMED`, `DRIVER_ASSIGNED`.
- Pending, failed, and cancelled orders never count as revenue.
- `granularity` is limited to `day`, `week`, or `month` by the pattern.

### The Orders screen

1. It calls `api.adminOrders(...)` with `status`, `search`, `sort`, and the date range.
2. The list shows the customer email, total, and status.
3. Opening an order calls `api.adminOrder(id)` for the full detail, including payment info and the status timeline.

### Catalogue management

- `api.adminRestaurants(...)` lists restaurants; `api.adminUpdateRestaurant(id, ...)` toggles availability or edits name, description, cuisine, and image.
- `api.adminMenuItems(...)` lists dishes; `api.adminUpdateMenuItem(id, ...)` toggles availability or edits price and details.

### Customers and deliveries

- `api.adminCustomers(...)` aggregates customers and their order counts.
- `api.adminDeliveries(...)` lists real `driver_assignments` rows joined to their orders.

### Analytics

- `api.adminAnalytics(...)` returns bucketed rows for charts, grouped in SQL by the chosen granularity.

## Admin endpoint map

| Screen | Endpoint |
|---|---|
| Overview | `GET /api/v1/admin/summary` |
| Analytics | `GET /api/v1/admin/analytics` |
| Orders | `GET /api/v1/admin/orders` |
| Order detail | `GET /api/v1/admin/orders/{order_id}` |
| Restaurants | `GET /api/v1/admin/restaurants`, `PATCH /api/v1/admin/restaurants/{restaurant_id}` |
| Menu Management | `GET /api/v1/admin/menu-items`, `PATCH /api/v1/admin/menu-items/{item_id}` |
| Customers | `GET /api/v1/admin/customers` |
| Deliveries | `GET /api/v1/admin/deliveries` |

## Data flow

- **Enters the endpoints:** the admin token, query parameters (`status`, `search`, `date_from`, `date_to`, `granularity`, `page`, `page_size`), and for `PATCH` bodies the fields to change.
- **The database reads:** `orders`, `order_items`, `users`, `restaurants`, `menu_items`, `driver_assignments`, `simulated_payments`, `order_status_history`, plus `outbox_events`, `retry_jobs`, and `quarantine_records` for the attention list.
- **The database writes (PATCH only):** a `restaurants` or `menu_items` row.
- **Leaves the endpoints:** typed admin schemas, for example `AdminSummaryOut` and `Paginated[AdminOrderListItemOut]`.

## Example

- The admin signs in and lands on `/admin`.
- The Overview page calls `GET /api/v1/admin/summary?date_from=2026-10-01&date_to=2026-10-17`.
- The backend counts statuses, sums revenue only for realised sales, and compares with the previous equal-length window.
- The admin clicks **Orders**, filters by `PAID`, and opens one order to see its payment and timeline.
- The admin opens **Menu Management** and marks a dish unavailable. That dish then disappears from customer browsing because the catalogue filters on `available`.

## What to remember

- The admin console lives entirely under `/admin` and is protected twice: in the router and in the API.
- `admin.py` is one file with all admin endpoints, each using `require_admin`.
- Revenue counts only `PAID`, `CONFIRMED`, and `DRIVER_ASSIGNED`.
- The Overview and Analytics screens share one date-range filter from `admin_range_controller.dart`.
- Aggregations are done in SQL, so the endpoints stay fast.

## Builds on

- 5. Frontend Routing and State
- 6. API Communication
- 7. Backend Routing and Persistence
- 8. Authentication and Authorization
