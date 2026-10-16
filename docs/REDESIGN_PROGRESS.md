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
  *(Superseded — see "Update: restaurant details, offers, carousel" below.)*
- Payment is a simulated worker; no payment-method selection or real fees exist,
  so checkout shows only the item total and says the server confirms the final
  amount.

---

## Update: restaurant details, offers, carousel

Status: done. Adds a full restaurant **detail page** for every restaurant,
per-restaurant **menu filtering/sorting**, a homepage **promo carousel**,
**offers** surfaced honestly, and **ratings/category/ETA** on cards — all
additive and backward-compatible with the Flutter client contracts.

### Data model & seed (additive)
- `models/catalog.py`: `Restaurant` gains nullable-but-defaulted `address`,
  `opening_hours`, `eta_minutes_min`/`eta_minutes_max`.
- Migration `alembic/versions/c5a1e2b47d90_add_restaurant_details.py` adds the
  columns and **backfills** existing rows (safe demo values, never a real-world
  address).
- `app/catalog/ids.py`: shared `stable_id(*parts)` + namespace, used by both
  `app/seed.py` and `scripts/seed_catalogue.py` so ids stay consistent.
- `app/seed.py`: the 8 legacy restaurants (40 dishes) are tagged idempotently and
  each gets one `kind='menu'` section (slug `menu`, "Full menu").
- Diet tags **are** the `vegetarian`/`non-vegetarian` global categories — there is
  no `is_veg` column. `is_veg` is derived per dish; both/neither tag ⇒ `null`
  (never guessed).

### Backend endpoints
- `schemas/catalog.py`: `CategoryTagOut`, extended `RestaurantOut`, `MenuItemOut`,
  `DishOut`, `PromoBannerOut`, `OfferOut`, `PromotionsOut`.
- `api/v1/restaurants.py`: enrichment + filter/sort helpers; `/restaurants`
  (food-type + sort), `/restaurants/{id}`, `/restaurants/{id}/menu`
  (search/category/food_type/sort), `/dishes` (category/food_type).
- `app/promotions.py`: 6 banners + 3 **demo** offers + `offers_for_restaurant()`,
  gated by `settings.demo_promotions_enabled` (True unless `APP_ENV=production`);
  every offer is badged "Demo offer" with a `disclosure` stating no discount is
  applied at checkout.
- `api/v1/promotions.py`: `GET /promotions` (registered in `api/v1/__init__.py`).

### Ratings & popularity (no fabrication)
- No rating/review data exists in the DB, so `rating`/`review_count` stay `NULL`
  and the UI omits them entirely (`hasRating`); ratings are never invented.
- "Top rated" sections/rows only render when real ratings exist; "popular" uses
  real order counts (`SALES_STATUSES = PAID, CONFIRMED, DRIVER_ASSIGNED`).

### Frontend
- `models/models.dart`: `CategoryTag`, extended `Restaurant`/`MenuItem`/`Dish`,
  `PromoBanner`/`Offer`/`Promotions`.
- `core/api_client.dart`: `restaurants`/`allRestaurants`, `restaurantDetail(id)`,
  `menu`/`allMenu`, `dishes`/`allDishes`, `promotions()`.
- `shared/cards.dart`: `VegMarker`, `RatingPill`, enhanced `RestaurantCard`
  (rating only when real, ETA, categories, "Demo offer" badge, dish count),
  `DishCard` (`isVeg`/`tags`), `DishCardData`, shared `DishGrid`.
- `shared/promo_carousel.dart` (new): PageView carousel, prev/next, indicators,
  pause toggle, demo badge + disclosure, route CTA. Auto-advance is gated by the
  static `PromoCarousel.autoAdvance` (tests set it `false`); 6s interval.
- `features/offers/offers_screen.dart` (new): offers page + disclosure + honest
  empty state; routed at `/offers`.
- `features/explore/explore_screen.dart`: Restaurants/Dishes mode, food-type
  chips, category chips, sorts (recommended/rating/popular/eta/newest/price/az/za/
  openFirst), `view=dishes` deep link.
- `features/menu/menu_screen.dart`: full **restaurant detail page** —
  `restaurantDetail` with `allRestaurants()` fallback, header facts (ETA/address/
  hours/dish count/rating/categories), offers card, combined filter bar
  (search + food type + category + sort + reset), no-match state, `DishGrid`.
- `features/home/home_screen.dart`: carousel, offers strip, Top-rated (only with
  real ratings), shared dish grid; categories merge cuisines + global categories.
- `router.dart`: `/offers` route; `/explore` maps `q`/`cuisine`|`category`/
  `food_type`/`sort`/`view`.

### Menu filtering decision
- Menus are small (≤ ~294 dishes each), so menu filters/sorts are applied
  **client-side** over the fully loaded menu; the same `food_type`/`category`/
  `sort` params are still sent to the backend for API parity with the mobile app.

### Verification this update
- `flutter analyze` → 0 errors (only the 2 pre-existing `dart:html` infos).
- `flutter test` → **28 pass** (23 existing + 5 new in
  `test/restaurant_details_test.dart`).
- Backend `pytest` → **70 passed** (`tests/test_restaurant_details.py` added).
- `docker compose build api web` then `docker compose up -d` — live stack verified.

## Update: pagination & infinite scroll (user-controlled toggle)

