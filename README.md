# QuickBite

A full-stack food-delivery order-processing system built with Flutter, FastAPI, PostgreSQL, and RabbitMQ. It includes asynchronous order processing, a transactional outbox, idempotent checkout, durable retries, failure injection, customer order tracking, persistent notifications, and a responsive admin dashboard.

The project can be started locally with Docker Compose and supports Flutter Web and Android builds. iOS compatibility remains unverified until an iOS build and simulator or device test are completed.

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Demo Accounts](#demo-accounts)
- [Technology Stack](#technology-stack)
- [Architecture](#architecture)
- [Order Lifecycle](#order-lifecycle)
- [Reliability and Failure Handling](#reliability-and-failure-handling)
- [Services](#services)
- [Responsive Admin Dashboard](#responsive-admin-dashboard)
- [Run on an Android Phone](#run-on-an-android-phone)
- [Platform Support](#platform-support)
- [Tests](#tests)
- [Useful Scripts](#useful-scripts)
- [Local Development Without Docker](#local-development-without-docker)
- [Project Structure](#project-structure)
- [Security Notes](#security-notes)
- [Screenshots](#screenshots)

## Features

### Customer Application

- User registration and login.
- Restaurant discovery and menu browsing.
- Food images, item prices, and cart management.
- Checkout and order placement.
- Order history and order-status tracking.
- Persistent in-app notifications.
- Responsive Flutter interface for web and mobile layouts.

### Admin Dashboard

- Overview of orders and order statuses.
- Analytics and KPI summaries.
- Order management and status filtering.
- Menu management.
- Restaurant management.
- Customer management.
- Delivery management.
- Settings and system configuration views.
- Responsive layouts for smaller screens, including flexible headers, adaptive KPI grids, wrapped pagination, and scrollable content.

### Backend and Order Processing

- FastAPI REST API with interactive Swagger documentation.
- PostgreSQL persistence and Alembic migrations.
- RabbitMQ-based asynchronous event processing.
- Transactional outbox for reliable event publication.
- Idempotent order creation.
- Independent payment, restaurant, delivery, and notification workers.
- Durable retry scheduling with configurable backoff.
- Quarantine handling for exhausted retries.
- Failure injection for testing error and recovery scenarios.
- Worker scaling and load-testing scripts.

## Quick Start

### Prerequisites

- Docker Desktop with Docker Compose.
- Git, if cloning the repository.
- Flutter SDK for local Flutter development or building APKs.
- Python 3.11 for backend development outside Docker.

### Start the complete stack

From the project root, run:

```bash
docker compose up --build -d
```

Docker Compose starts the database, message broker, migration and seed process, API, background workers, retry scheduler, outbox dispatcher, and web application.

### Open the services

| Service | URL | Purpose |
|---|---|---|
| Flutter Web | http://localhost:8088 | Customer application and admin dashboard |
| FastAPI Swagger | http://localhost:8000/docs | Interactive API documentation |
| FastAPI OpenAPI schema | http://localhost:8000/openapi.json | API specification |
| RabbitMQ Management | http://localhost:15672 | Queue and message monitoring |
| PostgreSQL | `localhost:55432` | Application database |

Local development credentials:

- RabbitMQ: `quickbite` / `quickbite`
- PostgreSQL: `quickbite` / `quickbite`, database `quickbite`

**Port note:** The web app is published on port `8088` and PostgreSQL on port `55432` to avoid conflicts with other local services. Adjust the port mappings in `compose.yaml` if necessary.

### Stop the application

```bash
docker compose stop
```

Restart the stopped containers with:

```bash
docker compose up -d
```

To stop the containers and remove the Compose network while preserving named volumes:

```bash
docker compose down
```

Do not use `docker compose down -v` unless you intentionally want to remove the associated named volumes and their stored database data.

## Demo Accounts

The following accounts are documented as seeded by the application. Confirm that the seed process has completed before using them.

| Role | Email | Password |
|---|---|---|
| Customer | `customer@quickbite.dev` | `Customer#123` |
| Customer 2 | `customer2@quickbite.dev` | `Customer#123` |
| Admin | `admin@quickbite.dev` | `Admin#123` |

These are development credentials only. Replace them and configure secure credentials before any public deployment.

## Technology Stack

### Backend

- Python 3.11
- FastAPI
- SQLAlchemy 2.x with asynchronous database access
- Alembic migrations
- Pydantic v2
- PostgreSQL 16
- RabbitMQ 3.13
- `aio-pika`
- PyJWT
- `bcrypt`

### Frontend

- Flutter and Dart
- Riverpod 2.x for state management
- `go_router` for navigation
- Dio for HTTP requests
- `flutter_secure_storage` for supported mobile storage scenarios
- Responsive customer and admin interfaces

### Infrastructure

- Docker Compose
- Nginx
- PostgreSQL
- RabbitMQ
- Dedicated background workers
- Transactional outbox and retry scheduler

Nginx serves the Flutter Web build and proxies the configured `/api` and `/static` paths to the API.

## Architecture

QuickBite separates the user interface, API, persistence, and asynchronous order-processing components.

```text
Flutter Web / Android
         |
         v
      Nginx
         |
         v
     FastAPI
         |
         +------> PostgreSQL
         |           |
         |           +--> Orders and order state
         |           +--> Outbox events
         |           +--> Retry jobs
         |           +--> Notifications
         |
         v
  Outbox Dispatcher
         |
         v
      RabbitMQ
         |
         +--> Payment Worker
         |
         +--> Restaurant Worker
         |
         +--> Delivery Worker
         |
         +--> Notification Worker
         |
         v
   Retry Scheduler
```

The diagram is a logical overview. The exact routing and deployment configuration are defined in `compose.yaml` and the backend source.

## Order Lifecycle

The main order lifecycle is:

```text
PENDING -> PAID -> CONFIRMED -> DRIVER_ASSIGNED
    |
    +----> PAYMENT_FAILED

PAID / CONFIRMED -> FAILED
```

The state transitions depend on successful processing and the configured failure-handling rules.

### Idempotent Checkout

`POST /api/v1/orders` supports idempotency through the `Idempotency-Key` header.

- The key is unique per customer.
- Repeating a request with the same key and payload replays the stored response.
- Reusing the same key with a different payload returns `409 Conflict`.

This helps prevent duplicate orders when clients retry requests after timeouts or interrupted connections.

### Transactional Outbox

The API writes domain changes and an `outbox_events` record in the same database transaction.

An outbox dispatcher publishes pending events to RabbitMQ using publisher confirms and mandatory routing. This pattern helps prevent database changes from succeeding while their corresponding events are silently lost.

### RabbitMQ Routing

The topic exchange is named `quickbite.orders`.

| Queue | Primary event |
|---|---|
| `payment.queue` | `order.created` |
| `restaurant.queue` | `order.paid` |
| `delivery.queue` | `order.confirmed` |
| `notification.queue` | `order.#` |

### Worker Processing

Workers use idempotent event processing and database transaction controls.

- `processed_events` tracks processed consumer/event combinations.
- `SELECT ... FOR UPDATE` locks the relevant order row.
- Expected order versions are validated before state changes.
- Domain changes and subsequent outbox events are committed together.
- Messages are acknowledged after the database transaction commits.

These mechanisms help protect against duplicate processing and concurrent state changes.

## Reliability and Failure Handling

### Durable Retries

Failures create durable entries in `retry_jobs`. The retry scheduler redelivers messages to their original queues using an `x_attempt` header.

The default retry delays are configured through `RETRY_DELAYS_SECONDS`, with the documented default sequence:

```text
2,10,30
```

After retry exhaustion, the event is moved to the quarantine queue and the corresponding terminal business status is applied according to the implementation.

### Persistent Notifications

Notifications are persisted per order and event type. Notification processing does not independently change the business status of an order.

### Failure Injection

Configure failure injection through environment variables documented in `backend/.env.example`.

| Variable | Supported values |
|---|---|
| `PAYMENT_FAILURE_MODE` | `none`, `twice_then_succeed`, `always_fail` |
| `RESTAURANT_FAILURE_MODE` | `none`, `always_fail` |
| `DELIVERY_FAILURE_MODE` | `none`, `always_fail` |
| `NOTIFICATION_FAILURE_MODE` | `none`, `always_fail` |
| `WORKER_CRASH_POINT` | `none`, `before_tx`, `after_tx` |

The crash-point options are intended to simulate worker process termination at selected points in processing.

Use these controls in a development or test environment, not in production.

## Services

The Compose stack includes:

| Service | Responsibility |
|---|---|
| `postgres` | Persistent relational database |
| `rabbitmq` | Asynchronous messaging |
| `migration` | Applies Alembic migrations and seeds data |
| `api` | FastAPI application |
| `payment-worker` | Payment processing |
| `restaurant-worker` | Restaurant confirmation |
| `delivery-worker` | Delivery assignment |
| `notification-worker` | Notification processing |
| `outbox-dispatcher` | Publishes pending outbox events |
| `retry-scheduler` | Schedules durable retries |
| `web` | Nginx and Flutter Web application |

### Scale Payment Workers

For example, run three payment-worker replicas:

```bash
docker compose up -d --scale payment-worker=3
```

Scaling worker services can help evaluate processing throughput under concurrent workloads. Verify the number of active replicas and compare results using the included load-testing script.

## Responsive Admin Dashboard

The admin interface contains the following modules:

- Overview
- Analytics
- Orders
- Menu management
- Restaurants
- Customers
- Deliveries
- Settings

The responsive implementation includes flexible section headers, adaptive KPI layouts, wrapped pagination, and scrollable content for narrower screens.

### Validate the Flutter Application

From PowerShell on Windows:

```powershell
cd frontend
flutter pub get
flutter analyze
flutter test
flutter build web
```

To build the Android debug APK with a phone-accessible backend URL, see [Run on an Android Phone](#run-on-an-android-phone).

**Testing note:** Record the actual test counts and analyzer results from the latest run. Do not rely on older counts in this README when the test suite changes.

## Run on an Android Phone

The Android application can communicate with the backend running on your laptop when both devices are on the same Wi-Fi network and the laptop firewall permits the connection.

### 1. Start the backend

From the project root:

```powershell
docker compose up -d
```

### 2. Find the laptop's Wi-Fi IPv4 address

Run:

```powershell
ipconfig
```

Find the IPv4 address for the active Wi-Fi adapter. The address used during local testing was `192.168.1.34`; your address may change.

### 3. Build the APK

From the frontend directory:

```powershell
cd frontend
flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.1.34:8000/api/v1
```

Replace `192.168.1.34` with the current laptop IPv4 address if it differs.

The expected output is:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

The complete path from the project root is:

```text
frontend/build/app/outputs/flutter-apk/app-debug.apk
```

Transfer the APK to your Android phone and install it. Depending on the device, you may need to authorize installation from that source.

### 4. Test connectivity

On the phone, open this URL in a browser, replacing the IP if necessary:

```text
http://192.168.1.34:8000/openapi.json
```

If the OpenAPI JSON is displayed, the phone can reach the API endpoint. This verifies network reachability, not every app workflow.

### Important local-network requirements

- Docker containers must be running.
- The phone and laptop must be on the same Wi-Fi network.
- The API must be published on a host interface reachable from the phone.
- Windows Firewall must permit the required local connection.
- The IP address must match the current laptop network configuration.

The local Android configuration may allow HTTP traffic for development. Use HTTPS and a production-appropriate API URL for public deployment.

## Platform Support

| Platform | Status | Notes |
|---|---|---|
| Web | Build supported | Flutter Web is served through the Compose web service. |
| Android | Debug APK built and tested locally | A phone can access the laptop-hosted backend over the local network. |
| iOS | Not yet verified | Requires a native iOS build and simulator or device testing using macOS and Xcode, or a compatible hosted Mac environment. |

The Flutter codebase is intended to support iOS, but a successful Android or Web build does not prove that the iOS build succeeds. Do not claim a validated iOS build until the build and required tests have been completed.

### Web Authentication Storage

On the web, authentication tokens are kept in memory because the configured secure-storage approach is not available in the same way as on mobile. Reloading the page signs the user out again.

## Tests

### Backend Tests

The backend test suite uses PostgreSQL and RabbitMQ. The Compose stack must be running, and the test database must be configured as expected by the test settings.

From the project root, in PowerShell:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m pytest tests -q
```

The previous README recorded 34 passing backend tests. Re-run the suite and update this number if the current test suite has changed.

### Flutter Tests

From the project root:

```powershell
cd frontend
flutter pub get
flutter analyze
flutter test
```

The latest reported Flutter results after the responsive admin work were:

- 88 tests passing across the reported full suite.
- Two informational analyzer messages relating to the existing `dart:html` implementation.
- Successful Flutter Web build.
- Successful Android debug APK build.

These results are reported from the development workflow and should be confirmed with a fresh local run before being treated as current verification results.

### End-to-End and Reliability Tests

The project includes tests and scripts for order creation, event processing, retry handling, and failure scenarios. Run the tests against the intended development environment and inspect their actual output before documenting a new result.

## Useful Scripts

### End-to-End Order Demo

Run from the project root after installing backend dependencies and starting the required services:

```powershell
.\backend\.venv\Scripts\python.exe backend/scripts/demo_order.py
```

The documented workflow demonstrates login, browsing, order placement, polling, the order timeline, and notifications.

### Load Test

Run the documented 100-order benchmark:

```powershell
.\backend\.venv\Scripts\python.exe backend/scripts/load_test.py --orders 100 --concurrency 10
```

The script reports submission and pipeline timing along with the order-status distribution.

For meaningful comparisons, run the same workload with one payment worker and then multiple workers. Record throughput and latency percentiles where available, and document the test environment and failure scenarios.

## Local Development Without Docker

Docker Compose is the recommended way to run the complete system.

For backend development without running the entire application stack in Docker, start PostgreSQL and RabbitMQ through Compose:

```powershell
docker compose up -d postgres rabbitmq
```

Then, from the `backend` directory:

1. Create a local virtual environment.
2. Install dependencies.
3. Copy `.env.example` to `.env`.
4. Configure the database and RabbitMQ connection strings.
5. Apply migrations and seed data.
6. Start the API.
7. Start the required worker processes.

Example PowerShell commands:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
.\.venv\Scripts\python.exe -m alembic upgrade head
.\.venv\Scripts\python.exe -m app.seed
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
```

Start each worker in its own terminal using the actual module paths in the repository, including the payment, restaurant, delivery, notification, outbox-dispatcher, and retry-scheduler processes.

## Project Structure

```text
QuickBitee/
├── backend/
│   ├── app/
│   │   ├── api/
│   │   ├── core/
│   │   ├── db/
│   │   ├── domain/
│   │   ├── messaging/
│   │   ├── models/
│   │   ├── schemas/
│   │   ├── services/
│   │   ├── seed/
│   │   └── static/catalog/
│   ├── workers/
│   │   ├── payment_worker
│   │   ├── restaurant_worker
│   │   ├── delivery_worker
│   │   ├── notification_worker
│   │   ├── outbox dispatcher
│   │   └── retry scheduler
│   ├── alembic/
│   ├── tests/
│   └── scripts/
│       ├── demo_order.py
│       ├── load_test.py
│       └── fetch_images.py
├── frontend/
│   ├── lib/
│   │   ├── core/
│   │   ├── features/
│   │   └── state/
│   ├── test/
│   └── build/
├── docs/
│   ├── IMAGES.md
│   └── screenshots/
├── compose.yaml
├── PROJECT_STATUS.md
└── README.md
```

This is a logical overview. Check the current repository for exact filenames and folders if the implementation changes.

## Security Notes

The included credentials and local HTTP setup are intended for development only.

Before exposing the system publicly:

- Replace all default passwords and development secrets.
- Configure strong JWT signing secrets.
- Use HTTPS.
- Restrict database and RabbitMQ management access.
- Do not expose internal service ports unnecessarily.
- Configure appropriate CORS and trusted-host settings.
- Keep `.env` files and other secrets out of Git.
- Use production-specific settings and credentials.
- Review logs to ensure sensitive information is not exposed.

## Screenshots

Screenshots are documented under `docs/screenshots/`. Verify that each file exists and reflects the current application before relying on the list below.

| File | Screen |
|---|---|
| `01-login.png` | Sign-in with demo accounts |
| `02-home.png` | Restaurant discovery |
| `03-menu.png` | Restaurant menu and food photos |
| `04-cart.png` | Shopping cart |
| `05-checkout.png` | Checkout and delivery address |
| `06-checkout-ack.png` | Order acceptance |
| `07-order-tracking.png` | Order tracking and delivery status |
| `08-order-history.png` | Order history |
| `09-notifications.png` | Notification feed |
| `10-admin.png` | Admin overview |

The previous documentation recorded an example order reaching `DRIVER_ASSIGNED`. Treat that as a recorded demo scenario, not a guarantee that every order reaches that status.

## Project Status

Android App Video
https://drive.google.com/drive/folders/1LDDqweZnOdmsTiLZMxx5uisErxPAPC5V

QuickBite brings together a Flutter client, a FastAPI backend, PostgreSQL persistence, and RabbitMQ-driven asynchronous processing. It includes reliability mechanisms such as idempotent checkout, a transactional outbox, durable retries, and failure injection, alongside customer features and a responsive admin interface.

For the latest verified implementation details, test results, screenshots, and known limitations, consult `PROJECT_STATUS.md` and the actual results of the current build and test commands.
