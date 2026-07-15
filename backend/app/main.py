import asyncio
from contextlib import AsyncExitStack, asynccontextmanager, suppress

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1 import health
from app.api.v1.router import api_router
from app.core.config import settings
from app.core.errors import register_exception_handlers
from app.core.middleware import RequestIdMiddleware
from app.services import media_retention_service


def _mcp_mount_enabled() -> bool:
    # The MCP SDK's StreamableHTTPSessionManager can only .run() once per process,
    # but the test suite re-enters the app lifespan (one per TestClient context) —
    # so the HTTP mount stays off under APP_ENV=test; tests drive the MCP server
    # and the chat tool loop directly instead.
    return settings.mcp_server_enabled and settings.app_env != "test"


@asynccontextmanager
async def _lifespan(app: FastAPI):
    async with AsyncExitStack() as stack:
        if _mcp_mount_enabled():
            # The streamable-HTTP session manager must be running for the mounted
            # MCP app (built in create_app) to serve requests.
            from app.mcp.server import mcp_server

            await stack.enter_async_context(mcp_server.session_manager.run())
        sweep_task: asyncio.Task | None = None
        if settings.media_sweep_interval_seconds > 0:
            sweep_task = asyncio.create_task(media_retention_service.run_sweep_loop())
        try:
            yield
        finally:
            if sweep_task is not None:
                sweep_task.cancel()
                with suppress(asyncio.CancelledError):
                    await sweep_task


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        docs_url="/docs" if settings.app_env != "production" else None,
        redoc_url="/redoc" if settings.app_env != "production" else None,
        lifespan=_lifespan,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_origin_regex=settings.cors_allowed_origin_regex,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.add_middleware(RequestIdMiddleware)
    register_exception_handlers(app)

    app.include_router(health.router)
    app.include_router(api_router, prefix=settings.api_prefix)

    if _mcp_mount_enabled():
        # The platform's tools as an MCP server (bearer-token gated); the Erlang AI
        # Agent chat connects to this as an MCP client, and external clients can too.
        from app.mcp.server import build_mcp_asgi_app

        app.mount(f"{settings.api_prefix}/mcp", build_mcp_asgi_app())

    return app


app = create_app()