A single, reusable module — `frontend/lib/shared/paged_list.dart` — now drives
every catalogue listing, so behaviour and styling are identical everywhere.

### What was added
- **`BrowseMode` + `browseModeProvider`** (Riverpod `Notifier`): a session-wide
  `infinite` / `pagination` choice, default `infinite`, so the mode the user
  picks carries between the home page, Explore and restaurant menus.
- **`PagedListController<T>`**: one controller type for both backend paging
  (`updateFetch` / `PagedFetch<T>`) and fully-loaded lists sliced client-side
  (`setLocalItems`). Guarantees: de-duplication by id, split
  `loading` / `paging` / `loadingMore` flags (so a page hop never flashes the
  skeleton), `hasMore` / `totalPages` / `rangeStart` / `rangeEnd`, and
  first-load vs. load-more error states.
- **`BrowseModeToggle`** — the visible Pagination / Infinite-scroll switch.
- **`PaginationControls`** — Previous / Next, numbered pages with an ellipsis
  window (`pageNumberWindow`) and a "Showing X–Y of N · Page i of n" summary.
- **`InfiniteScrollFooter`** — auto-triggered "Load more" (a real button for
  accessibility and short pages), a spinner while a page is in flight, inline
  error + retry, and an end-of-list marker.
- **`PagedResultsFooter`** — renders the right affordance for the active mode.
- **`scheduleNearBottomLoad`** — section-scoped infinite scroll: triggers when a
  section's footer nears the viewport bottom, so a listing that is only one
  section of a long page (home) still auto-loads correctly.

### Wiring decision (which list uses which strategy)
- **Explore → Dishes: backend pagination.** The live dish catalogue is
  **27,446** rows; requesting one page at a time keeps payloads small.
- **Explore → Restaurants, restaurant menus, home sections: load then slice
  client-side.** These sets are bounded in practice (live counts: **135**
  restaurants; menus ≤ a few hundred), so the full list is fetched once and the
  controller slices it. This also preserves the existing list/filter contract
  (menu filters stay client-side; the catalogue tests that expect every API page
  to load keep passing).
- All filters/sorts (search, veg/non-veg, category, price sort), offers and the
  cart are untouched by mode switches and page loads — they live outside the
  list controllers.

### Verification this update
- `flutter analyze` → 0 errors (only the 2 pre-existing `dart:html` infos).
- `flutter test` → **48 pass** (28 existing + 16 in `test/paged_list_test.dart`
  + 4 in `test/pagination_screen_test.dart`, covering the controller, the page
  window, the toggle, both footers, and the Explore/Menu/Home screens).
- `flutter build web` → **Built build/web**.
- Live API: `/dishes?page=1|2&page_size=5` returns distinct pages of a
  **27,446**-row catalogue.
- `docker compose build web` + `up -d web` — deployed bundle contains the new
  `Numbered pages` / `Infinite scroll` / `Load more` / `Showing …` strings.

### Known limitation
- The bounded lists (restaurants, menus, home sections) are still fetched in
  full before client-side slicing; only the dish catalogue uses true
  server-side pagination. If the restaurant catalogue grows very large, the
  same `PagedListController` can be switched to `updateFetch` with no UI change.

---

## Update: Home cohesion + reachable category bar

### Horizontal chip/category strips are now genuinely scrollable
Flutter only moves a horizontal list on the web with a **trackpad** or a touch
swipe: a plain mouse wheel emits a *vertical* delta, so chips past the right
edge were unreachable. New reusable `HorizontalChipScroller` in
`lib/shared/widgets.dart` wraps the strip in:
- a `Scrollbar` (clearly scrollable),
- a `Listener` that maps the wheel delta onto the strip and claims the pointer
  signal so the page behind it does not also scroll (at either end the event is
  released so the page keeps scrolling),
- a `ScrollBehavior` that also allows click-and-drag with a mouse.

Used by: Explore category chip row, Menu category chip row, Home "Browse by
category" tiles, Home "Offers for you" rail. Only the strip scrolls
horizontally; the page itself never does.

### Home: one shared browse control
`Popular right now` and `Restaurants near you` keep separate data, loading and
pagination state, but the duplicated per-section toggles were removed. A single
`_BrowseControls` heading ("Browse dishes & restaurants") with the one
`BrowseModeToggle` now governs both lists through the shared
`browseModeProvider`.

### Links audit
Every internal navigation target on the lower page (footer Home / Restaurants /
Your cart / Orders / Notifications / Profile, restaurant cards to
`/restaurant/:id`, category tiles to `/explore?cuisine=...`, offer/banner
targets, cart and checkout) resolves to a declared route in `lib/router.dart`.
There are **no external `http(s)` destinations** and no URL-launching
dependency, so nothing external needed wiring.

### Verification (this update)
- `flutter analyze` -> 0 errors (only the 2 pre-existing `dart:html` infos).
- `flutter test` -> **51 pass** (+2 in `test/horizontal_scroll_test.dart`,
  +1 home single-toggle test in `test/pagination_screen_test.dart`).
- `flutter build web` -> **Built build/web**.
- `docker compose build web` + `up -d --force-recreate web` -> `:8088` HTTP 200;
  served bundle contains the new `Browse dishes & restaurants` /
  `Browse by category` strings.

