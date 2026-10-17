# Knowledge Bytes — Index

This index shows what you will learn in each document. Read them in order for the best results.

| Document | What I will learn | Commit |
|---|---|---|
| [01-system-overview.md](01-system-overview.md) | What the project is, who uses it, and the overall architecture (frontend, API, PostgreSQL, RabbitMQ, workers). | Not committed |
| [02-project-structure.md](02-project-structure.md) | The important folders and files in `backend/`, `frontend/`, and where to find them. | Not committed |
| [03-application-startup.md](03-application-startup.md) | How everything starts: compose order, FastAPI entry, workers, and the Flutter app. | Not committed |
| [04-request-and-data-flow.md](04-request-and-data-flow.md) | Traces a real order placement end-to-end, including the idempotent API call and background processing. | Not committed |
| [05-frontend-routing-and-state.md](05-frontend-routing-and-state.md) | How `go_router` and `Riverpod` work together for login, routes, and the cart. | Not committed |
| [06-api-communication.md](06-api-communication.md) | The Dio API client, how errors are mapped, and how Nginx proxies requests. | Not committed |
| [07-backend-routing-and-persistence.md](07-backend-routing-and-persistence.md) | How FastAPI routes map to handlers, and the SQLAlchemy models and schemas that store data. | Not committed |
| [08-authentication-and-authorization.md](08-authentication-and-authorization.md) | JWT login, password hashing, and the `customer` vs `admin` guards. | Not committed |
| [09-order-pipeline-and-workers.md](09-order-pipeline-and-workers.md) | The transactional outbox, RabbitMQ topology, the state machine, and how workers move orders forward. | Not committed |
| [10-failure-handling-and-retries.md](10-failure-handling-and-retries.md) | Durable retries, quarantine, crash injection, and terminal status effects. | Not committed |
| [11-catalogue-and-search-workflow.md](11-catalogue-and-search-workflow.md) | How restaurants, dishes, and promotions are browsed, filtered, and enriched with real data. | Not committed |
| [12-admin-dashboard-workflow.md](12-admin-dashboard-workflow.md) | The admin console: overview, orders, catalogue, customers, deliveries, and analytics. | Not committed |
| [13-testing-and-debugging.md](13-testing-and-debugging.md) | How to run the 34 backend and 7 frontend tests, plus scripts and debugging tips. | Not committed |

The documents are short, use plain English and numbered steps, and point to real file paths and code snippets.
