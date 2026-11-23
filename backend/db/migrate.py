import asyncio
import os
from pathlib import Path
import asyncpg

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://eventflow:eventflow_dev@localhost:5432/eventflow",
).replace("postgresql+asyncpg://", "postgresql://")

MIGRATIONS_DIR = Path(__file__).parent / "migrations"


async def run_migrations(dsn: str = DATABASE_URL) -> list[str]:
    conn = await asyncpg.connect(dsn)
    applied_now: list[str] = []
    try:
        await conn.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version TEXT PRIMARY KEY,
                applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            );
            """
        )
        rows = await conn.fetch("SELECT version FROM schema_migrations")
        already = {r["version"] for r in rows}

        for sql_file in sorted(MIGRATIONS_DIR.glob("*.sql")):
            version = sql_file.name
            if version in already:
                continue
            sql = sql_file.read_text(encoding="utf-8")
            async with conn.transaction():
                await conn.execute(sql)
                await conn.execute(
                    "INSERT INTO schema_migrations (version) VALUES ($1)",
                    version,
                )
            applied_now.append(version)
            print(f"Applied migration: {version}")
    finally:
        await conn.close()
    return applied_now


if __name__ == "__main__":
    applied = asyncio.run(run_migrations())
    if not applied:
        print("No pending migrations.")
