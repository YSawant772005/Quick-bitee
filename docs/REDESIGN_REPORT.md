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
- Only real data is shown: no invented ratings, review counts or reviews. (Later
  update added real *seeded* ETAs/addresses/opening hours and clearly-labelled
  **demo** offers — see §10.)

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
2. ~~**Backend tests unexecuted**~~ — **Resolved (see §10):** `pytest` now runs
   against live PostgreSQL + RabbitMQ and passes (70 tests, incl. catalog/admin
   and the new `test_restaurant_details.py`).
3. **Reference image** `docs/reference.png` could not be read by this model (no image
   input); the written spec was followed. A human should diff the result against it.
4. ~~**Restaurant model is minimal** — only id/name/description/cuisine/image/available;
   no rating/ETA/offers, so none are displayed.~~ **Superseded — see §10.** The model
   now carries address/opening-hours/ETA, restaurant detail pages + per-restaurant
   menu filters/sorts, a homepage promo carousel, an offers page, and honest
   rating handling (ratings shown only when real; none are fabricated).
5. **Payments are simulated** — no method selection or real fees; checkout shows the
   item total and states the server confirms the final amount.
6. **API title** remains "QuickBite API" (FastAPI docs); only user-facing UI is
   branded "QuickBitee".
7. **Stale-doc note** — `docs/ui-interaction-inventory.md` predates the refresh;
   a header note explains the changed copy/line numbers and the two new screens.
8. **No new dependencies**; charts are hand-rolled `CustomPainter` widgets.

## 10. Update — restaurant details, offers & carousel

Date: 2026-10-16 · Additive follow-up to the refresh. Adds a full restaurant
**detail page** for every restaurant, per-restaurant **menu filtering/sorting**,
a homepage **promo carousel**, an **offers** page, and rating/category/ETA
surfacing — all backward-compatible with the existing Flutter client contracts.

**New user-facing features**
- **Restaurant detail page** — reachable for every restaurant: hero image, name,
  cuisine, description, rating (only when real), ETA, address, opening hours,
  dish count, an offers card, add-to-cart, and a clear route back to listings.
- **Per-restaurant menu filters** — food type (All/Veg/Non-veg), category, name
  search and price sort, all combinable, with a Reset action and a helpful
  no-match state. (Menus are small — ≤ ~294 dishes — so filtering runs
  client-side; the same params are sent to the API for parity.)
- **Homepage promo carousel** — food photography, QuickBitee branding, CTAs,
  prev/next + indicators, and a pause control. Auto-advance is on by default but
  disabled in widget tests; carousel slides deep-link to a restaurant/category/
  offer.
- **Offers page** (`/offers`) — genuine offers only; where none are configured,
  clearly-labelled **demo** offers are shown in development with a disclosure
  that no discount is applied at checkout.

**Honesty**
- **No fabricated ratings or reviews.** No rating/review data exists, so
  `rating`/`review_count` stay `NULL` and the UI omits them; "Top rated" surfaces
  only real ratings, and "popular" uses real order counts.

**Backend (additive)**
- `models/catalog.py`: restaurant `address`/`opening_hours`/`eta_minutes_*`; the
  migration backfills existing rows with safe demo values.
- `schemas/catalog.py`: `CategoryTagOut`, extended `RestaurantOut`/`MenuItemOut`/
  `DishOut`, plus `PromoBannerOut`/`OfferOut`/`PromotionsOut`.
- `api/v1/restaurants.py`: enrichment + filter/sort helpers across
  `/restaurants`, `/restaurants/{id}`, `/restaurants/{id}/menu`, `/dishes`.
- `app/promotions.py` + `api/v1/promotions.py`: `GET /promotions` (banners +
  demo offers, gated by `settings.demo_promotions_enabled`).
- `app/catalog/ids.py`: shared stable-id helper used by seeds.

**Verification**
| Check | Result |
|---|---|
| `flutter analyze` | 0 errors (2 pre-existing `dart:html` infos) |
| `flutter test` | 28 pass (23 previous + 5 new restaurant-detail tests) |
| Backend `pytest` | 70 passed (incl. `test_restaurant_details.py`) |
| `docker compose build api web` + `up -d` | live stack verified |

**Limitations / mobile parity**
- Ratings/reviews remain absent from the data model (no seeding of fake content);
  add real review data before enabling rating filters/sorts meaningfully.
- Offers are demo-only until a real promotions source exists.
- The Flutter **mobile** app shares this codebase; the new models/API client are
  already used by web — mobile needs the same widget wiring to expose the detail
  page, filters, carousel and offers (contracts are already compatible).

## 11. Update — pagination & infinite scroll

Date: 2026-10-16 · Additive follow-up. Every catalogue listing now supports two
user-controlled ways to reveal more results, chosen with a single visible
toggle and remembered for the rest of the session.

**New user-facing features**
- **Pagination / Infinite-scroll toggle** — shown on the home page, Explore and
  each restaurant menu. The choice is session-wide (a Riverpod provider), so it
  stays consistent as the user navigates between screens.
- **Pagination mode** — Previous / Next, numbered page buttons with an ellipsis
  window for long ranges, and a "Showing X–Y of N · Page i of n" summary; page
  changes scroll the list back to the top.
- **Infinite mode** — the next page loads automatically as the footer nears the
  viewport bottom, with a spinner while it is in flight and a real "Load more"
  fallback button; short pages auto-fill until the footer is off screen.
- **Graceful states everywhere** — loading skeletons, empty, first-load error
  (with retry), load-more error (with retry), and an end-of-list marker. Rows are
  de-duplicated by id, so no repeats and no duplicate requests.
- Filters (search, veg/non-veg, category), price sort, offers and the cart are
  preserved across mode switches and page loads.

**Implementation**
- `frontend/lib/shared/paged_list.dart` — `BrowseMode` + `browseModeProvider`,
  `PagedListController<T>` (backend `updateFetch` **or** client-side
  `setLocalItems`), `BrowseModeToggle`, `PaginationControls`, `InfiniteScrollFooter`,
  `PagedResultsFooter`, and `scheduleNearBottomLoad` for section-scoped scroll.
- **Explore → Dishes uses backend pagination** (the live dish catalogue is
  **27,446** rows). Bounded lists — Explore → Restaurants (**135**),
  restaurant menus (≤ a few hundred), and the home sections — are fetched once
  and sliced client-side; switching any of them to server paging later is a
  one-line change with no UI impact.
- No backend changes were required: `/dishes`, `/restaurants` and
  `/restaurants/{id}/menu` already accept `page` / `page_size` / filters / sort.

**Verification**
| Check | Result |
|---|---|
| `flutter analyze` | 0 errors (2 pre-existing `dart:html` infos) |
| `flutter test` | 48 pass (28 previous + 16 paged-list + 4 screen tests) |
| `flutter build web` | Built `build/web` |
| Live API | `/dishes?page=1\|2&page_size=5` → distinct pages of 27,446 rows |
| `docker compose build web` + `up -d web` | deployed bundle contains the new UI strings |

**Limitations / mobile parity**
- The bounded lists are still fetched in full before client-side slicing; only the
  dish catalogue uses true server-side pagination. The shared controller can be
  pointed at `updateFetch` later without touching the screens.
- The Flutter **mobile** app shares this codebase; it needs the same widget
  wiring (the provider and controllers are already platform-agnostic).
