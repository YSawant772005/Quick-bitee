# UI Interaction Inventory (assignment §16)

Every visible interactive control in the Flutter client, mapped to its API call,
state effect, failure behaviour and covering test.

Evidence legend:

- **[A]** automated test exists (file given in the *Test* column).
- **[M]** manually verified against the running app at `http://localhost:8088`
  (screenshot file and/or observed behaviour given).
- **[NV]** NOT VERIFIED — implemented in source but neither automated nor
  exercised manually during the audit; gap stated inline.

Source of truth for controls: `frontend/lib/features/**`, `frontend/lib/shared/widgets.dart`,
`frontend/lib/core/api_client.dart`.

---

## 1. Sign-in — `features/auth/login_screen.dart`

| Screen | Control | User action | Expected result | API | State changes | Failure behavior | Test |
|---|---|---|---|---|---|---|---|
| Sign-in | Email field | Enter an address | Accepts input; inline error if malformed | — | Local form state | Validator "Enter a valid email" **[A]** `test/login_screen_test.dart`; **[M]** `01-login.png` |
| Sign-in | Password field | Enter a password | Obscured input; inline error if empty | — | Local form state | Validator "Enter your password" **[A]** `test/login_screen_test.dart` |
| Sign-in | Eye `IconButton` (`login_screen.dart:88`) | Tap | Toggles `_obscure`; glyph switches `visibility` ⇄ `visibility_off` | — | `_obscure` only | None | **[NV]** — no test, never toggled manually. Gap: add widget test asserting glyph/obscure change. |
| Sign-in | "Sign in" button (`login_screen.dart:111`) | Tap | Disabled while `_submitting`; on success router redirects to `/` | `POST /api/v1/auth/login` | `cartProvider` untouched; `authController` → `SignedIn(user)`; token saved via storage adapter | `ApiException.message` shown inline; cart kept. Server 401 → `onUnauthorized` → `SignedOut` **[M]** (live sign-in in every capture session) | Validation only **[A]**; API path **[NV]** |

## 2. Home / restaurant discovery — `features/home/home_screen.dart`

| Screen | Control | User action | Expected result | API | State changes | Failure behavior | Test |
|---|---|---|---|---|---|---|---|
| Home | Restaurant card (`home_screen.dart:141`) | Tap | Push `/restaurant/{id}` (menu screen) | — | Route only | None | **[M]** tap navigated to menu, `03-menu.png` |
| Home | Search field (`home_screen.dart:97`) | Type + submit | Reloads list with `search` param | `GET /api/v1/restaurants?page&page_size&search` | `_search`, `_page`, list | `ErrorState` + Retry button **[NV]** — field exists, submit not exercised. Gap: no test. |
| Home | Cart `IconButton` (`:80`) | Tap | Push `/cart`; badge shows item count | — | Route only | Empty cart renders `EmptyState` | **[M]** badge `2`, `04-cart.png` |
| Home | Notifications `IconButton` (`:62`) | Tap | Push `/notifications` | — | Route only | — | **[M]** reached list, `09-notifications.png` |
| Home | Order history `IconButton` (`:66`) | Tap | Push `/orders` | — | Route only | — | **[M]** reached list, `08-order-history.png` |
| Home | Admin `IconButton` (`:57`) | Tap | Go `/admin` (only when `user.role == admin`, `router.dart` guard) | — | Route only | Non-admin redirected to `/` by router guard | **[M]** as admin, `10-admin.png` |
| Home | Sign out `IconButton` (`:72`) | Tap | Clears token, state `SignedOut`, router → `/login` | — | Storage cleared, `_api.token = null` | Storage errors swallowed | **[M]** sign-out routed to `#/login` |
| Home | Empty/error states (`:127`,`:132`) | — | `EmptyState` "No restaurants match" / `ErrorState` + Retry | — | — | Retry re-runs `_load` | **[NV]** — empty state seen only in source, not triggered |

## 3. Menu — `features/menu/menu_screen.dart`

| Screen | Control | User action | Expected result | API | State changes | Failure behavior | Test |
|---|---|---|---|---|---|---|---|
| Menu | "Add" `TextButton` (`:156`) | Tap | Item added; snackbar "… added to cart"; cart badge increments | — | `cartProvider` gains line at unit price from `menu_item_id` | Cart already bound to another restaurant → confirmation dialog | **[M]** two adds, snackbar + badge `2`, `03-menu.png` |
| Menu | Replace-cart dialog "Cancel" (`:61`) | Tap | Dismiss; cart unchanged | — | None | — | **[NV]** — dialog not exercised |
| Menu | Replace-cart dialog "Replace" (`:62`) | Tap | `Navigator.pop(true)`; cart swapped to this restaurant | — | `cartProvider.replaceRestaurant` | — | **[A]** `test/cart_controller_test.dart` (`replaceRestaurant`); **[NV]** dialog wiring |
| Menu | Cart `IconButton` (`:88`) | Tap | Push `/cart` | — | Route only | — | **[M]** reached cart, `04-cart.png` |

