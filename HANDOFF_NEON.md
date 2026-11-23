# Master Handoff Brief (v2 — Deep Audit) — EventFlow Practice 05

**Prepared for:** Fable 5.2 (to author the Master Prompt for Phase 2 Polish, UX Elevation & Full E2E Hardening)  
**Repository:** `https://github.com/sciomhs/eventflow-practice-05` (`main`, base commit `d70b9a8`)  
**Workspace Path:** `/Users/eliasansariy/.gemini/antigravity/scratch/eventflow-practice-05`  
**Original Spec:** `/Users/eliasansariy/Downloads/EVENTFLOW_Practice_5.pdf` (18 pages, Russian)  
**Design Skill Reference:** `skills/stitch-skills/plugins/stitch-utilities/skills/taste-design/SKILL.md` & `docs/DESIGN.md`

---

## 1. Executive Summary

The **backend + database + core concurrency engine** of EventFlow Practice 05 is **complete, tested, and rock-solid** (PostgreSQL 16 in Docker, FastAPI + `asyncpg` + SSE, atomic `SELECT ... FOR UPDATE` locks, `request_id` idempotency, `pytest` green, 10-parallel-scan race gate green, live SSE measured at `219 ms <= 3000 ms`).

The **Flutter application (`app/`)** compiles cleanly (`flutter test` 3/3 green, `flutter build web --release` green) and covers the basic happy paths for all 3 roles (`participant`, `organizer`, `controller`), **but** a line-by-line audit against `EVENTFLOW_Practice_5.pdf` reveals **10 concrete functional, UX, and visual gaps** that must be fixed so that:
1. Every single spec requirement (100-point rubric, pages 4–18) is genuinely fulfilled without shortcuts.
2. Every flow — from user registration, login, event creation/editing/publishing, ticket registration, QR display, controller scanning, cancellation, to live SSE updates — works seamlessly end-to-end.
3. The Web / Desktop / Mobile interface looks like a **polished, modern, human-designed event-tech product** rather than a wireframe of default cards and `ListTile`s.

---

## 2. Verified Environment & How to Run Right Now

- **Toolchain on host (macOS arm64):** Flutter `3.50.1`, Dart `3.14.0`, Python `3.14.7`, Docker `29.1.3`, PostgreSQL `16.11` (`eventflow_postgres` container on port `5432`), Node `v26.0.0`, `gh` authenticated as `sciomhs`.
- **Important Port Note:** Port `8000` is occupied by an unrelated local service on this Mac (returning 404). EventFlow's API server and `AuthStore` default to **port `8085`**.
- **Commands:**
  ```bash
  # 1. Database (already up; safe to re-run)
  docker compose -f docker/docker-compose.yml up -d
  backend/.venv/bin/python backend/db/migrate.py
  backend/.venv/bin/python backend/db/seed_demo.py

  # 2. Backend API + SSE
  backend/.venv/bin/uvicorn backend.app.main:app --host 0.0.0.0 --port 8085
  # Health check: curl http://127.0.0.1:8085/health

  # 3. Backend verification gates (DO NOT REGRESS)
  backend/.venv/bin/pytest backend/tests/test_api_and_races.py -v
  backend/.venv/bin/python backend/scripts/verify_race.py
  EVENTFLOW_URL=http://127.0.0.1:8085 backend/.venv/bin/python backend/scripts/run_t01_t16.py

  # 4. Flutter app
  cd app && flutter run -d chrome
  ```
- **Dev Demo Accounts (password: `EventFlow2026!`):**
  - `participant1@eventflow.dev`, `participant2@eventflow.dev`
  - `organizer@eventflow.dev`
  - `controller1@eventflow.dev`, `controller2@eventflow.dev`

---

## 3. Code-Level Audit: 10 Concrete Defects & Gaps to Fix

These were verified directly in the source files and MUST be addressed by the Master Prompt:

### Defect 1 — Event Creation & Editing Is Incomplete (`app/lib/features/organizer/event_editor_screen.dart`)
- **Current state:**
  - Lines 44–49 hardcode `starts_at`, `ends_at`, `registration_closes_at`, `admission_opens_at`, `admission_closes_at`, and `timezone = 'Asia/Yekaterinburg'`. Users cannot pick dates, times, or timezones!
  - Only 2 hardcoded category inputs (`Стандарт`, `VIP`); cannot add/rename categories.
  - **No Edit Event mode**, even though `PATCH /api/v1/organizer/events/{event_id}` is already fully implemented on the backend (including locking time edits and blocking capacity decreases after the first registration).
  - After creating a draft (`organizer_dashboard_screen.dart:259-265`), `_selectedEventId` stays on the previous event instead of selecting the newly created draft!
