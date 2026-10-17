# 8. Authentication and Authorization

## Purpose

- This document explains how a user signs in and how the backend knows who is asking.
- **Authentication** = proving who you are. **Authorization** = what you are allowed to do.
- QuickBitee has two roles: `customer` and `admin`.

## Files involved

- `backend/app/api/v1/auth.py` — the login and `me` endpoints.
- `backend/app/core/security.py` — password hashing and JWT create/decode.
- `backend/app/api/dependencies.py` — `get_current_user` and `require_admin`.
- `backend/app/models/users.py` — the `users` table with `role`.
- `frontend/lib/state/auth_controller.dart` — login, logout, session restore.
- `frontend/lib/core/auth_storage.dart` — where the token is stored.

## How it works

### Signing in

1. The user types an email and password on the login screen.
2. `AuthController.login(...)` calls `ApiClient.login(...)`.
3. `ApiClient.login` sends `POST /api/v1/auth/login` with `{email, password}`.
4. `login` in `backend/app/api/v1/auth.py` loads the user by lower-cased email.
5. It calls `verify_password(...)`, which uses bcrypt to compare the password with the stored hash.
6. On success it calls `create_access_token(user.id, user.role)`.
7. It returns `{access_token, expires_in, user}`.
8. The app saves the token and sets the state to `SignedIn`.

`backend/app/api/v1/auth.py`:

```python
@router.post("/login", response_model=TokenResponse)
async def login(payload: LoginRequest, session: AsyncSession = Depends(get_session)) -> TokenResponse:
    user = (await session.execute(select(User).where(User.email == payload.email.lower()))).scalar_one_or_none()
    if user is None or not verify_password(payload.password, user.password_hash):
        raise UnauthorizedError("Invalid email or password.", {"reason": "invalid_credentials"})
    token, expires_in = create_access_token(user.id, user.role)
    return TokenResponse(access_token=token, expires_in=expires_in, user=UserOut.model_validate(user))
```

- Wrong email and wrong password both return the same message, so an attacker cannot discover valid emails.
- The response includes the user so the app does not need a second call.

### Making a token

`backend/app/core/security.py`:

```python
def create_access_token(user_id: str, role: str) -> tuple[str, int]:
    expires_in = settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "role": role,
        "iat": now,
        "exp": now + timedelta(seconds=expires_in),
        "jti": str(uuid.uuid4()),
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM), expires_in
```

- A JWT (JSON Web Token) is a signed string that carries the user id (`sub`), the role, and an expiry.
- It is signed with `JWT_SECRET`, so it cannot be changed without the secret.
- It expires after `ACCESS_TOKEN_EXPIRE_MINUTES` (default 60 minutes).

### Checking a token on every request

- `get_current_user` reads the `Authorization: Bearer <token>` header.
- It decodes the token with `decode_access_token`.
- It loads the `User` row and returns it, or raises `UnauthorizedError`.
- Expired tokens raise a `401` with `details.reason = "expired"`.

`backend/app/core/security.py`:

```python
def decode_access_token(token: str) -> dict:
    try:
        return jwt.decode(token, settings.JWT_SECRET, algorithms=[settings.JWT_ALGORITHM])
    except jwt.ExpiredSignatureError as exc:
        raise UnauthorizedError("Token has expired.", {"reason": "expired"}) from exc
    except jwt.InvalidTokenError as exc:
        raise UnauthorizedError("Token is invalid.", {"reason": "invalid"}) from exc
```

### Authorization rules

- Most read endpoints require a signed-in user (`get_current_user`).
- Placing an order also requires `current_user.role == "customer"`.
- Every admin endpoint uses `require_admin`:

```python
async def require_admin(current_user: User = Depends(get_current_user)) -> User:
    if current_user.role != "admin":
        raise ForbiddenError("Administrator role required.")
    return current_user
```

- `403` means "signed in but not allowed"; `401` means "not signed in or bad token".

### Storing the token in the app

`frontend/lib/core/auth_storage.dart`:

- On mobile, the token is saved with `flutter_secure_storage`.
- On the web, `markWeb()` is called and the token is kept in memory only.
- On the web, reloading the page loses the token, so the user signs in again. This is a documented limitation.

### Signing out

- `AuthController.logout()` clears the stored token, clears the API client's token, and sets `SignedOut`.
- If any API call returns `401`, `ApiClient.onUnauthorized` calls `handleUnauthorized()`, which does the same thing automatically.

## Data flow

- **Enters login:** an email and a plain password.
- **The backend does:** look up the user, bcrypt-verify the password, sign a JWT.
- **Leaves login:** `{access_token, expires_in, user}`.
- **The app stores:** the token, in memory on web and in secure storage on mobile.
- **Later requests carry:** `Authorization: Bearer <token>`.
- **On expiry:** a `401` response triggers an automatic sign-out and return to `/login`.

## Example

- The admin signs in with `admin@quickbite.dev` / `Admin#123`.
- The token's `role` claim is `admin`, and `SignedIn(user)` has `role: "admin"`.
- The router redirects to `/admin`.
- The admin opens `/admin/orders`, which calls `GET /api/v1/admin/orders` with the token.
- `require_admin` accepts it. If a customer tried the same URL, the router would redirect to `/`, and the API would return `403` anyway.

## What to remember

- Login compares the password with a bcrypt hash and returns a signed JWT.
- The JWT carries the user id and role and expires after 60 minutes by default.
- `get_current_user` protects normal routes; `require_admin` protects admin routes.
- `401` = not authenticated, `403` = not authorized.
- On the web the token is memory-only, so a reload signs the user out.

## Builds on

- 3. Application Startup
- 5. Frontend Routing and State
- 7. Backend Routing and Persistence
