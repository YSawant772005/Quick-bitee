# 2. Project Structure

## Purpose

- This document explains the important folders in the repository.
- It helps you find where a piece of behaviour lives.
- It does not list every file. It focuses on the folders and files that explain the architecture.

## Top-level layout

```
QuickBitee/
  backend/      Python API, workers, migrations, tests
  frontend/     Flutter web app
  docs/         screenshots, notes, traceability matrix
  compose.yaml  one-command stack for all services
  README.md     how to run the project
```

## `backend/`

- **Purpose:** the server side. It contains the API, the background workers, and the database code.
- **Contains:** Python code, Alembic migrations, pytest tests, helper scripts.
- **Used by:** Docker Compose builds this folder into the `api` and worker containers.

Important files:

- `backend/Dockerfile` — builds the Python image used by the API and every worker.
- `backend/requirements.txt` — the Python packages and their exact versions.

### `backend/app/main.py`

- **Purpose:** the API entry point.
- It creates the FastAPI application, adds middleware, registers all routes, and defines `/health/live` and `/health/ready`.

### `backend/app/api/`

- **Purpose:** HTTP layer. Each file defines routes (also called endpoints).
- `backend/app/api/v1/__init__.py` — joins all routers under the `/api/v1` prefix.
- `backend/app/api/dependencies.py` — shares login checks (`get_current_user`, `require_admin`) and pagination.
- Route files: `auth.py`, `restaurants.py`, `promotions.py`, `orders.py`, `notifications.py`, `admin.py`.

### `backend/app/services/`

- **Purpose:** business logic that is bigger than one endpoint.
- `order_service.py` — `create_order(...)`, the heart of order placement and idempotency.
- `catalog_service.py` — small read helper that maps menu item ids to image URLs.

### `backend/app/models/`

- **Purpose:** the database table definitions (SQLAlchemy classes).
- `users.py`, `catalog.py`, `orders.py`, `messaging.py`.
- Each class maps to a table. Example: `Order` maps to `orders`.

### `backend/app/schemas/`

- **Purpose:** Pydantic models that define the JSON shapes for requests and responses.
- `orders.py`, `catalog.py`, `auth.py`, `admin.py`, `common.py` (shared helpers like `Paginated`).

### `backend/app/core/`

- **Purpose:** cross-cutting building blocks.
- `config.py` — all settings loaded from environment variables.
- `security.py` — password hashing and JWT create/decode.
- `errors.py` — the typed error classes and their HTTP status codes.
- `logging.py` — logging setup, including the request-id filter.

### `backend/app/db/`

- **Purpose:** database connection wiring.
- `session.py` — creates the async engine and `SessionFactory`, plus the `get_session` dependency.
- `base.py` — the shared `Base` class and id/timestamp mixins.

### `backend/app/domain/`

- **Purpose:** pure business rules that do not touch HTTP or the database directly.
- `order_state_machine.py` — the allowed status transitions.
- `events.py` — event names, routing keys, and the `EventEnvelope` shape.

### `backend/app/messaging/`

- **Purpose:** everything about talking to RabbitMQ and the outbox.
- `outbox.py` — writes and dispatches outbox events.
- `topology.py` — declares exchanges and queues.
- `publisher.py` — publishes a message.
- `consumer.py` — the shared worker consumer loop.
- `retries.py` — dedupe, retry scheduling, quarantine.
- `connection.py` — the shared RabbitMQ connection.

### `backend/app/catalog/` and `backend/app/static/catalog/`

- **Purpose:** seed data definitions and the food photos.
- `catalog/` holds the taxonomy and recipe data used by the seeder.
- `static/catalog/` holds the actual `.jpg` food images served at `/static/catalog/...`.

### `backend/app/seed.py`

- **Purpose:** fills the database with demo users, restaurants, and dishes.
- Run by the `migration` container after the migrations complete.

### `backend/workers/`

