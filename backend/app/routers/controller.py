import hashlib
import json
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field

from ..db import get_conn
from ..security import hash_ticket_token, is_valid_qr_format, require_role
from ..sse import broadcaster

router = APIRouter(prefix="/api/v1/controller", tags=["controller"])


class CheckInBody(BaseModel):
    event_id: UUID
    qr_token: str = Field(min_length=1, max_length=256)
    request_id: str = Field(min_length=4, max_length=128)


@router.get("/events")
async def assigned_events(
    user: dict = Depends(require_role("controller")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    rows = await conn.fetch(
        """
        SELECT e.id, e.title, e.location, e.starts_at, e.ends_at, e.timezone,
               e.admission_opens_at, e.admission_closes_at, e.status, e.capacity
        FROM controller_assignments ca
        JOIN events e ON e.id = ca.event_id
        WHERE ca.controller_id = $1
        ORDER BY e.starts_at ASC
        """,
        user["id"],
    )
    return {
        "items": [
            {
                "id": str(r["id"]),
                "title": r["title"],
                "location": r["location"],
                "starts_at": r["starts_at"].isoformat(),
                "ends_at": r["ends_at"].isoformat(),
                "timezone": r["timezone"],
                "admission_opens_at": r["admission_opens_at"].isoformat(),
                "admission_closes_at": r["admission_closes_at"].isoformat(),
                "status": r["status"],
                "capacity": r["capacity"],
            }
            for r in rows
        ]
    }


@router.post("/checkin")
async def checkin(
    body: CheckInBody,
    user: dict = Depends(require_role("controller")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    qr_clean = body.qr_token.strip()
    payload_hash = hashlib.sha256(f"{body.event_id}:{qr_clean}".encode()).hexdigest()

    sse_event: tuple[str, dict] | None = None
    response: dict

    async with conn.transaction():
        # 1. Check controller assignment inside transaction
        assigned = await conn.fetchval(
            "SELECT 1 FROM controller_assignments WHERE event_id = $1 AND controller_id = $2",
            body.event_id,
            user["id"],
        )
        if not assigned:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Вы не назначены на это событие или доступ отозван",
            )

        # 2. Idempotency reservation (controller_id, request_id)
        req_row = await conn.fetchrow(
            """
            SELECT payload_hash, response_json
            FROM checkin_requests
            WHERE controller_id = $1 AND request_id = $2
            FOR UPDATE
            """,
            user["id"],
            body.request_id,
        )
        if req_row:
            if req_row["payload_hash"] != payload_hash:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="request_id уже использован для другого билета",
                )
            saved = json.loads(req_row["response_json"])
            saved["idempotent_replay"] = True
            return saved

        # 3. Deterministic lock order: event -> ticket
        ev = await conn.fetchrow(
            "SELECT * FROM events WHERE id = $1 FOR UPDATE",
            body.event_id,
        )
        if not ev:
            raise HTTPException(status_code=404, detail="Событие не найдено")

        server_now = await conn.fetchval("SELECT NOW()")

        ticket_row = None
        if is_valid_qr_format(qr_clean):
            thash = hash_ticket_token(qr_clean)
            ticket_row = await conn.fetchrow(
                """
                SELECT t.*, tt.name AS type_name, u.name AS participant_name
                FROM tickets t
                JOIN ticket_types tt ON tt.id = t.type_id
                JOIN users u ON u.id = t.participant_id
                WHERE t.token_hash = $1
                FOR UPDATE OF t
                """,
                thash,
            )

        # 4. Evaluate exact entry status
        if ticket_row is None:
            response = {
                "status": "INVALID",
                "idempotent_replay": False,
                "server_time": server_now.isoformat(),
                "used_at": None,
                "ticket_code": None,
                "type_name": None,
                "participant_name": None,
                "message": "Недействительный или повреждённый QR-код",
            }
        elif ticket_row["event_id"] != body.event_id:
            response = {
                "status": "WRONG_EVENT",
                "idempotent_replay": False,
                "server_time": server_now.isoformat(),
                "used_at": None,
                "ticket_code": None,
                "type_name": None,
                "participant_name": None,
                "message": "Билет относится к другому мероприятию",
            }
        elif ev["status"] == "CANCELLED" or ticket_row["status"] == "CANCELLED":
            response = {
                "status": "CANCELLED",
                "idempotent_replay": False,
                "server_time": server_now.isoformat(),
                "used_at": None,
                "ticket_code": ticket_row["code"],
                "type_name": ticket_row["type_name"],
                "participant_name": None,
                "message": "Билет или мероприятие отменено",
            }
        elif server_now < ev["admission_opens_at"] or server_now >= ev["admission_closes_at"]:
            response = {
                "status": "CLOSED",
                "idempotent_replay": False,
                "server_time": server_now.isoformat(),
                "used_at": None,
                "ticket_code": ticket_row["code"],
                "type_name": ticket_row["type_name"],
                "participant_name": None,
                "message": "Окно допуска закрыто по серверному времени",
            }
        elif ticket_row["status"] == "USED":
            response = {
                "status": "ALREADY_USED",
                "idempotent_replay": False,
                "server_time": server_now.isoformat(),
                "used_at": ticket_row["used_at"].isoformat() if ticket_row["used_at"] else None,
                "ticket_code": ticket_row["code"],
                "type_name": ticket_row["type_name"],
                "participant_name": ticket_row["participant_name"],
                "message": "Билет уже был использован ранее",
            }
        else:
            # ticket_row["status"] == "ISSUED"
            await conn.execute(
                """
                UPDATE tickets
                SET status = 'USED', used_at = $2, used_by = $3
                WHERE id = $1
                """,
                ticket_row["id"],
                server_now,
                user["id"],
            )
            await conn.execute(
                """
                INSERT INTO entries (ticket_id, event_id, controller_id, entered_at)
                VALUES ($1, $2, $3, $4)
                """,
                ticket_row["id"],
                body.event_id,
                user["id"],
                server_now,
            )
            used_count = await conn.fetchval(
                "SELECT COUNT(*)::int FROM entries WHERE event_id = $1",
                body.event_id,
            )
            response = {
                "status": "ACCEPTED",
                "idempotent_replay": False,
                "server_time": server_now.isoformat(),
                "used_at": server_now.isoformat(),
                "ticket_code": ticket_row["code"],
                "type_name": ticket_row["type_name"],
                "participant_name": ticket_row["participant_name"],
                "message": "Вход разрешён",
            }
            sse_event = (
                "entry.accepted",
                {
                    "event_id": str(body.event_id),
                    "ticket_code": ticket_row["code"],
                    "used_at": server_now.isoformat(),
                    "used_count": used_count,
                    "server_time": server_now.isoformat(),
                },
            )

        if sse_event is None:
            sse_event = (
                "entry.rejected",
                {
                    "event_id": str(body.event_id),
                    "status": response["status"],
                    "server_time": server_now.isoformat(),
                },
            )

        # Save idempotent result and audit log (never store raw qr_token!)
        await conn.execute(
            """
            INSERT INTO checkin_requests (controller_id, request_id, payload_hash, response_json)
            VALUES ($1, $2, $3, $4::jsonb)
            """,
            user["id"],
            body.request_id,
            payload_hash,
            json.dumps(response, default=str),
        )
        await conn.execute(
            """
            INSERT INTO audit_logs (actor_id, event_id, ticket_id, action, result, server_time, request_id)
            VALUES ($1, $2, $3, 'CHECKIN', $4, $5, $6)
            """,
            user["id"],
            body.event_id,
            ticket_row["id"] if (ticket_row and ticket_row["event_id"] == body.event_id) else None,
            response["status"],
            server_now,
            body.request_id,
        )

    # Publish strictly after commit
    if sse_event:
        await broadcaster.publish(sse_event[0], sse_event[1])

    return response


@router.get("/journal")
async def controller_journal(
    event_id: UUID | None = Query(default=None),
    user: dict = Depends(require_role("controller")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    conditions = ["a.actor_id = $1", "a.action = 'CHECKIN'"]
    params: list = [user["id"]]
    if event_id:
        conditions.append("a.event_id = $2")
        params.append(event_id)

    rows = await conn.fetch(
        f"""
        SELECT a.id, a.event_id, a.result, a.server_time, a.request_id,
               t.code AS ticket_code, e.title AS event_title
        FROM audit_logs a
        LEFT JOIN tickets t ON t.id = a.ticket_id
        LEFT JOIN events e ON e.id = a.event_id
        WHERE {' AND '.join(conditions)}
        ORDER BY a.server_time DESC
        LIMIT 100
        """,
        *params,
    )
    return {
        "items": [
            {
                "id": str(r["id"]),
                "event_id": str(r["event_id"]) if r["event_id"] else None,
                "event_title": r["event_title"],
                "result": r["result"],
                "server_time": r["server_time"].isoformat(),
                "request_id": r["request_id"],
                "ticket_code": r["ticket_code"],
            }
            for r in rows
        ]
    }
