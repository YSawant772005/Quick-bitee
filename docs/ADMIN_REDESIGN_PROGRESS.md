# Admin dashboard redesign — working progress note

Goal: separate the admin console from the customer app architecturally
(dedicated `AdminShell`), and make it a professional operational dashboard
backed by real data.

## Inspection findings (why customer & admin looked similar)
- Only one shell existed (`CustomerShell`); the admin screen had its own
  hand-rolled sidebar inside a single file, but reused the customer canvas
  colour, gutters and card language.
- Admin nav was only Overview/Orders — everything else was missing.
- `/admin/summary` had **no date-range support** (fixed 14-day series + all-time
  totals) and **no period comparison**.
- `/admin/orders` had **no customer info, no payment status, no date filter,
  no sort** and used an **N+1 restaurant lookup** inside the row loop.
- **No admin endpoints at all** for restaurants, menu, customers or deliveries.
- **No admin status-transition endpoint exists** — the order state machine is
  advanced only by background workers (`payment_worker`, consumers). Therefore
  no transition controls will be invented.

## Role / data model reality check
- Roles: `customer` | `admin` only. No restaurant-owner or delivery-partner roles.
- Tables: users, restaurants, menu_items, orders, order_items,
  order_status_history, simulated_payments, driver_assignments, notifications,
  idempotency_records, outbox_events, retry_jobs, quarantine_records.
- **Not supported (will be documented as gaps, NOT faked):**
  Offers & Coupons (no model/endpoint), Reviews (no model/endpoint).
- Supported admin modules: Overview, Orders, Restaurants, Menu, Customers,
  Deliveries (read-only, real driver assignments), Analytics, Settings (read-only
  system info, no secrets).

## Backend plan (all additive / backward compatible)
- `schemas/orders.py`: + `TopDish.image_url/.restaurant_name/.menu_item_id`,
  + `TopRestaurant`, `AttentionItem`, `MetricDelta`, `PeriodComparison`,
  + optional analytics fields on `AdminSummaryOut`.
- `schemas/admin.py` (new): admin-only list/detail/update models.
- `api/v1/admin.py`:
  - `/admin/orders` + `date_from`, `date_to`, `sort`, customer+payment join,
    joins instead of N+1.
  - `/admin/orders/{id}` (new): full detail + customer + payment + timeline.
  - `/admin/summary` + `date_from`, `date_to`, `granularity`, comparison,
    attention items, top restaurants, catalogue counts.
  - `/admin/restaurants` (new) + `PATCH /admin/restaurants/{id}`.
  - `/admin/menu-items` (new) + `PATCH /admin/menu-items/{id}`.
  - `/admin/customers` (new, aggregated).
  - `/admin/deliveries` (new, active driver assignments).
  - `/admin/analytics` (new, deeper reporting).

## Frontend plan
- `features/admin/admin_shell.dart` — dedicated dark-sidebar AdminShell
  (desktop sidebar + header, mobile drawer). Not shared with customer.
- `state/admin_range_controller.dart` — shared date-range notifier.
- Pages: overview, orders (+detail), restaurants, menu, customers, deliveries,
  analytics, settings.
- Router: `ShellRoute` under `/admin` (all role-guarded).

## Status
- [x] Inspection
- [x] Backend schemas (`schemas/admin.py` new; `schemas/orders.py` extended)
- [x] Backend endpoints (all 10 admin routes, `require_admin` on each)
- [x] Backend tests
- [x] Frontend shell + range state (`AdminShell`, `adminRangeProvider`)
- [x] Frontend pages (overview, orders, order detail, restaurants, menu,
      customers, deliveries, analytics, settings)
- [x] Router (`ShellRoute` + role guard on every `/admin` subroute)
- [x] Verification (see below)

## Verification results
- Backend `pytest -q` — **55 passed** (includes 20 in `tests/test_admin.py`).
- `flutter analyze --no-pub` — **2 issues**, both pre-existing `dart:html`
  infos in `lib/core/web_origin_web.dart` unrelated to this work. 0 errors,
  0 warnings.