- **Purpose:** the background processes.
- `common.py` — shared worker core: dedupe, lock the order, run the effect.
- `payment_worker.py`, `restaurant_worker.py`, `delivery_worker.py`, `notification_worker.py` — each owns one pipeline stage.
- `outbox_dispatcher.py` — publishes pending outbox rows.
- `retry_scheduler.py` — redelivers scheduled retries.

### `backend/alembic/`

- **Purpose:** database migrations.
- `alembic/versions/` holds the migration files that build the schema step by step.

### `backend/tests/`

- **Purpose:** the pytest suite. It runs against a real PostgreSQL and RabbitMQ.
- See Knowledge Byte 13.

### `backend/scripts/`

- **Purpose:** manual helpers.
- `demo_order.py` runs a full end-to-end demo. `load_test.py` submits many orders.

## `frontend/`

- **Purpose:** the Flutter web application.
- **Contains:** Dart code, web assets, tests, and the Nginx config.
- **Used by:** Docker Compose builds it and serves it through Nginx on port 8088.

Important files:

- `frontend/Dockerfile` — builds the Flutter web bundle and copies it into Nginx.
- `frontend/nginx.conf` — serves the app and proxies `/api/` and `/static/` to the API.
- `frontend/pubspec.yaml` — the Dart package list.

### `frontend/lib/main.dart`

- **Purpose:** the first Dart file that runs. It starts Riverpod and the app widget.

### `frontend/lib/app.dart`

- **Purpose:** builds `MaterialApp.router` and wires the router to Riverpod.

### `frontend/lib/router.dart`

- **Purpose:** all URL routes and the login/role redirect rules.
- It also contains `AuthRefresher`, which tells the router when auth changes.

### `frontend/lib/core/`

- **Purpose:** low-level shared code.
- `api_client.dart` — the Dio-based API client. Every backend call lives here.
- `config.dart` — resolves the API base URL for web and mobile.
- `auth_storage.dart` — saves the token (secure storage on mobile, memory on web).

### `frontend/lib/state/`

- **Purpose:** Riverpod controllers (the app state).
- `auth_controller.dart` — login, logout, session restore, and the `apiClientProvider`.
- `cart_controller.dart` — the cart contents and rules.
- `admin_range_controller.dart` — the admin date-range filter.

### `frontend/lib/models/models.dart`

- **Purpose:** Dart classes that match the JSON the API returns.
- Example: `OrderDetail`, `Restaurant`, `MenuItem`, `User`.

### `frontend/lib/features/`

- **Purpose:** one folder per screen area.
- `auth/`, `home/`, `explore/`, `menu/`, `cart/`, `checkout/`, `orders/`, `notifications/`, `offers/`, `profile/`, `admin/`.

### `frontend/lib/shared/`

- **Purpose:** reusable UI pieces (theme, layout, widgets).

### `frontend/test/`

- **Purpose:** Flutter widget and unit tests. See Knowledge Byte 13.

## `docs/`

- **Purpose:** screenshots, the traceability matrix, and design notes.
- `docs/screenshots/` — ten real screenshots of the running app.

## `compose.yaml`

- **Purpose:** starts every service in the right order.
- It defines `postgres`, `rabbitmq`, `migration`, `api`, the four workers, `outbox-dispatcher`, `retry-scheduler`, and `web`.

## Example

- You want to change what the "Place order" button does.
- Start in `frontend/lib/features/checkout/checkout_screen.dart` (the button).
- Then follow the call into `frontend/lib/core/api_client.dart` (`placeOrder`).
- Then `backend/app/api/v1/orders.py` (`place_order`), then `backend/app/services/order_service.py` (`create_order`).

## What to remember

- `backend/` and `frontend/` are the two halves of the system.
- Inside the backend: `api/` is HTTP, `services/` is business logic, `models/` is the database, `workers/` is background processing, `messaging/` is RabbitMQ plus the outbox.
- Inside the frontend: `core/` talks to the API, `state/` holds app state, `features/` holds screens.
- `compose.yaml` is the map of all running processes.
- Follow a feature from a screen (`features/`) to the API client (`core/api_client.dart`) to the backend route to the service.

## Builds on

- 1. System Overview
