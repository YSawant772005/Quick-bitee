# QuickBitee — UI/UX Redesign Final Report

Date: 2026-10-15 · Scope: whole-app visual + interaction refresh of the Flutter
client (web + Android from one codebase) and additive backend support, without
changing existing API contracts or removing features.

---

## 1. Objective & outcome

Refreshed the QuickBitee client into a cohesive "Forest Green + Lime Green + Warm
Cream + realistic food photography" product, covering every customer screen and
the admin console, while preserving all functionality, the API contract, auth
flow, state management and models.

Outcome: **complete**. `flutter analyze` is clean, all widget/unit tests pass,
and `flutter build web` succeeds. Backend changes are additive only.

## 2. Design system

- Single source of truth: `frontend/lib/shared/theme.dart`.
- Palette: forest `#123B35`, deep `#0B2925`, lime `#B8E986`, cream `#F7F4EB`,
  white surfaces, text `#17231F` / `#6D7771`, border `#E6E8E0`, success
  `#218653`, warning `#E6A23C`, error `#D94B4B`, info `#2F6FB3`.
- Scales: spacing (4→64), radii (10/14/20/28/pill), three soft shadows,
  breakpoints (mobile <720, tablet 720–1079, desktop ≥1080).
- Typography: the platform default (Roboto) with a tighter, larger display ramp —
  no font dependency added.
- Icons: Material's rounded/outlined glyph set only. **No emoji as UI icons.**
- Honest chrome: gradients limited to brand/hero surfaces, no decorative controls.

## 3. Customer experience

- **Splash** — branded mark + spinner while the stored session restores.
- **Login** — responsive split layout (brand panel + form on desktop). Email/password
  validators preserved; inline error surface; tap-to-fill demo accounts.
- **Home** — photographic hero with search, real cuisine categories derived from
  restaurant data, "Popular right now" dish grid (real `/dishes` data), restaurant
  grid, value strip, footer, cart FAB.
- **Explore** (new) — combined search/filter/sort discovery over restaurants, with
  cuisine chips, "open now" toggle and sort; reacts to `?q=`/`?cuisine=` deep links.
- **Menu** — restaurant header, in-menu search, dish cards with add-to-cart and the
  single-restaurant replace-cart dialog.
- **Cart** — line items with images, quantity steppers, item total, checkout CTA.
- **Checkout** — items, delivery address (validated), simulated-payment notice, price
  breakdown, and a sticky bottom action bar so the total + "Place order" are always
  visible. Idempotency-key retry behaviour preserved.
- **Acknowledgement** — success illustration; real confirmed items + total fetched
  from the API; track / continue actions.
- **Order tracking** — status hero with live indicator, canonical progress stepper,
  real history activity log, item images, driver card, delivery address, failure
  banner, per-order notifications, pull-to-refresh, 2s polling until terminal,
  "Order again" (re-adds currently-available items via the real menu).
- **Order history** — image thumbnails resolved from the same product data as menus.
- **Notifications** — event-typed cards linking to the related order.
- **Profile** (new) — account identity, quick links, admin entry for admins, sign out.

## 4. Admin console

Role-protected (`/admin` guarded; backend `require_admin`). Desktop: persistent
sidebar + content; mobile: segmented Overview/Orders.

- **Overview** — KPI cards (revenue with sparkline, orders, active customers, AOV),
  14-day revenue area chart, orders-by-status bar chart, top dishes, operations
  pipeline (successful/failed/in-progress, outbox, retry backlog, quarantine).
- **Orders** — order-id search, status filter chips, responsive table (desktop) /
  cards (mobile), pagination, row → order tracking.
- All values are computed from real data; no fabricated metrics.

## 5. Responsive behaviour & accessibility

- Every screen uses `CustomerShell` (desktop top nav / mobile bottom nav) or a
  dedicated admin chrome; content is width-constrained on large screens.
- Verified at mobile/tablet/desktop widths via `flutter analyze`, tests and web build.
- Semantic labels on form fields; tooltips on icon-only actions; `ChoiceChip`/
  `SegmentedButton` for selection; charts have text fallbacks and labelled axes.
- Animations are limited to feedback (loading states, refresh, snackbars).

## 6. Backend changes (additive, backward-compatible)

No existing field, route or contract was changed; only additions:

- `schemas/catalog.py`: `DishOut`.
- `schemas/orders.py`: `OrderItemOut.image_url`, `OrderListItemOut.thumbnail_url`,
  `DailyRevenue`, `TopDish`, analytics fields on `AdminSummaryOut`.
- `api/v1/restaurants.py`: `GET /dishes` (search + `sort=name|popular`, paginated).
- `api/v1/orders.py`: populate item `image_url` and list `thumbnail_url`.
- `api/v1/admin.py`: real analytics aggregation (revenue, AOV, active customers,
  14-day series, top dishes) and thumbnails; sales = PAID/CONFIRMED/DRIVER_ASSIGNED.
- `services/catalog_service.py`: `item_image_map` helper.
- New tests: `tests/test_catalog.py`, `tests/test_admin.py`.

## 7. Images & content integrity

- Real, licensed photography in `backend/app/static/catalog/` (40 dishes + 8
  restaurants), served via the existing `/static` mount; authorship in `docs/IMAGES.md`.
- `AppImage` gives a branded, non-broken fallback for missing/slow images — no
  placeholder boxes or broken URLs.
- Order-history and tracking images come from product data, not guesses.
- Only real data is shown: no invented ratings, delivery ETAs, offers or fees.

## 8. Verification performed

| Check | Result |
|---|---|
| `flutter analyze` | 0 errors, 0 warnings (2 pre-existing `dart:html` infos) |
| `flutter test` | 9/9 pass (cart, checkout idempotency, login, tracking) |
| `flutter build web --no-pub` | built successfully |
| Backend `compileall` + `import app.main` + new-module imports | OK |
| Backend pytest | **not run** — Docker daemon down (no PostgreSQL/RabbitMQ) |

Two widget tests were updated for legitimate copy changes: the wordmark
`QuickBitee`, and the friendly status label `Out for delivery` (replacing raw
`DRIVER ASSIGNED`).

## 9. Known gaps, limitations & follow-ups

1. **No `DELIVERED` status** — `DRIVER_ASSIGNED` is terminal
   (`TERMINAL_STATUSES = {PAYMENT_FAILED, FAILED, DRIVER_ASSIGNED}`). The UI shows
   "Out for delivery" as the final happy-path stage rather than a fake "Delivered".
   Add a `DELIVERED` transition if a true delivery step is required.
2. **Backend tests unexecuted** — run `pytest` once Docker (PostgreSQL + RabbitMQ)
   is up; the new catalog/admin tests are included.
3. **Reference image** `docs/reference.png` could not be read by this model (no image
   input); the written spec was followed. A human should diff the result against it.
4. **Restaurant model is minimal** — only id/name/description/cuisine/image/available;
   no rating/ETA/offers, so none are displayed.
5. **Payments are simulated** — no method selection or real fees; checkout shows the
   item total and states the server confirms the final amount.
6. **API title** remains "QuickBite API" (FastAPI docs); only user-facing UI is
   branded "QuickBitee".
7. **Stale-doc note** — `docs/ui-interaction-inventory.md` predates the refresh;
   a header note explains the changed copy/line numbers and the two new screens.
8. **No new dependencies**; charts are hand-rolled `CustomPainter` widgets.
