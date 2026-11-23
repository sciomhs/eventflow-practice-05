import hashlib
import json
from datetime import datetime, timezone
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field

from ..db import get_conn
from ..security import decrypt_ticket_token, generate_ticket_token, require_role
from ..sse import broadcaster

router = APIRouter(prefix="/api/v1/events", tags=["events"])


class RegisterTicketBody(BaseModel):
    type_id: UUID
    request_id: str = Field(min_length=4, max_length=128)


def _format_ticket(row: dict, raw_token: str | None = None) -> dict:
    return {
        "id": str(row["id"]),
        "event_id": str(row["event_id"]),
        "type_id": str(row["type_id"]),
        "type_name": row.get("type_name"),
        "event_title": row.get("event_title"),
        "event_location": row.get("event_location"),
        "event_starts_at": row["event_starts_at"].isoformat() if row.get("event_starts_at") else None,
        "event_timezone": row.get("event_timezone"),
        "participant_id": str(row["participant_id"]),
        "code": row["code"],
        "status": row["status"],
        "issued_at": row["issued_at"].isoformat() if row.get("issued_at") else None,
        "cancelled_at": row["cancelled_at"].isoformat() if row.get("cancelled_at") else None,
        "used_at": row["used_at"].isoformat() if row.get("used_at") else None,
        "qr_token": raw_token,
    }


