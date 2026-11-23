import asyncio
import json
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Request
from sse_starlette.sse import EventSourceResponse

from ..security import get_current_user
from ..sse import broadcaster

router = APIRouter(prefix="/api/v1", tags=["stream"])


@router.get("/stream")
async def stream_events(
    request: Request,
    user: dict = Depends(get_current_user),
):
    queue = broadcaster.subscribe()

    async def event_generator():
        try:
            yield {
                "id": "0",
                "event": "connected",
                "data": json.dumps(
                    {
                        "user_id": str(user["id"]),
                        "role": user["role"],
                        "server_time": datetime.now(timezone.utc).isoformat(),
                    }
                ),
            }
            while True:
                if await request.is_disconnected():
                    break
                try:
                    msg = await asyncio.wait_for(queue.get(), timeout=15.0)
                    yield msg
                except asyncio.TimeoutError:
                    yield {"comment": "keep-alive"}
        finally:
            broadcaster.unsubscribe(queue)

    return EventSourceResponse(event_generator())
