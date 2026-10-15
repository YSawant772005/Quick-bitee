# QuickBitee UI/UX Redesign — working progress note

Status: in progress. Reference image at `docs/reference.png` could NOT be
viewed (model has no image input); design follows the written spec
(forest #123B35 + lime #B8E986 + cream #F7F4EB + real food photography).

## Environment
- Flutter present: `C:\flutter\bin\flutter.bat` (not on PATH).
- Docker installed but **daemon not running** → backend integration tests
  (need live PostgreSQL + RabbitMQ) cannot be run in this session.
- Frontend is one Flutter codebase (web + Android). "Website" = responsive
  Flutter web; "mobile app" = same code narrowed. Both redesigned together.

## Backend gaps found (addressed with additive, backward-compatible changes)
1. `OrderItemOut` had no `image_url` → order pages could not show dish images.
2. `OrderListItemOut` had no thumbnail → history couldn't show food images.
3. Admin had only counts, no revenue/customers/AOV/top-dish/time-series.
4. No global dish endpoint → home "popular dishes" / dish discovery.

## Changes
### Backend (additive only, existing API fields untouched)
- `schemas/catalog.py`: + `DishOut` (MenuItem fields + restaurant_name + order_count)
- `schemas/orders.py`: + `OrderItemOut.image_url`, + `OrderListItemOut.thumbnail_url`,
  + `DailyRevenue`, + `TopDish`, + analytics fields on `AdminSummaryOut`
- `api/v1/restaurants.py`: + `GET /dishes` (search + sort=name|popular, paginated)
- `api/v1/orders.py`: populate item image_url + list thumbnail_url
- `api/v1/admin.py`: thumbnail_url + real analytics aggregation

### Frontend
- `shared/theme.dart` — full design-token rewrite (forest/lime/cream), spacing/radius scale
- `shared/widgets.dart` — brand logo, AppImage upgrade, cards, chips, badges, empty/error
- `shared/layout.dart` — breakpoints, responsive chrome (desktop top nav + mobile bottom nav)
- `shared/charts.dart` — dependency-free CustomPainter sparkline/area/bar charts
- `features/explore/explore_screen.dart` — new discovery screen
- `features/profile/profile_screen.dart` — new account screen
- rewrote home, menu, cart, checkout + ack, order history, order detail (tracking),
  notifications, admin
- `router.dart` — tab routes + shell; `core/api_client.dart` + `models/models.dart` updates
- `web/index.html` — brand title, loading colours, favicon

## Done (whole-app refresh complete)
- All customer screens rewritten/added: home, explore, menu, cart, checkout +
  acknowledgement, order tracking, order history, notifications, profile, login.
- Admin console rewritten: KPI cards, 14-day revenue area chart, orders-by-status
  bar chart, top dishes, operations/pipeline health, searchable+paged orders table.
- `router.dart` — added `/explore` and `/profile`, wired `?q=`/`?cuisine=` into
  Explore, branded `/splash`; role guard for `/admin` preserved.
- App title + `web/index.html` + manifest copy rebranded to **QuickBitee**.
- Charts are dependency-free (`CustomPainter`) — no new pub packages added.

## Verification performed this session
- `flutter analyze` → 0 errors, 0 warnings (only 2 pre-existing `dart:html`
  deprecation infos in `core/web_origin_web.dart`).
- `flutter test` → all 9 tests pass (cart, checkout idempotency, login, tracking).
  Two tests were updated to match new UI copy (`QuickBitee` wordmark; friendly
  status label "Out for delivery" instead of the raw `DRIVER ASSIGNED`).
- `flutter build web --no-pub` → built successfully (`build/web`).
- Backend: `compileall` + `import app.main` + imports of all new/changed modules
  all succeed.

## Not done / blocked
- Backend **pytest could not run**: Docker daemon is not running, so PostgreSQL and
  RabbitMQ are unavailable. New tests (`tests/test_catalog.py`, `tests/test_admin.py`)
  are written but unexecuted.
- Exact pixel fidelity to `docs/reference.png` is impossible for this model
  (no image input); the written spec was followed instead.

## Known backend gaps (documented, not "fixed" to keep contracts stable)
- There is **no `DELIVERED` status**: `DRIVER_ASSIGNED` is the terminal success
  state (`TERMINAL_STATUSES = {PAYMENT_FAILED, FAILED, DRIVER_ASSIGNED}`). The UI
  therefore shows "Out for delivery" as the final happy-path stage rather than a
  fabricated "Delivered" step.
- `RestaurantOut` exposes only id/name/description/cuisine/image_url/available —
  no rating, delivery ETA, or offers — so no such data is shown anywhere.
- Payment is a simulated worker; no payment-method selection or real fees exist,
  so checkout shows only the item total and says the server confirms the final
  amount.
