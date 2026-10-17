# 13. Testing, Debugging and Development Commands

## Purpose

- This document explains how to run the tests and how they work.
- It also lists useful commands for developing and debugging.
- It covers both backend (pytest) and frontend (Flutter) tests.

## Files involved

- `backend/pytest.ini` — pytest settings.
- `backend/tests/conftest.py` — shared fixtures.
- `backend/tests/*.py` — 34 backend tests.
- `backend/scripts/demo_order.py`, `load_test.py` — manual helpers.
- `frontend/test/*.dart` — 7 Flutter tests.
- `frontend/pubspec.yaml` — Flutter scripts and deps.
- `compose.yaml` — the stack to run against.

## Backend tests

### Where they run

- The backend tests run against **real** PostgreSQL and **real** RabbitMQ.
- As stated in `README.md`, they use the compose stack on the same ports.
- `conftest.py` points to `postgresql+asyncpg://quickbite:quickbite@localhost:55432/quickbite_test` and `amqp://quickbite:quickbite@localhost:5672/`.
- A dedicated database `quickbite_test` is created, migrated, and seeded.
- Between tests, tables are cleaned up.

### Running them

From `backend/`:

```bash
python -m venv .venv && .venv/Scripts/pip install -r requirements.txt
.venv/Scripts/python -m pytest tests -q     # 34 tests, all passing
```

Or from Windows batch: `run_tests.bat`.

### What each test file covers

| File | Purpose |
|---|---|
| `test_health.py` | `/health/live` and `/health/ready` return the right status. |
| `test_auth.py` | Login, wrong password, `GET /auth/me`. |
| `test_catalog.py` | Restaurants, menu, dishes, pagination. |
| `test_checkout.py` | Idempotency, replay, conflict on same key with different payload, concurrent idempotency. |
| `test_admin.py` | Admin access, listing, filters, summary logic, analytics. |
| `test_restaurant_details.py` | Restaurant detail validation. |
| `test_recovery.py` | Outbox dispatch, crash recovery, deduplication. |
| `test_workers.py` | Worker behaviours (payment twice-then-succeed, etc.). |

- `test_checkout.py` shows that a concurrent double submission creates only one order.
- `test_recovery.py` shows that "crash after commit, before ack" redelivers without a duplicate effect.

## Frontend tests

### Running them

From `frontend/`:

```bash
flutter pub get
flutter test
flutter analyze
```

- The README notes `flutter` may not be on `PATH`; call the full path if needed (`C:\flutter\bin\flutter.bat`).
- There are 7 tests.

### What they cover

| Test | Purpose |
|---|---|
| `login_screen_test.dart` | Login UI and behaviour. |
| `routing_test.dart` | Redirect rules. |
| `cart_controller_test.dart` | Cart logic (add, replace restaurant, mismatch). |
| `checkout_screen_test.dart` | Checkout screen behaviour. |
| `order_detail_screen_test.dart` | Tracking and polling logic. |
| `restaurant_details_test.dart` | Restaurant detail loading. |
| `catalogue_layout_test.dart`, `admin_*_test.dart`, `pagination_screen_test.dart`, `paged_list_test.dart`, `horizontal_scroll_test.dart` | UI and layout tests. |

## Useful scripts

From `backend/` (with the virtualenv active):

```bash
# End-to-end demo: login → browse → order → poll → timeline → notifications
.venv/Scripts/python backend/scripts/demo_order.py

# 100-order load benchmark (submit + pipeline wall time, status distribution)
.venv/Scripts/python backend/scripts/load_test.py --orders 100 --concurrency 10
```

## Local development without Docker

1. Start Postgres and RabbitMQ via Docker: `docker compose up -d postgres rabbitmq`.
2. From `backend/`, copy `.env.example` to `.env` and adjust if needed.
3. Install requirements.
4. Run migrations and seed: `alembic upgrade head && python -m app.seed`.
5. Start the API: `uvicorn app.main:app`.
6. Start each worker module: `python -m workers.payment_worker`, `python -m workers.restaurant_worker`, `python -m workers.delivery_worker`, `python -m workers.notification_worker`, `python -m workers.outbox_dispatcher`, `python -m workers.retry_scheduler`.

For the web app: `flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1`.

## Debugging tips

- **Watch the logs.** With Docker, `docker compose logs api` or `docker compose logs payment-worker` shows what is happening.
- **Poll the order.** The tracking screen polls every 2 seconds. You can also call `GET /api/v1/orders/{id}` with curl or Postman.
- **Check the outbox.** `outbox_events` shows pending and sent events.
- **Check retries and quarantine.** `retry_jobs` and `quarantine_records` show what was delayed or stopped.
- **Look for processed_events.** The dedupe rows explain why a redelivered event was skipped.
- **Use the request-id.** The API sets `X-Request-ID` on responses. It also appears in logs.
- **Inspect the broker.** RabbitMQ management is at `http://localhost:15672` (`quickbite`/`quickbite`).

## Verification checklist

- Backend: `pytest` passes all 34 tests.
- Frontend: `flutter test` passes; `flutter analyze` has 0 errors.
- Health checks: `GET /health/live` returns 200 and `GET /health/ready` returns 200 when the stack is up.
- Demo: `scripts/demo_order.py` runs and finishes to `DRIVER_ASSIGNED`.

## What to remember

- Tests run against real PostgreSQL and RabbitMQ (not mocks).
- 34 backend tests cover auth, catalog, checkout, admin, recovery, and workers.
- 7 Flutter tests cover login, routing, cart, checkout, and tracking.
- The transactional outbox, retries, and deduplication are explicitly tested.
- The seed creates three demo users: `customer@quickbite.dev`, `customer2@quickbite.dev`, and `admin@quickbite.dev` with the passwords shown in `README.md`.

## Builds on

- 3. Application Startup
- 9. Order Pipeline, Messaging and Workers
- 10. Failure Handling, Retries and Quarantine
