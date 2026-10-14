# QUICKBITE — MASTER IMPLEMENTATION BLUEPRINT
## Complete Full-Stack Food Ordering System
**Version:** 2.0 — Implementation specification for an AI IDE  
**Primary stack:** Flutter + Dart, Python + FastAPI, PostgreSQL, RabbitMQ, Docker Compose, Nginx  
**Primary objective:** Build a complete, reliable, visually polished, testable food-ordering application for Web, Android, and iOS, with asynchronous order processing and demonstrable failure recovery.

---

# 1. MASTER OBJECTIVE

Build QuickBite as a complete food-ordering application inspired by the usability of Swiggy and Zomato, while keeping the implementation suitable for an academic engineering assignment.

This is not a static UI prototype or a collection of disconnected CRUD endpoints.

Every required screen, route, button, form, API, database operation, worker, queue, status transition, retry mechanism, notification, and administrative feature must be connected to a working end-to-end workflow.

The application must support:

1. Customers signing in and browsing restaurants.
2. Browsing restaurant menus containing real food photographs.
3. Adding and removing products from a cart.
4. Validating delivery details and placing orders.
5. Processing orders asynchronously through RabbitMQ.
6. Simulating payment, restaurant confirmation, and driver assignment.
7. Tracking orders and their complete status history.
8. Displaying persisted in-app notifications.
9. Viewing paginated order history.
10. Administrators inspecting orders and system processing statistics.
11. Handling duplicate requests, worker failures, retries, broker outages, and recovery.
12. Running the complete development stack using one documented startup command.
13. Testing and demonstrating the application on Web, Android, and iOS.
14. Providing reproducible setup instructions, automated tests, architecture documentation, and submission evidence.

**Definition of done:** A feature is complete only when its UI, API, database changes, authorization, error handling, and applicable tests work together. A button that only changes the UI, a route that returns placeholder data, or a worker that does not actually consume RabbitMQ messages is not a completed feature.

# 2. INSTRUCTIONS FOR THE AI IDE

Act as a senior full-stack engineer, backend architect, Flutter engineer, database engineer, DevOps engineer, and test engineer.

Use this document as the authoritative implementation specification.

## 2.1 Working rules

- First inspect the existing repository, its source files, project structure, Git state, configuration, tests, and current implementation.
- If an existing QuickBite project is present, extend it rather than replacing it unnecessarily.
- Preserve working features and existing user data.
- Do not delete working modules simply to impose a preferred structure.
- Reuse existing installed tools and dependencies whenever suitable.
- Do not repeatedly check whether tools are installed after their availability has already been established.
- Do not waste tokens repeatedly rereading unchanged files or producing progress reports without implementation.
- Make reasonable implementation decisions autonomously.
- Implement the project phase by phase, preserving working code between phases.
- Run focused tests after each meaningful phase and the full test suite before completion.
- Fix failures caused by your changes before proceeding.
- Do not claim a test passed without executing it and observing the result.
- Do not mark features complete merely because code was generated.
- Never commit credentials, populated secret environment files, access tokens, signing keys, or real customer information.
- Do not introduce unrelated features before the mandatory scope is complete.
- Do not stop after producing an architecture document, plan, mockup, or initial scaffold. Continue implementing the actual application.

## 2.2 Required engineering workflow

For every feature:

1. Define the expected user behavior.
2. Identify the relevant Flutter screens and controls.
3. Identify the API endpoints and request/response contracts.
4. Identify the database entities and transactions involved.
5. Identify the asynchronous events and workers involved, if applicable.
6. Implement the complete feature.
7. Add appropriate validation, authorization, and error handling.
8. Add automated tests.
9. Verify the complete workflow.
10. Update the implementation tracker and documentation.

Maintain a requirements traceability matrix connecting each requirement to its implementation files, API routes, UI controls, tests, and verification evidence.

# 3. REQUIRED TECHNOLOGY STACK

Use the following stack unless an existing compatible implementation already satisfies the requirement.

| Layer | Technology | Responsibility |
|---|---|---|
| Frontend | Flutter | Shared application for Web, Android and iOS |
| Language | Dart | Frontend application logic |
| State management | Riverpod | Shared application state and async UI states |
| HTTP client | Dio | API requests, timeouts, authentication and error handling |
| Request/response models | Dart typed models, using a consistent serialization approach | Type-safe API integration |
| Backend | Python + FastAPI | REST API and application services |
| Validation | Pydantic v2 | Request, response and configuration validation |
| ORM | SQLAlchemy 2.x async | Database access |
| Database migrations | Alembic | Versioned schema migrations |
| Database | PostgreSQL | Persistent application and messaging metadata |
| Messaging | RabbitMQ | Asynchronous event distribution |
| Python broker client | aio-pika | Publishing and consuming AMQP messages |
| Reverse proxy | Nginx | Public HTTP entry point, routing and Flutter Web hosting |
| Containers | Docker | Isolated, reproducible service environments |
| Orchestration | Docker Compose | Starts and manages the complete local stack |
| Backend tests | pytest | API, transaction, worker and integration tests |
| Frontend tests | flutter_test | Widget and state tests |
| End-to-end tests | integration_test | Application workflow tests |
| HTTP load tests | Locust or a repeatable Python load-test script | Latency, throughput and backlog measurements |
| Logging | Python structured JSON logging | Request, event, worker and recovery observability |
| API documentation | FastAPI OpenAPI | API contract and interactive API documentation |
| Version control | Git + GitHub | Source control and reproducible changes |

