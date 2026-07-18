from collections import defaultdict, deque
from threading import Lock
import time
from uuid import uuid4

from fastapi import Request

from app.core.config import settings
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.responses import JSONResponse, Response


class RequestIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        request_id = request.headers.get("X-Request-ID", str(uuid4()))
        request.state.request_id = request_id

        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        return response


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Small in-process abuse guard for public authentication boundaries."""

    _rules = (
        ("login", "/api/v1/auth/firebase/login", 10, 60.0),
        # Event creation can schedule a cloud-Qwen verification. Keep a separate
        # ceiling below the general edge API limit to control cost abuse.
        ("qwen_verification", "/api/v1/edge/events", 30, 60.0),
        # Heartbeats normally use about 30 requests/minute per edge device.
        ("edge", "/api/v1/edge/", 240, 60.0),
    )
    _attempts: dict[tuple[str, str], deque[float]] = defaultdict(deque)
    _lock = Lock()

    @staticmethod
    def _client_ip(request: Request) -> str:
        # Caddy is the only network peer of FastAPI in the production container group.
        forwarded = request.headers.get("x-forwarded-for", "")
        if forwarded:
            return forwarded.split(",", 1)[0].strip()
        return request.client.host if request.client else "unknown"

    @classmethod
    def reset(cls) -> None:
        """Test hook; production state is process-local and self-pruning."""
        with cls._lock:
            cls._attempts.clear()

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        if settings.app_env != "production" or request.method == "OPTIONS":
            return await call_next(request)

        rule = next(
            (
                (name, limit, window)
                for name, prefix, limit, window in self._rules
                if request.url.path == prefix or request.url.path.startswith(prefix)
            ),
            None,
        )
        if rule is None:
            return await call_next(request)

        name, limit, window = rule
        now = time.monotonic()
        key = (name, self._client_ip(request))
        with self._lock:
            attempts = self._attempts[key]
            cutoff = now - window
            while attempts and attempts[0] <= cutoff:
                attempts.popleft()
            if len(attempts) >= limit:
                retry_after = max(1, int(attempts[0] + window - now))
                return JSONResponse(
                    status_code=429,
                    content={"detail": {"code": "rate_limited", "message": "Too many requests"}},
                    headers={"Retry-After": str(retry_after)},
                )
            attempts.append(now)

        return await call_next(request)


class RequestSizeLimitMiddleware(BaseHTTPMiddleware):
    """Reject oversized HTTP API bodies before JSON parsing or database work."""

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        if settings.app_env != "production" or not request.url.path.startswith("/api/"):
            return await call_next(request)

        content_length = request.headers.get("content-length")
        if content_length:
            try:
                is_oversized = int(content_length) > settings.max_request_body_bytes
            except ValueError:
                is_oversized = True
            if is_oversized:
                return JSONResponse(
                    status_code=413,
                    content={
                        "detail": {
                            "code": "request_too_large",
                            "message": "Request body exceeds the configured limit",
                        }
                    },
                )
        return await call_next(request)


class CsrfOriginMiddleware(BaseHTTPMiddleware):
    """Require same-origin browser mutations when an authenticated cookie is sent."""

    _safe_methods = {"GET", "HEAD", "OPTIONS", "TRACE"}

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        if (
            settings.app_env == "production"
            and request.method not in self._safe_methods
            and settings.session_cookie_name in request.cookies
        ):
            origin = request.headers.get("origin")
            if origin not in settings.cors_origins:
                return JSONResponse(
                    status_code=403,
                    content={
                        "detail": {
                            "code": "csrf_origin_rejected",
                            "message": "Cookie-authenticated requests must come from an allowed origin",
                        }
                    },
                )
        return await call_next(request)