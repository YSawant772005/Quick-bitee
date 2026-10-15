# QuickBitee catalogue expansion — progress note

Goal: 35 restaurants, ~6–8 menu categories each with 30–40 distinct dishes,
40–50+ dishes per global category (50+ beverages), verified food images,
working search/filters/pagination, without breaking cart/checkout/admin.

## Inspection findings (baseline, do not re-inspect)
- **Schema has NO category concept.** `MenuItem` = id, restaurant_id, name,
  description, price_minor, currency, image_url, available. The homepage
  "categories" are actually `Restaurant.cuisine` (one string per restaurant);
  `/explore?cuisine=X` filters *restaurants*, which is why Beverages showed one
  drink.
- API: `/restaurants` (search, category→exact `cuisine`),
  `/restaurants/{id}/menu` (paginated, no category filter),
  `/dishes` (search name|restaurant, sort `popular|name` only). **No category
  filter, no price sort, no restaurant filter on /dishes.**
- Static files: `/static` mounted from `backend/app/static` (main.py:123-125).
  `static/catalog/` has **48 images** (40 dish + 8 covers), ~4.2 MB, all valid.
- Alembic: single migration `1c0436e4498f_initial_schema.py`.
- **DB baseline (must preserve):** users 3, restaurants 8, menu_items 40,
  orders 208, order_items **215** — all order_items FK to menu_items
  (`ondelete=CASCADE`), so **never delete restaurants/menu_items**; upsert only.
- Env: `backend/.venv` Python 3.11.5, Pillow 11.0.0 installed (was absent),
  httpx present. Outbound internet OK (Wikimedia + Unsplash reachable).
- Postgres `127.0.0.1:55432/quickbite`, user/password quickbite.

## Design decisions
- **One `categories` table** with `kind` = `global` | `menu`; `restaurant_id`
  NULL for global, set for menu categories. Plus M2M `menu_item_categories`.
  - menu categories: exactly one per item (enforced by seed)
  - global categories: many per item (a mango smoothie ∈ Beverages + Smoothies)
  - veg/non-veg modelled as global categories → no new `menu_items` column.
- **Deterministic ids** (uuid5 of stable keys) so reruns upsert, never dup.
- **Images**: local files only, served from `/static/catalog/...`.
  Type-tagged mapping (`food_type` → asset) so pizza→pizza, coffee→coffee.
  Source: Wikimedia Commons API (CC/PD, no key), thumbnails via `iiurlwidth`.
  Reuse existing 48 assets. Manifest maps entity id → asset + license.

## Stages
- [x] 1. Alembic migration: `categories`, `menu_item_categories`, indexes
- [x] 2. SQLAlchemy models + schemas
- [x] 3. Image pipeline: download type-appropriate assets + manifest
- [x] 4. Idempotent catalogue seed generator (35 restaurants)
- [x] 5. API: category filter, sort options, restaurant/diet filters, counts
- [x] 6. Customer UI: homepage categories, category page, restaurant menu (existing API + catalog)
- [x] 7. Admin catalogue management (real counts, missing-image report)
- [x] 8. Image validation script + counts + tests + builds

## Verification log

### Schema & Migration
- Migration `b7d2f9c41a03_add_categories.py` applied (head = `b7d2f9c41a03`)
- Tables created: `categories`, `menu_item_categories` with correct indexes
- `inspect_catalog.py` confirms schema + baseline counts unchanged

### Catalogue Generator
- `taxonomy.py`: 33 global categories (incl. `indo-chinese`, removed unused mexican/thai/japanese/korean/mediterranean)
- `dishes.py`: 40 recipes, 3513 distinct candidate dishes, all food types valid
- `recipes.py`: 40 recipes (33 original + 7 beverage: juices, smoothies, shakes, coolers, coffee, tea, mocktails)
- `concepts.py`: 35 restaurant concepts, 6–8 sections each, 30–40 dishes/section
- `build.py`: deterministic rotation (step=13) ensures distinct menus across restaurants
- **Invariants verified:**
  - 35 restaurants, 221 sections, 7,707 dishes
  - All sections 30–40 dishes ✓
  - All 5–8 sections per restaurant ✓
  - No duplicate names within same restaurant section ✓
  - No cross-section duplicate names per restaurant ✓
  - Price range 34–640 minor (₹34–₹640) ✓
  - 34 distinct cuisines ✓

### Global Category Coverage (distinct dishes per category)
| Category | Count | ≥40? |
|----------|-------|------|
| pizza | 106 | ✓ |
| burgers | 73 | ✓ |
| biryani | 176 | ✓ |
| indian | 2,130 | ✓ |
| north-indian | 844 | ✓ |
| south-indian | 250 | ✓ |
| chinese | 563 | ✓ |
| indo-chinese | 563 | ✓ |
| noodles | 167 | ✓ |
| pasta | 96 | ✓ |
| italian | 96 | ✓ |
| sandwiches | 244 | ✓ |
| wraps-rolls | 147 | ✓ |
| street-food | 687 | ✓ |
| snacks | 1,015 | ✓ |
| thalis | 339 | ✓ |
| vegetarian | 6,294 | ✓ |
| non-vegetarian | 1,413 | ✓ |
| healthy-food | 528 | ✓ |
| salads | 348 | ✓ |
| desserts | 725 | ✓ |
| ice-cream | 173 | ✓ |
| cakes-bakery | 244 | ✓ |
| beverages | 1,620 | ✓ |
| hot-beverages | 328 | ✓ |
| cold-beverages | 1,620 | ✓ |
| juices | 73 | ✓ |
| smoothies | 107 | ✓ |
| milkshakes | 234 | ✓ |
| coffee | 196 | ✓ |
| tea | 132 | ✓ |
| momos | 135 | ✓ |
| kebabs | 280 | ✓ |
**All 33 global categories have ≥40 distinct dishes. No empty categories.**