Pin compatible dependency and container image versions. Commit applicable lockfiles. Document the actual versions used.

Do not add Redis, Kubernetes, Elasticsearch, a separate frontend framework, or unrelated infrastructure unless a concrete requirement justifies it.

# 4. SYSTEM ARCHITECTURE

## 4.1 Logical architecture

The system must follow this architecture:

```text
                  CUSTOMER / ADMIN
                          |
              Flutter Application
             Web / Android / iOS
                          |
                     HTTP / HTTPS
                          |
                        NGINX
                   /              \
            Flutter Web         /api/v1
            Static Assets           |
                               FastAPI API
                                   |
                     +-------------+-------------+
                     |                           |
                 PostgreSQL                  Authentication
                     |
          +----------+-----------+
          |                      |
     Order Transaction      Outbox Events
          |                      |
          |                Outbox Dispatcher
          |                      |
          |                   RabbitMQ
          |                      |
          |       +--------------+-------------+
          |       |              |             |
          |    Payment       Restaurant     Delivery
          |     Worker         Worker        Worker
          |       |              |             |
          |       +--------------+-------------+
          |                      |
          |               Domain Event Outbox
          |                      |
          |              Notification Worker
          |                      |
          +----------------------+
                     |
                PostgreSQL
                     |
             FastAPI Read APIs
                     |
             Flutter Polling UI

Additional infrastructure:
- Retry Scheduler
- Durable retry_jobs records
- Quarantine records and dead-letter queue
- RabbitMQ Management UI
- Health checks
- Structured logs
- Load and recovery test scripts
```

## 4.2 Service boundaries

Flutter must communicate only with FastAPI.

Nginx is the public entry point for the browser deployment. The Flutter mobile applications communicate with the reachable FastAPI API address, directly or through the deployed reverse-proxy endpoint.

The browser and mobile clients must never connect directly to PostgreSQL or RabbitMQ.

All order status reads must come from the backend. The client must not infer that payment or delivery succeeded just because a certain amount of time has passed.

PostgreSQL is the authoritative source for business state.

RabbitMQ transports events; it is not the authoritative order database.

The payment, restaurant, delivery and notification workers must run as independently managed processes.

## 4.3 One-command startup requirement

The user must be able to start the complete local application with one documented command:

```bash
docker compose up --build -d
```

The command must start the complete required stack, including:

- Nginx and Flutter Web hosting.
- FastAPI.
- PostgreSQL.
- RabbitMQ and its management interface.
- Payment worker.
- Restaurant worker.
- Delivery worker.
- Notification worker.
- Outbox dispatcher.
- Retry scheduler.

Use a single Compose project with named services and shared configuration.

**Important architectural decision:** One command should start the whole system, but the system must not be implemented as one giant container containing every process. Separate containers preserve the worker boundaries required for scaling, independent restarts, graceful shutdown, and failure demonstrations.

Docker Compose is the single startup interface. Multiple containers are still necessary internally.

Use health checks and dependency readiness rather than relying only on startup order.

Migrations and data seeding must be explicit, repeatable operations. The Compose startup workflow must ensure they finish before application services begin using the schema. Do not allow every worker to run migrations concurrently.

Provide an idempotent initialization mechanism, such as a dedicated migration/seed service or documented initialization script.

Use named volumes for PostgreSQL and RabbitMQ persistence.

# 5. NGINX REQUIREMENTS

Nginx is required for the Web deployment.

Configure it to:

1. Serve the compiled Flutter Web application.
2. Serve static assets efficiently.
3. Support Flutter SPA deep-link fallback.
4. Forward `/api/v1/*` requests to FastAPI.
5. Forward health-check requests appropriately.
6. Support API timeouts suitable for normal HTTP requests.
7. Set reasonable request body limits.
8. Forward appropriate request headers.
9. Avoid exposing database or broker credentials.
10. Support HTTPS through a documented deployment configuration.
11. Keep the RabbitMQ Management UI separate from the public customer-facing interface.
12. Return meaningful HTTP errors when the backend is unavailable.

Example routing concept:

