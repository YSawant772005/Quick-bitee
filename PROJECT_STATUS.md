# PROJECT STATUS — QuickBite

Last audited: 2026-10-14 · Blueprint: `Implementation blueprint.md` v2.0
This file is the handoff document. Update it at milestones, before switching
IDEs, or when the context limit approaches — not after every small change.

## 1. Objective

Deliver the full-stack "QuickBite" food-ordering platform described in
`Implementation blueprint.md`: Flutter web client, FastAPI backend,
PostgreSQL, RabbitMQ with a transactional outbox, durable retries, failure
injection, automated tests, and a one-command Docker Compose startup.

## 2. Technology stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (web + Android), Riverpod, go_router, Dio, flutter_secure_storage (mobile) |
| Backend | Python 3.11, FastAPI, SQLAlchemy 2.x async, Alembic, Pydantic v2, aio-pika, PyJWT, bcrypt |
| Messaging | RabbitMQ 3.13, topic exchange `quickbite.orders`, transactional outbox + publisher confirms |
| Data | PostgreSQL 16 (single initial migration `1c0436e4498f_initial_schema.py`) |
| Edge | Nginx serving the Flutter web build, proxying `/api/v1/*` and `/static/*` |
| Orchestration | Docker Compose, 10 long-running services + 1 one-shot migration/seed job |

## 3. Completed work (verified this audit)

### Infrastructure
- `compose.yaml` — postgres (55432), rabbitmq (15672), migration (alembic
  upgrade + seed), api, payment/restaurant/delivery/notification workers,
  outbox-dispatcher, retry-scheduler, web (8088).
- `backend/Dockerfile`, `frontend/Dockerfile`, `frontend/nginx.conf`.
- Stack verified running: `docker compose ps` shows all 10 services `Up`,
  postgres and rabbitmq `healthy`.

### Backend (`backend/app/`, 117 tracked files)
- Auth (JWT), restaurants/catalog, orders/checkout with `Idempotency-Key`,
  notifications, admin overview.
- Order state machine `backend/app/domain/order_state_machine.py`.
- Outbox `backend/app/messaging/outbox.py`, publisher confirms, retries with
  quarantine `backend/app/messaging/retries.py`, topology, consumer.
- Seed data + 48 local food images served from `backend/app/static/catalog/`
  with attribution in `docs/IMAGES.md`.

### Frontend (`frontend/lib/`, 22 Dart files)
- Screens A–I from blueprint §6.3 (sign-in, home, menu, cart, checkout ack,
  order tracking, history, notifications, admin).
- `frontend/lib/router.dart` with `AuthRefresher` bridging Riverpod auth state
  into go_router; cart controller, Dio client, money formatting.

### Tests and tooling
- Backend pytest: **34 passed** in 145 s against live PostgreSQL + RabbitMQ
  (`backend/tests/`: test_auth, test_catalog, test_checkout, test_workers,
  test_recovery, test_admin, test_health). Note: earlier revisions of this
  file claimed 36; the actual collected count is 34.
- Flutter: **8 passed** (`cart_controller_test.dart` 4, `login_screen_test.dart`
  2, `order_detail_screen_test.dart` 1, money formatting 1).
- `flutter analyze`: **0 errors**, 2 infos (web-only `dart:html` deprecation
  in `lib/core/web_origin_web.dart`) — expected and accepted.
- Load benchmark `backend/scripts/load_test.py` (untracked) — 100 orders,
  concurrency 10; 0 failures; p95 checkout 749 ms with 3 payment workers vs
  3365 ms with 1.
- Android debug APK built: `frontend/build/app/outputs/flutter-apk/app-debug.apk`.

### Documentation
- `Implementation blueprint.md`, `README.md` (untracked), `docs/IMAGES.md`,
  `docs/traceability-matrix.md`, `docs/QuickBite_Document_Pack/`.

## 4. Git status (branch main)

Commits added in this session:

| Hash | Contents |
|---|---|
| `e1beb87` | Riverpod 3.x migration (`router.dart`, `app.dart`, `analysis_options.yaml`) + `frontend/android/` scaffolding |
| *this commit* | Documentation and tooling: `README.md`, `PROJECT_STATUS.md`, `docs/traceability-matrix.md`, `docs/screenshots/*.png`, `backend/scripts/load_test.py` |
| *this commit* | `fix: render order tracking history and notifications` — the `Paginated<T>` cast fix, its regression test, the refreshed `07-order-tracking.png` and this status record. Committed 2026-10-15; **not pushed**. (A commit cannot contain its own hash; read it with `git log --oneline -1`.) |

Nothing was pushed to the remote. No existing change was reset, cleaned or
overwritten at any point.

## 5. Completed this session

- Verified the uncommitted Riverpod 3 work and committed it as `e1beb87`.
- Captured the nine missing screenshots (all ten now exist and were visually
  verified against the live UI at 1280×800) by driving headless Chrome over
  the DevTools protocol. A real order (`5b882aa3`) was placed and progressed
  PENDING → PAID → CONFIRMED → DRIVER_ASSIGNED during the capture.
- Corrected stale documentation: backend test count 36 → **34**, screenshot
  inventory added, Flutter reproduction commands now use the verified
  executable path (`C:\flutter\bin\flutter.bat`, since `flutter` is not on
  `PATH`).
- Created the missing assignment §16 deliverable:
  **`docs/ui-interaction-inventory.md`** — all visible controls across the nine
  screens, with the eight required columns (screen, control, user action,
  expected result, API, state changes, failure behaviour, test) and all **17
  mandatory interactions** covered. Each row is marked **[A]** automated /
  **[M]** manually verified live / **[NV]** not verified, with the gap named.
  3 of 17 groups have automated coverage, 10 were exercised in the running
  app, the remainder are source-only and listed as outstanding §16 work.
  Documentation only — no application code, test, configuration, screenshot,
  database or Compose change was made.

### Order tracking timeline bug — root cause and fix

**Symptom:** `docs/screenshots/07-order-tracking.png` showed an empty
"Timeline" section and "No notifications yet." under Updates, while the same
order had four notifications on the notifications screen.

**Ruled out first (as required):**
- Database — the order's rows are correct. `GET /api/v1/notifications`
  (`total=317`) returns all four notifications for order `5b882aa3` on
  **page 1** (`order.created`, `order.paid`, `order.confirmed`,
  `order.driver.assigned`), so pagination is not the cause.
- API contract — `NotificationOut.order_id` is a `str` equal to
  `OrderDetailOut.id`, and `GET /orders/{id}/history` returns 4 rows. No
  mismatch.

**Root cause:** `frontend/lib/features/orders/order_detail_screen.dart`
`_refresh()` awaited three futures and assigned two of them with invalid
casts:

```dart
_history = results[1] as List<HistoryEntry>;          // actually Paginated<HistoryEntry>
_notifications = results[2] as List<AppNotification>; // actually Paginated<AppNotification>
```

`Paginated<T>` (`frontend/lib/models/models.dart:91`) is a plain wrapper class,
not a `List`. The casts compile (the list from `Future.wait` is typed
`List<Object>`) but throw `TypeError` at runtime. The throw happens inside the
`setState` callback, so **no** state is applied; the failure is swallowed by
the surrounding `catch`, the screen keeps polling, and after five failures it
can only show the generic error/spinner state. Timeline and Updates therefore
never populate.

**Fix (2 lines):** unwrap the paginated envelope.

```dart
_history = (results[1] as Paginated<HistoryEntry>).items;
_notifications = (results[2] as Paginated<AppNotification>).items;
```

**Changed files**
- `frontend/lib/features/orders/order_detail_screen.dart` (fix, lines 63–64)
- `frontend/test/order_detail_screen_test.dart` (new regression test)
- `docs/screenshots/07-order-tracking.png` (re-captured from the fixed build)
- `PROJECT_STATUS.md` (this record)

