import asyncio
import json
from typing import Any


class SseBroadcaster:
    """In-process pub/sub broadcaster for Server-Sent Events."""

    def __init__(self) -> None:
        self._subscribers: set[asyncio.Queue[dict[str, Any]]] = set()
        self._event_counter: int = 0

    def subscribe(self) -> asyncio.Queue[dict[str, Any]]:
        q: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=256)
        self._subscribers.add(q)
        return q

    def unsubscribe(self, q: asyncio.Queue[dict[str, Any]]) -> None:
        self._subscribers.discard(q)

    async def publish(self, event: str, data: dict[str, Any]) -> None:
        self._event_counter += 1
        msg = {
            "id": str(self._event_counter),
            "event": event,
            "data": json.dumps(data, default=str),
        }
        stale: list[asyncio.Queue[dict[str, Any]]] = []
        for q in list(self._subscribers):
            try:
                q.put_nowait(msg)
            except asyncio.QueueFull:
                stale.append(q)
        for q in stale:
            self._subscribers.discard(q)


broadcaster = SseBroadcaster()