@router.get("")
async def list_events(
    search: str | None = Query(default=None),
    status_filter: str = Query(default="PUBLISHED", alias="status"),
    category: str | None = Query(default=None),
    city: str | None = Query(default=None),
    date_from: datetime | None = Query(default=None),
    date_to: datetime | None = Query(default=None),
    sort: str = Query(default="starts_at_asc"),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    conn: asyncpg.Connection = Depends(get_conn),
):
    if status_filter not in ("PUBLISHED", "CANCELLED"):
        status_filter = "PUBLISHED"

    conditions = ["e.status = $1"]
    params: list = [status_filter]
    idx = 2

    if search:
        conditions.append(f"(e.title ILIKE ${idx} OR e.description ILIKE ${idx} OR e.location ILIKE ${idx})")
        params.append(f"%{search.strip()}%")
        idx += 1
    if category:
        conditions.append(f"e.category = ${idx}")
        params.append(category.strip())
        idx += 1
    if city:
        conditions.append(f"e.city = ${idx}")
        params.append(city.strip())
        idx += 1
    if date_from:
        conditions.append(f"e.starts_at >= ${idx}")
        params.append(date_from)
        idx += 1
    if date_to:
        conditions.append(f"e.starts_at <= ${idx}")
        params.append(date_to)
        idx += 1

    where_sql = " AND ".join(conditions)
    order_sql = {
        "starts_at_asc": "e.starts_at ASC",
        "starts_at_desc": "e.starts_at DESC",
        "seats_desc": "free_seats DESC, e.starts_at ASC",
    }.get(sort, "e.starts_at ASC")

    total = await conn.fetchval(f"SELECT COUNT(*) FROM events e WHERE {where_sql}", *params)
    offset = (page - 1) * page_size

    rows = await conn.fetch(
        f"""
        SELECT
            e.id, e.title, e.description, e.category, e.city, e.location,
            e.starts_at, e.ends_at, e.timezone,
            e.registration_closes_at, e.admission_opens_at, e.admission_closes_at,
            e.capacity, e.status,
            u.name AS organizer_name,
            (e.capacity - COALESCE(t.occupied, 0))::int AS free_seats
        FROM events e
        JOIN users u ON u.id = e.organizer_id
        LEFT JOIN (
            SELECT event_id, COUNT(*) AS occupied
            FROM tickets
            WHERE status IN ('ISSUED', 'USED')
            GROUP BY event_id
        ) t ON t.event_id = e.id
        WHERE {where_sql}
        ORDER BY {order_sql}
        LIMIT ${idx} OFFSET ${idx + 1}
        """,
        *params,
        page_size,
        offset,
    )

    items = []
    for r in rows:
        items.append(
            {
                "id": str(r["id"]),
                "title": r["title"],
                "description": r["description"],
                "category": r["category"],
                "city": r["city"],
                "location": r["location"],
                "starts_at": r["starts_at"].isoformat(),
                "ends_at": r["ends_at"].isoformat(),
                "timezone": r["timezone"],
                "registration_closes_at": r["registration_closes_at"].isoformat(),
                "admission_opens_at": r["admission_opens_at"].isoformat(),
                "admission_closes_at": r["admission_closes_at"].isoformat(),
                "capacity": r["capacity"],
                "free_seats": max(0, r["free_seats"]),
                "status": r["status"],
                "organizer_name": r["organizer_name"],
            }
        )

    return {
        "items": items,
        "total": total,
        "page": page,
        "page_size": page_size,
        "server_time": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/{event_id}")
async def get_event_detail(
    event_id: UUID,
    conn: asyncpg.Connection = Depends(get_conn),
):
    ev = await conn.fetchrow(
        """
        SELECT e.*, u.name AS organizer_name
        FROM events e
        JOIN users u ON u.id = e.organizer_id
        WHERE e.id = $1 AND e.status != 'DRAFT'
        """,
        event_id,
    )
    if not ev:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Событие не найдено")

    types = await conn.fetch(
        """
        SELECT
            tt.id, tt.name, tt.capacity,
            COALESCE(COUNT(t.id) FILTER (WHERE t.status IN ('ISSUED', 'USED')), 0)::int AS occupied
        FROM ticket_types tt
        LEFT JOIN tickets t ON t.type_id = tt.id
        WHERE tt.event_id = $1
        GROUP BY tt.id, tt.name, tt.capacity
        ORDER BY tt.name ASC
        """,
        event_id,
    )
    total_occupied = sum(t["occupied"] for t in types)

    return {
        "id": str(ev["id"]),
        "title": ev["title"],
        "description": ev["description"],
        "category": ev["category"],
        "city": ev["city"],
        "location": ev["location"],
        "starts_at": ev["starts_at"].isoformat(),
        "ends_at": ev["ends_at"].isoformat(),
        "timezone": ev["timezone"],
        "registration_closes_at": ev["registration_closes_at"].isoformat(),
        "admission_opens_at": ev["admission_opens_at"].isoformat(),
        "admission_closes_at": ev["admission_closes_at"].isoformat(),
        "capacity": ev["capacity"],
        "free_seats": max(0, ev["capacity"] - total_occupied),
        "status": ev["status"],
        "organizer_name": ev["organizer_name"],
        "ticket_types": [
            {
                "id": str(t["id"]),
                "name": t["name"],
                "capacity": t["capacity"],
                "occupied": t["occupied"],
                "remaining": max(0, t["capacity"] - t["occupied"]),
            }
            for t in types
        ],
        "server_time": datetime.now(timezone.utc).isoformat(),
    }


@router.post("/{event_id}/register")
async def register_for_event(
    event_id: UUID,
    body: RegisterTicketBody,
    user: dict = Depends(require_role("participant")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    payload_hash = hashlib.sha256(f"{event_id}:{body.type_id}".encode()).hexdigest()
    sse_payload: dict | None = None

    async with conn.transaction():
        # 1. Idempotency check
        req_row = await conn.fetchrow(
            """
            SELECT payload_hash, response_json
            FROM registration_requests
            WHERE participant_id = $1 AND request_id = $2
            FOR UPDATE
            """,
            user["id"],
            body.request_id,
        )
        if req_row:
            if req_row["payload_hash"] != payload_hash:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Ключ запроса уже использован для других параметров",
                )
            saved = json.loads(req_row["response_json"])
            saved["idempotent_replay"] = True
            return saved

        # 2. Deterministic lock order: event -> ticket_type
        ev = await conn.fetchrow(
            "SELECT * FROM events WHERE id = $1 FOR UPDATE",
            event_id,
        )
        if not ev or ev["status"] == "DRAFT":
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Событие не найдено")

        server_now = await conn.fetchval("SELECT NOW()")

        if ev["status"] == "CANCELLED":
            resp = {"outcome": "CANCELLED", "idempotent_replay": False, "ticket": None, "server_time": server_now.isoformat()}
            await _save_reg_req(conn, user["id"], body.request_id, payload_hash, resp)
            return resp

        if server_now >= ev["registration_closes_at"]:
            resp = {"outcome": "CLOSED", "idempotent_replay": False, "ticket": None, "server_time": server_now.isoformat()}
            await _save_reg_req(conn, user["id"], body.request_id, payload_hash, resp)
            return resp

        tt = await conn.fetchrow(
            "SELECT * FROM ticket_types WHERE id = $1 AND event_id = $2 FOR UPDATE",
            body.type_id,
            event_id,
        )
        if not tt:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Категория билета не найдена")

        # 3. Check existing active ticket (R3)
        existing = await conn.fetchrow(
            """
            SELECT t.*, tt.name AS type_name, e.title AS event_title,
                   e.location AS event_location, e.starts_at AS event_starts_at,
                   e.timezone AS event_timezone
            FROM tickets t
            JOIN ticket_types tt ON tt.id = t.type_id
            JOIN events e ON e.id = t.event_id
            WHERE t.event_id = $1 AND t.participant_id = $2 AND t.status IN ('ISSUED', 'USED')
            FOR UPDATE OF t
            """,
            event_id,
            user["id"],
        )
        if existing:
            raw = decrypt_ticket_token(existing["token_encrypted"]) if existing["status"] == "ISSUED" else None
            resp = {
                "outcome": "ALREADY_REGISTERED",
                "idempotent_replay": False,
                "ticket": _format_ticket(dict(existing), raw),
                "server_time": server_now.isoformat(),
            }
            await _save_reg_req(conn, user["id"], body.request_id, payload_hash, resp)
            return resp

        # 4. Atomic seat check (event + category)
        event_occupied = await conn.fetchval(
            "SELECT COUNT(*) FROM tickets WHERE event_id = $1 AND status IN ('ISSUED', 'USED')",
            event_id,
        )
        type_occupied = await conn.fetchval(
            "SELECT COUNT(*) FROM tickets WHERE type_id = $1 AND status IN ('ISSUED', 'USED')",
            body.type_id,
        )
        if event_occupied >= ev["capacity"] or type_occupied >= tt["capacity"]:
            resp = {"outcome": "SOLD_OUT", "idempotent_replay": False, "ticket": None, "server_time": server_now.isoformat()}
            await _save_reg_req(conn, user["id"], body.request_id, payload_hash, resp)
            return resp

        # 5. Issue ticket
        seq = await conn.fetchval("SELECT nextval('ticket_code_seq')")
        code = f"EF-{seq:04d}"
        raw, thash, tenc = generate_ticket_token()
        inserted = await conn.fetchrow(
            """
            INSERT INTO tickets (event_id, type_id, participant_id, code, token_hash, token_encrypted, status)
            VALUES ($1, $2, $3, $4, $5, $6, 'ISSUED')
            RETURNING *
            """,
            event_id,
            body.type_id,
            user["id"],
            code,
            thash,
            tenc,
        )
        ticket_dict = dict(inserted)
        ticket_dict["type_name"] = tt["name"]
        ticket_dict["event_title"] = ev["title"]
        ticket_dict["event_location"] = ev["location"]
        ticket_dict["event_starts_at"] = ev["starts_at"]
        ticket_dict["event_timezone"] = ev["timezone"]

        await conn.execute(
            """
            INSERT INTO audit_logs (actor_id, event_id, ticket_id, action, result, request_id)
            VALUES ($1, $2, $3, 'TICKET_ISSUE', 'ISSUED', $4)
            """,
            user["id"],
            event_id,
            inserted["id"],
            body.request_id,
        )

        resp = {
            "outcome": "ISSUED",
            "idempotent_replay": False,
            "ticket": _format_ticket(ticket_dict, raw),
            "server_time": server_now.isoformat(),
        }
        await _save_reg_req(conn, user["id"], body.request_id, payload_hash, resp)

        free_after = max(0, ev["capacity"] - (event_occupied + 1))
        sse_payload = {
            "event_id": str(event_id),
            "type_id": str(body.type_id),
            "free_seats": free_after,
            "server_time": server_now.isoformat(),
        }

    # Publish SSE strictly AFTER commit
    if sse_payload:
        await broadcaster.publish("ticket.issued", sse_payload)

    return resp


async def _save_reg_req(
    conn: asyncpg.Connection,
    participant_id: UUID,
    request_id: str,
    payload_hash: str,
    resp: dict,
) -> None:
    await conn.execute(
        """
        INSERT INTO registration_requests (participant_id, request_id, payload_hash, response_json)
        VALUES ($1, $2, $3, $4::jsonb)
        ON CONFLICT (participant_id, request_id) DO NOTHING
        """,
        participant_id,
        request_id,
        payload_hash,
        json.dumps(resp, default=str),
    )
