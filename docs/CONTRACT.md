# EventFlow Practice 05 — Architecture & API Contract

This document is the single source of truth for the PostgreSQL schema, REST API, SSE events, and entry status enums.

---

## 1. Enums

### `user_role`
- `participant`
- `organizer`
- `controller`

### `event_status`
- `DRAFT`
- `PUBLISHED`
- `CANCELLED`

### `ticket_status`
- `ISSUED`
- `USED`
- `CANCELLED`

### `entry_status` (Check-in result enum — 7 required states)
- `ACCEPTED` — First valid scan; ticket transitioned `ISSUED -> USED`; `entries` row created.
- `ALREADY_USED` — Ticket was already `USED`; returns original `used_at`.
- `WRONG_EVENT` — Valid ticket format/hash, but belongs to a different `event_id`. No PII returned.
- `INVALID` — Malformed token, unknown `token_hash`, or tampered QR. No PII returned.
- `CLOSED` — Outside admission window `[admission_opens_at, admission_closes_at)` in server UTC time.
- `SOLD_OUT` — Capacity/category limit reached (used on registration; included in shared status enum).
- `CANCELLED` — Ticket is `CANCELLED` or event is `CANCELLED`.

---

## 2. Database Schema (PostgreSQL 16)

All timestamps are `TIMESTAMPTZ` in UTC. Server time (`NOW()`) is authoritative.

1. **`users`**: `id` (UUID PK), `name` (TEXT), `email` (TEXT UNIQUE), `password_hash` (TEXT), `role` (TEXT CHECK IN `participant`, `organizer`, `controller`), `created_at` (TIMESTAMPTZ).
2. **`events`**: `id` (UUID PK), `organizer_id` (UUID FK -> `users.id`), `title` (TEXT), `description` (TEXT), `category` (TEXT), `city` (TEXT), `location` (TEXT), `starts_at` (TIMESTAMPTZ), `ends_at` (TIMESTAMPTZ), `timezone` (TEXT), `registration_closes_at` (TIMESTAMPTZ), `admission_opens_at` (TIMESTAMPTZ), `admission_closes_at` (TIMESTAMPTZ), `capacity` (INT CHECK > 0), `status` (TEXT CHECK IN `DRAFT`, `PUBLISHED`, `CANCELLED`), `created_at` (TIMESTAMPTZ).
   - Constraints: `starts_at < ends_at`, `admission_opens_at < admission_closes_at`, `registration_closes_at <= starts_at`, `admission_opens_at <= starts_at`, `admission_closes_at >= starts_at`.
3. **`ticket_types`**: `id` (UUID PK), `event_id` (UUID FK -> `events.id` ON DELETE CASCADE), `name` (TEXT), `capacity` (INT CHECK > 0), `UNIQUE(event_id, name)`.
4. **`tickets`**: `id` (UUID PK), `event_id` (UUID FK -> `events.id`), `type_id` (UUID FK -> `ticket_types.id`), `participant_id` (UUID FK -> `users.id`), `code` (TEXT UNIQUE, e.g. `EF-0001`), `token_hash` (TEXT UNIQUE), `token_encrypted` (TEXT), `status` (TEXT CHECK IN `ISSUED`, `USED`, `CANCELLED`), `issued_at` (TIMESTAMPTZ), `cancelled_at` (TIMESTAMPTZ NULL), `used_at` (TIMESTAMPTZ NULL), `used_by` (UUID NULL FK -> `users.id`).
   - Partial unique index: `uq_active_ticket_per_user_event` ON `tickets(event_id, participant_id)` WHERE `status IN ('ISSUED', 'USED')`.
5. **`controller_assignments`**: `id` (UUID PK), `event_id` (UUID FK -> `events.id`), `controller_id` (UUID FK -> `users.id`), `assigned_at` (TIMESTAMPTZ), `UNIQUE(event_id, controller_id)`.
6. **`entries`**: `id` (UUID PK), `ticket_id` (UUID UNIQUE FK -> `tickets.id`), `event_id` (UUID FK -> `events.id`), `controller_id` (UUID FK -> `users.id`), `entered_at` (TIMESTAMPTZ).
7. **`registration_requests`**: `id` (UUID PK), `participant_id` (UUID FK -> `users.id`), `request_id` (TEXT), `payload_hash` (TEXT), `response_json` (JSONB), `created_at` (TIMESTAMPTZ), `UNIQUE(participant_id, request_id)`.
8. **`checkin_requests`**: `id` (UUID PK), `controller_id` (UUID FK -> `users.id`), `request_id` (TEXT), `payload_hash` (TEXT), `response_json` (JSONB), `created_at` (TIMESTAMPTZ), `UNIQUE(controller_id, request_id)`.
9. **`audit_logs`**: `id` (UUID PK), `actor_id` (UUID NULL), `event_id` (UUID NULL), `ticket_id` (UUID NULL), `action` (TEXT), `result` (TEXT), `server_time` (TIMESTAMPTZ), `request_id` (TEXT NULL). Never stores raw QR tokens.

---

## 3. REST API Endpoints