- **Required fix:**
  - Build a full Create + Edit `EventEditorScreen` with:
    - Interactive date + time pickers for `starts_at`, `ends_at`, `registration_closes_at`, `admission_opens_at`, `admission_closes_at` with live client-side validation matching `chk_event_dates` (`starts_at < ends_at`, `admission_opens_at <= starts_at <= admission_closes_at`, `registration_closes_at <= starts_at`).
    - Timezone selector (`Asia/Yekaterinburg`, `Europe/Moscow`, `UTC`, etc.).
    - Dynamic ticket category builder (minimum 2 categories, shows live total capacity sum).
    - In Edit mode: if tickets already exist (`occupied > 0`), clearly lock date/time inputs with a Russian tooltip ("После первой регистрации перенос времени заблокирован") and allow only increasing capacity/category limits.
    - Optionally offer "Сохранить черновик" AND "Создать и опубликовать" actions, and auto-select the newly created event in the dashboard.

### Defect 2 — Organizer Dashboard Missing Chart, Category Filter, Edit Action & Sidebar Navigation (`app/lib/features/organizer/organizer_dashboard_screen.dart` & `app/lib/core/models/models.dart`)
- **Current state:**
  - Backend `GET /api/v1/organizer/events/{id}/stats` already returns `timeline: [{bucket, count}]`, **but** `OrganizerStats` (`models.dart:194-224`) drops it and the UI renders no chart! Spec page 6 explicitly shows an **"Входы по времени" bar chart**.
  - Spec page 6 shows a dedicated **5-section sidebar** (`Обзор`, `Мероприятия`, `Участники`, `Контролёры`, `Журнал`); currently `app.dart` puts only 1 item (`Управление`) in `NavigationRail` and squeezes 4 tabs inside a nested `TabBar`.
  - Participants tab (`organizer_dashboard_screen.dart:347-378`) is missing the **filter by ticket category (`type_id`)** required by spec page 6 (backend already supports `type_id` query param!).
  - No **Edit Event** button for owned events.
  - Event selector `DropdownButton` (line 223) lacks `isExpanded: true`, risking horizontal clipping at `360px`.
  - `_loadSelectedDetails()` (line 130) has `catch (_) {}` — silently swallows network/API errors instead of surfacing `EfErrorBanner`.
  - Journal displays raw English strings (`TICKET_ISSUE -> ISSUED`, `CHECKIN -> ACCEPTED`) instead of clear Russian action/status labels.
  - Desktop (`>= 1000 px`) uses flat `ListTile` cards instead of crisp `DataTable` views for Participants and Journal.

### Defect 3 — Controller Scanner Misclassifies `403` / `409` as Network Timeout & Lacks Revocation/Camera Polish (`app/lib/features/controller/scanner_screen.dart`)
- **Current state:**
  - Lines 110–123 catch ALL errors identically as `status: 'UNCERTAIN'` ("Нет связи или истёк таймаут"). When an organizer revokes a controller (`403 FORBIDDEN`, T15) or a `request_id` payload conflicts (`409`), the UI falsely says there is no network!
  - Does not subscribe to `widget.auth.sse.messages` for `controller.revoked` events (which the backend already broadcasts!).
  - `MobileScanner` (line 193) has no `errorBuilder` to handle denied/missing camera permission gracefully on Web/Android with a Russian prompt to use manual code entry.
  - Manual/USB-HID code `TextField` does not auto-focus (`FocusNode`) after clicking «Следующий посетитель», slowing down USB barcode scanners on Windows/Web.
  - `DropdownButtonFormField` (line 164) lacks `isExpanded: true` for `360px` widths.
  - `app/web/index.html` still has default `<title>eventflow_app</title>`, default description, and needs explicit Web title (`EventFlow — Платформа мероприятий`) and verification of `mobile_scanner` Web camera setup.

