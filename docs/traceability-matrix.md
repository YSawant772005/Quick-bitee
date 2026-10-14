# Requirements Traceability Matrix

Columns: Requirement | Frontend (screen / file) | API | Backend file | DB entities | RabbitMQ | Automated test | Status / evidence

## AUTH-001 Sign in with email + password, JWT session
- UI: Login screen — `frontend/lib/features/auth/login_screen.dart`
- API: `POST /api/v1/auth/login`, `GET /api/v1/auth/me`
- Backend: `app/api/v1/auth.py`, `app/core/security.py`
- DB: `users`
- MQ: —
- Tests: `tests/test_auth.py` (6 tests: success, wrong password, unknown user, no token, profile, garbage token)
- Status: ✅ verified (pytest)

## AUTH-002 Route guards; global 401 handling; admin-only admin screen
- UI: `frontend/lib/router.dart` (redirect + admin guard), `lib/main.dart` (onUnauthorized → sign out)
- API: `require_admin` dependency — `app/api/dependencies.py`
- Backend: `app/api/v1/admin.py`
- DB: `users.role`
- MQ: —
- Tests: `tests/test_admin.py::test_admin_orders_requires_admin`, `tests/test_checkout.py::test_checkout_admin_role_forbidden`
- Status: ✅ verified

## CATALOG-001 Browse restaurants (real photos, search, availability)
- UI: Home screen — `frontend/lib/features/home/home_screen.dart`
- API: `GET /api/v1/restaurants`
- Backend: `app/api/v1/restaurants.py`, `app/seed.py`, `app/static/catalog/` (48 photos, `docs/IMAGES.md`)
- DB: `restaurants`
- MQ: —
- Tests: `tests/test_catalog.py::test_restaurants_listed`
- Status: ✅ verified

## CATALOG-002 Browse menu with prices in minor units
- UI: Menu screen — `frontend/lib/features/menu/menu_screen.dart`
- API: `GET /api/v1/restaurants/{id}/menu`
- Backend: `app/api/v1/restaurants.py`
- DB: `menu_items`
- MQ: —
- Tests: `tests/test_catalog.py::test_menu_items`, `test_menu_unknown_restaurant_404`
- Status: ✅ verified

## CART-001 Add/remove items, single-restaurant constraint
- UI: Menu + cart screens — `frontend/lib/features/cart/cart_screen.dart`, `lib/state/cart_controller.dart`
- API: —
- Backend: —
- DB: —
- MQ: —
- Tests: `frontend/test/cart_controller_test.dart` (4 tests)
- Status: ✅ verified

## CHECKOUT-001 Place order with validated delivery address + idempotency
- UI: Checkout + ack — `frontend/lib/features/checkout/checkout_screen.dart` (per-screen `Idempotency-Key`)
- API: `POST /api/v1/orders` (202; requires header 8–80 chars)
- Backend: `app/api/v1/orders.py`, `app/services/order_service.py`
- DB: `orders`, `order_items`, `order_status_history`, `idempotency_records`, `outbox_events`
- MQ: `order.created` → `payment.queue`
- Tests: `tests/test_checkout.py` (9 tests incl. replay, 409 mismatch, duplicate items, mixed restaurant, roles); server-total test
- Status: ✅ verified

## ORDER-001 Async pipeline PENDING → PAID → CONFIRMED → DRIVER_ASSIGNED
- UI: Order detail with 2 s polling until terminal — `frontend/lib/features/orders/order_detail_screen.dart`
- API: `GET /api/v1/orders/{id}`, `/orders/{id}/history`
- Backend: `workers/payment_worker.py`, `workers/restaurant_worker.py`, `workers/delivery_worker.py`, `workers/common.py`
- DB: `orders.version`, `order_status_history`, `simulated_payments`, `driver_assignments`
- MQ: `order.created`/`order.paid`/`order.confirmed`/`order.driver.assigned`
- Tests: `tests/test_workers.py::test_full_pipeline_happy_path`
- Status: ✅ verified

