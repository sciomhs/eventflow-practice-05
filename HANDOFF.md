# Handoff Document — EventFlow Practice 05

**Repository:** `https://github.com/sciomhs/eventflow-practice-05` (`main`, latest commit after `2978250`)  
**Local Path:** `/Users/eliasansariy/.gemini/antigravity/scratch/eventflow-practice-05`  
**Spec:** `/Users/eliasansariy/Downloads/EVENTFLOW_Practice_5.pdf` (18 pages, Russian)  
**Target:** Next-stage agent / Master Prompt author for UI/UX elevation & full end-to-end polish.

---

## 1. Current State (What Already Works)

### Infrastructure & Database
- **PostgreSQL 16** runs in Docker (`docker/docker-compose.yml`, container `eventflow_postgres`, port `5432`).
- **Migrations & Seeder:** `backend/db/migrations/001_init.sql`, `backend/db/migrate.py`, `backend/db/seed_demo.py`.
  - Enforces `UNIQUE(ticket_id)` on `entries`, partial unique index `uq_active_ticket_per_user_event` on `tickets`, date-order `CHECK` constraints (`chk_event_dates`), and idempotency tables (`registration_requests`, `checkin_requests`).
  - Demo accounts (dev password `EventFlow2026!`):
    - `participant1@eventflow.dev`, `participant2@eventflow.dev`
    - `organizer@eventflow.dev`
    - `controller1@eventflow.dev`, `controller2@eventflow.dev`

### Backend (`backend/app/`)
- **FastAPI + asyncpg + `sse-starlette`**, verified on port **`8085`** (note: port `8000` on this Mac is occupied by another service, so `AuthStore` and `README.md` default to `8085`).
- Start command:
  ```bash
  backend/.venv/bin/uvicorn backend.app.main:app --host 0.0.0.0 --port 8085
  ```
- **Verified Tests:**
  - `backend/.venv/bin/pytest backend/tests/test_api_and_races.py -v` -> `1 passed`
  - `backend/.venv/bin/python backend/scripts/verify_race.py` -> `10 ACCEPTED`, `10 ALREADY_USED`, `10 entries`
  - `EVENTFLOW_URL=http://127.0.0.1:8085 backend/.venv/bin/python backend/scripts/run_t01_t16.py` -> **T01–T05, T08–T15** passed (`sse_event_received_in=219ms <= 3000ms`).

### Flutter App (`app/`)
- **Single codebase** (`Flutter 3.50.1`, `Dart 3.14.0`) with Android, Web, and Windows runners scaffolded (`app/android/`, `app/web/`, `app/windows/`).
- **Verified:**
  - `dart format --output=none --set-exit-if-changed lib test` -> 0 changes
  - `flutter test --no-pub` -> `3/3` widget tests passed (`360x800` and `1280x800`)
  - `flutter build web --release --no-pub` -> succeeded (`app/build/web`)

---

## 2. Known Gaps & Next Priorities for Master Prompt

### A. Visual & UX Elevation (Web + Mobile + Desktop)
The current Flutter UI is functional and passes `360px`/`1280px` overflow tests, but needs a **human-grade editorial product polish** using `skills/stitch-skills/plugins/stitch-utilities/skills/taste-design/SKILL.md` and `docs/DESIGN.md`:
1. **Auth Screen (`app/lib/features/auth/auth_screen.dart`):**
   - Improve desktop split-screen visual balance, typography hierarchy, and subtle brand visual/illustration (no generic card-on-blank-canvas feel).
   - Update server-settings dialog hint text to reference port `8085` (`http://10.0.2.2:8085` / `http://localhost:8085`).
2. **Participant Catalog & Ticket Experience (`app/lib/features/participant/`):**
   - Add cleaner filter bar (collapsible/compact on 360 px mobile, inline toolbar on 1280 px web/desktop), visual capacity progress bar on event cards, clearer timezone display, and richer perforated QR ticket pass with download/copy feedback.
   - Add an offline read-only cache (`SharedPreferences`) for catalog & owned tickets with explicit offline indicator (spec §13).
3. **Organizer Dashboard (`app/lib/features/organizer/`):**
   - Render the **hourly check-in timeline chart** (`timeline` array is already returned by `GET /api/v1/organizer/events/{id}/stats`, currently unused in UI!) as a clean bar chart matching `EVENTFLOW_Practice_5.pdf` page 6.
   - Add **Edit Event** UI (`PATCH /api/v1/organizer/events/{id}` exists on backend, currently only Create exists in `event_editor_screen.dart`), plus **date/time pickers** for `starts_at`, `ends_at`, `registration_closes_at`, `admission_opens_at`, `admission_closes_at` instead of hardcoded offsets.
   - On `>= 1000 px` desktop/web, replace plain `ListTile` participant & journal lists with proper `DataTable` / structured columns.
4. **Controller Scanner (`app/lib/features/controller/`):**
   - Ensure Web `mobile_scanner` works smoothly (check `app/web/index.html` for ZXing / camera permission UX and graceful fallback when camera is denied or unavailable).
   - Add distinct visual/audio-free confirmation banner & clear focus management for USB-HID keyboard-wedge scanners on Windows/Web.

### B. Full End-to-End Live Browser & Cross-Platform Verification
- Run the live backend (`8085`) + `flutter run -d chrome` (or Playwright/browser subagent) and manually/automatically walk through **every UI flow**:
  1. Register a brand-new participant account -> browse catalog -> filter -> open event -> register for `Стандарт`/`VIP` -> view QR -> cancel ticket -> re-register -> verify old QR fails.
  2. Login as `organizer@eventflow.dev` -> create a new event with custom dates & categories -> publish it -> assign `controller1` & `controller2` -> watch live SSE stats increment within `<= 3 s` when participant registers and controller scans.
  3. Login as `controller1@eventflow.dev` -> scan/enter ticket code -> verify `ACCEPTED` -> re-enter -> verify `ALREADY_USED` with original `used_at` -> test `WRONG_EVENT`, `INVALID`, `CANCELLED`, `CLOSED`, and revoked controller `403`.
- Record real UI screenshots at `360x800` and `1280x800` into `docs/screenshots/` and link them in `docs/TESTS.md`.

### C. Remaining Platform Builds (Host-Dependent)
- **Android APK (`flutter build apk`):** Install Android SDK `cmdline-tools` and accept licenses (`flutter doctor --android-licenses`), then run `flutter build apk --release`.
- **Windows Desktop (`flutter build windows`):** Run on a Windows 10/11 machine with Visual Studio (*Desktop development with C++*) and verify USB-HID / manual code entry.

---

## 3. Non-Negotiable Rules to Preserve
1. **Flutter/Dart only** for all UI (no separate HTML/React/JS frontends).
2. **Server owns all business truth** (roles, limits, atomic locks, `NOW()` UTC).
3. **Single shared PostgreSQL** (no local-only DBs; local storage is read-only cache).
4. **No secrets committed** (`.env` is gitignored; `.env.example` holds placeholders).
5. **UI in Russian; code/identifiers/comments in English.**
6. **Keep `docs/CONTRACT.md` as the single source of truth** if any API field is added.