### Defect 4 — Participant Flow Bugs (`app/lib/features/participant/`)
- **Current state:**
  - `catalog_screen.dart:136-156`: Search `TextField` has no `onChanged` (debounced search + `setState`), so the clear (`X`) button never appears while typing and users must press Enter to filter.
  - `event_detail_screen.dart:50`: Calls `GET /api/v1/tickets/my` unconditionally, which returns `403` if opened by an `organizer` or `controller` (spec page 4 states ALL 3 roles can view the published catalog!).
  - `event_detail_screen.dart`: Does NOT subscribe to SSE (`ticket.issued`, `ticket.cancelled`, `event.cancelled`), so remaining seats per category stay stale while on the event detail screen.
  - `event_detail_screen.dart:66-67`: `_selectedTypeId` defaults to `ev.ticketTypes.first.id` even if that category has `remaining == 0` (sold out) while another category still has seats!
  - `event_detail_screen.dart`: Shows the active ticket inline, but lacks a direct "Отменить регистрацию" button or "Скопировать код" button right on that card (only available in `MyTicketsScreen`).

### Defect 5 — Missing Catalog Access for Organizer & Controller (`app/lib/app.dart`)
- **Spec requirement (page 4 role matrix):** Published events catalog is accessible to **Участник = Да, Организатор = Да, Контролёр = Да**.
- **Current state:** Only `participant` has a «Каталог» destination in `app.dart`. Add a read-only «Каталог» destination for `organizer` and `controller` (hiding registration CTA cleanly while backend continues enforcing `403` on `/register`).

### Defect 6 — Russian Date/Time Localization & Explicit Event Timezone Display
- **Current state:** `DateFormat('d MMM, HH:mm')` and `DateFormat('d MMMM yyyy, HH:mm')` across `catalog_screen.dart`, `event_detail_screen.dart`, `my_tickets_screen.dart`, and `scanner_screen.dart` format months in **English** (`Nov`, `December`) because `initializeDateFormatting('ru')` is never called in `main.dart` and `DateFormat(..., 'ru')` is not passed.
- **Required fix:** Initialize Russian locale (`intl/date_symbol_data_local.dart`) in `main.dart`, format all dates in Russian (`24 ноября, 18:00`), and clearly display event timezone (`Asia/Yekaterinburg`, `Europe/Moscow`) per spec page 8.

### Defect 7 — Stale Port `8000` Cache & Missing Pre-Login Connection Check (`app/lib/core/auth_store.dart` & `auth_screen.dart`)
- **Current state:**
  - `auth_screen.dart:76` still displays `http://10.0.2.2:8000` in the server dialog hint text.
  - If a browser previously cached `http://localhost:8000` in `SharedPreferences`, the app keeps hitting port `8000` (getting `404` from the unrelated local service).
- **Required fix:** Update hint text to port `8085`, add a live **server connection indicator & "Проверить связь (`/health`)"** button in the Server Settings dialog, and provide a "Сбросить по умолчанию" button.

### Defect 8 — Offline Read-Only Cache Not Implemented (Spec Page 13)
- **Spec requirement:** *"Каталог и сохранённый билет можно показать из кеша с отметкой о связи. Новая регистрация, отмена и вход без подтверждения сервера не считаются выполненными."*
- **Current state:** When offline, catalog and tickets screens show an error banner with no cached items.
- **Required fix:** Cache the latest fetched JSON for `/api/v1/events` and `/api/v1/tickets/my` in `SharedPreferences` (keyed per user/baseUrl). On network failure, render cached catalog/tickets with an explicit amber banner ("Показаны сохранённые данные — нет связи с сервером") and disable write actions (register / cancel / check-in) with clear Russian explanation.

### Defect 9 — Visual & UX Craft Does Not Yet Meet "Professionally Pleasing" Standard (`skills/stitch-skills/.../taste-design/SKILL.md`)
- **Current state:**
  - Uses generic `CircularProgressIndicator()` everywhere instead of layout-matched **skeletal loaders** (explicitly requested by `taste-design/SKILL.md` §5).
  - Visual hierarchy is flat: uniform bordered cards, plain `ListTile` rows, default Material `DropdownButton`, raw enum strings (`PUBLISHED`, `DRAFT`, `ISSUED`, `USED`) instead of localized badges (`Опубликовано`, `Черновик`, `Действителен`, `Использован`).
  - `AuthScreen` quick-fill demo chips sit exposed at the bottom of the production-looking card instead of a subtle collapsible/clean "Демо-аккаунты" section with role descriptions.
  - Event cards lack visual rhythm (no capacity progress bar, no crisp date badge block, no asymmetric editorial layout on desktop).
  - Organizer stats cards lack comparative context (occupancy percentage bar + hourly bar chart + quick KPI summary).
