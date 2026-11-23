"""G4 Gate: 10 parallel scans of 10 fresh tickets -> 10 ACCEPTED, repeats ALREADY_USED, 1 entry row each."""
import asyncio
import sys
import uuid
from pathlib import Path

import asyncpg
import httpx

BACKEND_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_ROOT))

from app.main import app
from db.migrate import run_migrations
from db.seed_demo import DATABASE_URL, DEV_PASSWORD, seed_demo


async def main() -> None:
    await run_migrations(DATABASE_URL)
    seed_info = await seed_demo(DATABASE_URL)
    ev_id = seed_info["event_published_id"]
    fresh = seed_info["fresh_tickets"]

    async with app.router.lifespan_context(app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            c1 = (await client.post("/api/v1/auth/login", json={"email": "controller1@eventflow.dev", "password": DEV_PASSWORD})).json()["access_token"]
            c2 = (await client.post("/api/v1/auth/login", json={"email": "controller2@eventflow.dev", "password": DEV_PASSWORD})).json()["access_token"]

            async def race_one(qr: str):
                return await asyncio.gather(
                    client.post("/api/v1/controller/checkin", headers={"Authorization": f"Bearer {c1}"}, json={"event_id": ev_id, "qr_token": qr, "request_id": str(uuid.uuid4())}),
                    client.post("/api/v1/controller/checkin", headers={"Authorization": f"Bearer {c2}"}, json={"event_id": ev_id, "qr_token": qr, "request_id": str(uuid.uuid4())}),
                )

            results = await asyncio.gather(*(race_one(t["qr_token"]) for t in fresh))
            accepted = 0
            already_used = 0
            for r_a, r_b in results:
                for r in (r_a, r_b):
                    st = r.json()["status"]
                    if st == "ACCEPTED":
                        accepted += 1
                    elif st == "ALREADY_USED":
                        already_used += 1

            conn = await asyncpg.connect(DATABASE_URL)
            entries_count = await conn.fetchval("SELECT COUNT(*) FROM entries WHERE event_id = $1", uuid.UUID(ev_id))
            await conn.close()

            print(f"Parallel race results: ACCEPTED={accepted}, ALREADY_USED={already_used}, DB entries={entries_count}")
            assert accepted == 10, f"Expected 10 ACCEPTED, got {accepted}"
            assert already_used == 10, f"Expected 10 ALREADY_USED, got {already_used}"
            assert entries_count == 10, f"Expected 10 entries rows, got {entries_count}"
            print("G4 RACE GATE PASSED!")


if __name__ == "__main__":
    asyncio.run(main())
