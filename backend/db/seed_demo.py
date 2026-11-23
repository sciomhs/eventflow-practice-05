"""Demo data seeder for EventFlow Practice 05.

Idempotent: safe to run multiple times; resets/ensures demo accounts,
3+ events (PUBLISHED, DRAFT, CANCELLED, plus 1-seat event for T03),
and 10 fresh ISSUED tickets for repeatable T09/race testing.
"""
import asyncio
import base64
import hashlib
import os
import secrets
from datetime import datetime, timedelta, timezone
import asyncpg
from cryptography.fernet import Fernet
from passlib.context import CryptContext

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://eventflow:eventflow_dev@localhost:5432/eventflow",
).replace("postgresql+asyncpg://", "postgresql://")

DEFAULT_FERNET_KEY = base64.urlsafe_b64encode(
    hashlib.sha256(b"dev-only-fernet-key-placeholder-32-bytes=").digest()
).decode()
TOKEN_ENCRYPTION_KEY = os.getenv("TOKEN_ENCRYPTION_KEY", DEFAULT_FERNET_KEY)

pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")
DEV_PASSWORD = "EventFlow2026!"


def get_fernet() -> Fernet:
    key = TOKEN_ENCRYPTION_KEY.encode()
    try:
        return Fernet(key)
    except Exception:
        derived = base64.urlsafe_b64encode(hashlib.sha256(key).digest())
        return Fernet(derived)


def make_token(fernet: Fernet) -> tuple[str, str, str]:
    raw = f"EF1:{secrets.token_hex(16)}"
    token_hash = hashlib.sha256(raw.encode()).hexdigest()
    token_enc = fernet.encrypt(raw.encode()).decode()
    return raw, token_hash, token_enc