- **Required visual upgrade:**
  - Follow `docs/DESIGN.md` & `taste-design/SKILL.md` strictly: Warm Paper (`#FAF7F2`), Pure Card (`#FFFFFF`), Warm Stone (`#F1ECE2`), Deep Ink (`#1C1B18`), single Event Emerald accent (`#1F9D6B`), semantic Coral (`#D94F3D`) and Amber (`#C97A16`). **Zero AI purple/neon gradients, zero pure `#000000`, zero emojis in UI chrome, zero raw hex colors outside `lib/design/tokens.dart`.**
  - Add custom skeletal shimmer placeholders (`EfSkeletonCard`), editorial date blocks on event cards, occupancy progress bars, a custom `CustomPainter` / bar chart for Organizer "Входы по времени", desktop `DataTable` views with alternating subtle Warm Stone headers, and tactile button/card hover & focus rings for keyboard navigation.
  - Resolve `flutter analyze` deprecation infos cleanly (migrate `RadioListTile` `groupValue` to Flutter 3.50's `RadioGroup` or clean custom selectable category cards; keep `flutter analyze` zero warnings/errors).

### Defect 10 — Missing Live Browser E2E Verification, Screenshots & Android/Windows Binaries
- **Current state:**
  - `docs/TESTS.md` has verified backend/API/SSE evidence for T01–T05 & T08–T15 and widget test evidence for T06, **but** no committed UI screenshots at `360px` and `1280px` (`docs/screenshots/`) and no full browser-driven E2E walkthrough verifying every click from registration to event creation to check-in.
  - `flutter build web --release` succeeded; `flutter build apk` was blocked by missing Android SDK `cmdline-tools`; `flutter build windows` requires a Windows host with Visual Studio C++ workload.

---

## 4. End-to-End Flows That Must Work Flawlessly (Acceptance Checklist)

The next agent must execute and visually verify **every** flow in a real running browser (Web on Chrome against live FastAPI on port `8085` + PostgreSQL 16):

1. **Flow 1 — Brand-New User Registration & Session Persistence:**
   - Open app → switch to "Регистрация" → register new participant → lands on Catalog → reload browser page (`F5`) → session restores automatically via `/api/v1/auth/me` and SSE reconnects.
2. **Flow 2 — Organizer Full Event Lifecycle (Create → Edit → Publish → Assign Controllers → Live Stats):**
   - Login as `organizer@eventflow.dev` → open "Создать событие" → fill title, description, category, city, venue, custom dates/times, timezone, and >=2 ticket categories (`Стандарт`, `VIP`) → save draft → edit draft (verify changes persist) → click "Опубликовать" → switch to "Контролёры" and assign `controller1` & `controller2` → open "Обзор" and keep live stats + bar chart visible.
3. **Flow 3 — Participant Discovery, Filtering, Registration, QR & Cancellation:**
   - Login as participant → test all 6 filters (live search, status, category, city, date preset, sort) + pagination → open the newly published event → see live remaining seats → select category → register → verify perforated QR pass + readable code `EF-...` + full token `EF1:...` + copy button → verify Organizer stats update automatically via SSE in `<= 3 s` without reload → cancel ticket (with confirmation dialog) → verify seat returns to catalog & Organizer stats → re-register → verify new QR token differs from old one.
4. **Flow 4 — Controller Verification, All 7 Statuses, Revocation & Re-Entry:**
   - Login as `controller1@eventflow.dev` → select assigned event → verify camera permission/fallback UI + manual/USB-HID code entry → test:
     - Fresh ticket → `ВХОД РАЗРЕШЁН (ACCEPTED)` + participant name + category + server time + Organizer chart/counters increment live.
     - Same ticket again → `УЖЕ ИСПОЛЬЗОВАН (ALREADY_USED)` with exact original `used_at` (counters do not increase).
     - Old cancelled ticket → `ОТМЕНЁН (CANCELLED)`.
     - Ticket from another event → `ДРУГОЕ СОБЫТИЕ (WRONG_EVENT)` (no PII).
     - Corrupted code → `НЕВЕРНЫЙ КОД (INVALID)` (no PII).
     - Closed admission window → `ОКНО ДОПУСКА ЗАКРЫТО (CLOSED)`.
     - Organizer revokes `controller1` → `controller1` immediately sees revocation / receives clear `403` refusal (NOT "no network"!).
     - Stop server / offline → shows `РЕЗУЛЬТАТ УТОЧНЯЕТСЯ (UNCERTAIN)` + offline banner; cached catalog/tickets remain readable; restart server → retry with same `request_id` succeeds idempotently without creating a second `entries` row.
5. **Flow 5 — Responsive & Keyboard Audit (`360x800` & `1280x800`):**
   - Verify every screen at `360px` (bottom `NavigationBar`, single-column cards, zero horizontal scroll, `>= 48x48` tap targets) and `1280px` (left `NavigationRail`, split panels, `DataTable`s, full Tab/Enter keyboard navigation).
   - Capture and commit screenshots to `docs/screenshots/` and embed/link them in `docs/TESTS.md`.

---

## 5. Non-Negotiable Constraints to Carry Into the Master Prompt

1. **One Flutter/Dart codebase** for Android, Web, and Windows — zero separate HTML/JS/React frontends.
2. **Do not weaken any backend invariant**: keep `SELECT ... FOR UPDATE`, `UNIQUE(ticket_id)` on `entries`, `uq_active_ticket_per_user_event`, server UTC `NOW()`, and `pytest` + `verify_race.py` + `run_t01_t16.py` 100% green.
3. **Russian UI everywhere** (including month names, statuses, audit log labels, error messages, empty states); **English code, identifiers, and comments**.
4. **No raw hex colors outside `app/lib/design/tokens.dart`**, no emojis in UI chrome, no AI purple/neon aesthetic, no `Inter` font.
5. **No secrets in git** (`.env` stays gitignored; `.env.example` holds placeholders only).
6. **Verify every claim with real execution**: run `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`, `flutter build web --release`, `pytest`, `verify_race.py`, `run_t01_t16.py`, and live browser E2E walkthrough before marking done. Commit and push to `https://github.com/sciomhs/eventflow-practice-05` after each milestone.

---

## 6. Recommended Structure for Fable 5.2's Master Prompt

When Fable 5.2 drafts the Master Prompt from this handoff, organize execution into **5 tight, verifiable milestones**:
- **M1 — Core UX & Localization Foundation:** Russian `intl` date formatting, `tokens.dart` + skeleton loaders + localized status/action mappers, `AuthStore` port `8085` health check & offline read-only cache, Web `index.html` branding & camera setup, read-only Catalog access for Organizer/Controller.
- **M2 — Auth & Participant Editorial Redesign:** Split-screen editorial `AuthScreen` with collapsible demo drawer; upgraded `ParticipantCatalogScreen` (live debounced search, capacity bars, date badges, 2-col desktop grid, offline cache banner); upgraded `EventDetailScreen` (SSE live seat updates, smart default available category, role-safe loading, inline copy/cancel) & `MyTicketsScreen` (premium perforated ticket pass).
- **M3 — Organizer Control Room Overhaul:** Full 5-section desktop sidebar (`Обзор`, `Мероприятия`, `Участники`, `Контролёры`, `Журнал`); complete Create + Edit `EventEditorScreen` with date/time pickers, timezone selector, dynamic categories, and post-registration lock rules; hourly check-in bar chart (`timeline`); category + status + search filters; desktop `DataTable` views; proper error surfacing.
- **M4 — Controller Scanner Hardening:** Fix `403`/`409` vs network `UNCERTAIN` distinction; SSE `controller.revoked` live handling; `MobileScanner` `errorBuilder`; USB-HID `FocusNode` auto-refocus; clear 7-status full-width result cards with server timestamps; localized journal.
- **M5 — Live E2E Verification, Visual QA & Final Gate:** Execute all 5 E2E flows in Chrome against live FastAPI (`8085`) + Postgres 16; capture `360px` & `1280px` screenshots into `docs/screenshots/`; update `docs/TESTS.md`, `README.md`, `GOAL_LOG.md`; re-run all backend & Flutter gates; attempt `flutter build apk` if Android `cmdline-tools` are installed; commit, tag, and push to `sciomhs/eventflow-practice-05`.
