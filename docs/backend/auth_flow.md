# Authentication Flow

Erlang AI Vision uses two separate authentication paths:

| Actor | Auth method |
|---|---|
| Web app and mobile users | Firebase Google sign-in with backend-managed session. |
| Laptop edge service or camera gateway | Device-bound edge token. |

## User Login Flow

1. User opens the web app.
2. Web app signs the user in with Firebase Auth Google sign-in.
3. Firebase returns a Firebase ID token to the frontend.
4. Web app sends the ID token to `POST /api/v1/auth/firebase/login`.
5. Backend validates the Firebase ID token with Firebase Admin SDK.
6. Backend creates or updates the local `users` row.
7. Backend creates a secure session cookie.
8. Web app calls `GET /api/v1/users/me` to load the current user.

## Google User Mapping

The local `users` table stores the app profile. Firebase Auth is the identity broker, with Google as the enabled provider.

| Field | Source |
|---|---|
| `google_sub` | Stable Firebase `uid`. |
| `email` | Firebase user email. |
| `email_verified` | Firebase email verification claim. |
| `display_name` | Firebase token `name` claim. |
| `avatar_url` | Firebase token `picture` claim. |
| `role` | Erlang AI Vision app role. |

Use `google_sub` as the stable identity key for now, even though it stores the Firebase `uid`. Do not use email as the primary identity key because email can change.

## Session Cookie Requirements

Recommended cookie settings:

| Setting | Value |
|---|---|
| `HttpOnly` | `true` |
| `Secure` | `true` in production |
| `SameSite` | `Lax` for normal web flows |
| Expiry | Controlled by `SESSION_EXPIRE_MINUTES` |

If cookies are used for authenticated mutation routes, add CSRF protection before production.

## Firebase Validation Rules

The backend login endpoint must validate:

- Firebase token signature and issuer
- Firebase project audience
- email verification
- optional allowed domain policy, if the app is private

## Edge Token Flow

1. User logs in with Firebase Google sign-in.
2. User registers a device through `POST /api/v1/devices`.
3. Backend creates `devices.device_id`.
4. Backend creates a raw edge token and stores only `edge_token_hash`.
5. Backend returns the raw token once.
6. Laptop edge service stores that raw token locally.
7. Edge service calls edge APIs with:

```http
Authorization: Bearer <edge_token>
```

The backend resolves:

```text
edge_token -> device_id -> user_id
```

Edge requests must not be allowed to choose an arbitrary trusted `user_id`.

## Authorization Rules

- User-facing APIs must filter by authenticated `user_id`.
- Edge APIs must derive `device_id` and `user_id` from the edge token.
- Device tokens should be rotatable and revocable.
- Tool calls must validate target device ownership before command relay.
- Signed media URLs must only be generated for media owned by the current user.

## Logout

`POST /api/v1/auth/logout` should clear or invalidate the backend session.

For server-side sessions, delete the session record. For signed-cookie sessions, clear the cookie and use short expiry.
