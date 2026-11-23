# Environment Notes — EventFlow Practice 05

Recorded during **G0** on macOS (`darwin-arm64`, macOS 26.5.2).

## 1. Toolchain Versions
- **Flutter**: `3.50.1` (channel `stable`, installed via `brew install --cask flutter`)
- **Dart**: `3.14.0`
- **Python**: `3.14.7` (`backend/.venv` with FastAPI, Uvicorn, `asyncpg`, `sse-starlette`, `pytest`)
- **Node.js**: `v26.0.0`
- **Docker**: `29.1.3`, Docker Compose `v2.40.3-desktop.1`
- **PostgreSQL**: `16.11` (`postgres:16-alpine` via `docker/docker-compose.yml`)
- **Git**: `2.50.1`
- **GitHub CLI (`gh`)**: authenticated as `sciomhs`

## 2. `flutter doctor` Summary & Platform Notes
- `[✓]` **Flutter** (`3.50.1`)
- `[✓]` **Chrome** — Web build (`flutter build web --release`) verified on this host.
- `[✓]` **Xcode** (`26.5`) — iOS/macOS toolchain available.
- `[✗]` **Android toolchain** — `cmdline-tools` / Android SDK not installed on this macOS host (`flutter build apk` requires Android SDK + `cmdline-tools` + accepted licenses).
- **Windows desktop** — `windows/` runner is scaffolded in `app/windows/`, and `flutter build windows` must be executed on a Windows 10/11 host with Visual Studio (*Desktop development with C++* workload).

## 3. Antigravity Skills & Marketplace
- **Stitch Design Skills**: Cloned from `https://github.com/google-labs-code/stitch-skills` into `skills/stitch-skills/`. Applied `taste-design/SKILL.md` to produce `docs/DESIGN.md` and `app/lib/design/tokens.dart`.
- **Marketplace Check**: `antigravity-plugins-official/plugin/flutter` (Dart and Flutter) and `antigravity-plugins-partners/plugin/supabase` (Postgres best practices) identified in catalog; not auto-installed per workspace policy.

## 4. Database Verification
- `docker compose -f docker/docker-compose.yml up -d` starts `eventflow_postgres` on port `5432`.
- Confirmed `asyncpg` connection from Python (`PG CONNECTED: PostgreSQL 16.11 on aarch64-unknown-linux-musl`).