```nginx
server {
    listen 80;
    server_name localhost;

    root /usr/share/nginx/html;
    index index.html;

    location /api/ {
        proxy_pass http://api:8000;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

This is a routing illustration, not a complete production configuration. Generate and test the actual configuration, including appropriate proxy timeouts, health checks, static caching, security headers, and WebSocket upgrade headers if WebSockets are implemented.

Do not configure public HTTPS with a self-signed or imaginary production certificate. Document the actual deployment requirements.

For mobile development, use an appropriate reachable API address. Do not hard-code the browser's localhost address for every device.

# 6. FRONTEND IMPLEMENTATION SPECIFICATION

Build a polished, responsive food-ordering experience with reusable widgets and a consistent design system.

## 6.1 Design requirements

Use a modern food-commerce visual style.

Required elements:

- High-quality, real food photography.
- Clear restaurant and dish cards.
- Readable typography and consistent spacing.
- Clear primary and secondary buttons.
- Visible cart count.
- Prominent order status.
- Consistent success, warning and failure states.
- Responsive phone and desktop layouts.
- Keyboard navigation on Web.
- Semantic labels and sufficient contrast.
- Proper loading skeletons or loading indicators.
- Useful empty states and retry actions.
- Accessible text scaling.
- No overflowing cards, clipped buttons or inaccessible navigation.
- No dead links or decorative controls pretending to be functional.

Avoid a generic unstyled admin template or a screen containing only text lists.

## 6.2 Real food images are mandatory

The restaurant and menu screens must display actual photographs of food, not emojis, gradients, generated placeholder blocks, or repeated stock images used to fill every card.

Requirements:

1. Source suitable images from legitimate, reusable image sources such as Unsplash or Pexels.
2. Verify the selected image URL or download the actual image asset.
3. Check image licensing and attribution requirements.
4. Prefer locally packaged image assets for the seeded restaurant and menu catalog so the demonstration is not dependent on a third-party image server.
5. Use appropriate thumbnail sizes and image caching.
6. Use a consistent aspect ratio for restaurant covers and menu item photographs.
7. Provide a graceful fallback if an image fails to load.
8. Avoid broken links, irrelevant food photographs, duplicate images across unrelated dishes, and excessively large source files.
9. Maintain a catalog-to-image mapping so each seeded item displays the correct photograph.
10. Document image sources and attribution in the repository.

Seed a varied demonstration catalog, for example:

- Biryani and rice dishes.
- Pizza.
- Burgers.
- South Indian food.
- North Indian meals.
- Noodles and Asian food.
- Desserts.
- Beverages.

Use fictional restaurant names and realistic seeded menu data. Each menu item must have its own stable ID, name, description, price, availability, restaurant association and image mapping.

Do not invent a successful download or assume an external URL works. Verify the actual assets.

## 6.3 Required customer screens

### Screen A — Sign-in

Elements:

- Email input.
- Password input.
- Password visibility toggle.
- Sign-in button.
- Loading state.
- Invalid-credentials message.
- Network-error message.
- Token-expired handling.
- Seeded demo-account instructions.

Every control must work.

Registration is optional.

### Screen B — Home / Restaurant discovery

Elements:

- QuickBite branding.
- Restaurant list.
- Restaurant image.
- Restaurant name and description.
- Restaurant availability.
- Search and category filtering as a useful frontend extension.
- Empty state.
- Retry/refresh action.
- Cart indicator.
- Account and order-history navigation.

The required baseline includes restaurant browsing. Search and richer filters are optional extensions unless separately required by the assessment.

### Screen C — Restaurant menu

Elements:

- Restaurant information and cover image.
- Menu item image.
- Item name and description.
- Server-provided price.
- Availability indicator.
- Quantity controls or Add button.
- Cart count update.
- Clear unavailable-item state.
- Back navigation.

### Screen D — Cart

Elements:

- Selected item photographs.
- Item names and unit prices.
- Quantity increment/decrement.
- Item removal.
- Subtotal.
- Delivery address.
- Address validation.
- Checkout button.
- Empty-cart state.
- Checkout loading state.
- Validation errors.

The client may display an estimated subtotal, but the server calculates the authoritative order total.

Each order must contain items from exactly one restaurant.

### Screen E — Checkout acknowledgement

Display:

- Server-issued order ID.
- Accepted total and currency.
- Initial order status.
- Message that processing is continuing.
- View order button.
- Navigation to order history.

Do not claim that payment succeeded when the server has only accepted the order.

### Screen F — Order details and tracking

Display:

- Order ID.
- Order items and photographs.
- Accepted total.
- Delivery address in the authorized owner's view.
- Current status.
- Ordered status timeline.
- Current driver assignment when present.
- Persisted notifications.
- Failure reason when applicable.
- Last updated timestamp.
- Refresh or retry control.
- Back-to-history action.

Poll approximately every two seconds while the active order details screen is visible.

Stop or reduce polling when the screen is disposed, the app is backgrounded, or the order reaches a terminal state. Back off after failures and refresh when the app resumes.

### Screen G — Order history

Display:

- Order ID.
- Date/time.
- Item summary.
- Total.
- Current status.
- Pagination controls or incremental loading.
- Refresh.
- Open-order-details action.
- Empty state.
- Loading and error states.

The customer must see only their own orders.

### Screen H — Notifications

Display persisted notifications retrieved from the backend.

Include:

- Notification title or message.
- Related order.
- Event timestamp.
- Navigation to the related order.
- Empty and error states.

Notification persistence is required. OS push notifications are not required.

### Screen I — Admin overview

Display:

- Total orders.
- Counts by order status.
- Paginated cross-customer order list.
- Status filtering.
- Order details.
- Pending outbox count.
- Retry backlog count.
- Quarantine count.

Admin pages must be read-only for this assignment.

Do not expose administrative controls to customers merely by hiding a button. Backend authorization is mandatory.

## 6.4 Flutter architecture

Organize the frontend into clear responsibilities:

```text
frontend/lib/
  app/
    app.dart
    router.dart
    theme/
  core/
    api/
      api_client.dart
      api_errors.dart
    auth/
    storage/
    config/
    widgets/
  features/
    auth/
    restaurants/
    menu/
    cart/
    checkout/
    orders/
    notifications/
    admin/
  models/
  shared/
