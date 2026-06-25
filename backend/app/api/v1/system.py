from __future__ import annotations

import socket

from fastapi import APIRouter, Depends, Request

from app.api.deps import get_current_user
from app.models.user import User


router = APIRouter(prefix="/system", tags=["system"])


def _detect_lan_ip() -> str | None:
    """Best-effort primary LAN IPv4 of this host.

    Opens a UDP socket "towards" a public address (no packets are sent) so the
    OS picks the outbound interface, then reads back its local address. This is
    the address an edge device on the same network should use to reach the
    backend — `localhost` would only work on the host itself.
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except OSError:
        return None
    finally:
        sock.close()


@router.get("/network")
async def get_network_info(
    request: Request,
    current_user: User = Depends(get_current_user),
) -> dict:
    """Returns a LAN-reachable host/port for the backend, used to pre-fill the
    camera pairing QR so the device can reach this server."""
    return {
        "data": {
            "lan_ip": _detect_lan_ip(),
            "port": request.url.port or 8000,
        }
    }
