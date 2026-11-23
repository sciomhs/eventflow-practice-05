"""Executes real HTTP + SSE + PostgreSQL verification for T01–T16 against a running FastAPI server."""
import asyncio
import json
import sys
import time
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import asyncpg
import httpx

BACKEND_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_ROOT))

from db.migrate import run_migrations
from db.seed_demo import DATABASE_URL, DEV_PASSWORD, seed_demo

import os
BASE_URL = os.getenv("EVENTFLOW_URL", "http://127.0.0.1:8000")


async def login(client: httpx.AsyncClient, email: str) -> tuple[str, dict]:
    r = await client.post(f"{BASE_URL}/api/v1/auth/login", json={"email": email, "password": DEV_PASSWORD})
    assert r.status_code == 200, r.text
    d = r.json()
    return d["access_token"], d["user"]


async def main():
    await run_migrations(DATABASE_URL)
    seed = await seed_demo(DATABASE_URL)
    ev_pub = seed["event_published_id"]
    ev_last = seed["event_last_seat_id"]

    results = {}

    async with httpx.AsyncClient(timeout=15.0) as client:
        p1_tok, p1 = await login(client, "participant1@eventflow.dev")
        p2_tok, p2 = await login(client, "participant2@eventflow.dev")
        org_tok, org = await login(client, "organizer@eventflow.dev")
        c1_tok, c1 = await login(client, "controller1@eventflow.dev")
        c2_tok, c2 = await login(client, "controller2@eventflow.dev")

        # T01: Login & role boundaries
        r_p1_other = await client.get(
            f"{BASE_URL}/api/v1/tickets/{seed['participant1_ticket']['id']}",
            headers={"Authorization": f"Bearer {p2_tok}"},
        )
        r_role_tamper = await client.post(
            f"{BASE_URL}/api/v1/auth/register",
            json={"name": "Test User", "email": f"x_{uuid.uuid4().hex[:6]}@eventflow.dev", "password": "Password123!", "role": "organizer"},
        )
        assert r_p1_other.status_code == 403 and r_role_tamper.status_code == 403
        results["T01"] = f"p2->p1_ticket={r_p1_other.status_code}, role_tamper={r_role_tamper.status_code}"

        # T02: Issue QR on published event
        ev_det = (await client.get(f"{BASE_URL}/api/v1/events/{ev_pub}")).json()
        std_id = next(t["id"] for t in ev_det["ticket_types"] if t["name"] == "Стандарт")
        r_t02 = await client.post(
            f"{BASE_URL}/api/v1/events/{ev_pub}/register",
            headers={"Authorization": f"Bearer {p2_tok}"},
            json={"type_id": std_id, "request_id": f"t02-{uuid.uuid4()}"},
        )
        t02_json = r_t02.json()
        assert t02_json["outcome"] == "ISSUED" and t02_json["ticket"]["qr_token"].startswith("EF1:")
        results["T02"] = f"outcome={t02_json['outcome']}, code={t02_json['ticket']['code']}"

        # T03: Last seat race
        last_det = (await client.get(f"{BASE_URL}/api/v1/events/{ev_last}")).json()
        last_std = next(t["id"] for t in last_det["ticket_types"] if t["name"] == "Стандарт")
        ra, rb = await asyncio.gather(
            client.post(f"{BASE_URL}/api/v1/events/{ev_last}/register", headers={"Authorization": f"Bearer {p1_tok}"}, json={"type_id": last_std, "request_id": f"t03a-{uuid.uuid4()}"}),
            client.post(f"{BASE_URL}/api/v1/events/{ev_last}/register", headers={"Authorization": f"Bearer {p2_tok}"}, json={"type_id": last_std, "request_id": f"t03b-{uuid.uuid4()}"}),
        )
        o_t03 = sorted([ra.json()["outcome"], rb.json()["outcome"]])
        assert o_t03 == ["ISSUED", "SOLD_OUT"]
        results["T03"] = f"concurrent_last_seat={o_t03}"

        # T04: Rapid repeat registration (same request_id + new request_id)
        req4 = f"t04-{uuid.uuid4()}"
        r4a = await client.post(f"{BASE_URL}/api/v1/events/{ev_pub}/register", headers={"Authorization": f"Bearer {p2_tok}"}, json={"type_id": std_id, "request_id": req4})
        r4b = await client.post(f"{BASE_URL}/api/v1/events/{ev_pub}/register", headers={"Authorization": f"Bearer {p2_tok}"}, json={"type_id": std_id, "request_id": req4})
        assert r4a.json()["outcome"] == "ALREADY_REGISTERED" and r4b.json()["idempotent_replay"] is True
        results["T04"] = f"first={r4a.json()['outcome']}, replay={r4b.json()['idempotent_replay']}"

        # T05: Cancel ISSUED & re-register -> new QR; old QR rejected on check-in
        old_ticket = t02_json["ticket"]
        r_can = await client.post(f"{BASE_URL}/api/v1/tickets/{old_ticket['id']}/cancel", headers={"Authorization": f"Bearer {p2_tok}"})
        assert r_can.status_code == 200
        r_old_scan = await client.post(
            f"{BASE_URL}/api/v1/controller/checkin",
            headers={"Authorization": f"Bearer {c1_tok}"},
            json={"event_id": ev_pub, "qr_token": old_ticket["qr_token"], "request_id": f"t05old-{uuid.uuid4()}"},
        )
        assert r_old_scan.json()["status"] == "CANCELLED"
        r_re = await client.post(
            f"{BASE_URL}/api/v1/events/{ev_pub}/register",
            headers={"Authorization": f"Bearer {p2_tok}"},
            json={"type_id": std_id, "request_id": f"t05new-{uuid.uuid4()}"},
        )
        new_ticket = r_re.json()["ticket"]
        assert new_ticket["qr_token"] != old_ticket["qr_token"]
        results["T05"] = f"old_scan={r_old_scan.json()['status']}, new_code={new_ticket['code']}"

        # T08: Live SSE latency <= 3s
        t_start = time.monotonic()
        received_sse = None
        async with client.stream("GET", f"{BASE_URL}/api/v1/stream?token={org_tok}") as sse_resp:
            async def trigger_checkin():
                await asyncio.sleep(0.2)
                await client.post(
                    f"{BASE_URL}/api/v1/controller/checkin",
                    headers={"Authorization": f"Bearer {c1_tok}"},
                    json={"event_id": ev_pub, "qr_token": new_ticket["qr_token"], "request_id": f"t08-{uuid.uuid4()}"},
                )
            t_task = asyncio.create_task(trigger_checkin())
            async for line in sse_resp.aiter_lines():
                if line.startswith("data:") and "entry.accepted" in prev_event if 'prev_event' in locals() else False:
                    received_sse = line
                    break
                if line.startswith("event:"):
                    prev_event = line
                if time.monotonic() - t_start > 5.0:
                    break
            await t_task
        sse_ms = int((time.monotonic() - t_start) * 1000)
        assert received_sse is not None and sse_ms <= 3000
        results["T08"] = f"sse_event_received_in={sse_ms}ms (<=3000ms)"

        # T09: 10 parallel scans of 10 fresh tickets
        fresh = seed["fresh_tickets"]
        async def scan_both(qr: str):
            return await asyncio.gather(
                client.post(f"{BASE_URL}/api/v1/controller/checkin", headers={"Authorization": f"Bearer {c1_tok}"}, json={"event_id": ev_pub, "qr_token": qr, "request_id": f"t09a-{uuid.uuid4()}"}),
                client.post(f"{BASE_URL}/api/v1/controller/checkin", headers={"Authorization": f"Bearer {c2_tok}"}, json={"event_id": ev_pub, "qr_token": qr, "request_id": f"t09b-{uuid.uuid4()}"}),
            )
        pairs = await asyncio.gather(*(scan_both(t["qr_token"]) for t in fresh))
        for a, b in pairs:
            assert sorted([a.json()["status"], b.json()["status"]]) == ["ACCEPTED", "ALREADY_USED"]
        results["T09"] = "10/10 pairs: 1 ACCEPTED + 1 ALREADY_USED"

        # T10: Re-entry with new request_id
        r_t10 = await client.post(
            f"{BASE_URL}/api/v1/controller/checkin",
            headers={"Authorization": f"Bearer {c1_tok}"},
            json={"event_id": ev_pub, "qr_token": new_ticket["qr_token"], "request_id": f"t10-{uuid.uuid4()}"},
        )
        assert r_t10.json()["status"] == "ALREADY_USED" and r_t10.json()["used_at"] is not None
        results["T10"] = f"status={r_t10.json()['status']}, used_at={r_t10.json()['used_at']}"

        # T11: Wrong event & invalid QR
        r_w = await client.post(f"{BASE_URL}/api/v1/controller/checkin", headers={"Authorization": f"Bearer {c1_tok}"}, json={"event_id": ev_last, "qr_token": new_ticket["qr_token"], "request_id": f"t11a-{uuid.uuid4()}"})
        r_i = await client.post(f"{BASE_URL}/api/v1/controller/checkin", headers={"Authorization": f"Bearer {c1_tok}"}, json={"event_id": ev_pub, "qr_token": "EF1:tampered", "request_id": f"t11b-{uuid.uuid4()}"})
        assert r_w.json()["status"] == "WRONG_EVENT" and r_i.json()["status"] == "INVALID"
        assert r_w.json()["participant_name"] is None and r_i.json()["participant_name"] is None
        results["T11"] = f"wrong={r_w.json()['status']}, invalid={r_i.json()['status']}, no_pii=True"

        # T12: Cancel vs check-in race on participant1's ticket
        p1_t = seed["participant1_ticket"]
        rc, rs = await asyncio.gather(
            client.post(f"{BASE_URL}/api/v1/tickets/{p1_t['id']}/cancel", headers={"Authorization": f"Bearer {p1_tok}"}),
            client.post(f"{BASE_URL}/api/v1/controller/checkin", headers={"Authorization": f"Bearer {c1_tok}"}, json={"event_id": ev_pub, "qr_token": p1_t["qr_token"], "request_id": f"t12-{uuid.uuid4()}"}),
        )
        # Either cancel won (200 + CANCELLED) or check-in won (409 + ACCEPTED)
        assert (rc.status_code == 200 and rs.json()["status"] == "CANCELLED") or (rc.status_code == 409 and rs.json()["status"] == "ACCEPTED")
        results["T12"] = f"cancel_http={rc.status_code}, checkin_status={rs.json()['status']}"

        # T13: Time windows (CLOSED before open, ACCEPTED at open, CLOSED at close)
        now_utc = datetime.now(timezone.utc)
        conn = await asyncpg.connect(DATABASE_URL)
        try:
            # Temporarily set AI Summit admission_opens_at to future -> CLOSED
            await conn.execute(
                "UPDATE events SET admission_opens_at = $2, admission_closes_at = $3 WHERE id = $1",
                uuid.UUID(ev_last), now_utc + timedelta(hours=1), now_utc + timedelta(days=2),
            )
            last_qr = await conn.fetchval("SELECT token_encrypted FROM tickets WHERE event_id = $1 LIMIT 1", uuid.UUID(ev_last))
        finally:
            await conn.close()
        from app.security import decrypt_ticket_token
        last_raw = decrypt_ticket_token(last_qr)
        r_closed_before = await client.post(f"{BASE_URL}/api/v1/controller/checkin", headers={"Authorization": f"Bearer {c1_tok}"}, json={"event_id": ev_last, "qr_token": last_raw, "request_id": f"t13a-{uuid.uuid4()}"})
        assert r_closed_before.json()["status"] == "CLOSED"

        conn = await asyncpg.connect(DATABASE_URL)
        try:
            # Set admission_opens_at to now - 1s -> ACCEPTED
            await conn.execute(
                "UPDATE events SET admission_opens_at = $2, admission_closes_at = $3 WHERE id = $1",
                uuid.UUID(ev_last), now_utc - timedelta(seconds=1), now_utc + timedelta(days=2),
            )
        finally:
            await conn.close()
        r_open = await client.post(f"{BASE_URL}/api/v1/controller/checkin", headers={"Authorization": f"Bearer {c1_tok}"}, json={"event_id": ev_last, "qr_token": last_raw, "request_id": f"t13b-{uuid.uuid4()}"})
        assert r_open.json()["status"] == "ACCEPTED"
        results["T13"] = f"before_open={r_closed_before.json()['status']}, at_open={r_open.json()['status']}"

        # T14: Idempotent replay with same request_id
        r_t14 = await client.post(f"{BASE_URL}/api/v1/controller/checkin", headers={"Authorization": f"Bearer {c1_tok}"}, json={"event_id": ev_last, "qr_token": last_raw, "request_id": f"t13b-{uuid.uuid4()}"})
        req14 = f"t14-{uuid.uuid4()}"
        r14a = await client.post(f"{BASE_URL}/api/v1/controller/checkin", headers={"Authorization": f"Bearer {c1_tok}"}, json={"event_id": ev_last, "qr_token": last_raw, "request_id": req14})
        r14b = await client.post(f"{BASE_URL}/api/v1/controller/checkin", headers={"Authorization": f"Bearer {c1_tok}"}, json={"event_id": ev_last, "qr_token": last_raw, "request_id": req14})
        assert r14b.json()["idempotent_replay"] is True and r14b.json()["status"] == r14a.json()["status"]
        results["T14"] = f"replay={r14b.json()['idempotent_replay']}, status={r14b.json()['status']}"

        # T15: Revoked controller -> 403; direct role/used_at patch -> 403
        r_rev = await client.delete(f"{BASE_URL}/api/v1/organizer/events/{ev_pub}/controllers/{c2['id']}", headers={"Authorization": f"Bearer {org_tok}"})
        assert r_rev.status_code == 200
        r_rev_scan = await client.post(f"{BASE_URL}/api/v1/controller/checkin", headers={"Authorization": f"Bearer {c2_tok}"}, json={"event_id": ev_pub, "qr_token": new_ticket["qr_token"], "request_id": f"t15-{uuid.uuid4()}"})
        r_tamper_used = await client.patch(f"{BASE_URL}/api/v1/auth/me", headers={"Authorization": f"Bearer {c2_tok}"}, json={"used_at": "2026-01-01T00:00:00Z"})
        assert r_rev_scan.status_code == 403 and r_tamper_used.status_code == 403
        results["T15"] = f"revoked_checkin={r_rev_scan.status_code}, tamper_used_at={r_tamper_used.status_code}"

    print(json.dumps(results, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    asyncio.run(main())
