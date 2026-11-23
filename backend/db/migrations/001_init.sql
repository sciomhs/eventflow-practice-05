-- EventFlow Practice 05 — Initial PostgreSQL Schema

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('participant', 'organizer', 'controller')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organizer_id UUID NOT NULL REFERENCES users(id),
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL,
    city TEXT NOT NULL,
    location TEXT NOT NULL,
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    timezone TEXT NOT NULL DEFAULT 'Asia/Yekaterinburg',
    registration_closes_at TIMESTAMPTZ NOT NULL,
    admission_opens_at TIMESTAMPTZ NOT NULL,
    admission_closes_at TIMESTAMPTZ NOT NULL,
    capacity INTEGER NOT NULL CHECK (capacity > 0),
    status TEXT NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'PUBLISHED', 'CANCELLED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_event_dates CHECK (
        starts_at < ends_at
        AND admission_opens_at < admission_closes_at
        AND registration_closes_at <= starts_at
        AND admission_opens_at <= starts_at
        AND admission_closes_at >= starts_at
    )
);

CREATE INDEX IF NOT EXISTS idx_events_status_starts ON events(status, starts_at);
CREATE INDEX IF NOT EXISTS idx_events_organizer ON events(organizer_id);

CREATE TABLE IF NOT EXISTS ticket_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    capacity INTEGER NOT NULL CHECK (capacity > 0),
    UNIQUE (event_id, name)
);

CREATE SEQUENCE IF NOT EXISTS ticket_code_seq START 1;

CREATE TABLE IF NOT EXISTS tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events(id),
    type_id UUID NOT NULL REFERENCES ticket_types(id),
    participant_id UUID NOT NULL REFERENCES users(id),
    code TEXT NOT NULL UNIQUE,
    token_hash TEXT NOT NULL UNIQUE,
    token_encrypted TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'ISSUED' CHECK (status IN ('ISSUED', 'USED', 'CANCELLED')),
    issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cancelled_at TIMESTAMPTZ NULL,
    used_at TIMESTAMPTZ NULL,
    used_by UUID NULL REFERENCES users(id)
);

-- R3: At most one active ticket (ISSUED or USED) per participant + event
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_ticket_per_user_event
    ON tickets(event_id, participant_id)
    WHERE status IN ('ISSUED', 'USED');

CREATE INDEX IF NOT EXISTS idx_tickets_event_status ON tickets(event_id, status);
CREATE INDEX IF NOT EXISTS idx_tickets_type_status ON tickets(type_id, status);
CREATE INDEX IF NOT EXISTS idx_tickets_participant ON tickets(participant_id, issued_at DESC);

CREATE TABLE IF NOT EXISTS controller_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    controller_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (event_id, controller_id)
);

-- Guarantee at most one successful entry per ticket
CREATE TABLE IF NOT EXISTS entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL UNIQUE REFERENCES tickets(id),
    event_id UUID NOT NULL REFERENCES events(id),
    controller_id UUID NOT NULL REFERENCES users(id),
    entered_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_entries_event_entered ON entries(event_id, entered_at DESC);

CREATE TABLE IF NOT EXISTS registration_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    participant_id UUID NOT NULL REFERENCES users(id),
    request_id TEXT NOT NULL,
    payload_hash TEXT NOT NULL,
    response_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (participant_id, request_id)
);

CREATE TABLE IF NOT EXISTS checkin_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    controller_id UUID NOT NULL REFERENCES users(id),
    request_id TEXT NOT NULL,
    payload_hash TEXT NOT NULL,
    response_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (controller_id, request_id)
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id UUID NULL,
    event_id UUID NULL,
    ticket_id UUID NULL,
    action TEXT NOT NULL,
    result TEXT NOT NULL,
    server_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    request_id TEXT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_event_time ON audit_logs(event_id, server_time DESC);