- `flutter test --no-pub` — **15 passed** (9 pre-existing + 6 new in
  `test/admin_console_test.dart`).
- `flutter build web --no-pub` — **succeeded** (`√ Built build\web`); emits the
  same pre-existing `dart:html`/`cupertino_icons` warnings as before.
- Live HTTP verification against the rebuilt `quickbite-api` container
  (`docker compose build api && up -d api`) — **28/28 checks passed**:
  anonymous → 401, admin login → 200, all 7 admin GETs → 200, inverted
  date range → 422, customer on all 7 admin routes → 403, customer
  `/auth/me` + `/orders` → 200, admin restaurant/menu `PATCH` → 200,
  customer `PATCH` → 403. Summary echoed the requested range
  (`2026-10-09..2026-10-15`) and returned 7 real daily buckets.

### New `test/admin_console_test.dart` (6 tests, real router + stubbed API)
1. Admin console renders its own shell/sidebar/KPIs, omits unsupported modules
   (`Offers & Coupons`, `Reviews`), contains no customer chrome, and actually
   queries `/admin/summary` + `/admin/orders`.
2. Changing the reporting period (Last 7 → Last 30 → Today) re-queries both
   `/admin/summary` and `/admin/orders` with the new `date_from`/`date_to`.
3. Orders search text and status filter are sent server-side (`search`,
   `status`, `page=1` reset).
4. A `customer` session mounting `/admin` is redirected to the customer app and
   never calls any admin endpoint.
5. At a 390×844 phone viewport the console has no drawer rail, the drawer nav
   opens from the menu button, and nothing overflows.
6. Tapping **View** on an order row loads `/admin/orders/{id}` and renders the
   detail view (customer, address, line items, totals, timeline) with no
   overflow.

## Fixed along the way
- `_bucket_days` condition inverted (day granularity was month-bucketed).
- Customer desktop header search was a fixed-width Row child that overflowed by
  21px at 1440w — wrapped in `Flexible` (`shared/layout.dart`).
- `AdminDropdown`/menu dropdown needed `isExpanded: true` to avoid RenderFlex
  overflow inside their fixed widths.
- **`/login` bounced every signed-in user to `/` (the customer homepage).**
  `router.dart` had `if (location == '/login' || location == '/splash') return '/';`
  unconditionally, so a successful **admin** login landed on the customer
  homepage (Home/Explore/Orders/Profile/notifications/cart), and an
  authenticated admin re-entering `/login` was again dumped there. Since the
  customer shell has no admin nav (only a role-gated Profile tile), the console
  looked unreachable. The backend was **not** at fault — `POST /auth/login`
  returns `"role":"admin"` and `User.fromJson` parses `role` correctly.
  Fixed by making the landing role-aware: `return isAdmin ? '/admin' : '/';`
  (non-admins are still blocked from `/admin` by the unchanged guard).
  Covered by the 5 tests in `test/routing_test.dart`.
- `AdminPage` content was an unscrollable Column — now wraps in
  `SingleChildScrollView`. The header now keeps the page body at full width
  (title + date-range/refresh share one line; below 860px they stack and the
  controls scroll sideways), instead of forcing the controls into a fixed-width
  Row beside a shrinking body (that Row overflowed by 231px at 390w, and an
  earlier 60/40 split starved the orders table to 616px and overflowed it).

## Known gaps (documented, never faked)
- No admin status-transition endpoint: the order state machine advances only
  via background workers. Surfaced in Settings + order-detail notes; no
  transition buttons exist anywhere.
- Offers & Coupons and Reviews: no backend model/endpoint → modules not offered
  in the sidebar.
- Restaurants/menu items: no create/delete endpoints → management pages are
  edit/availability only, no "Add" buttons.
- `Restaurant.updated_at` / `MenuItem.updated_at` do not exist → not shown.
