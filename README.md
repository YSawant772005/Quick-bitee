# QuickBite

Full-stack food-delivery order-processing system: Flutter web app, FastAPI
backend, PostgreSQL, RabbitMQ with transactional outbox, durable retries,
failure injection, and a one-command Docker Compose startup.

## Quick start (one command)

```bash
docker compose up --build -d
```

Then open:

| Service | URL |
|---|---|
| Web app (Flutter) | http://localhost:8088 |
| API (FastAPI, auto docs) | http://localhost:8000/docs |
| RabbitMQ management | http://localhost:15672 (`quickbite` / `quickbite`) |
| PostgreSQL | `localhost:55432` (`quickbite` / `quickbite`, db `quickbite`) |

> Port note: this host runs other services on 5432 and 8080, so Postgres is
> published on **55432** and the web app on **8088**. Change the mappings in
> `compose.yaml` if your machine is free.

### Demo accounts (seeded automatically)

| Role | Email | Password |
|---|---|---|
| Customer | `customer@quickbite.dev` | `Customer#123` |
| Customer 2 | `customer2@quickbite.dev` | `Customer#123` |
| Admin | `admin@quickbite.dev` | `Admin#123` |

## Stack

- **Backend** — Python 3.11, FastAPI, SQLAlchemy 2.x (async), Alembic,
  Pydantic v2, aio-pika, PyJWT, bcrypt.
- **Frontend** — Flutter web, Riverpod 2.x, go_router, Dio,
  flutter_secure_storage (mobile).
- **Infrastructure** — PostgreSQL 16, RabbitMQ 3.13, Nginx (serves the Flutter
  web build and proxies `/api` + `/static` to the API), Docker Compose.

## Architecture

Order lifecycle (state machine):

```
PENDING → PAID → CONFIRMED → DRIVER_ASSIGNED
   └────→ PAYMENT_FAILED        PAID/CONFIRMED ──→ FAILED
```

- `POST /api/v1/orders` is idempotent via the `Idempotency-Key` header
  (unique per customer + key; same payload replays the stored response,
  different payload returns `409`).
- The API writes domain changes and an `outbox_events` row in the **same
  database transaction** (transactional outbox). A dispatcher publishes
  pending rows with publisher confirms + mandatory routing.
- RabbitMQ topic exchange `quickbite.orders`; queues: `payment.queue`
  (`order.created`), `restaurant.queue` (`order.paid`),
  `delivery.queue` (`order.confirmed`), `notification.queue` (`order.#`).
- Workers are idempotent (`processed_events` unique consumer+event), lock the
  order row (`SELECT ... FOR UPDATE`), validate the expected version, mutate
  state, emit the next event into the outbox — single commit, ack after
  commit.
- Failures raise a durable `retry_jobs` entry with backoff
  (`RETRY_DELAYS_SECONDS`, default `2,10,30`); a scheduler redelivers to the
  original queue with an `x_attempt` header. Exhaustion moves the event to
  the quarantine queue and applies the terminal business status.
- Notifications are persisted per order + event type and never mutate
  business status.

Deterministic failure injection (env vars, see `backend/.env.example`):

| Variable | Values |
|---|---|
| `PAYMENT_FAILURE_MODE` | `none` (default) \| `twice_then_succeed` \| `always_fail` |
| `RESTAURANT_FAILURE_MODE` / `DELIVERY_FAILURE_MODE` / `NOTIFICATION_FAILURE_MODE` | `none` \| `always_fail` |
| `WORKER_CRASH_POINT` | `none` \| `before_tx` \| `after_tx` (process kill) |

## Services (compose)

`postgres`, `rabbitmq`, `migration` (alembic upgrade + seed, runs to
completion), `api`, `payment-worker`, `restaurant-worker`, `delivery-worker`,
`notification-worker`, `outbox-dispatcher`, `retry-scheduler`, `web`.

Scale workers, e.g. `docker compose up -d --scale payment-worker=3`.

## Tests

Backend (requires the compose stack running — tests use the real PostgreSQL
on 55432 and RabbitMQ on 5672, in a dedicated `quickbite_test` database):

```bash
cd backend
python -m venv .venv && .venv/Scripts/pip install -r requirements.txt
.venv/Scripts/python -m pytest tests -q     # 34 tests, all passing
```

Flutter (7 tests, 0 analyzer errors):

```bash
cd frontend
flutter pub get
flutter test
flutter analyze
```

> `flutter` is not on `PATH` on this machine. Either prepend the SDK to
> `PATH` (`$env:PATH = "C:\flutter\bin;$env:PATH"` in PowerShell) or call the
> absolute path `C:\flutter\bin\flutter.bat`.

## Useful scripts

```bash
# End-to-end demo: login → browse → order → poll → timeline → notifications
backend/.venv/Scripts/python backend/scripts/demo_order.py

# 100-order load benchmark (submit + pipeline wall time, status distribution)
backend/.venv/Scripts/python backend/scripts/load_test.py --orders 100 --concurrency 10
```

## Local development without Docker

Run Postgres/RabbitMQ via compose (`docker compose up -d postgres rabbitmq`),
then from `backend/`: copy `.env.example` to `.env`, install requirements, run
`alembic upgrade head && python -m app.seed`, start `uvicorn app.main:app`,
and start each worker module (`workers.payment_worker`, etc.).

## Project layout

```
backend/
  app/            FastAPI app: api, core, db, domain, messaging, models,
                  schemas, services, seed, static/catalog (food photos)
  workers/        payment/restaurant/delivery/notification workers,
                  outbox dispatcher, retry scheduler
  alembic/        migrations
  tests/          pytest suite (real PG + RabbitMQ)
  scripts/        demo_order.py, load_test.py, fetch_images.py
frontend/
  lib/features/   auth, home, menu, cart, checkout, orders, notifications,
                  admin
  lib/core/       config, api_client (Dio), auth storage
  lib/state/      Riverpod controllers
  test/           widget + unit tests
compose.yaml      one-command stack
docs/             IMAGES.md (photo attribution), screenshots
```

## Platform notes / limitations

- **Android**: build a debug APK with `flutter build apk --debug` (SDK
  present on this machine). **iOS cannot be built on Windows** — no Xcode;
  the codebase is iOS-compatible but unverified.
- On the web, tokens are kept in memory (secure storage is unavailable);
  reloading signs you out again.
- Screenshots and the traceability matrix live in `docs/` and
  `PROJECT_STATUS.md`.

## Screenshots (`docs/screenshots/`)

All ten were captured from the running stack at `http://localhost:8088`
(1280×800) and show a real order (`5b882aa3`) travelling through the pipeline
to `DRIVER_ASSIGNED`:

| File | Screen |
|---|---|
| `01-login.png` | Sign-in with demo accounts |
| `02-home.png` | Restaurant discovery |
| `03-menu.png` | Restaurant menu with real dish photos |
| `04-cart.png` | Cart (2 × Chicken 65 Biryani, ₹680) |
| `05-checkout.png` | Checkout with delivery address |
| `06-checkout-ack.png` | Order accepted (PENDING) |
| `07-order-tracking.png` | Live tracking, DRIVER_ASSIGNED, driver card |
| `08-order-history.png` | Order history |
| `09-notifications.png` | Notification feed |
| `10-admin.png` | Admin overview (counts, status filter, order list) |