```

Adapt the exact layout to the existing repository if necessary.

Use:

- A centralized Dio client.
- Typed request and response models.
- Centralized authentication handling.
- Riverpod providers/notifiers for shared state.
- Clear separation between presentation, domain logic and API adapters.
- Platform-specific token-storage adapters.
- Build-time `API_BASE_URL` configuration.

On mobile, use appropriate secure storage for persistent tokens. On Web, in-memory token storage is acceptable for the required implementation, with sign-in required again after a page reload.

Never persist passwords.

# 7. BACKEND ARCHITECTURE

Separate the API, domain logic, persistence and messaging concerns.

Suggested layout:

```text
backend/
  app/
    main.py
    core/
      config.py
      security.py
      logging.py
      errors.py
    api/
      dependencies.py
      v1/
        auth.py
        users.py
        restaurants.py
        menu.py
        orders.py
        notifications.py
        admin.py
    schemas/
    models/
    repositories/
    services/
    domain/
      order_state_machine.py
      transitions.py
      pricing.py
    messaging/
      connection.py
      topology.py
      envelopes.py
      publisher.py
      consumer.py
      outbox.py
      retries.py
      quarantine.py
    db/
      session.py
      base.py
  workers/
    payment_worker.py
    restaurant_worker.py
    delivery_worker.py
    notification_worker.py
    outbox_dispatcher.py
    retry_scheduler.py
  migrations/
  tests/
```

Create separate modules for routes, schemas, services, repositories and worker responsibilities.

Do not place the complete application inside a single enormous Python file.

# 8. DATABASE DESIGN

Use PostgreSQL for all required concurrency and transaction demonstrations.

Implement migrations for these entities.

| Entity | Required responsibility |
|---|---|
| users | Customer/admin accounts, password hashes and roles |
| restaurants | Restaurant information and availability |
| menu_items | Item information, price, currency and availability |
| orders | Customer, restaurant, total, status, version and timestamps |
| order_items | Item snapshot, quantity and checkout price |
| order_status_history | Append-only status transitions |
| simulated_payments | One logical payment result per order |
| driver_assignments | Simulated driver assignment |
| notifications | Persisted customer event notifications |
| processed_events | Worker/event deduplication |
| outbox_events | Pending and completed outgoing event publications |
| retry_jobs | Durable delayed retry scheduling |
| quarantine_records | Failed or malformed event inspection |
| idempotency records | Checkout request key, canonical payload hash and stored response |

Use normalized tables, foreign keys, database constraints and indexes.

Required data rules:

- Orders have one customer and one restaurant.
- Order items retain the menu item name and server-authoritative price at checkout.
- Money is represented in integer minor units.
- API timestamps use UTC with timezone information.
- Order history is append-only.
- Every valid transition increments the order version.
- Unique constraints prevent duplicate payment, assignment and relevant notification records.
- Idempotency records are scoped to the authenticated customer.
- Menu prices and order totals are never trusted from the client.

Document any naming differences or equivalent normalized structures.

# 9. REST API CONTRACT

Use `/api/v1` for domain routes.

Implement every route below and document it in OpenAPI.

| Method | Endpoint | Access | Required behavior |
|---|---|---|---|
| POST | `/api/v1/auth/login` | Public | Return expiring access token and user role |
| GET | `/api/v1/me` | Signed in | Return current profile |
| GET | `/api/v1/restaurants` | Signed in | Paginated restaurant list |
| GET | `/api/v1/restaurants/{id}/menu` | Signed in | Paginated menu |
| POST | `/api/v1/orders` | Customer | Create idempotent asynchronous order |
| GET | `/api/v1/orders` | Customer | Paginated personal order history |
| GET | `/api/v1/orders/{id}` | Owner or admin | Order details and current status |
| GET | `/api/v1/orders/{id}/history` | Owner or admin | Ordered status timeline |
| GET | `/api/v1/orders/{id}/notifications` | Owner or admin | Paginated notification feed |
| GET | `/api/v1/admin/orders` | Admin | Cross-customer order overview |
| GET | `/api/v1/admin/summary` | Admin | Status counts and backlog counts |
| GET | `/health/live` | Health probe | Process liveness |
| GET | `/health/ready` | Health probe | Bounded dependency readiness checks |

Use consistent pagination:

- `page`
- `page_size`
- `total`

The maximum page size is 100.

Use a consistent error structure:

```json
{
  "code": "INVALID_REQUEST",
  "message": "The request could not be processed.",
  "details": {},
  "request_id": "req_example"
}
```

Implement suitable status codes:

- 401 — missing, invalid or expired authentication.
- 403 — authenticated user lacks permission.
- 404 — missing resources or another customer's protected order.
- 409 — conflicting reuse of an idempotency key.
- 422 — invalid input.

Protect all routes consistently and test them directly.

# 10. CHECKOUT AND ORDER STATE MACHINE

## 10.1 Checkout request

The Flutter client submits:

```http
POST /api/v1/orders
Authorization: Bearer <access_token>
Idempotency-Key: <client-generated-uuid>
Content-Type: application/json
```

```json
{
  "restaurant_id": "rest_123",
  "delivery_address": "12 Lake Road, Bengaluru",
  "items": [
    {
      "menu_item_id": "item_biryani",
      "quantity": 2
    },
    {
      "menu_item_id": "item_lassi",
      "quantity": 1
    }
  ]
}
```

The client must not submit an authoritative customer ID, price or total.

## 10.2 Checkout transaction

In one PostgreSQL transaction:

1. Validate the authenticated customer.
2. Validate the restaurant and menu items.
3. Reject unavailable items.
4. Reject mixed-restaurant items.
5. Validate quantities and address.
6. Calculate the total from current server-side menu prices.
7. Check and reserve the idempotency key.
8. Create the order in `PENDING`.
9. Insert initial status history.
10. Store the canonical request hash and acceptance response.
11. Insert the `order.created` outbox event.
12. Commit the transaction.
13. Return HTTP 202 Accepted and the order ID.

If the transaction fails, do not return an accepted response.

If the same customer retries with the same key and payload, return the same order ID and acceptance response.

If the same key is reused with a different payload, return HTTP 409.

Concurrent identical submissions must produce exactly one order.

If RabbitMQ is offline after the transaction commits, the outbox must preserve the event for later publication.

## 10.3 Allowed order transitions

```text
PENDING
  |
  +----> PAID
  |        |
  |        +----> CONFIRMED
  |                    |
  |                    +----> DRIVER_ASSIGNED
  |
  +----> PAYMENT_FAILED

