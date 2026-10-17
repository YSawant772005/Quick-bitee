# 6. API Communication

## Purpose

- This document explains how the Flutter app talks to the backend.
- All backend calls happen in one file: `frontend/lib/core/api_client.dart`.
- It also explains how errors are turned into simple messages for the user.

## Files involved

- `frontend/lib/core/api_client.dart` — the Dio client and every API method.
- `frontend/lib/core/config.dart` — decides the API base URL.
- `frontend/lib/models/models.dart` — the Dart classes that parse JSON.
- `frontend/nginx.conf` — proxies `/api/` from the browser to the API container.
- `backend/app/main.py` — CORS and the error handlers.

## How it works

1. The app creates one `ApiClient` at startup (see `apiClientProvider`).
2. `AppConfig.resolveApiBaseUrl()` returns the base URL.
   - On the web build it is `/api/v1` (relative), so requests go to the same origin.
   - On mobile it is an absolute URL passed with `--dart-define=API_BASE_URL=...`.
3. Every method calls `_guard(...)`.
4. `_guard` attaches the `Authorization: Bearer <token>` header, then runs the request.
5. If Dio throws, `_mapError` converts it into an `ApiException` with a `code`, `message`, and `details`.
6. If the status is `401`, the client calls `onUnauthorized`, which signs the user out.

## Important code

### The base URL logic

`frontend/lib/core/config.dart`:

```dart
static const String rawApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000/api/v1',
);

static String resolveApiBaseUrl() {
  var base = rawApiBaseUrl;
  if (base.endsWith('/')) base = base.substring(0, base.length - 1);
  if (base.startsWith('/')) {
    assert(kIsWeb, 'Relative API_BASE_URL is only valid on Flutter Web');
    base = '$_webOrigin$base';
  }
  return base;
}
```

- In the Docker image, `frontend/Dockerfile` builds with `--dart-define=API_BASE_URL=/api/v1`.
- A relative `/api/v1` becomes `http://localhost:8088/api/v1` in the browser.
- Nginx then forwards it to the API container.

### The request wrapper

`frontend/lib/core/api_client.dart`:

```dart
Future<Response<T>> _guard<T>(Future<Response<T>> Function() call) async {
  try {
    attachAuthHeader();
    return await call();
  } on DioException catch (e) {
    throw _mapError(e);
  }
}
```

- Every request goes through `_guard`.
- It guarantees the auth header is fresh and that errors are consistent.

### Error mapping

```dart
ApiException _mapError(DioException e) {
  final data = e.response?.data;
  if (data is Map<String, dynamic>) {
    return ApiException(
      e.response?.statusCode ?? 0,
      data['code']?.toString() ?? 'UNKNOWN',
      data['message']?.toString() ?? 'Request failed.',
      details: (data['details'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
  final status = e.response?.statusCode ?? 0;
  if (status == 401) {
    onUnauthorized?.call();
    return ApiException(401, 'UNAUTHENTICATED', 'Your session has expired. Sign in again.');
  }
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout) {
    return ApiException(0, 'TIMEOUT', 'The request timed out. You can safely retry.');
  }
  return ApiException(status, 'NETWORK', 'Network error. Check your connection.');
}
```

- The backend always returns `{code, message, details, request_id}` on errors (see `backend/app/main.py`).
- This method reads those fields directly, so the user sees the backend's plain-language message.
- Timeouts get a special "you can safely retry" message because placing an order is idempotent.

## The API methods

| Dart method | HTTP call | Used by |
|---|---|---|
| `login` | `POST /auth/login` | Login screen |
| `me` | `GET /auth/me` | Session restore |
| `restaurants` / `allRestaurants` | `GET /restaurants` | Home, Explore |
| `restaurantDetail` | `GET /restaurants/{id}` | Menu screen header |
| `menu` / `allMenu` | `GET /restaurants/{id}/menu` | Menu screen |
| `dishes` / `allDishes` | `GET /dishes` | Explore, Home carousels |
| `promotions` | `GET /promotions` | Home banners, Offers |
| `placeOrder` | `POST /orders` | Checkout |
| `orders` | `GET /orders` | Order history |
| `order` | `GET /orders/{id}` | Tracking (polls) |
| `orderHistory` | `GET /orders/{id}/history` | Tracking timeline |
| `notifications` | `GET /notifications` | Notifications feed |
| `adminOrders`, `adminOrder` | `GET /admin/orders...` | Admin console |
| `adminSummary`, `adminAnalytics` | `GET /admin/summary`, `/admin/analytics` | Admin overview |
| `adminRestaurants`, `adminUpdateRestaurant` | `GET`/`PATCH /admin/restaurants...` | Admin restaurants |
| `adminMenuItems`, `adminUpdateMenuItem` | `GET`/`PATCH /admin/menu-items...` | Admin menu |
| `adminCustomers` | `GET /admin/customers` | Admin customers |
| `adminDeliveries` | `GET /admin/deliveries` | Admin deliveries |

### Pagination helper

- `allRestaurants`, `allMenu`, and `allDishes` page through the API until every row is loaded.
- They exist because catalogue screens must not silently drop items after the first page.

### The idempotent order call

```dart
Future<OrderAccepted> placeOrder({
  required String restaurantId,
  required String deliveryAddress,
  required List<OrderLine> items,
  required String idempotencyKey,
}) async {
  final resp = await _guard(() => _dio.post<Map<String, dynamic>>(
        '/orders',
        data: {...},
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      ));
  return OrderAccepted.fromJson(resp.data!);
}
```

- The `Idempotency-Key` header is set here. The checkout screen generates it once per visit with `const Uuid().v4()`.
- Retrying with the same key replays the same order instead of creating a new one.

## Data flow

- **Enters the client:** a method call with Dart values (for example `placeOrder(...)`).
- **The client builds:** a URL path, query parameters or a JSON body, and the auth header.
- **Leaves the client:** an HTTP request to Nginx, which proxies it to FastAPI.
- **Comes back:** a JSON map, which a `fromJson` in `models.dart` turns into a typed object.
- **On error:** an `ApiException` that the screen shows to the user.

## Example

- The Home screen calls `apiClient.allRestaurants(sort: 'popular')`.
- The client sends `GET /api/v1/restaurants?page=1&page_size=100&sort=popular` with the token.
- Nginx forwards it to the API, which returns a paginated list.
- The client builds `Restaurant` objects and the screen renders cards.
- If the token expired, the API returns `401`, the client calls `onUnauthorized`, and the app returns to `/login`.

## What to remember

- `api_client.dart` is the only place the app makes HTTP calls.
- `_guard` adds the token and `_mapError` converts failures into friendly messages.
- The web build uses a relative `/api/v1` URL that Nginx proxies; mobile uses an absolute URL.
- The `Idempotency-Key` header on `placeOrder` is what makes order retries safe.
- A `401` response signs the user out automatically.

## Builds on

- 2. Project Structure
- 3. Application Startup
- 5. Frontend Routing and State
