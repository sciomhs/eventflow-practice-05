from datetime import datetime, timezone
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from ..db import get_conn
from ..security import decrypt_ticket_token, require_role
from ..sse import broadcaster

router = APIRouter(prefix="/api/v1/tickets", tags=["tickets"])


def _ticket_out(row: dict) -> dict:
    raw_token = None
    if row["status"] == "ISSUED":
        raw_token = decrypt_ticket_token(row["token_encrypted"])
    return {
        "id": str(row["id"]),
        "event_id": str(row["event_id"]),
        "type_id": str(row["type_id"]),
        "type_name": row["type_name"],
        "event_title": row["event_title"],
        "event_location": row["event_location"],
        "event_starts_at": row["event_starts_at"].isoformat(),
        "event_timezone": row["event_timezone"],
        "event_status": row["event_status"],
        "participant_id": str(row["participant_id"]),
        "code": row["code"],
        "status": row["status"],
        "issued_at": row["issued_at"].isoformat(),
        "cancelled_at": row["cancelled_at"].isoformat() if row["cancelled_at"] else None,
        "used_at": row["used_at"].isoformat() if row["used_at"] else None,
        "qr_token": raw_token,
    }


@router.get("/my")
async def my_tickets(
    user: dict = Depends(require_role("participant")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    rows = await conn.fetch(
        """
        SELECT t.*, tt.name AS type_name,
               e.title AS event_title, e.location AS event_location,
               e.starts_at AS event_starts_at, e.timezone AS event_timezone,
               e.status AS event_status
        FROM tickets t
        JOIN ticket_types tt ON tt.id = t.type_id
        JOIN events e ON e.id = t.event_id
        WHERE t.participant_id = $1
        ORDER BY t.issued_at DESC
        """,
        user["id"],
    )
    return {
        "items": [_ticket_out(dict(r)) for r in rows],
        "server_time": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/{ticket_id}")
async def get_ticket(
    ticket_id: UUID,
    user: dict = Depends(require_role("participant")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    row = await conn.fetchrow(
        """
        SELECT t.*, tt.name AS type_name,
               e.title AS event_title, e.location AS event_location,
               e.starts_at AS event_starts_at, e.timezone AS event_timezone,
               e.status AS event_status
        FROM tickets t
        JOIN ticket_types tt ON tt.id = t.type_id
        JOIN events e ON e.id = t.event_id
        WHERE t.id = $1
        """,
        ticket_id,
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Билет не найден")
    if row["participant_id"] != user["id"]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Нет доступа к чужому билету")
    return _ticket_out(dict(row))


@router.post("/{ticket_id}/cancel")
async def cancel_ticket(
    ticket_id: UUID,
    user: dict = Depends(require_role("participant")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    sse_payload: dict | None = None
    result_ticket: dict | None = None

    async with conn.transaction():
        t_row = await conn.fetchrow(
            "SELECT * FROM tickets WHERE id = $1 FOR UPDATE",
            ticket_id,
        )
        if not t_row:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Билет не найден")
        if t_row["participant_id"] != user["id"]:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Нет доступа к чужому билету")
        if t_row["status"] == "USED":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Нельзя отменить билет после зафиксированного входа",
            )
        if t_row["status"] == "CANCELLED":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Билет уже отменён",
            )

        ev = await conn.fetchrow("SELECT * FROM events WHERE id = $1 FOR UPDATE", t_row["event_id"])
        server_now = await conn.fetchval("SELECT NOW()")

        updated = await conn.fetchrow(
            """
            UPDATE tickets
            SET status = 'CANCELLED', cancelled_at = $2
            WHERE id = $1
            RETURNING *
            """,
            ticket_id,
            server_now,
        )
        tt_name = await conn.fetchval("SELECT name FROM ticket_types WHERE id = $1", updated["type_id"])
        occupied = await conn.fetchval(
            "SELECT COUNT(*) FROM tickets WHERE event_id = $1 AND status IN ('ISSUED', 'USED')",
            ev["id"],
        )

        await conn.execute(
            """
            INSERT INTO audit_logs (actor_id, event_id, ticket_id, action, result)
            VALUES ($1, $2, $3, 'TICKET_CANCEL', 'CANCELLED')
            """,
            user["id"],
            ev["id"],
            ticket_id,
        )

        full = dict(updated)
        full["type_name"] = tt_name
        full["event_title"] = ev["title"]
        full["event_location"] = ev["location"]
        full["event_starts_at"] = ev["starts_at"]
        full["event_timezone"] = ev["timezone"]
        full["event_status"] = ev["status"]
        result_ticket = _ticket_out(full)

        sse_payload = {
            "event_id": str(ev["id"]),
            "type_id": str(updated["type_id"]),
            "free_seats": max(0, ev["capacity"] - occupied),
            "server_time": server_now.isoformat(),
        }

    if sse_payload:
        await broadcaster.publish("ticket.cancelled", sse_payload)

    return {"ticket": result_ticket}