PAID -----------------------> FAILED

CONFIRMED ------------------> FAILED
```

`PAYMENT_FAILED`, `FAILED` and `DRIVER_ASSIGNED` are terminal states for this assignment.

Implement transition validation in a shared domain service.

Use row locks or compare-and-set version checks. Reject backward transitions.

Transient failures must leave the order at its last successful state until processing succeeds or the retry policy is exhausted.

Notification failures must never change business order status.

# 11. RABBITMQ EVENT ARCHITECTURE

Use a durable topic exchange:

`quickbite.orders`

Declare the complete queue topology before publishing events.

| Queue | Binding | Worker responsibility |
|---|---|---|
| `payment.queue` | `order.created` | Simulate payment |
| `restaurant.queue` | `order.paid` | Simulate restaurant confirmation |
| `delivery.queue` | `order.confirmed` | Assign simulated driver |
| `notification.queue` | `order.#` | Persist notifications for supported order events |

The notification binding must be `order.#`, not `order.*`, because notification processing must also receive multi-segment events such as `order.payment.failed`.

Implement these event types:

- `order.created`
- `order.paid`
- `order.payment.failed`
- `order.confirmed`
- `order.driver.assigned`
- `order.failed`

Each event must include:

- `event_id`
- `schema_version`
- `event_type`
- `order_id`
- `order_version`
- `occurred_at`
- `correlation_id`
- `causation_id`
- `data`

Use immutable event IDs and preserve them across redelivery.

Configure persistent messages, publisher confirms, mandatory routing, manual acknowledgements, durable exchanges and queues, bounded prefetch, reconnect backoff and graceful shutdown.

A publisher confirmation alone does not establish that a message was successfully routed. Handle unroutable messages and publication failures.

# 12. TRANSACTIONAL OUTBOX AND WORKER IDEMPOTENCY

The outbox dispatcher must:

1. Select eligible unsent records.
2. Claim them using a lock or lease safe for multiple dispatcher instances.
3. Publish to the configured exchange and routing key.
4. Use publisher confirms and mandatory routing.
5. Mark the record sent only after confirmation and successful routing.
6. Leave failed records eligible for a delayed retry.
7. Avoid losing records if the dispatcher crashes.

A crash after publishing but before marking the event sent may create duplicate delivery. Downstream consumers must therefore be idempotent.

Every worker must follow this sequence:

1. Receive the event.
2. Validate the envelope and supported schema.
3. Acquire the appropriate database lock.
4. Check `processed_events` using the unique pair `(consumer_name, event_id)`.
5. Validate the current order status and version.
6. Apply the allowed transition at most once.
7. Insert associated business records, status history and outgoing outbox events in the same transaction.
8. Commit.
9. Acknowledge the incoming RabbitMQ message.

If the event has already been processed, acknowledge it without repeating effects.

If the transaction fails, do not mark the event successfully processed.

Do not claim exactly-once message delivery.

# 13. RETRIES, QUARANTINE AND FAILURE INJECTION

Implement durable retries with this default policy:

- Initial processing attempt.
- Retry after approximately 2 seconds.
- Retry after approximately 10 seconds.
- Retry after approximately 30 seconds.
- Quarantine after all allowed attempts fail.

Make retry attempts and delays configurable.

Persist retry jobs and schedule targeted redelivery to the queue of the failing worker.

Do not republish a payment retry to the general topic exchange if doing so would incorrectly send the event to unrelated subscribers.