### Health & Auth
- `GET /health` -> `200 { "status": "ok", "db": "ok", "server_time": "..." }`
- `POST /api/v1/auth/register` -> `{ "name", "email", "password" }` (rejects `role` tampering with `403`) -> `201 { "access_token", "token_type": "bearer", "user": {...} }`
- `POST /api/v1/auth/login` -> `{ "email", "password" }` -> `200 { "access_token", "token_type": "bearer", "user": {...} }` (401 generic message on failure)
- `GET /api/v1/auth/me` -> `200 { "id", "name", "email", "role" }`
- `PATCH /api/v1/auth/me` -> rejects role/privilege escalation with `403`

### Public / Participant Events & Tickets
- `GET /api/v1/events` -> Query: `search`, `status` (defaults `PUBLISHED`), `category`, `city`, `date_from`, `date_to`, `sort` (`starts_at_asc`, `starts_at_desc`, `seats_desc`), `page` (1), `page_size` (20) -> `200 { "items": [...], "total", "page", "page_size", "server_time" }`
- `GET /api/v1/events/{event_id}` -> `200 { ...event, "ticket_types": [...], "my_ticket": {...} | null, "server_time" }`
- `POST /api/v1/events/{event_id}/register` (participant) -> `{ "type_id", "request_id" }` -> `200 { "outcome": "ISSUED" | "ALREADY_REGISTERED" | "SOLD_OUT" | "CLOSED" | "CANCELLED", "idempotent_replay": bool, "ticket": {...} | null }`
- `GET /api/v1/tickets/my` (participant) -> `200 { "items": [...], "server_time" }` (includes decrypted `qr_token` for `ISSUED` tickets)
- `GET /api/v1/tickets/{ticket_id}` (participant owner) -> `200 { ... }` (`403` if not owner)
- `POST /api/v1/tickets/{ticket_id}/cancel` (participant owner) -> `200 { "ticket": {...} }` (`409` if `USED`, `403` if not owner)

### Organizer
- `GET /api/v1/organizer/events` -> `200 { "items": [...] }`
- `POST /api/v1/organizer/events` -> `{ title, description, category, city, location, starts_at, ends_at, timezone, registration_closes_at, admission_opens_at, admission_closes_at, capacity, ticket_types: [{name, capacity}] }` -> `201`
- `PATCH /api/v1/organizer/events/{event_id}` -> update event/limits (`403` if not owner; `409` if reducing capacity/changing times after first registration)
- `POST /api/v1/organizer/events/{event_id}/publish` -> `200`
- `POST /api/v1/organizer/events/{event_id}/cancel` -> `200`
- `GET /api/v1/organizer/events/{event_id}/stats` -> `200 { "capacity", "issued_count", "used_count", "cancelled_count", "free_seats", "scans_total", "last_24h_entries", "by_type": [...], "timeline": [...], "server_time" }`
- `GET /api/v1/organizer/events/{event_id}/participants` -> Query: `search`, `type_id`, `status` -> `200 { "items": [...] }`
- `GET /api/v1/organizer/events/{event_id}/journal` -> `200 { "items": [...] }`
- `GET /api/v1/organizer/controllers` -> `200 { "items": [...] }`
- `GET /api/v1/organizer/events/{event_id}/controllers` -> `200 { "items": [...] }`
- `POST /api/v1/organizer/events/{event_id}/controllers` -> `{ "controller_id" }` -> `201`
- `DELETE /api/v1/organizer/events/{event_id}/controllers/{controller_id}` -> `200`

### Controller
- `GET /api/v1/controller/events` -> `200 { "items": [...] }` (assigned events only)
- `POST /api/v1/controller/checkin` -> `{ "event_id", "qr_token", "request_id" }` -> `200 { "status": "<entry_status>", "idempotent_replay": bool, "server_time": "...", "used_at": "..." | null, "ticket_code": "..." | null, "type_name": "..." | null, "participant_name": "..." | null, "message": "..." }` (`403` if controller not assigned / revoked; `409` if `request_id` reused with different payload)
- `GET /api/v1/controller/journal` -> Query: `event_id` -> `200 { "items": [...] }`

---

## 4. Server-Sent Events (SSE)

Endpoint: `GET /api/v1/stream?token=<jwt>` (or `Authorization: Bearer <jwt>`)

Emitted events (all published **after** DB `COMMIT`):
- `connected`: `{ "server_time": "..." }`
- `ticket.issued`: `{ "event_id", "type_id", "free_seats", "server_time" }`
- `ticket.cancelled`: `{ "event_id", "type_id", "free_seats", "server_time" }`
- `entry.accepted`: `{ "event_id", "ticket_code", "used_at", "used_count", "server_time" }`
- `entry.rejected`: `{ "event_id", "status", "server_time" }`
- `event.updated`: `{ "event_id", "status", "server_time" }`
- `event.cancelled`: `{ "event_id", "server_time" }`
- `controller.revoked`: `{ "event_id", "controller_id", "server_time" }`
- Keep-alive comment `: keep-alive` every 15 seconds.

Clients must subscribe to `/api/v1/stream`, update UI within ≤ 3 s on stable networks, and on reconnect immediately refresh active views via REST.