## 4. Cart — `features/cart/cart_screen.dart`

| Screen | Control | User action | Expected result | API | State changes | Failure behavior | Test |
|---|---|---|---|---|---|---|---|
| Cart | `QtyStepper` "+" / "−" (`shared/widgets.dart:159`,`:170`) | Tap | Quantity changes; subtotal recomputed in minor units; "−" disabled at 1 | — | `cartProvider.setQuantity`; set to 0 removes the line | Mixing restaurants throws `CartRestaurantMismatch` | **[A]** `cart_controller_test.dart` (add accumulates, setQuantity zero removes, mismatch throws); **[M]** quantity `2`, subtotal `₹680`, `04-cart.png` |
| Cart | Delete `IconButton` (`:40`) | Tap | Line removed; empty cart shows `EmptyState` | — | `cartProvider.remove` | — | **[A]** via `setQuantity`/remove paths; **[NV]** button not tapped manually |
| Cart | "Proceed to checkout" (`:66`) | Tap | Push `/checkout` | — | Route only | — | **[M]** reached checkout, `05-checkout.png` |

## 5. Checkout and acknowledgement — `features/checkout/checkout_screen.dart`

| Screen | Control | User action | Expected result | API | State changes | Failure behavior | Test |
|---|---|---|---|---|---|---|---|
| Checkout | Delivery address field (`:103`) | Enter < 10 chars, submit | Blocks submit, shows "Enter a full delivery address (min 10 characters)" | — | None | Inline validation, no request sent | **[M]** validation message observed before correction |
| Checkout | "Place order" (`:123`) | Tap (empty cart) | Renders `EmptyState` "Your cart is empty" instead of a form | — | None | — | **[NV]** |
| Checkout | "Place order" (`:123`) | Tap (valid) | Disabled while submitting; on 202 clear cart and `go('/checkout-ack', extra: accepted)` | `POST /api/v1/orders` with header `Idempotency-Key: <uuid v4 generated once per screen>` | `cartProvider.clear`; order row + `order_items` + `order_status_history` + `outbox_events` in one transaction | `ApiException.message` inline; generic failure → "Network error. Your cart is kept — retry with the same key." | Backend **[A]** `tests/test_checkout.py`; UI **[A]** `test/checkout_screen_test.dart` (timeout → cart kept; 202 → cart cleared); success screen **[M]** `06-checkout-ack.png` |
| Checkout | Retry after timeout (same key) | Tap "Place order" again after a timeout | `_idempotencyKey` is `late final` per screen instance, so the retry reuses the identical key; server replays the stored order instead of creating a duplicate | `POST /api/v1/orders` (same key) | No new order row; original order returned | — | Backend replay **[A]** `test_checkout_same_key_replays_same_order`; frontend reuse **[A]** `test/checkout_screen_test.dart` — a receive-timeout then retry asserts both `POST /orders` carry an identical `Idempotency-Key` and identical payload, that the cart survives the failure, and that it clears only on the 202. |
| Acknowledgement | "Track order" (`:185`) | Tap | `go('/orders/{orderId}')` | — | Route only | — | **[M]** reached tracking, `07-order-tracking.png` |
| Acknowledgement | "View order history" (`:191`) | Tap | `go('/orders')` | — | Route only | — | **[NV]** |

## 6. Order tracking — `features/orders/order_detail_screen.dart`

| Screen | Control | User action | Expected result | API | State changes | Failure behavior | Test |
|---|---|---|---|---|---|---|---|
| Order detail | (automatic) | Screen opens | Loads order, history, notifications; then polls every 2 s until a terminal status | `GET /api/v1/orders/{id}`, `/orders/{id}/history`, `/notifications` | `_order`, `_history`, `_notifications`; `_pollTimer` cancelled on terminal status | 5 consecutive failures → `ErrorState`; cart retained | **[A]** `test/order_detail_screen_test.dart` (renders 4 history entries + 4 notifications, empty state absent) |
| Order detail | Pull-to-refresh `RefreshIndicator` (`:105`) | Drag down | Re-runs `_refresh` immediately | same three GETs | `_order` updated | Error banner via `ErrorState` | **[NV]** |
| Order detail | Notifications bell `IconButton` (`:87`) | Tap | Push `/notifications` | — | Route only | — | **[NV]** |
| Order detail | Failure banner (`:160`) | — | Shown only when `failureReason` present (PAYMENT_FAILED / FAILED) | — | — | — | **[NV]** — no failing order opened during the audit |

