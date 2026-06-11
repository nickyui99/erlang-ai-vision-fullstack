# Authentication Flow

SentinelEdge uses two separate authentication paths:

| Actor | Auth method |
|---|---|
| Web app and mobile WebView users | Google OAuth with backend-managed session. |
| Laptop edge service or camera gateway | Device-bound edge token. |

## User Login Flow

1. User opens the web app.
2. Web app sends the user to `GET /api/v1/auth/google/start`.
3. Backend generates OAuth `state` and redirects to Google.
4. Google redirects back to `GET /api/v1/auth/google/callback`.
5. Backend validates the OAuth callback.
6. Backend creates or updates the local `users` row.
7. Backend creates a secure session cookie.
8. Web app calls `GET /api/v1/users/me` to load the current user.

## Google User Mapping

The local `users` table stores the app profile. Google remains the identity provider.

| Field | Source |
|---|---|
| `google_sub` | Stable Google subject claim. |
| `email` | Google profile email. |
| `email_verified` | Google email verification claim. |
| `display_name` | Google profile name. |
| `avatar_url` | Google profile picture URL. |
| `role` | SentinelEdge app role. |

Use `google_sub` as the stable identity key. Do not use email as the primary identity key because email can change.

## Session Cookie Requirements

Recommended cookie settings:

| Setting | Value |
|---|---|
| `HttpOnly` | `true` |
| `Secure` | `true` in production |
| `SameSite` | `Lax` for normal web flows |
| Expiry | Controlled by `SESSION_EXPIRE_MINUTES` |

If cookies are used for authenticated mutation routes, add CSRF protection before production.

## OAuth Validation Rules

The callback must validate:

- OAuth `state`
- Google token signature and issuer
- Google OAuth client ID audience
- email verification
- redirect URI consistency
- optional allowed domain policy, if the app is private

## Edge Token Flow

1. User logs in with Google OAuth.
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