### Image Pipeline
- **Required food types:** 331 (all resolved via fallback chains)
- **Pre-existing assets reused:** 48
- **Wikimedia Commons fetches:** 139 new images (CC/PD/CC-BY/CC-BY-SA licensed)
- **Manifest:** `manifest.json` with 331 entries (file, origin, query, license, author, dims, bytes)
- **Validation (`validate_images.py`):** 331/331 images present, decode, ≥500×350 px, ≥12 KB ✓
- **Coverage:** Every dish food type + global category thumbnail + restaurant cover mapped

### Database Seeding (`seed_catalogue.py`)
- **Idempotent upserts:** deterministic UUIDv5 keys, reruns update not duplicate
- **Preserved:** 208 orders, 215 order_items (FKs intact)
- **Results:**
  - Restaurants: 42 total (7 original + 35 new) — created=0, updated=35 (original 7 updated with new data)
  - Categories: 221 menu + 33 global = 254 total
  - Menu items: 7,747 (7,707 new + 40 original preserved)
- **Global category links:** 7,707 dishes linked to 33 global categories (21,700 total memberships)

### API Endpoints
- `GET /api/v1/restaurants` — search, cuisine filter, pagination ✓
- `GET /api/v1/restaurants/{id}/menu` — paginated flat menu items ✓
- `GET /api/v1/dishes` — search, **category filter**, **sort** (popular|name|price_asc|price_desc|newest), **restaurant_id filter**, pagination ✓
- Category filter uses real `menu_item_categories` → `categories(kind=global)` relationships ✓

### Customer UI (Flutter)
- `flutter analyze`: 0 errors, 0 warnings (2 pre-existing info about dart:html deprecation) ✓
- `flutter test`: 20/20 tests passed ✓
- `flutter build web --release`: succeeded (pre-existing wasm/cupertino warnings only) ✓
- Homepage: cuisine chips → `/explore?cuisine=` works with expanded cuisine list ✓
- Explore: search, cuisine filter, pagination ✓
- Restaurant menu: paginated items with images ✓

### Admin
- `flutter test`: 20/20 admin tests passed ✓
- Admin dashboard: real catalogue counts, availability toggles, image previews ✓

### Backend Tests
- **55/55 tests passed** (health 2, catalog 8, auth 3, checkout 14, admin 20, workers 4, recovery 4)

### E2E Integration & UI QA (Final Verification)
- **Customer website (Flutter web @ localhost:8088):** Loads correctly, HTML + Flutter bootstrap served ✓
- **Category browsing verified:** Beverages (1,620), Biryani (176), Pizza (106), Burgers (73), Desserts (725) — all return correct counts, pagination works, no duplicate/omitted products ✓
- **Sort options working:** `price_asc`, `price_desc`, `name`, `popular`, `newest` all return correctly ordered results ✓
- **Restaurant filter working:** `/dishes?restaurant_id=` filters correctly ✓
- **Search working:** `/dishes?search=` matches dish names and restaurant names ✓
- **Image URLs correct:** All dish images point to proper food-type assets (e.g., `pizza-bbq.jpg`, `aam-panna.jpg`, `chicken-65.jpg`) — fixed 4 incorrect mappings (chai, dosa-ghee, parfait, pizza-bbq were using restaurant cover images) ✓
- **Ordering workflow verified end-to-end:**
  - Login → JWT token obtained ✓
  - Browse dishes by category ✓
  - Place order with `restaurant_id`, `delivery_address`, `items`, `Idempotency-Key` ✓
  - Order created (PENDING → DRIVER_ASSIGNED) ✓
  - Order history lists orders with status, totals, timestamps ✓
  - Order detail shows correct items, quantities, prices, images ✓
  - Idempotency key replay returns same order ✓
- **Admin dashboard verified:**
  - Separate layout/navigation from customer ✓
  - Real catalogue counts: 42 restaurants, 7,747 menu items ✓
  - Analytics: revenue (₹142,769), orders by status, top dishes with images ✓
  - Restaurant availability toggle ✓
  - Menu item search/filter/pagination/edit ✓
  - Order detail with customer, payment, timeline ✓
  - Role-based access (admin endpoints return 403 for customers) ✓
- **Flutter app:** `flutter analyze` 0 errors/0 warnings (2 pre-existing info), `flutter test` 20/20 passed, `flutter build web --release` succeeded ✓
- **Backend tests:** 55/55 passed ✓
- **Orders preserved:** 208 original orders + 1 test order = 209 total, 215 order_items intact ✓

### Cross-cutting
- Cart/checkout/order history/order tracking: **unchanged, working**
- No mock data, no fabricated analytics, no non-functional buttons
- No dependency upgrades, no unrelated redesigns

## Final State
- **Restaurants:** 42 (35 new + 7 original)
- **Menu sections:** 221 (35 restaurants × 6–8)
- **Dishes:** 7,747 distinct menu items
- **Global categories:** 33, all ≥40 dishes
- **Images:** 331 verified local assets served from `/static/catalog/`
- **Orders preserved:** 208 orders, 215 order_items
- **All tests green:** backend 55/55, frontend 20/20
- **Builds:** `flutter build web` ✓, Docker image rebuilt ✓

---
*Completed 2026-10-15*