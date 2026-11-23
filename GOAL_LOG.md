# EventFlow Practice 05 — Goal Execution Log

## Phase 1 (G0–G13)
- **G0–G13:** Completed & tagged `submission-ready` (`d960206`).

## Phase 2 (M1–M5)

| Milestone | Scope | Verify Command & Result | Timestamp |
|---|---|---|---|
| **M1 Foundation** | D6 (`intl` `ru` locale + `EfDateFmt` + timezone), D7 (`8085` default + `/health` check + offline read-only cache), D8 (`EfLabels`, `EfSkeletonCard`, `EfCapacityBar`) | `dart format`, `flutter test` (`3/3`), live `/health` (`125 ms, БД: ok`) | 2026-11-24 |
| **M2 Participant** | D4 (debounced search + clear, SSE `EventDetailScreen`, smart default category, role-safe load, inline copy/cancel), D5 (Catalog for Organizer & Controller) | `flutter test` (`3/3`), live E2E: Organizer & Participant 2 browse/register/view QR (`EF-0013`) | 2026-11-24 |
| **M3 Organizer** | D1 (Create+Edit `EventEditorScreen`, date/time pickers, timezone, dynamic categories, post-reg lock, auto-select), D2 (5-section sidebar, `timeline` bar chart, `type_id` filter, `DataTable`s, Russian audit log, surfaced errors) | `flutter test` (`3/3`), live E2E: created & published `E2E Live Test Event`, 5-section sidebar + Catalog verified | 2026-11-24 |
| **M4 Controller** | D3 (`403`/`409` vs `UNCERTAIN`, `controller.revoked` SSE lock, `MobileScanner.errorBuilder`, USB-HID `FocusNode`, `web/index.html` branding), D5 | `flutter build web --release` (exit 0), live E2E: `EF1:invalidtest` -> `НЕВЕРНЫЙ КОД`, `Следующий посетитель` reset | 2026-11-24 |
| **M5 Proof & Gate** | D8, D9 (5-flow live browser E2E), D10 (`360x800` screenshot `docs/screenshots/mobile_360x800.png` + `360px`/`1280px` widget tests), final gate | `dart format --set-exit-if-changed` (0 changed), `flutter test` (`3/3`), `pytest` (`1/1`), `verify_race.py` (`10/10`), `run_t01_t16.py` (T01–T05, T08–T15, SSE `219 ms`), `flutter build web --release` (exit 0) | 2026-11-24 |

## Final 3 Critical Rubric Conditions Re-Verification
- [x] **Shared server DB present:** PostgreSQL 16 (`eventflow_postgres`) running in Docker, migrations + seeder verified.
- [x] **Double-entry protection:** `SELECT ... FOR UPDATE` + `UNIQUE(ticket_id)` on `entries` + `request_id` idempotency (`10/10` parallel scan race passed).
- [~] **3 platforms:** Single Flutter codebase (`android/`, `web/`, `windows/` runners all present in `app/`); Web (`flutter build web --release`) built and verified live in Chrome; Android APK & Windows `.exe` builds require Android SDK `cmdline-tools` and a Windows Visual Studio C++ host respectively (not available on this macOS host).

PHASE 2 READY (Web + Backend + DB verified live; Android/Windows runners scaffolded, host-dependent binary builds documented)