## ORDER-002 Version guard + idempotent redelivery
- Backend: `workers/common.py` (`record_processed`, `SELECT FOR UPDATE`, version check)
- DB: `processed_events` unique(consumer, event)
- Tests: `tests/test_workers.py::test_worker_processing_is_idempotent`, `test_version_mismatch_raises_process_failure`
- Status: ✅ verified

## ORDER-003 Paginated order history
- UI: `frontend/lib/features/orders/order_history_screen.dart`
- API: `GET /api/v1/orders` (page/page_size)
- Backend: `app/api/v1/orders.py`
- DB: `orders`
- Tests: `tests/test_admin.py::test_admin_orders_pagination` (admin list), manual UI check
- Status: ✅ verified

## NOTIFY-001 Persisted notifications, never change business status
- UI: `frontend/lib/features/notifications/notifications_screen.dart`
- API: `GET /api/v1/notifications`, `/orders/{id}/notifications`
- Backend: `workers/notification_worker.py`
- DB: `notifications` unique(order, event_type)
- MQ: `notification.queue` bound `order.#`
- Tests: `tests/test_workers.py::test_notification_worker_never_changes_business_status`
- Status: ✅ verified

## ADMIN-001 Read-only dashboard: orders + status filter + system stats
- UI: `frontend/lib/features/admin/admin_screen.dart`
- API: `GET /api/v1/admin/orders`, `/api/v1/admin/summary`
- Backend: `app/api/v1/admin.py`
- DB: all orders tables + `outbox_events`, `retry_jobs`, `quarantine_records`
- Tests: `tests/test_admin.py` (4 tests)
- Status: ✅ verified

## OUTBOX-001 Transactional outbox, confirms + mandatory, at-least-once recovery
- Backend: `app/messaging/outbox.py` (`emit_outbox`, lease + skip_locked dispatch), `app/messaging/publisher.py`
- DB: `outbox_events`
- MQ: publish to `quickbite.orders`
- Tests: `tests/test_recovery.py::test_outbox_dispatch_publishes_and_marks_sent`; live recovery of a stuck order observed during development
- Status: ✅ verified

## RETRY-001 Durable retries with backoff, targeted redelivery
- Backend: `app/messaging/retries.py` (`schedule_retry`, on-conflict update), `workers/retry_scheduler.py`
- DB: `retry_jobs` unique(event_id)
- MQ: direct redelivery to queue with `x_attempt` header
- Tests: `tests/test_recovery.py::test_retry_job_scheduled_and_updates`
- Status: ✅ verified

## QUARANTINE-001 Exhausted events quarantined; terminal status applied
- Backend: `app/messaging/retries.py` (`quarantine_event`, `_apply_terminal_effects`)
- DB: `quarantine_records`
- MQ: `quickbite.quarantine` exchange + `quarantine.queue`
- Tests: `tests/test_workers.py::test_payment_always_fail_then_retry_exhaustion` → PAYMENT_FAILED + `order.payment.failed`
- Status: ✅ verified (live demo + pytest)

## RECOVERY-001 Failure injection: payment modes, worker crash points
- Backend: `workers/common.py` (`maybe_crash` before/after tx), failure modes in each worker
- Config: env vars (`backend/.env.example`)
- Tests: live runs during development (`always_fail` → PAYMENT_FAILED; `twice_then_succeed` → success at attempt 3); crash recovery relies on outbox + dedupe
- Status: ✅ verified live; partially automated

## LOAD-001 100-order benchmark + 1 vs 3 payment workers
- Script: `backend/scripts/load_test.py`
- Status: see PROJECT_STATUS.md for measured numbers

## PLATFORM-001 One-command startup; docs; tests; evidence
- `compose.yaml` (11 services), `README.md`, `docs/screenshots/`, `PROJECT_STATUS.md`
- Status: ✅ verified (compose up output + screenshots)

## Platform matrix
- Web (Flutter build → Nginx): ✅ verified end-to-end
- Android: debug APK buildable (`flutter build apk --debug`); not shipped in repo
- iOS: not buildable on Windows (no Xcode) — documented limitation