Do not use an immediate `nack(requeue=True)` loop for known processing failures.

When retrying:

1. Roll back the failed business transaction.
2. Persist a uniquely identified retry job and scheduled retry publication.
3. Commit that transaction.
4. Acknowledge the original message only after the retry is durably scheduled.

If durable retry scheduling fails, preserve the original message for safe recovery.

When attempts are exhausted, persist quarantine information and publish the quarantine envelope through the configured durable dead-letter path.

For exhausted payment processing, transition to `PAYMENT_FAILED` and emit `order.payment.failed`.

For exhausted restaurant or delivery processing, transition to `FAILED` and emit `order.failed`.

For notification processing, record the failure without changing the order's business status.

Provide deterministic development/test failure controls:

- Payment succeeds.
- Payment fails twice and then succeeds.
- Payment always fails.
- Worker crashes at a selected checkpoint.
- Restaurant confirmation fails.
- Driver assignment fails.
- Notification processing fails.

Keep failure injection outside ordinary customer checkout fields. Restrict it to test configuration or protected demonstration scripts.

# 14. AUTHENTICATION AND SECURITY

Implement:

- Password hashing with an established password-hashing library.
- Signed, expiring bearer tokens.
- Server-side role enforcement.
- Seeded customer and admin accounts.
- Validated JWT claims.
- Token-expiry handling.
- Customer order ownership enforcement.
- Explicit CORS origins for Web.
- Environment-based secrets and configuration.
- Secure token storage on supported mobile platforms.
- No persistent passwords.
- No credentials bundled in Flutter or exposed in the repository.
- No tokens, passwords or full delivery addresses in logs.

Document the demo accounts in the README.

The backend must enforce authorization independently of the frontend.

# 15. ORDER NOTIFICATIONS AND TRACKING

Persist notifications in PostgreSQL.

Generate notification records from the supported order events, using a uniqueness rule that prevents duplicate logical notifications.

The Flutter app must display notifications even if the notification worker was temporarily unavailable.

Use the backend's current order state as the source of truth.

On an active order detail screen:

- Poll approximately every two seconds.
- Stop or reduce polling when the order reaches a terminal state.
- Stop polling when the screen is disposed or the app is backgrounded.
- Back off after repeated request failures.
- Refresh when the app resumes.
- Never show a simulated success solely because time has elapsed.

WebSockets may be added later, but polling is sufficient for the required implementation.

# 16. END-TO-END BUTTON AND ROUTE COMPLETENESS

Every visible interactive element must have a documented action.

Create a UI interaction inventory with these columns:

| Field | Description |
|---|---|
| Screen | Where the control appears |
| Control | Exact button, link, form or selector |
| User action | What the user does |
| Expected result | What should happen |
| API | Endpoint called, if any |
| State changes | Frontend/database state changes |
| Failure behavior | Error, retry or validation behavior |
| Test | Test verifying the interaction |

Mandatory interactions include:

- Sign-in submission and password visibility.
- Restaurant navigation.
- Menu navigation.
- Add to cart.
- Quantity increment/decrement.
- Remove cart item.
- Checkout validation and submission.
- Safe retry after a checkout timeout using the same idempotency key.
- View order.
- Refresh order.
- Navigate between order history pages.
- Open an order from history.
- Navigate from a notification to its order.
- Admin status filtering and pagination.
- Logout or session expiry handling.
- All relevant back-navigation controls.
- Loading and error-state retry controls.

Audit all buttons, links, dropdowns, text inputs, tabs, navigation destinations and form submissions.

Do not add controls that have no meaningful behavior.

# 17. TESTING STRATEGY

Use pytest for backend tests and Flutter's testing tools for frontend verification.

## Backend tests

Test:

- Login success and failure.
- Expired and invalid tokens.
- Customer/admin permissions.
- Order ownership.
- Restaurant and menu pagination.
- Unavailable menu items.
- Invalid quantities.
- Mixed-restaurant orders.
- Server-side price calculation.
- Idempotent checkout.
- Concurrent checkout.
- Conflicting idempotency-key reuse.
- Valid and invalid state transitions.
- Outbox publication and recovery.
- Worker event deduplication.
- Manual acknowledgement boundaries.
- Retry scheduling.
- Quarantine handling.
- Duplicate payment and assignment prevention.
- Notification persistence.
- Health endpoints.

## Integration tests

Use a real PostgreSQL instance and real RabbitMQ for the required transaction, acknowledgement, redelivery and concurrency demonstrations.

Test:

1. Worker crash during processing.
2. Worker crash after database commit but before acknowledgement.
3. Broker outage after checkout acceptance.
4. Dispatcher crash after publish but before marking an event sent.
5. Duplicate and out-of-order event delivery.
6. Notification-worker outage.
7. Fail-twice-then-succeed payment.
8. Permanent payment failure.
9. Terminal restaurant and delivery failures.
10. Safe recovery after restart.

Mocks alone are not sufficient for these broker and transaction guarantees.

## Flutter tests

Test:

- Sign-in and authentication errors.
- Restaurant/menu rendering.
- Cart totals and quantities.
- Checkout validation.
- Checkout timeout and same-key retry.
- Order acknowledgement.
- Tracking and polling lifecycle.
- History pagination.
- Notification navigation.
- Admin authorization and filtering.
- Empty, loading, error and offline states.
- Phone and desktop responsive layouts.

Add an end-to-end test covering:

`Sign in → Browse restaurant → Open menu → Add items → Checkout → Track order → View history`

## Load and scaling test

Run at least 100 orders with a fixed successful simulation.

Compare one payment worker against three payment workers under the same workload and repeat the measurements at least twice.

Record:

- Hardware and runtime environment.
- Order count and concurrency.
- Simulated stage delays.
- API p50 and p95 latency.
- Total processing time.
- Orders per second.
- Queue backlog.
- Outbox backlog and age.
- Worker throughput.

Target create-order p95 below 500 ms in the documented local environment, but report actual measured results rather than inventing a passing benchmark.

# 18. DOCKER COMPOSE REQUIREMENTS

Create a working `compose.yaml` with services equivalent to:

```text
nginx
api
postgres
rabbitmq
payment-worker
restaurant-worker
delivery-worker
notification-worker
outbox-dispatcher
retry-scheduler
migration-seed
```

The Flutter Web build must be included in the Nginx image or supplied through an equivalent reproducible build stage.

Use:

- Named persistent volumes.
- Health checks.
- Internal Docker networking.
- Restart policies where appropriate.
- Environment variables.
- A shared backend image for worker services where sensible.
- Independent worker commands.
- No fixed container names that interfere with scaling.
- No unnecessary host ports for internal services.
- Local-only RabbitMQ management access by default.
- A documented way to scale the payment worker.

Required commands should include:

```bash
docker compose up --build -d
docker compose ps
docker compose logs -f
docker compose logs -f api payment-worker
docker compose down
docker compose down -v
```

Explain that `docker compose down -v` deletes the named volumes and persisted local database/broker data. It must not be presented as a routine restart command.

The README must state the actual Web URL, API URL and RabbitMQ management URL after successful startup.

Provide an appropriate development workflow for running Flutter on Android and iOS, because native mobile builds are not themselves run as Compose services.

# 19. CONFIGURATION AND REPRODUCIBILITY

Provide `.env.example` containing placeholders for:

- Database URL.
- AMQP URL.
- JWT signing configuration.
- CORS origins.
- Simulated stage delays.
- Test failure controls.
- Retry policy.
- Logging configuration.

Validate required settings at application startup.

Do not commit a populated `.env`.

Use `API_BASE_URL` as a Flutter build/run configuration parameter, for example:

```bash
flutter run -d chrome \
  --dart-define=API_BASE_URL=http://localhost/api/v1
```

Adjust the actual URL and prefix consistently with the API client and Nginx configuration. Avoid double-appending `/api/v1`.

For Android emulators, document the appropriate reachable host address or the Nginx endpoint if the deployment configuration supports it.

For physical devices, document the required reachable LAN address or HTTPS endpoint.

For iOS simulator/device testing, document the required macOS/Xcode setup.

# 20. IMPLEMENTATION PHASES

Implement the project in this order.

## Phase 0 — Repository audit and baseline

- Inspect the existing repository and Git state.
- Identify implemented, partially implemented and missing features.
- Inspect dependencies, tests and current run commands.
- Preserve working implementation.
- Create a requirement-to-file/API/test traceability matrix.
- Record baseline build and test results.

**Exit criteria:** A verified project inventory exists, and no unnecessary replacement of working code has occurred.

## Phase 1 — Architecture and foundation

- Define the domain model.
- Define the order state machine.
- Define the API contract and event schemas.
- Scaffold or complete FastAPI and Flutter.
- Establish configuration management.
- Create the initial Docker Compose environment.
- Add PostgreSQL and RabbitMQ.
- Add Nginx and verify basic routing.
- Implement Alembic migrations and repeatable seed scripts.

**Exit criteria:** The stack starts, dependencies become healthy, migrations run successfully, and health endpoints work.

## Phase 2 — Authentication and catalog

- Implement password hashing and token-based login.
- Seed customer and admin accounts.
- Implement role and ownership authorization.
- Create restaurant and menu APIs.
- Seed realistic catalog data.
- Source and verify actual food photographs.
- Implement restaurant and menu screens.
- Test catalog pagination and API error handling.

**Exit criteria:** A user can sign in, browse restaurants and open a menu containing correct, working food images.

## Phase 3 — Cart, checkout and persistence

- Implement cart state and quantity handling.
- Implement address validation.
- Implement server-side price calculation.
- Implement order and order-item persistence.
- Implement checkout idempotency.
- Implement initial status history.
- Implement transactional outbox records.
- Implement order acknowledgement and order-read APIs.
- Add concurrency tests.

**Exit criteria:** A customer can place an order, receive a stable order ID, safely retry checkout and read the accepted order.

## Phase 4 — RabbitMQ and asynchronous workers

- Define durable queues, bindings and event envelopes.
- Implement outbox dispatch.
- Implement payment worker.
- Implement restaurant worker.
- Implement delivery worker.
- Implement notification worker.
- Implement database-backed event deduplication.
- Implement safe transaction/acknowledgement boundaries.
- Implement concurrency-safe state transitions.

