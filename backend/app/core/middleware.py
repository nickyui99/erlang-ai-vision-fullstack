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