from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from .db import create_db_pool
from .routers import auth, controller, events, organizer, stream, tickets


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.pool = await create_db_pool()
    try:
        yield
    finally:
        await app.state.pool.close()


app = FastAPI(
    title="EventFlow Practice 05 API",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(events.router)
app.include_router(tickets.router)
app.include_router(organizer.router)
app.include_router(controller.router)
app.include_router(stream.router)


@app.get("/health")
async def health(request: Request):
    val = await request.app.state.pool.fetchval("SELECT 1")
    return {
        "status": "ok" if val == 1 else "error",
        "db": "ok" if val == 1 else "error",
        "server_time": datetime.now(timezone.utc).isoformat(),
    }
