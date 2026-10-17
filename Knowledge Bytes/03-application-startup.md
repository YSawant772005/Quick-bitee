# 3. Application Startup

## Purpose

- This document explains what happens when the project starts.
- It covers the backend, the workers, and the frontend separately.
- It answers "which file runs first?" and "how does configuration get loaded?".

## Files involved

- `compose.yaml` — starts every container and sets the order and health checks.
- `backend/app/core/config.py` — loads all settings from environment variables.
- `backend/app/db/session.py` — creates the database engine and session factory.
- `backend/app/main.py` — builds and starts the FastAPI app.
- `backend/app/seed.py` — fills the database with demo data.
- `backend/workers/*.py` — each worker's `main()` entry point.
- `frontend/lib/main.dart` — the first Dart file that runs.
- `frontend/lib/app.dart` — builds the Flutter app widget.
- `frontend/nginx.conf` — serves the built web app.

## Part A: Docker Compose startup order

1. `docker compose up --build -d` reads `compose.yaml`.
2. `postgres` starts and becomes healthy (`pg_isready`).
3. `rabbitmq` starts and becomes healthy (`rabbitmq-diagnostics ping`).
4. `migration` waits for both, then runs `alembic upgrade head && python -m app.seed`.
5. `api` waits for `migration` to complete successfully, then runs `uvicorn app.main:app`.
6. The four workers and the `outbox-dispatcher` and `retry-scheduler` also wait for `migration` to complete.
7. `web` starts and serves the Flutter build. It only depends on `api`.

```mermaid
flowchart TD
    PG[(postgres healthy)]
    RMQ[(rabbitmq healthy)]
    MIG[migration<br/>alembic upgrade head<br/>+ python -m app.seed]
    API[api<br/>uvicorn app.main:app]
    W[workers + dispatcher + scheduler]
    WEB[web<br/>nginx + Flutter build]

    PG --> MIG
    RMQ --> MIG
    MIG -->|completed successfully| API
    MIG -->|completed successfully| W
    API --> WEB
```

### Diagram explained

1. The database and broker must be ready first.
2. The one-off `migration` container creates tables and seeds demo data.
3. Only after that do the API and the background workers start.
4. The web container starts last and proxies API calls.

## Part B: How the backend starts

1. `uvicorn` imports `backend/app/main.py`.
2. At the bottom of that file, `app = create_app()` runs immediately.
3. `create_app()` builds the FastAPI object, adds middleware and exception handlers, and includes the API router.
4. The `/health/live` and `/health/ready` routes are added. `/health/ready` actually checks PostgreSQL and RabbitMQ.
5. The `/static` folder is mounted so food photos are served.

Real startup code from `backend/app/main.py`:

```python
def create_app() -> FastAPI:
    app = FastAPI(title="QuickBite API", version="1.0.0", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins_list,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    ...
    app.include_router(api_router)
    ...
    app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")
    return app
```

- This function is called once at import time.
- `include_router(api_router)` is what makes every `/api/v1/...` endpoint available.
- `app.mount("/static", ...)` is what makes food images load.

### How configuration is loaded

- `config.py` defines a `Settings` class that reads environment variables.
- It loads a `.env` file if one exists. Inside Docker, values come from `compose.yaml`.
- `settings = get_settings()` runs at import time, so every module sees the same settings object.

```python
class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    DATABASE_URL: str = "postgresql+asyncpg://quickbite:quickbite@localhost:5432/quickbite"
    AMQP_URL: str = "amqp://quickbite:quickbite@localhost:5672/"
    JWT_SECRET: str = "dev-insecure-secret-change-me"
    ...
```

- Each line is one setting with a safe default.
- In Compose, `DATABASE_URL` points at the `postgres` service and `AMQP_URL` at `rabbitmq`.

### How the database connection is created

- `backend/app/db/session.py` creates the async engine and the session factory.
- No connection is opened at import time. Connections open lazily when a request needs one.

```python
engine = create_async_engine(settings.DATABASE_URL, pool_size=10, max_overflow=10, pool_pre_ping=True)
SessionFactory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
```

- `pool_size=10` keeps up to 10 open database connections.
- `pool_pre_ping=True` checks a connection is still alive before using it.

### When the API shuts down

- `main.py` defines a `lifespan` function.
- After the app stops serving, `await engine.dispose()` closes the database pool.

## Part C: How a worker starts

1. Compose runs `python -m workers.payment_worker` (and the other modules).
2. Each worker's `main()` calls `setup_logging()` and then `asyncio.run(...)`.
3. The worker builds an `EventConsumer` and calls `.run()`.
4. `.run()` connects to RabbitMQ, declares the queues, and starts consuming.

Real code from `backend/workers/payment_worker.py`:

```python
def main() -> None:
    setup_logging()
    asyncio.run(
        EventConsumer("payment-worker", "payment.queue", handle).run()
    )
```

- `"payment-worker"` is the consumer name used for deduplication.
- `"payment.queue"` is the RabbitMQ queue it listens to.
- The worker then loops forever, one message at a time (`prefetch=1`).

## Part D: How the frontend starts

1. Nginx starts and serves `/usr/share/nginx/html`, which contains the Flutter build.
2. The browser downloads and runs the compiled Dart app.
3. `frontend/lib/main.dart` runs first.

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.bindPlatformOrigin();
  final container = ProviderContainer();
  container.read(apiClientProvider).onUnauthorized = () {
    container.read(authControllerProvider.notifier).handleUnauthorized();
  };
  runApp(UncontrolledProviderScope(container: container, child: const QuickBiteApp()));
}
```

- It sets up Riverpod's `ProviderContainer` (the shared state holder).
- It connects the API client's "401 unauthorized" callback to the auth controller.
- Then it starts the app widget.

4. `QuickBiteApp` in `frontend/lib/app.dart` builds the router and shows `MaterialApp.router`.
5. The router's `redirect` sends the user to `/splash`, then `/login` or `/` based on auth state.

## Example

- You run `docker compose up --build -d`.
- Postgres and RabbitMQ become healthy.
- The `migration` container runs Alembic, then the seeder creates `customer@quickbite.dev` and the restaurants.
- The API starts and answers `GET /health/ready` with `{"status": "ready"}`.
- You open `http://localhost:8088`, and the Flutter app starts at the splash screen.

## What to remember

- Compose starts Postgres and RabbitMQ first, then a one-off migration/seed step, then the API and workers, then the web app.
- `create_app()` in `backend/app/main.py` is the backend entry point and runs at import time.
- `settings` in `backend/app/core/config.py` is loaded once and shared everywhere.
- Each worker is its own process with a `main()` that connects to one RabbitMQ queue.
- The Flutter app starts in `frontend/lib/main.dart`, sets up Riverpod, then shows the router.

## Builds on

- 1. System Overview
- 2. Project Structure
