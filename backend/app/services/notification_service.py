"""Firebase Cloud Messaging (FCM) push delivery.

Reuses the Firebase Admin SDK already initialized for auth, so no extra
credentials or infrastructure are required. The service degrades gracefully:
if Firebase is not configured it reports a failure result rather than raising,
so push delivery never breaks the calling flow (e.g. event ingestion).
"""

from __future__ import annotations

from dataclasses import dataclass, field

from app.services.auth_service import _initialize_firebase_admin


@dataclass
class PushResult:
    success_count: int = 0
    failure_count: int = 0
    # Tokens FCM reported as permanently invalid/unregistered; the caller should
    # prune these from storage.
    invalid_tokens: list[str] = field(default_factory=list)
    error: str | None = None

    @property
    def delivered(self) -> bool:
        return self.success_count > 0


# FCM error codes that mean the token is dead and should be removed.
_INVALID_TOKEN_ERRORS = {
    "UNREGISTERED",
    "INVALID_ARGUMENT",
    "registration-token-not-registered",
    "invalid-registration-token",
    "invalid-argument",
}


def send_push(
    tokens: list[str],
    title: str,
    body: str,
    data: dict[str, str] | None = None,
) -> PushResult:
    """Send a single notification to many FCM tokens.

    Returns a :class:`PushResult` summarizing delivery; invalid tokens are
    collected so the caller can prune them. Never raises on delivery failure.
    """

    if not tokens:
        return PushResult()

    try:
        _initialize_firebase_admin()
        from firebase_admin import messaging
    except Exception as exc:  # noqa: BLE001 - configuration / import failure
        return PushResult(failure_count=len(tokens), error=str(exc))

    message = messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(title=title, body=body),
        # FCM data values must be strings.
        data={k: str(v) for k, v in (data or {}).items()},
    )

    try:
        response = messaging.send_each_for_multicast(message)
    except Exception as exc:  # noqa: BLE001 - transport / FCM failure
        return PushResult(failure_count=len(tokens), error=str(exc))

    invalid: list[str] = []
    for token, resp in zip(tokens, response.responses):
        if resp.success:
            continue
        code = getattr(getattr(resp, "exception", None), "code", None)
        if code in _INVALID_TOKEN_ERRORS:
            invalid.append(token)

    return PushResult(
        success_count=response.success_count,
        failure_count=response.failure_count,
        invalid_tokens=invalid,
    )
