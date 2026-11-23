from datetime import datetime, timezone
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field

from ..db import get_conn
from ..security import require_role
from ..sse import broadcaster

router = APIRouter(prefix="/api/v1/organizer", tags=["organizer"])


class TicketTypeIn(BaseModel):
    name: str = Field(min_length=1, max_length=60)
    capacity: int = Field(gt=0)


class EventCreateBody(BaseModel):
    title: str = Field(min_length=2, max_length=160)
    description: str = Field(min_length=2, max_length=2000)
    category: str = Field(min_length=2, max_length=80)
    city: str = Field(min_length=2, max_length=80)
    location: str = Field(min_length=2, max_length=160)
    starts_at: datetime
    ends_at: datetime
    timezone: str = Field(default="Asia/Yekaterinburg", max_length=64)
    registration_closes_at: datetime
    admission_opens_at: datetime
    admission_closes_at: datetime
    capacity: int = Field(gt=0)
    ticket_types: list[TicketTypeIn] = Field(min_length=2)


class EventUpdateBody(BaseModel):
    title: str | None = Field(default=None, min_length=2, max_length=160)
    description: str | None = Field(default=None, min_length=2, max_length=2000)
    category: str | None = Field(default=None, min_length=2, max_length=80)
    city: str | None = Field(default=None, min_length=2, max_length=80)
    location: str | None = Field(default=None, min_length=2, max_length=160)
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    registration_closes_at: datetime | None = None
    admission_opens_at: datetime | None = None
    admission_closes_at: datetime | None = None
    capacity: int | None = Field(default=None, gt=0)
    ticket_types: list[TicketTypeIn] | None = None


class AssignControllerBody(BaseModel):
    controller_id: UUID


def _validate_event_dates_and_types(
    starts_at: datetime,
    ends_at: datetime,
    reg_closes: datetime,
    adm_opens: datetime,
    adm_closes: datetime,
    capacity: int,
    ticket_types: list[TicketTypeIn],
) -> None:
    if starts_at >= ends_at:
        raise HTTPException(status_code=422, detail="Время начала должно быть раньше окончания")
    if adm_opens >= adm_closes:
        raise HTTPException(status_code=422, detail="Открытие допуска должно быть раньше закрытия")
    if reg_closes > starts_at:
        raise HTTPException(status_code=422, detail="Срок регистрации не может быть позже начала события")
    if adm_opens > starts_at or adm_closes < starts_at:
        raise HTTPException(status_code=422, detail="Окно допуска должно включать время начала события")
    if len(ticket_types) < 2:
        raise HTTPException(status_code=422, detail="Требуется минимум две категории билетов")
    if sum(t.capacity for t in ticket_types) != capacity:
        raise HTTPException(status_code=422, detail="Сумма лимитов категорий должна равняться вместимости события")


async def _get_owned_event(conn: asyncpg.Connection, event_id: UUID, organizer_id: UUID) -> asyncpg.Record:
    ev = await conn.fetchrow("SELECT * FROM events WHERE id = $1", event_id)
    if not ev:
        raise HTTPException(status_code=404, detail="Событие не найдено")
    if ev["organizer_id"] != organizer_id:
        raise HTTPException(status_code=403, detail="Нет прав на управление чужим событием")
    return ev


