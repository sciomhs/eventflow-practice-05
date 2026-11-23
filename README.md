# EventFlow Practice 05

Единая кроссплатформенная платформа мероприятий (**Android / Web / Windows**) на **Flutter/Dart** с общим сервером **FastAPI + PostgreSQL 16** и синхронизацией в реальном времени через **SSE**.

## Архитектура и ключевые гарантии
- **Единый Flutter-клиент** (`app/`): три роли (`participant`, `organizer`, `controller`) в одном приложении, адаптивный интерфейс (`360 px` и `1280 px`), дизайн-система Stitch в `app/lib/design/tokens.dart`.
- **Единая серверная БД** (`backend/db/`): PostgreSQL 16 в Docker, все бизнес-правила, роли, владение, лимиты и время (`NOW()` UTC) контролируются сервером.
- **Атомарность и идемпотентность**: блокировки `SELECT ... FOR UPDATE` в едином порядке, `UNIQUE(ticket_id)` в `entries`, частичный уникальный индекс `uq_active_ticket_per_user_event`, ключи идемпотентности `request_id`.
- **Синхронизация ≤ 3 с**: `GET /api/v1/stream` (SSE) с публикацией событий строго после `COMMIT` и авто-переподключением на клиенте.

## Стек и версии
- **Backend**: Python 3.14, FastAPI, Uvicorn, `asyncpg`, `sse-starlette`, PostgreSQL 16 (`postgres:16-alpine`)
- **Frontend**: Flutter / Dart (устанавливается в G0; точные версии фиксируются в `docs/ENVIRONMENT.md`)

## Быстрый старт

### 1. Конфигурация (без секретов в репозитории)
Скопируйте `.env.example` в `.env` (файл `.env` добавлен в `.gitignore`):
```bash
cp .env.example .env
```

### 2. База данных и миграции
```bash
docker compose -f docker/docker-compose.yml up -d
backend/.venv/bin/python backend/db/migrate.py
backend/.venv/bin/python backend/db/seed_demo.py
```

### 3. Сервер API + SSE
```bash
backend/.venv/bin/uvicorn backend.app.main:app --host 0.0.0.0 --port 8085
```
Проверка: `curl http://127.0.0.1:8085/health`

### 4. Flutter-приложение
Укажите адрес сервера на экране входа (значок сервера в правом верхнем углу):
- Web / Windows (локально): `http://localhost:8085`
- Android-эмулятор: `http://10.0.2.2:8085`
- Реальное устройство: `http://<IP-вашего-ПК>:8085`

```bash
cd app
flutter pub get
flutter run -d chrome      # Web
flutter run -d <android>   # Android
flutter run -d windows     # Windows (на хосте Windows)
```

## Демо-аккаунты (только для разработки)
Пароль для всех dev-аккаунтов: `EventFlow2026!`

| Роль | Email |
|---|---|
| Участник 1 | `participant1@eventflow.dev` |
| Участник 2 | `participant2@eventflow.dev` |
| Организатор | `organizer@eventflow.dev` |
| Контролёр 1 | `controller1@eventflow.dev` |
| Контролёр 2 | `controller2@eventflow.dev` |

## Повторный запуск тестов (T01–T16)
```bash
# Модульные и интеграционные тесты гонок (pytest)
backend/.venv/bin/pytest backend/tests/test_api_and_races.py -v

# Проверка гонки 10 параллельных сканов
backend/.venv/bin/python backend/scripts/verify_race.py

# Полный прогон T01–T15 против запущенного сервера
EVENTFLOW_URL=http://127.0.0.1:8000 backend/.venv/bin/python backend/scripts/run_t01_t16.py
```
Подробные протоколы всех 16 тестов см. в [docs/TESTS.md](docs/TESTS.md).

## Сценарий демонстрации (10–12 минут, стр. 18 спецификации)
1. **Организатор (Windows / 1280 px)**: входит под `organizer@eventflow.dev`, открывает *TECH FORUM 2026* (или публикует черновик), проверяет назначение двух контролёров (`controller1`, `controller2`) и открывает вкладку «Обзор» со статистикой.
2. **Участник (Android / 360 px)**: входит под `participant2@eventflow.dev`, фильтрует каталог, выбирает категорию «Стандарт» и регистрируется — получает QR-билет `EF-...` и полный код `EF1:...`. На экране организатора счётчики обновляются по SSE без перезагрузки (≤ 3 с).
3. **Контролёр (Web)**: входит под `controller1@eventflow.dev`, сканирует или вводит код билета → статус `ВХОД РАЗРЕШЁН (ACCEPTED)`, время серверное.
4. **Два одновременных скана**: в двух независимых сессиях (`controller1` и `controller2`) отправляется один свежий билет → один получает `ACCEPTED`, второй `ALREADY_USED` с временем первого входа; в таблице `entries` ровно 1 запись.
5. **Последнее место (T03)**: на событии *AI Summit: Последнее место* (1 свободное место) два участника отправляют регистрацию одновременно → один получает `ISSUED`, второй `SOLD_OUT`.
6. **Отмена и запрещённый запрос (T05, T01, T15)**: участник отменяет `ISSUED` билет (место возвращается), попытка входа по старому QR даёт `CANCELLED`; прямой запрос чужого билета или отозванным контролёром возвращает `403`.
7. **Таймаут и переподключение (T14)**: при потере связи клиент показывает баннер переподключения, повтор того же `request_id` возвращает сохранённый результат без нового входа, после восстановления связи данные синхронизируются.

## Артефакты сборки
См. [docs/ENVIRONMENT.md](docs/ENVIRONMENT.md) и раздел сборок после завершения G12.
