# 5. Frontend Routing and State

## Purpose

- This document explains how the Flutter app decides which screen to show.
- It also explains how the app remembers data between screens (state).
- Terms: **route** = a URL path mapped to a screen. **State** = data the app holds in memory.

## Files involved

- `frontend/lib/main.dart` — starts Riverpod and the app.
- `frontend/lib/app.dart` — builds `MaterialApp.router`.
- `frontend/lib/router.dart` — all routes, redirects, and the login guard.
- `frontend/lib/state/auth_controller.dart` — current user and token.
- `frontend/lib/state/cart_controller.dart` — cart contents.
- `frontend/lib/state/admin_range_controller.dart` — admin date-range filter.

## Part A: Routing

- The router is built by `buildRouter(...)` in `frontend/lib/router.dart`.
- It uses the `go_router` package.
- Each `GoRoute` maps a URL path to a screen (a `builder`).
- A `redirect` function runs before every navigation and enforces the login and role rules.

### The redirect rules

1. If auth state is `AuthUnknown` (still restoring a session), go to `/splash`.
2. If auth state is `SignedOut`, go to `/login`.
3. If the user is signed in and tries `/login` or `/splash`, send them to `/` (customer) or `/admin` (admin).
4. If a non-admin tries any `/admin...` path, send them to `/`.

Real code from `frontend/lib/router.dart`:

```dart
redirect: (context, state) {
  final auth = refresher.currentState;
  final location = state.matchedLocation;
  if (auth is AuthUnknown) return location == '/splash' ? null : '/splash';
  if (auth is SignedOut) return location == '/login' ? null : '/login';
  final user = (auth as SignedIn).user;
  final isAdmin = user.role == 'admin';
  if (location == '/login' || location == '/splash') {
    return isAdmin ? '/admin' : '/';
  }
  if (location.startsWith('/admin') && !isAdmin) return '/';
  return null;
}
```

- This single function protects the whole app.
- Admins land on `/admin`; customers land on `/`.

### Main routes

| Path | Screen | Notes |
|---|---|---|
| `/splash` | `SplashScreen` | Shows while the session is restored. |
| `/login` | `LoginScreen` | Email + password. |
| `/` | `HomeScreen` | Restaurant discovery. |
| `/explore` | `ExploreScreen` | Search + filters from query parameters. |
| `/restaurant/:id` | `MenuScreen` | One restaurant's menu. |
| `/offers` | `OffersScreen` | Demo promotions. |
| `/cart` | `CartScreen` | Cart contents. |
| `/checkout` | `CheckoutScreen` | Address + place order. |
| `/checkout-ack` | `CheckoutAckScreen` | Order accepted confirmation. |
| `/orders` | `OrderHistoryScreen` | Past orders. |
| `/orders/:id` | `OrderDetailScreen` | Live tracking, polls every 2s. |
| `/notifications` | `NotificationsScreen` | Notification feed. |
| `/profile` | `ProfileScreen` | Account + logout. |
| `/admin...` | Admin pages | Protected by the redirect. |

### How the router reacts to login changes

- `AuthRefresher` (in `router.dart`) listens to `authControllerProvider`.
- When the auth state changes, it calls `notifyListeners()`.
- The router is created with `refreshListenable: refresher`, so it re-runs the redirect.

## Part B: State management with Riverpod

- QuickBitee uses **Riverpod** to hold state.
- A **provider** is a named source of state. A **controller** is a provider that can change.
- Screens read state with `ref.watch(...)` and change it with `ref.read(...notifier)`.

### Auth state

`frontend/lib/state/auth_controller.dart`:

- `AuthState` is a sealed class with three cases: `AuthUnknown`, `SignedOut`, `SignedIn(user)`.
- `AuthController.build()` starts a session restore and returns `AuthUnknown`.
- `_restore()` reads the stored token and calls `GET /auth/me`.
- `login(...)` calls the API, saves the token, and sets `SignedIn`.
- `logout()` clears the token and sets `SignedOut`.
- `handleUnauthorized()` is called by the API client on any 401.

```dart
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(baseUrl: AppConfig.resolveApiBaseUrl());
});
```

- This one provider creates the single API client used everywhere.
- `main.dart` attaches the 401 handler to it.

### Cart state

`frontend/lib/state/cart_controller.dart`:

- `CartState` holds `restaurantId`, `restaurantName`, and a map of menu item id → `OrderLine`.
- `add(item)` throws `CartRestaurantMismatch` if the item is from a different restaurant.
- `setQuantity(...)` changes or removes a line.
- `replaceRestaurant(...)` clears the cart and starts again.
- `subtotalMinor` and `totalQuantity` are computed getters.

### Admin range state

- `frontend/lib/state/admin_range_controller.dart` holds the admin date range so all admin pages share one filter.

## Data flow

- **Enters auth state:** email and password from the login screen.
- **Auth state leaves:** a `SignedIn(user)` object, which the router reads to allow or block navigation.
- **Enters cart state:** a `MenuItem` when the user taps Add.
- **Cart state leaves:** a list of `OrderLine` objects sent at checkout.
- **Where it is stored:** in memory only (Riverpod). On web, the token is also memory-only, so a page reload signs the user out.

## Example

1. The user opens `http://localhost:8088`.
2. Auth state is `AuthUnknown`, so the router shows `/splash`.
3. There is no saved token, so `_restore()` sets `SignedOut`.
4. The router redirects to `/login`.
5. The user signs in, and the state becomes `SignedIn(customer)`.
6. The router redirects to `/`.
7. The user adds a dish; `cartProvider` now holds one `OrderLine`.
8. The cart badge on the shell updates because the widget watches `cartProvider`.

## What to remember

- `go_router` maps URLs to screens; one `redirect` protects login and admin access.
- Riverpod holds all app state: auth, cart, and admin filters.
- `authControllerProvider` is the source of truth for who is signed in.
- The router listens to auth changes through `AuthRefresher`.
- On the web, the token lives in memory, so reloading signs you out.

## Builds on

- 1. System Overview
- 2. Project Structure
- 3. Application Startup
