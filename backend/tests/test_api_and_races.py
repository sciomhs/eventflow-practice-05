import asyncio
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
import uuid

import asyncpg
import httpx
import pytest

BACKEND_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_ROOT))

from app.main import app
from db.migrate import run_migrations
from db.seed_demo import seed_demo, DATABASE_URL, DEV_PASSWORD


@pytest.fixture(scope="module")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


async def _login(client: httpx.AsyncClient, email: str, password: str = DEV_PASSWORD) -> str:
    r = await client.post("/api/v1/auth/login", json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


@pytest.mark.asyncio
async def test_full_api_and_concurrency():
    await run_migrations(DATABASE_URL)
    seed_info = await seed_demo(DATABASE_URL)

    async with app.router.lifespan_context(app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            # Login all roles
            p1_tok = await _login(client, "participant1@eventflow.dev")
            p2_tok = await _login(client, "participant2@eventflow.dev")
            org_tok = await _login(client, "organizer@eventflow.dev")
            c1_tok = await _login(client, "controller1@eventflow.dev")
            c2_tok = await _login(client, "controller2@eventflow.dev")

            # T01: Role tampering & ownership
            r_tamper = await client.post(
                "/api/v1/auth/register",
                json={"name": "Hacker", "email": "hacker@eventflow.dev", "password": "Password123!", "role": "organizer"},
            )
            assert r_tamper.status_code == 403

            r_patch = await client.patch(
                "/api/v1/auth/me",
                headers={"Authorization": f"Bearer {p1_tok}"},
                json={"role": "organizer", "used_at": "2026-01-01T00:00:00Z"},
            )
            assert r_patch.status_code == 403

            p1_ticket_id = seed_info["participant1_ticket"]["id"]
            r_other_ticket = await client.get(
                f"/api/v1/tickets/{p1_ticket_id}",
                headers={"Authorization": f"Bearer {p2_tok}"},
            )
            assert r_other_ticket.status_code == 403

            # T02 & T04: Registration + idempotent replay + R3 uniqueness
            ev_pub_id = seed_info["event_published_id"]
            ev_detail = (await client.get(f"/api/v1/events/{ev_pub_id}")).json()
            std_type_id = next(t["id"] for t in ev_detail["ticket_types"] if t["name"] == "Стандарт")

            req_id_1 = f"reg-{uuid.uuid4()}"
            r1, r2 = await asyncio.gather(
                client.post(
                    f"/api/v1/events/{ev_pub_id}/register",
                    headers={"Authorization": f"Bearer {p2_tok}"},
                    json={"type_id": std_type_id, "request_id": req_id_1},
                ),
                client.post(
                    f"/api/v1/events/{ev_pub_id}/register",
                    headers={"Authorization": f"Bearer {p2_tok}"},
                    json={"type_id": std_type_id, "request_id": req_id_1},
                ),
            )
            assert r1.status_code == 200 and r2.status_code == 200
            outcomes = {r1.json()["outcome"], r2.json()["outcome"]}
            assert "ISSUED" in outcomes

            # Different request_id -> ALREADY_REGISTERED
            r3 = await client.post(
                f"/api/v1/events/{ev_pub_id}/register",
                headers={"Authorization": f"Bearer {p2_tok}"},
                json={"type_id": std_type_id, "request_id": f"reg-{uuid.uuid4()}"},
            )
            assert r3.json()["outcome"] == "ALREADY_REGISTERED"

            # T03: Last-seat race (AI Summit has 1 Стандарт seat left)
            ev_last_id = seed_info["event_last_seat_id"]
            last_detail = (await client.get(f"/api/v1/events/{ev_last_id}")).json()
            last_std_id = next(t["id"] for t in last_detail["ticket_types"] if t["name"] == "Стандарт")

            race_a, race_b = await asyncio.gather(
                client.post(
                    f"/api/v1/events/{ev_last_id}/register",
                    headers={"Authorization": f"Bearer {p1_tok}"},
                    json={"type_id": last_std_id, "request_id": f"last-{uuid.uuid4()}"},
                ),
                client.post(
                    f"/api/v1/events/{ev_last_id}/register",
                    headers={"Authorization": f"Bearer {p2_tok}"},
                    json={"type_id": last_std_id, "request_id": f"last-{uuid.uuid4()}"},
                ),
            )
            last_outcomes = sorted([race_a.json()["outcome"], race_b.json()["outcome"]])
            assert last_outcomes == ["ISSUED", "SOLD_OUT"]

            # T09: 10 parallel scans of 10 fresh tickets by 2 controllers concurrently
            fresh = seed_info["fresh_tickets"]
            assert len(fresh) == 10

            async def scan_pair(qr_tok: str):
                return await asyncio.gather(
                    client.post(
                        "/api/v1/controller/checkin",
                        headers={"Authorization": f"Bearer {c1_tok}"},
                        json={"event_id": ev_pub_id, "qr_token": qr_tok, "request_id": f"c1-{uuid.uuid4()}"},
                    ),
                    client.post(
                        "/api/v1/controller/checkin",
                        headers={"Authorization": f"Bearer {c2_tok}"},
                        json={"event_id": ev_pub_id, "qr_token": qr_tok, "request_id": f"c2-{uuid.uuid4()}"},
                    ),
                )

            pair_results = await asyncio.gather(*(scan_pair(t["qr_token"]) for t in fresh))
            for a, b in pair_results:
                statuses = sorted([a.json()["status"], b.json()["status"]])
                assert statuses == ["ACCEPTED", "ALREADY_USED"]

            # Verify DB has exactly 1 entry row per fresh ticket
            conn = await asyncpg.connect(DATABASE_URL)
            try:
                entry_count = await conn.fetchval(
                    "SELECT COUNT(*) FROM entries WHERE event_id = $1",
                    uuid.UUID(ev_pub_id),
                )
                assert entry_count == 10
            finally:
                await conn.close()

            # T10 & T14: Re-entry with new request_id -> ALREADY_USED; same request_id -> idempotent replay
            replay_req = f"replay-{uuid.uuid4()}"
            p1_qr = seed_info["participant1_ticket"]["qr_token"]
            first_scan = await client.post(
                "/api/v1/controller/checkin",
                headers={"Authorization": f"Bearer {c1_tok}"},
                json={"event_id": ev_pub_id, "qr_token": p1_qr, "request_id": replay_req},
            )
            assert first_scan.json()["status"] == "ACCEPTED"

            same_req_scan = await client.post(
                "/api/v1/controller/checkin",
                headers={"Authorization": f"Bearer {c1_tok}"},
                json={"event_id": ev_pub_id, "qr_token": p1_qr, "request_id": replay_req},
            )
            assert same_req_scan.json()["status"] == "ACCEPTED"
            assert same_req_scan.json()["idempotent_replay"] is True

            new_req_scan = await client.post(
                "/api/v1/controller/checkin",
                headers={"Authorization": f"Bearer {c1_tok}"},
                json={"event_id": ev_pub_id, "qr_token": p1_qr, "request_id": f"new-{uuid.uuid4()}"},
            )
            assert new_req_scan.json()["status"] == "ALREADY_USED"
            assert new_req_scan.json()["used_at"] == first_scan.json()["used_at"]

            # T05: USED ticket cannot be cancelled
            r_cancel_used = await client.post(
                f"/api/v1/tickets/{p1_ticket_id}/cancel",
                headers={"Authorization": f"Bearer {p1_tok}"},
            )
            assert r_cancel_used.status_code == 409

            # T11: Foreign event & tampered QR -> no PII leaked
            r_wrong = await client.post(
                "/api/v1/controller/checkin",
                headers={"Authorization": f"Bearer {c1_tok}"},
                json={"event_id": ev_last_id, "qr_token": p1_qr, "request_id": f"w-{uuid.uuid4()}"},
            )
            assert r_wrong.json()["status"] == "WRONG_EVENT"
            assert r_wrong.json()["participant_name"] is None

            r_invalid = await client.post(
                "/api/v1/controller/checkin",
                headers={"Authorization": f"Bearer {c1_tok}"},
                json={"event_id": ev_pub_id, "qr_token": "EF1:deadbeef", "request_id": f"inv-{uuid.uuid4()}"},
            )
            assert r_invalid.json()["status"] == "INVALID"
            assert r_invalid.json()["participant_name"] is None

            # T15: Revoke controller2 -> 403 on check-in
            c2_id = (await client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {c2_tok}"})).json()["id"]
            r_rev = await client.delete(
                f"/api/v1/organizer/events/{ev_pub_id}/controllers/{c2_id}",
                headers={"Authorization": f"Bearer {org_tok}"},
            )
            assert r_rev.status_code == 200
            r_rev_scan = await client.post(
                "/api/v1/controller/checkin",
                headers={"Authorization": f"Bearer {c2_tok}"},
                json={"event_id": ev_pub_id, "qr_token": p1_qr, "request_id": f"rev-{uuid.uuid4()}"},
            )
            assert r_rev_scan.status_code == 403
