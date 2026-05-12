from __future__ import annotations

import asyncio
from collections.abc import Iterable

from fastapi import WebSocket

from ..schemas import RealtimeEnvelope


class RealtimeHub:
    def __init__(self) -> None:
        self._connections: set[WebSocket] = set()
        self._lock = asyncio.Lock()

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        async with self._lock:
            self._connections.add(websocket)

    async def disconnect(self, websocket: WebSocket) -> None:
        async with self._lock:
            self._connections.discard(websocket)

    async def broadcast(self, envelope: RealtimeEnvelope) -> None:
        async with self._lock:
            sockets: Iterable[WebSocket] = tuple(self._connections)
        stale: list[WebSocket] = []
        for websocket in sockets:
            try:
                await websocket.send_json(envelope.model_dump(mode="json"))
            except Exception:
                stale.append(websocket)
        if stale:
            async with self._lock:
                for websocket in stale:
                    self._connections.discard(websocket)