@router.get("/events")
async def list_own_events(
    user: dict = Depends(require_role("organizer")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    rows = await conn.fetch(
        """
        SELECT e.*,
               COALESCE(COUNT(t.id) FILTER (WHERE t.status IN ('ISSUED', 'USED')), 0)::int AS occupied,
               COALESCE(COUNT(t.id) FILTER (WHERE t.status = 'USED'), 0)::int AS used_count
        FROM events e
        LEFT JOIN tickets t ON t.event_id = e.id
        WHERE e.organizer_id = $1
        GROUP BY e.id
        ORDER BY e.created_at DESC
        """,
        user["id"],
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
                "free_seats": max(0, r["capacity"] - r["occupied"]),
                "used_count": r["used_count"],
                "status": r["status"],
            }
        )
    return {"items": items, "server_time": datetime.now(timezone.utc).isoformat()}


@router.post("/events", status_code=status.HTTP_201_CREATED)
async def create_event(
    body: EventCreateBody,
    user: dict = Depends(require_role("organizer")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    _validate_event_dates_and_types(
        body.starts_at,
        body.ends_at,
        body.registration_closes_at,
        body.admission_opens_at,
        body.admission_closes_at,
        body.capacity,
        body.ticket_types,
    )
    async with conn.transaction():
        ev = await conn.fetchrow(
            """
            INSERT INTO events (
                organizer_id, title, description, category, city, location,
                starts_at, ends_at, timezone,
                registration_closes_at, admission_opens_at, admission_closes_at,
                capacity, status
            ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,'DRAFT')
            RETURNING *
            """,
            user["id"],
            body.title.strip(),
            body.description.strip(),
            body.category.strip(),
            body.city.strip(),
            body.location.strip(),
            body.starts_at,
            body.ends_at,
            body.timezone,
            body.registration_closes_at,
            body.admission_opens_at,
            body.admission_closes_at,
            body.capacity,
        )
        for tt in body.ticket_types:
            await conn.execute(
                "INSERT INTO ticket_types (event_id, name, capacity) VALUES ($1, $2, $3)",
                ev["id"],
                tt.name.strip(),
                tt.capacity,
            )
    return {"id": str(ev["id"]), "status": ev["status"], "title": ev["title"]}


@router.patch("/events/{event_id}")
async def update_event(
    event_id: UUID,
    body: EventUpdateBody,
    user: dict = Depends(require_role("organizer")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    async with conn.transaction():
        ev = await conn.fetchrow("SELECT * FROM events WHERE id = $1 FOR UPDATE", event_id)
        if not ev:
            raise HTTPException(status_code=404, detail="Событие не найдено")
        if ev["organizer_id"] != user["id"]:
            raise HTTPException(status_code=403, detail="Нет прав на управление чужим событием")
        if ev["status"] == "CANCELLED":
            raise HTTPException(status_code=409, detail="Отменённое событие нельзя редактировать")

        has_tickets = await conn.fetchval(
            "SELECT EXISTS(SELECT 1 FROM tickets WHERE event_id = $1 AND status IN ('ISSUED', 'USED'))",
            event_id,
        )

        new_starts = body.starts_at or ev["starts_at"]
        new_ends = body.ends_at or ev["ends_at"]
        new_reg = body.registration_closes_at or ev["registration_closes_at"]
        new_adm_open = body.admission_opens_at or ev["admission_opens_at"]
        new_adm_close = body.admission_closes_at or ev["admission_closes_at"]
        new_cap = body.capacity if body.capacity is not None else ev["capacity"]

        if has_tickets:
            if (
                body.starts_at is not None
                or body.ends_at is not None
                or body.registration_closes_at is not None
                or body.admission_opens_at is not None
                or body.admission_closes_at is not None
            ):
                raise HTTPException(
                    status_code=409,
                    detail="После первой регистрации перенос времени заблокирован",
                )
            if new_cap < ev["capacity"]:
                raise HTTPException(
                    status_code=409,
                    detail="После первой регистрации вместимость можно только увеличивать",
                )

        if body.ticket_types is not None:
            _validate_event_dates_and_types(
                new_starts, new_ends, new_reg, new_adm_open, new_adm_close, new_cap, body.ticket_types
            )
            existing_types = await conn.fetch(
                "SELECT id, name, capacity FROM ticket_types WHERE event_id = $1 FOR UPDATE",
                event_id,
            )
            existing_by_name = {r["name"]: r for r in existing_types}
            if has_tickets:
                for tt in body.ticket_types:
                    old = existing_by_name.get(tt.name.strip())
                    if old and tt.capacity < old["capacity"]:
                        raise HTTPException(
                            status_code=409,
                            detail=f"После регистрации лимит категории «{tt.name}» можно только увеличивать",
                        )
            for tt in body.ticket_types:
                name = tt.name.strip()
                if name in existing_by_name:
                    await conn.execute(
                        "UPDATE ticket_types SET capacity = $1 WHERE id = $2",
                        tt.capacity,
                        existing_by_name[name]["id"],
                    )
                else:
                    await conn.execute(
                        "INSERT INTO ticket_types (event_id, name, capacity) VALUES ($1, $2, $3)",
                        event_id,
                        name,
                        tt.capacity,
                    )

        await conn.execute(
            """
            UPDATE events
            SET title = COALESCE($2, title),
                description = COALESCE($3, description),
                category = COALESCE($4, category),
                city = COALESCE($5, city),
                location = COALESCE($6, location),
                starts_at = $7,
                ends_at = $8,
                registration_closes_at = $9,
                admission_opens_at = $10,
                admission_closes_at = $11,
                capacity = $12
            WHERE id = $1
            """,
            event_id,
            body.title.strip() if body.title else None,
            body.description.strip() if body.description else None,
            body.category.strip() if body.category else None,
            body.city.strip() if body.city else None,
            body.location.strip() if body.location else None,
            new_starts,
            new_ends,
            new_reg,
            new_adm_open,
            new_adm_close,
            new_cap,
        )

    await broadcaster.publish(
        "event.updated",
        {"event_id": str(event_id), "status": ev["status"], "server_time": datetime.now(timezone.utc).isoformat()},
    )
    return {"ok": True}


@router.post("/events/{event_id}/publish")
async def publish_event(
    event_id: UUID,
    user: dict = Depends(require_role("organizer")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    async with conn.transaction():
        ev = await conn.fetchrow("SELECT * FROM events WHERE id = $1 FOR UPDATE", event_id)
        if not ev:
            raise HTTPException(status_code=404, detail="Событие не найдено")
        if ev["organizer_id"] != user["id"]:
            raise HTTPException(status_code=403, detail="Нет прав на управление чужим событием")
        if ev["status"] == "CANCELLED":
            raise HTTPException(status_code=409, detail="Нельзя опубликовать отменённое событие")

        types = await conn.fetch("SELECT capacity FROM ticket_types WHERE event_id = $1", event_id)
        if len(types) < 2 or sum(t["capacity"] for t in types) != ev["capacity"]:
            raise HTTPException(status_code=422, detail="Проверьте категории билетов и вместимость")

        await conn.execute("UPDATE events SET status = 'PUBLISHED' WHERE id = $1", event_id)
        await conn.execute(
            "INSERT INTO audit_logs (actor_id, event_id, action, result) VALUES ($1, $2, 'EVENT_PUBLISH', 'PUBLISHED')",
            user["id"],
            event_id,
        )

    await broadcaster.publish(
        "event.updated",
        {"event_id": str(event_id), "status": "PUBLISHED", "server_time": datetime.now(timezone.utc).isoformat()},
    )
    return {"id": str(event_id), "status": "PUBLISHED"}


@router.post("/events/{event_id}/cancel")
async def cancel_event(
    event_id: UUID,
    user: dict = Depends(require_role("organizer")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    async with conn.transaction():
        ev = await conn.fetchrow("SELECT * FROM events WHERE id = $1 FOR UPDATE", event_id)
        if not ev:
            raise HTTPException(status_code=404, detail="Событие не найдено")
        if ev["organizer_id"] != user["id"]:
            raise HTTPException(status_code=403, detail="Нет прав на управление чужим событием")
        if ev["status"] == "CANCELLED":
            return {"id": str(event_id), "status": "CANCELLED"}

        await conn.execute("UPDATE events SET status = 'CANCELLED' WHERE id = $1", event_id)
        await conn.execute(
            "INSERT INTO audit_logs (actor_id, event_id, action, result) VALUES ($1, $2, 'EVENT_CANCEL', 'CANCELLED')",
            user["id"],
            event_id,
        )

    await broadcaster.publish(
        "event.cancelled",
        {"event_id": str(event_id), "server_time": datetime.now(timezone.utc).isoformat()},
    )
    return {"id": str(event_id), "status": "CANCELLED"}


@router.get("/events/{event_id}/stats")
async def event_stats(
    event_id: UUID,
    user: dict = Depends(require_role("organizer")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    ev = await _get_owned_event(conn, event_id, user["id"])
    counts = await conn.fetchrow(
        """
        SELECT
            COALESCE(COUNT(*) FILTER (WHERE status = 'ISSUED'), 0)::int AS issued_only,
            COALESCE(COUNT(*) FILTER (WHERE status = 'USED'), 0)::int AS used_count,
            COALESCE(COUNT(*) FILTER (WHERE status = 'CANCELLED'), 0)::int AS cancelled_count
        FROM tickets
        WHERE event_id = $1
        """,
        event_id,
    )
    scans_total = await conn.fetchval(
        "SELECT COUNT(*)::int FROM audit_logs WHERE event_id = $1 AND action = 'CHECKIN'",
        event_id,
    )
    last_24h = await conn.fetchval(
        "SELECT COUNT(*)::int FROM entries WHERE event_id = $1 AND entered_at >= NOW() - INTERVAL '24 hours'",
        event_id,
    )
    by_type = await conn.fetch(
        """
        SELECT tt.id, tt.name, tt.capacity,
               COALESCE(COUNT(t.id) FILTER (WHERE t.status IN ('ISSUED', 'USED')), 0)::int AS occupied,
               COALESCE(COUNT(t.id) FILTER (WHERE t.status = 'USED'), 0)::int AS used_count
        FROM ticket_types tt
        LEFT JOIN tickets t ON t.type_id = tt.id
        WHERE tt.event_id = $1
        GROUP BY tt.id, tt.name, tt.capacity
        ORDER BY tt.name ASC
        """,
        event_id,
    )
    timeline_rows = await conn.fetch(
        """
        SELECT date_trunc('hour', entered_at) AS bucket, COUNT(*)::int AS count
        FROM entries
        WHERE event_id = $1
        GROUP BY bucket
        ORDER BY bucket ASC
        """,
        event_id,
    )

    total_tickets = counts["issued_only"] + counts["used_count"]
    return {
        "event_id": str(event_id),
        "status": ev["status"],
        "capacity": ev["capacity"],
        "issued_count": total_tickets,
        "used_count": counts["used_count"],
        "cancelled_count": counts["cancelled_count"],
        "free_seats": max(0, ev["capacity"] - total_tickets),
        "scans_total": scans_total,
        "last_24h_entries": last_24h,
        "by_type": [
            {
                "id": str(r["id"]),
                "name": r["name"],
                "capacity": r["capacity"],
                "occupied": r["occupied"],
                "used_count": r["used_count"],
                "remaining": max(0, r["capacity"] - r["occupied"]),
            }
            for r in by_type
        ],
        "timeline": [
            {"bucket": r["bucket"].isoformat(), "count": r["count"]}
            for r in timeline_rows
        ],
        "server_time": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/events/{event_id}/participants")
async def event_participants(
    event_id: UUID,
    search: str | None = Query(default=None),
    type_id: UUID | None = Query(default=None),
    status_filter: str | None = Query(default=None, alias="status"),
    user: dict = Depends(require_role("organizer")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    await _get_owned_event(conn, event_id, user["id"])
    conditions = ["t.event_id = $1"]
    params: list = [event_id]
    idx = 2
    if search:
        conditions.append(f"(u.name ILIKE ${idx} OR t.code ILIKE ${idx})")
        params.append(f"%{search.strip()}%")
        idx += 1
    if type_id:
        conditions.append(f"t.type_id = ${idx}")
        params.append(type_id)
        idx += 1
    if status_filter:
        conditions.append(f"t.status = ${idx}")
        params.append(status_filter)
        idx += 1

    rows = await conn.fetch(
        f"""
        SELECT t.id, t.code, t.status, t.issued_at, t.used_at, t.cancelled_at,
               tt.name AS type_name, u.name AS participant_name, u.email AS participant_email
        FROM tickets t
        JOIN ticket_types tt ON tt.id = t.type_id
        JOIN users u ON u.id = t.participant_id
        WHERE {' AND '.join(conditions)}
        ORDER BY t.issued_at DESC
        """,
        *params,
    )
    return {
        "items": [
            {
                "ticket_id": str(r["id"]),
                "code": r["code"],
                "status": r["status"],
                "type_name": r["type_name"],
                "participant_name": r["participant_name"],
                "participant_email": r["participant_email"],
                "issued_at": r["issued_at"].isoformat(),
                "used_at": r["used_at"].isoformat() if r["used_at"] else None,
                "cancelled_at": r["cancelled_at"].isoformat() if r["cancelled_at"] else None,
            }
            for r in rows
        ]
    }


@router.get("/events/{event_id}/journal")
async def event_journal(
    event_id: UUID,
    user: dict = Depends(require_role("organizer")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    await _get_owned_event(conn, event_id, user["id"])
    rows = await conn.fetch(
        """
        SELECT a.id, a.action, a.result, a.server_time, a.request_id,
               u.name AS actor_name, t.code AS ticket_code
        FROM audit_logs a
        LEFT JOIN users u ON u.id = a.actor_id
        LEFT JOIN tickets t ON t.id = a.ticket_id
        WHERE a.event_id = $1
        ORDER BY a.server_time DESC
        LIMIT 200
        """,
        event_id,
    )
    return {
        "items": [
            {
                "id": str(r["id"]),
                "action": r["action"],
                "result": r["result"],
                "server_time": r["server_time"].isoformat(),
                "request_id": r["request_id"],
                "actor_name": r["actor_name"],
                "ticket_code": r["ticket_code"],
            }
            for r in rows
        ]
    }


@router.get("/controllers")
async def list_all_controllers(
    user: dict = Depends(require_role("organizer")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    rows = await conn.fetch(
        "SELECT id, name, email FROM users WHERE role = 'controller' ORDER BY name ASC"
    )
    return {"items": [{"id": str(r["id"]), "name": r["name"], "email": r["email"]} for r in rows]}


@router.get("/events/{event_id}/controllers")
async def list_event_controllers(
    event_id: UUID,
    user: dict = Depends(require_role("organizer")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    await _get_owned_event(conn, event_id, user["id"])
    rows = await conn.fetch(
        """
        SELECT u.id, u.name, u.email, ca.assigned_at
        FROM controller_assignments ca
        JOIN users u ON u.id = ca.controller_id
        WHERE ca.event_id = $1
        ORDER BY u.name ASC
        """,
        event_id,
    )
    return {
        "items": [
            {
                "id": str(r["id"]),
                "name": r["name"],
                "email": r["email"],
                "assigned_at": r["assigned_at"].isoformat(),
            }
            for r in rows
        ]
    }


@router.post("/events/{event_id}/controllers", status_code=status.HTTP_201_CREATED)
async def assign_controller(
    event_id: UUID,
    body: AssignControllerBody,
    user: dict = Depends(require_role("organizer")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    await _get_owned_event(conn, event_id, user["id"])
    ctrl = await conn.fetchrow(
        "SELECT id, role FROM users WHERE id = $1 AND role = 'controller'",
        body.controller_id,
    )
    if not ctrl:
        raise HTTPException(status_code=404, detail="Контролёр не найден")
    await conn.execute(
        """
        INSERT INTO controller_assignments (event_id, controller_id)
        VALUES ($1, $2)
        ON CONFLICT (event_id, controller_id) DO NOTHING
        """,
        event_id,
        body.controller_id,
    )
    return {"ok": True}


@router.delete("/events/{event_id}/controllers/{controller_id}")
async def revoke_controller(
    event_id: UUID,
    controller_id: UUID,
    user: dict = Depends(require_role("organizer")),
    conn: asyncpg.Connection = Depends(get_conn),
):
    await _get_owned_event(conn, event_id, user["id"])
    await conn.execute(
        "DELETE FROM controller_assignments WHERE event_id = $1 AND controller_id = $2",
        event_id,
        controller_id,
    )
    await broadcaster.publish(
        "controller.revoked",
        {
            "event_id": str(event_id),
            "controller_id": str(controller_id),
            "server_time": datetime.now(timezone.utc).isoformat(),
        },
    )
    return {"ok": True}