async def seed_demo(dsn: str = DATABASE_URL) -> dict:
    conn = await asyncpg.connect(dsn)
    fernet = get_fernet()
    pw_hash = pwd_ctx.hash(DEV_PASSWORD)
    now = datetime.now(timezone.utc)

    try:
        async with conn.transaction():
            # Clean existing demo data in dependency order for deterministic re-runs
            await conn.execute("DELETE FROM audit_logs")
            await conn.execute("DELETE FROM checkin_requests")
            await conn.execute("DELETE FROM registration_requests")
            await conn.execute("DELETE FROM entries")
            await conn.execute("DELETE FROM controller_assignments")
            await conn.execute("DELETE FROM tickets")
            await conn.execute("DELETE FROM ticket_types")
            await conn.execute("DELETE FROM events")
            await conn.execute("DELETE FROM users")
            await conn.execute("ALTER SEQUENCE ticket_code_seq RESTART WITH 1")

            # 1. Users: 2 participants, 1 organizer, 2 controllers + 10 race-test participants
            async def insert_user(name: str, email: str, role: str):
                return await conn.fetchval(
                    """
                    INSERT INTO users (name, email, password_hash, role)
                    VALUES ($1, $2, $3, $4)
                    RETURNING id
                    """,
                    name,
                    email,
                    pw_hash,
                    role,
                )

            p1_id = await insert_user("Алина Соколова", "participant1@eventflow.dev", "participant")
            p2_id = await insert_user("Дмитрий Волков", "participant2@eventflow.dev", "participant")
            org_id = await insert_user("Елена Кузнецова", "organizer@eventflow.dev", "organizer")
            ctrl1_id = await insert_user("Артём Морозов", "controller1@eventflow.dev", "controller")
            ctrl2_id = await insert_user("Ирина Павлова", "controller2@eventflow.dev", "controller")

            race_users = []
            for i in range(1, 11):
                uid = await insert_user(
                    f"Участник Тест {i:02d}",
                    f"race{i:02d}@eventflow.dev",
                    "participant",
                )
                race_users.append(uid)

            # 2. Events:
            # Event A: PUBLISHED (admission open right now for live check-in tests!)
            ev_pub_id = await conn.fetchval(
                """
                INSERT INTO events (
                    organizer_id, title, description, category, city, location,
                    starts_at, ends_at, timezone,
                    registration_closes_at, admission_opens_at, admission_closes_at,
                    capacity, status
                ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,'PUBLISHED')
                RETURNING id
                """,
                org_id,
                "TECH FORUM 2026",
                "Ежегодный форум о кроссплатформенной разработке, архитектуре и надёжных распределённых системах.",
                "Технологии",
                "Екатеринбург",
                "Конгресс-холл, Зал A",
                now + timedelta(hours=1),
                now + timedelta(hours=5),
                "Asia/Yekaterinburg",
                now + timedelta(minutes=50),
                now - timedelta(hours=1),
                now + timedelta(hours=4),
                120,
            )
            tt_pub_std = await conn.fetchval(
                "INSERT INTO ticket_types (event_id, name, capacity) VALUES ($1, 'Стандарт', 90) RETURNING id",
                ev_pub_id,
            )
            tt_pub_vip = await conn.fetchval(
                "INSERT INTO ticket_types (event_id, name, capacity) VALUES ($1, 'VIP', 30) RETURNING id",
                ev_pub_id,
            )

            # Event B: DRAFT
            ev_draft_id = await conn.fetchval(
                """
                INSERT INTO events (
                    organizer_id, title, description, category, city, location,
                    starts_at, ends_at, timezone,
                    registration_closes_at, admission_opens_at, admission_closes_at,
                    capacity, status
                ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,'DRAFT')
                RETURNING id
                """,
                org_id,
                "Design Meetup: Типографика и сетки",
                "Практический разбор дизайн-систем для мобильных и десктопных приложений.",
                "Дизайн",
                "Москва",
                "Пространство «Хлебозавод», павильон 4",
                now + timedelta(days=5),
                now + timedelta(days=5, hours=3),
                "Europe/Moscow",
                now + timedelta(days=4, hours=20),
                now + timedelta(days=4, hours=23),
                now + timedelta(days=5, hours=2),
                40,
            )
            await conn.execute(
                "INSERT INTO ticket_types (event_id, name, capacity) VALUES ($1, 'Стандарт', 30), ($1, 'VIP', 10)",
                ev_draft_id,
            )

            # Event C: CANCELLED
            ev_cancel_id = await conn.fetchval(
                """
                INSERT INTO events (
                    organizer_id, title, description, category, city, location,
                    starts_at, ends_at, timezone,
                    registration_closes_at, admission_opens_at, admission_closes_at,
                    capacity, status
                ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,'CANCELLED')
                RETURNING id
                """,
                org_id,
                "Закрытый хакатон «Осень»",
                "Событие отменено организатором; исторические данные сохранены.",
                "Хакатон",
                "Санкт-Петербург",
                "Технопарк «Ингрия»",
                now + timedelta(days=2),
                now + timedelta(days=2, hours=8),
                "Europe/Moscow",
                now + timedelta(days=1, hours=20),
                now + timedelta(days=1, hours=23),
                now + timedelta(days=2, hours=6),
                60,
            )
            await conn.execute(
                "INSERT INTO ticket_types (event_id, name, capacity) VALUES ($1, 'Стандарт', 40), ($1, 'VIP', 20)",
                ev_cancel_id,
            )

            # Event D: PUBLISHED with 1 free seat remaining (for T03 last-seat race test)
            ev_last_id = await conn.fetchval(
                """
                INSERT INTO events (
                    organizer_id, title, description, category, city, location,
                    starts_at, ends_at, timezone,
                    registration_closes_at, admission_opens_at, admission_closes_at,
                    capacity, status
                ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,'PUBLISHED')
                RETURNING id
                """,
                org_id,
                "AI Summit: Последнее место",
                "Камерная сессия для проверки конкурентной регистрации на последнее свободное место.",
                "Технологии",
                "Екатеринбург",
                "Малый зал B",
                now + timedelta(days=1),
                now + timedelta(days=1, hours=3),
                "Asia/Yekaterinburg",
                now + timedelta(hours=23),
                now + timedelta(hours=23),
                now + timedelta(days=1, hours=2),
                2,
            )
            tt_last_std = await conn.fetchval(
                "INSERT INTO ticket_types (event_id, name, capacity) VALUES ($1, 'Стандарт', 1) RETURNING id",
                ev_last_id,
            )
            tt_last_vip = await conn.fetchval(
                "INSERT INTO ticket_types (event_id, name, capacity) VALUES ($1, 'VIP', 1) RETURNING id",
                ev_last_id,
            )

            # Assign both controllers to TECH FORUM 2026 and AI Summit
            await conn.execute(
                """
                INSERT INTO controller_assignments (event_id, controller_id)
                VALUES ($1, $3), ($1, $4), ($2, $3), ($2, $4)
                """,
                ev_pub_id,
                ev_last_id,
                ctrl1_id,
                ctrl2_id,
            )

            # Issue 1 VIP ticket on AI Summit so exactly 1 Стандарт seat remains
            async def issue_ticket(event_id, type_id, participant_id):
                seq = await conn.fetchval("SELECT nextval('ticket_code_seq')")
                code = f"EF-{seq:04d}"
                raw, thash, tenc = make_token(fernet)
                tid = await conn.fetchval(
                    """
                    INSERT INTO tickets (event_id, type_id, participant_id, code, token_hash, token_encrypted, status)
                    VALUES ($1, $2, $3, $4, $5, $6, 'ISSUED')
                    RETURNING id
                    """,
                    event_id,
                    type_id,
                    participant_id,
                    code,
                    thash,
                    tenc,
                )
                return {"id": str(tid), "code": code, "qr_token": raw}

            await issue_ticket(ev_last_id, tt_last_vip, race_users[0])

            # Issue 10 fresh tickets on TECH FORUM 2026 for repeatable T09/race tests
            fresh_tokens = []
            for uid in race_users:
                t = await issue_ticket(ev_pub_id, tt_pub_std, uid)
                fresh_tokens.append(t)

            # Also issue 1 ticket for participant1 on TECH FORUM 2026 so demo starts with live data
            p1_ticket = await issue_ticket(ev_pub_id, tt_pub_vip, p1_id)

            return {
                "event_published_id": str(ev_pub_id),
                "event_last_seat_id": str(ev_last_id),
                "fresh_tickets": fresh_tokens,
                "participant1_ticket": p1_ticket,
            }
    finally:
        await conn.close()


if __name__ == "__main__":
    res = asyncio.run(seed_demo())
    print("Seeded demo data successfully.")
    print("TECH FORUM 2026 ID:", res["event_published_id"])
    print("AI Summit (1 seat left) ID:", res["event_last_seat_id"])
    print("Fresh race tickets:", len(res["fresh_tickets"]))
