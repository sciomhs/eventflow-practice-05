# EventFlow Practice 05 — Goal Execution Log

| Goal | Status | Timestamp | Summary / Verify Output |
|---|---|---|---|
| G0 | DONE | 2026-11-24 | Flutter 3.50.1, Dart 3.14.0, Python 3.14.7, Docker 29.1.3, Postgres 16.11 up, `stitch-skills` cloned, `docs/ENVIRONMENT.md` written. |
| G1 | DONE | 2026-11-24 | GitHub repo `sciomhs/eventflow-practice-05` created and pushed. |
| G2 | DONE | 2026-11-24 | `docs/ARCHITECTURE_NOTES.md` and `docs/CONTRACT.md` committed with DB schema, REST API, SSE events, and 7 entry statuses. |
| G3 | DONE | 2026-11-24 | `001_init.sql` migrated, `seed_demo.py` seeded (2 participants, 1 organizer, 2 controllers, 4 events, 12 ISSUED tickets), verified via `psql`. |
| G4 | DONE | 2026-11-24 | FastAPI + asyncpg race logic; `pytest` 1/1 passed; `verify_race.py` 10/10 ACCEPTED, 10 ALREADY_USED, 10 `entries` rows. |
| G5 | DONE | 2026-11-24 | `lib/design/tokens.dart` (Stitch), `EfAdaptiveShell`, `ApiClient`, `SseClient` with auto-reconnect, `AuthStore`. |
| G6 | DONE | 2026-11-24 | Participant module: 6-filter catalog, pagination, live 1-ticket rule, QR card, cancel, history. |
| G7 | DONE | 2026-11-24 | Organizer module: create/publish/cancel, categories/limits, controller assign/revoke, live SSE stats, journal. |
| G8 | DONE | 2026-11-24 | Controller module: `mobile_scanner` + manual/USB code entry, all 7 statuses, re-entry `used_at`, journal, timeout retry. |
| G9–G10 | DONE | 2026-11-24 | T01–T16 executed & recorded in `docs/TESTS.md` (SSE latency measured at `219 ms <= 3000 ms`). |
| G11 | DONE | 2026-11-24 | `flutter test` 3/3 passed at `360x800` (`NavigationBar`) and `1280x800` (`NavigationRail`) with zero overflow. |
| G12 | PARTIAL (Host OS) | 2026-11-24 | `flutter build web --release` succeeded (`app/build/web`). `flutter build apk` requires Android SDK `cmdline-tools` (missing on host); `flutter build windows` requires a Windows host with Visual Studio C++ workload. |
| G13 | DONE | 2026-11-24 | `README.md`, `docs/DB_SCHEMA.md`, 10–12 min demo script, Reviewer gate passed, tagged `submission-ready`. |

## Final Rubric Self-Check (G13)
- [x] Shared server DB (PostgreSQL 16 in Docker, migrations + seeder)
- [x] Double-entry protection (`SELECT ... FOR UPDATE`, `UNIQUE(ticket_id)` on `entries`, `request_id` idempotency)
- [x] 3 roles in one Flutter codebase (`participant`, `organizer`, `controller`)
- [x] Participant, Organizer, Controller features per spec
- [x] SSE real-time sync (`219 ms <= 3000 ms`) + auto-reconnect
- [x] Adaptive UI (`360 px` & `1280 px`), Stitch design system (`tokens.dart`), 16 tests & docs
- [ ] Host-specific binary builds: Web built on this macOS host; APK and Windows `.exe` require Android SDK `cmdline-tools` and a Windows host respectively.

SUBMISSION READY (macOS host scope: backend + DB + Flutter Web + full source for Android/Windows)
