from typing import AsyncGenerator
import asyncpg
from fastapi import Request
from .config import settings


async def create_db_pool() -> asyncpg.Pool:
    return await asyncpg.create_pool(
        dsn=settings.database_url,
        min_size=2,
        max_size=20,
    )


async def get_pool(request: Request) -> asyncpg.Pool:
    return request.app.state.pool


async def get_conn(request: Request) -> AsyncGenerator[asyncpg.Connection, None]:
    pool: asyncpg.Pool = request.app.state.pool
    async with pool.acquire() as conn:
        yield conn