## 7. Order history — `features/orders/order_history_screen.dart`

| Screen | Control | User action | Expected result | API | State changes | Failure behavior | Test |
|---|---|---|---|---|---|---|---|
| Order history | Order row (`:101`) | Tap | Push `/orders/{id}` | — | Route only | — | **[M]** rows rendered, `08-order-history.png` |
| Order history | Chevron "‹" (`:110`) | Tap | Loads previous page; disabled on page 1 | `GET /api/v1/orders?page&page_size` | `_page`, list | `ErrorState` + Retry (`:63`) | **[NV]** — pagination buttons not clicked; backend pagination **[A]** `test_admin_orders_pagination` |

## 8. Notifications — `features/notifications/notifications_screen.dart`

| Screen | Control | User action | Expected result | API | State changes | Failure behavior | Test |
|---|---|---|---|---|---|---|---|
| Notifications | Notification row (`:88`) | Tap | Push `/orders/{n.orderId}` | — | Route only | — | **[M]** list rendered, `09-notifications.png` |
| Notifications | Chevron "‹"/"›" (`:97`,`:103`) | Tap | Changes page of the feed | `GET /api/v1/notifications?page&page_size` | `_page`, list | `ErrorState` + Retry (`:66`) | **[NV]** |
| Notifications | Empty state (`:70`) | — | `EmptyState` when no notifications | — | — | — | **[NV]** |

## 9. Admin — `features/admin/admin_screen.dart`

| Screen | Control | User action | Expected result | API | State changes | Failure behavior | Test |
|---|---|---|---|---|---|---|---|
| Admin | Status filter dropdown (`:134`) | Select a status | Reloads orders filtered by status; metric cards unchanged | `GET /api/v1/admin/orders?page&page_size&status` | `_status`, `_page`, list | `ErrorState` + Retry (`:82`) | Backend **[A]** `test_admin_orders_lists_and_filters`; UI **[M]** filter control visible, `10-admin.png`; **[NV]** selection not exercised |
| Admin | Chevron "‹"/"›" (`:178`,`:183`) | Tap | Changes orders page | `GET /api/v1/admin/orders?page&page_size` | `_page`, list | `ErrorState` | Backend **[A]** `test_admin_orders_pagination`; UI **[NV]** |
| Admin | Order row (`:169`) | Tap | Push `/orders/{id}` (read-only for admins) | — | Route only | Non-admin blocked by `require_admin` **[A]** | **[NV]** |

## 10. Cross-cutting controls

| Screen | Control | User action | Expected result | API | State changes | Failure behavior | Test |
|---|---|---|---|---|---|---|---|
| All detail screens | AppBar back arrow (implicit `leading`) | Tap | Pops to the previous route; go_router restores the prior screen | — | Route only | None | **[M]** back arrows visible in `03`–`07`; **[NV]** not clicked |
| Home, Menu, History, Notifications, Admin, Order detail | `ErrorState` "Retry" button (`shared/widgets.dart:80`) | Tap | Re-runs that screen's loader with the current page | per-screen GET | Reloads list/detail | — | **[NV]** — all six error states render in source but none triggered |
| Any screen | Expired/invalid JWT | Any request returns 401 | `ApiClient._mapError` → `onUnauthorized` → `AuthController.handleUnauthorized()` → token cleared, `SignedOut`, router refreshes to `/login` | any GET returning 401 | Storage cleared, route change | — | **[M]** logout path only; **[NV]** 401 interception during an active screen |

---

## Summary of coverage

| Status | Count |
|---|---|
| Fully covered by an automated test | 4 of 17 mandatory interaction groups (sign-in validation, cart add/quantity/remove, checkout submission + idempotent retry, admin filtering at the API level) |
| Manually verified in the live app | 10 groups |
| NOT VERIFIED (source-only) | password visibility toggle, replace-cart dialog, pull-to-refresh, history pagination clicks, admin filter selection, admin row navigation, notification paging, acknowledgement "View order history", all six `ErrorState` retry paths, active-session 401 interception |

Assignment §16 requires an interaction to have a documented *Test*; the majority
of rows above currently resolve to "none". Closing that is the main outstanding
work item for this section.