**Exit criteria:** The complete successful order lifecycle works asynchronously, and duplicate event deliveries do not duplicate committed business effects.

## Phase 5 — Retry, quarantine and recovery

- Implement durable retry jobs and scheduler.
- Implement targeted delayed redelivery.
- Implement quarantine records and dead-letter routing.
- Implement deterministic failure scenarios.
- Implement reconnection and graceful shutdown.
- Verify worker and dispatcher crash recovery.
- Verify RabbitMQ outage recovery.
- Verify notification isolation.

**Exit criteria:** Every required failure scenario can be reproduced and its recovery can be demonstrated with database records, logs and queue evidence.

## Phase 6 — Complete customer and admin frontend

- Finish all required Flutter screens.
- Connect every control to its actual action.
- Implement tracking and polling lifecycle.
- Implement persisted notification display.
- Implement paginated history.
- Implement read-only admin overview and summary.
- Implement responsive Web/phone layouts.
- Fix empty, loading, error and offline states.
- Verify session expiry and safe checkout retry.

**Exit criteria:** Every required user workflow works end to end without dead buttons, mock order status or disconnected screens.

## Phase 7 — Testing and scaling

- Run backend unit tests.
- Run real PostgreSQL/RabbitMQ integration tests.
- Run Flutter widget tests.
- Run Flutter integration tests.
- Run Web and Android checks.
- Run iOS checks where macOS/Xcode access is available.
- Execute the 100-order load test.
- Compare one versus three payment workers.
- Record actual metrics.
- Fix failures and rerun affected tests.

**Exit criteria:** All required checks have recorded results, and any platform validation that could not be performed is explicitly identified.

## Phase 8 — Packaging and submission

- Verify one-command Docker Compose startup.
- Verify the Web app is served through Nginx.
- Verify SPA deep links after reload.
- Verify API routing and health checks.
- Verify persistent volumes.
- Finalize README and exact commands.
- Finalize architecture and event-flow diagrams.
- Document API contracts and event schemas.
- Capture screenshots and demo recordings.
- Generate the Android debug APK.
- Produce iOS simulator evidence or document the pending validation and build plan.
- Finalize the engineering report and demo script.

**Exit criteria:** Another developer can clone the repository, follow the documented steps, start the stack, run tests and reproduce the demonstration.

# 21. REQUIREMENTS TRACEABILITY AND FINAL AUDIT

Maintain a machine-readable or tabular requirements matrix with these columns:

```text
Requirement ID
Requirement description
Priority
Frontend screen/control
Frontend file
API method/path
Backend file
Database entities
RabbitMQ event/worker
Automated test
Manual verification
Status
Evidence
```

Use unique IDs such as:

- `AUTH-001`
- `CATALOG-001`
- `CART-001`
- `CHECKOUT-001`
- `ORDER-001`
- `NOTIFY-001`
- `ADMIN-001`
- `OUTBOX-001`
- `RETRY-001`
- `QUARANTINE-001`
- `RECOVERY-001`
- `LOAD-001`
- `PLATFORM-001`

Before declaring completion, perform these audits:

1. Compare every required screen against the implementation.
2. Compare every required API route against the OpenAPI contract and tests.
3. Compare every visible button and link against the interaction inventory.
4. Compare every state transition against the domain state machine.
5. Compare every event type against queue bindings and consumer tests.
6. Compare every database entity against migrations and constraints.
7. Compare every failure scenario against executable test scripts.
8. Verify all required images and image mappings.
9. Verify every Compose service starts and becomes healthy.
10. Verify customer/admin authorization directly against the backend.
11. Verify the clean-install process from documented instructions.
12. Verify the final report reflects actual test results and limitations.

# 22. OPTIONAL FEATURES — ONLY AFTER THE REQUIRED BASELINE

Possible extensions include:

- WebSocket updates with polling fallback.
- Prometheus/Grafana metrics.
- Role-protected quarantine inspection and replay.
- Real email/SMS or operating-system push notifications.
- Registration and token refresh.
- Notification read/unread state.
- CI build and test automation.
- TLS deployment and rate limiting.
- Real payment sandbox integration.
- Cancellation/refunds or inventory reservations.

These are secondary. Do not delay the mandatory implementation to add them.

# 23. FINAL EXECUTION INSTRUCTION

Start by auditing the current repository. Then execute the implementation phases sequentially, using the requirements matrix as the source of truth.

Do not merely explain what should be built. Make the changes in the repository, run the relevant commands and tests, fix failures, and preserve evidence of what actually works.

Do not skip requirements because they are complex. If a requirement cannot be completed because of an actual external constraint, implement the available portion, document the blocker, and identify the exact remaining action.

Do not claim all three platforms, recovery guarantees, load targets, real images, or Docker startup have been verified unless the corresponding checks have actually been performed.

The final result must be a complete, maintainable QuickBite implementation with a working Flutter client, FastAPI backend, PostgreSQL persistence, RabbitMQ processing, reliable workers, Nginx web hosting, one-command Docker Compose startup, real food photographs, complete user workflows, automated tests, and reproducible documentation.