**Regression test:** `order_detail_screen_test.dart` mounts the real
`OrderDetailScreen` against a stubbed Dio `HttpClientAdapter` serving payloads
copied verbatim from the live API. It asserts the order renders, both timeline
entries render, the empty state is absent and this order's notifications
render. It **fails on the pre-fix code** ("Found 0 widgets with text 'Order
accepted'") and passes after the fix.

**Verification:** `flutter test` **8 passed** (was 7); `flutter analyze`
**0 errors**, same 2 accepted web-only infos. Backend untouched, so the
pytest suite was not re-run (last result: 34 passed).

**Live verification (2026-10-14, 23:08 IST):** the web image was rebuilt
(`docker compose build web` → image `dd66ff015d9d`) and **only** the web
container was recreated; api, workers, PostgreSQL and RabbitMQ were untouched
(still `Up 3–4 hours`). The running app was inspected at
`http://localhost:8088` for order `5b882aa3`: the Timeline renders all four
history entries (PENDING → PAID → CONFIRMED → DRIVER_ASSIGNED) and Updates
renders all four notifications; "No notifications yet." is gone and there were
no page errors. `docs/screenshots/07-order-tracking.png` was re-captured from
this verified state, so the screenshot evidence now matches the fixed build.

## 6. Remaining work

- None blocking. Optional future items are listed in §7.

## 7. Errors / known issues

- The tracking-timeline defect is fixed and **verified in the running stack**
  (see §5). Fix, regression test and refreshed screenshot are committed;
  **nothing has been pushed to the remote**.
- No other compile or test failures at audit time.
- The tracking-timeline defect was root-caused and fixed; it had rendered the
  timeline and notifications empty on the tracking screen. Verified fixed in
  the live application, and `07-order-tracking.png` re-captured — see §5.
- Admin overview shows `Quarantined 497`. These are retained failure records
  from the earlier 100-order load test and `always_fail` injections, not a
  live backlog (`Pending outbox 0`, `Retry backlog 0`).
- `conftest.py:54` uses the deprecated `event_loop` fixture override
  (pytest-asyncio warning only).
- `frontend/ios/` does not exist and iOS cannot be built on this Windows host.
- Android APK is debug-signed and ~159 MB; a release build needs a signing key.
- Web tokens are held in memory by design; a page reload signs the user out.
- Host port remapping (55432 / 8088) because 5432 and 8080 are occupied.
- No CI workflow exists (`.github/` absent); all verification is manual.
- `load_test.py` embeds the seeded demo credentials (`customer@quickbite.dev` /
  `Customer#123`), which are published in the README; these are not secrets.

## 7. Architectural decisions

- Single database transaction writes order state + outbox row, guaranteeing
  at-least-once event delivery; dispatcher uses publisher confirms and the
  outbox is drained to 0 in every verified run.
- Idempotency keyed on (customer, key): identical payload replays the stored
  response, differing payload returns 409.
- Stage workers are separate services so payment can be scaled independently
  (1 vs 3 instances measured); restaurant/delivery stages remain serialized
  and are the post-payment bottleneck.
- One-shot `migration` service runs Alembic upgrade and seeding before the API
  starts, keeping `docker compose up` a single command.
- Outbox dedupe + quarantine tables give durable retries; failure injection is
  driven by order attributes (`always_fail`, `twice_then_succeed`) rather than
  monkeypatching.

## 8. How to reproduce

```bash
docker compose up --build -d
# web http://localhost:8088 · api http://localhost:8000/docs · rabbitmq http://localhost:15672
cd backend  && .venv\Scripts\python.exe -m pytest tests -q          # 34 tests
cd frontend && C:\flutter\bin\flutter.bat test                       # 7 tests
cd frontend && C:\flutter\bin\flutter.bat analyze                    # 0 errors
backend\.venv\Scripts\python.exe backend\scripts\load_test.py --orders 100 --concurrency 10
```

Note: `flutter` is not on PATH; use `C:\flutter\bin\flutter.bat` or prepend it.

### How the screenshots were captured

Headless Google Chrome driven over the DevTools protocol from Node 24 (native
`WebSocket`, no npm packages installed). Flutter's semantics tree was enabled
via the `flt-semantics-placeholder`, which exposes real DOM inputs, so
credentials could be typed with `Input.dispatchMouseEvent` /
`Input.insertText`. No application code was modified to obtain them.