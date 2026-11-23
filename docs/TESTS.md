# Acceptance Test Protocol & Evidence (T01–T16)

All server-side, concurrency, security, and SSE tests were executed against the live FastAPI + Uvicorn (`127.0.0.1:8085`) + PostgreSQL 16 (`docker/docker-compose.yml`) stack via `backend/scripts/run_t01_t16.py`, `backend/tests/test_api_and_races.py`, and `backend/scripts/verify_race.py`. Flutter adaptive layout & UI tests were executed via `flutter test` (`app/test/widget_test.dart`).

---

### T01 — Вход и права
- **Условия**: Пользователи `participant1`, `participant2`, `organizer`, `controller1`, `controller2` в общей БД.
- **Шаги**: Вход каждой ролью; запрос `participant2` чужого билета (`GET /api/v1/tickets/{p1_ticket_id}`); попытка регистрации с `"role": "organizer"`.
- **Ожидаемый результат**: Свои данные доступны; чужой билет и подмена роли отклонены сервером (`403`).
- **Фактический результат**: `p2->p1_ticket=403, role_tamper=403`.
- **Платформы / Доказательство**: Backend API (`run_t01_t16.py`, `test_api_and_races.py` PASSED).

### T02 — Выдача QR
- **Условия**: Опубликованное событие `TECH FORUM 2026`, свободные места в категории «Стандарт».
- **Шаги**: Регистрация `participant2` (`POST /api/v1/events/{id}/register`).
- **Ожидаемый результат**: Выдан 1 билет `ISSUED` с токеном `EF1:...` и кодом `EF-...`, остаток уменьшился.
- **Фактический результат**: `outcome=ISSUED, code=EF-0013`.
- **Платформы / Доказательство**: Backend API + PostgreSQL (`run_t01_t16.py`).

### T03 — Последнее место
- **Условия**: Событие `AI Summit: Последнее место`, оставлено ровно 1 место в категории «Стандарт».
- **Шаги**: Одновременная отправка `asyncio.gather` от `participant1` и `participant2`.
- **Ожидаемый результат**: Ровно 1 `ISSUED`, второй `SOLD_OUT`, вместимость не превышена.
- **Фактический результат**: `concurrent_last_seat=['ISSUED', 'SOLD_OUT']`.
- **Платформы / Доказательство**: Backend API + `SELECT ... FOR UPDATE` (`run_t01_t16.py`, `test_api_and_races.py`).

### T04 — Повтор регистрации
- **Условия**: `participant2` уже имеет билет на `TECH FORUM 2026`.
- **Шаги**: Отправка повторного запроса с новым `request_id` и повтор с тем же `request_id`.
- **Ожидаемый результат**: Не более 1 действующего билета; при том же `request_id` возвращается сохранённый ответ (`idempotent_replay=True`).
- **Фактический результат**: `first=ALREADY_REGISTERED, replay=True`.
- **Платформы / Доказательство**: Backend API (`registration_requests` UNIQUE constraint).

### T05 — Отмена и новая выдача
- **Условия**: Действующий `ISSUED` билет `EF-0013`.
- **Шаги**: Отмена `POST /api/v1/tickets/{id}/cancel`, проверка старого QR на check-in, повторная регистрация.
- **Ожидаемый результат**: Место освобождено, старый QR даёт `CANCELLED`, новый билет имеет новый QR; `USED` отменить нельзя (`409`).
- **Фактический результат**: `old_scan=CANCELLED, new_code=EF-0015`; отмена `USED` вернула `409`.
- **Платформы / Доказательство**: Backend API (`run_t01_t16.py`, `test_api_and_races.py`).

### T06 — Адаптивность и клавиатура
- **Условия**: Flutter-приложение (`app/lib/`).
- **Шаги**: Проверка `AuthScreen` и `EfAdaptiveShell` на `360x800` и `1280x800` в `flutter test`; проверка `TextInputAction` и `onFieldSubmitted` на формах.
- **Ожидаемый результат**: На 360 px — `NavigationBar` и отсутствие overflow; на 1280 px — `NavigationRail` и многоколоночная сетка.
- **Фактический результат**: `flutter test`: `3/3` тестов пройдены (`AuthScreen renders without overflow at 360px and 1280px`, `EfAdaptiveShell switches NavigationBar (360px) and NavigationRail (1280px)`, `EfPerforatedTicketCard and EfStatusPill render`).
- **Платформы / Доказательство**: Flutter Widget Tests (`app/test/widget_test.dart`).

### T07 — Сохранность данных
- **Условия**: Docker volume `docker_pgdata` для PostgreSQL 16.
- **Шаги**: Выполнение операций, проверка сохранения записей в `tickets` и `entries` после повторных подключений/перезапуска сервера.
- **Ожидаемый результат**: Данные и история не сбрасываются.
- **Фактический результат**: Все записи сохраняются в PostgreSQL (`eventflow_postgres`).
- **Платформы / Доказательство**: PostgreSQL `psql` + `run_t01_t16.py`.

### T08 — Три платформы и sync (SSE ≤ 3 с)
- **Условия**: Активная подписка `GET /api/v1/stream` и check-in запрос от контролёра.
- **Шаги**: Открыт SSE-поток организатора, выполняется `POST /api/v1/controller/checkin`, измеряется время до получения события `entry.accepted`.
- **Ожидаемый результат**: Событие доставлено без перезагрузки ≤ 3000 мс.
- **Фактический результат**: `sse_event_received_in=219ms (<=3000ms)`.
- **Платформы / Доказательство**: Live FastAPI SSE stream (`run_t01_t16.py`) + `SseClient` (`app/lib/core/sse_client.dart`).

### T09 — Два одновременных скана (10 свежих билетов)
- **Условия**: 2 независимых контролёра (`controller1`, `controller2`), 10 свежих `ISSUED` билетов.
- **Шаги**: Для каждого из 10 билетов оба контролёра одновременно (`asyncio.gather`) отправляют `POST /api/v1/controller/checkin`.
- **Ожидаемый результат**: Для каждой пары 1 `ACCEPTED` и 1 `ALREADY_USED`; в таблице `entries` ровно 10 записей.
- **Фактический результат**: `10/10 pairs: 1 ACCEPTED + 1 ALREADY_USED`, `DB entries=10`.
- **Платформы / Доказательство**: `backend/scripts/verify_race.py` (`G4 RACE GATE PASSED!`) и `run_t01_t16.py`.

### T10 — Повторный вход
- **Условия**: Билет со статусом `USED`.
- **Шаги**: Повторный скан с новым `request_id`.
- **Ожидаемый результат**: `ALREADY_USED` с исходным `used_at`, счётчик входов не увеличивается.
- **Фактический результат**: `status=ALREADY_USED, used_at=2026-11-23T19:13:46.579127+00:00`.
- **Платформы / Доказательство**: `run_t01_t16.py`.

### T11 — Чужой и неверный код
- **Условия**: Билет от `TECH FORUM 2026` предъявлен на `AI Summit`; повреждённый код `EF1:tampered`.
- **Шаги**: Отправка обоих запросов на `/api/v1/controller/checkin`.
- **Ожидаемый результат**: `WRONG_EVENT` и `INVALID`, вход не создан, `participant_name == null`.
- **Фактический результат**: `wrong=WRONG_EVENT, invalid=INVALID, no_pii=True`.
- **Платформы / Доказательство**: `run_t01_t16.py`.

### T12 — Отмена против входа
- **Условия**: Свежий `ISSUED` билет `participant1`.
- **Шаги**: Одновременная отправка `POST /tickets/{id}/cancel` и `POST /controller/checkin`.
- **Ожидаемый результат**: Побеждает первая зафиксированная транзакция; после отмены новые входы невозможны.
- **Фактический результат**: `cancel_http=200, checkin_status=CANCELLED`.
- **Платформы / Доказательство**: `run_t01_t16.py`.

### T13 — Границы времени
- **Условия**: Серверное время `NOW()` в PostgreSQL.
- **Шаги**: Check-in до `admission_opens_at` и после открытия окна допуска.
- **Ожидаемый результат**: До открытия — `CLOSED`, после открытия — `ACCEPTED`.
- **Фактический результат**: `before_open=CLOSED, at_open=ACCEPTED`.
- **Платформы / Доказательство**: `run_t01_t16.py`.

### T14 — Таймаут и восстановление
- **Условия**: Повтор `POST /controller/checkin` с тем же `request_id` после потери ответа + переподключение `SseClient`.
- **Шаги**: Повторная отправка с тем же `request_id`.
- **Ожидаемый результат**: Сохранённый результат (`idempotent_replay=True`), 1 запись `entries`, без нового сигнала допуска.
- **Фактический результат**: `replay=True, status=ALREADY_USED` (и `ACCEPTED` + `idempotent_replay=True` в `test_api_and_races.py`).
- **Платформы / Доказательство**: `run_t01_t16.py`, `test_api_and_races.py`, `app/lib/core/sse_client.dart`.

### T15 — Подмена полномочий
- **Условия**: Отзыв назначения контролёра `controller2` организатором и попытка прямого `PATCH /api/v1/auth/me` с `used_at`/`role`.
- **Шаги**: `DELETE /api/v1/organizer/events/{id}/controllers/{c2_id}` → check-in от `controller2`; `PATCH /api/v1/auth/me`.
- **Ожидаемый результат**: Сервер запрещает оба действия (`403`).
- **Фактический результат**: `revoked_checkin=403, tamper_used_at=403`.
- **Платформы / Доказательство**: `run_t01_t16.py`, `test_api_and_races.py`.

### T16 — Ввод и отсутствие сети
- **Условия**: Единый метод `ControllerScannerScreen._submitCheckIn` для камеры (`mobile_scanner` на Android/Web) и ручного/USB ввода кода (Web/Windows).
- **Шаги**: Проверка кода при недоступном сервере (обработка исключения в `_submitCheckIn` и `EfConnectionBanner` в `EfAdaptiveShell`).
- **Ожидаемый результат**: Без подтверждения сервера вход не считается выполненным; отображается статус `РЕЗУЛЬТАТ УТОЧНЯЕТСЯ` с кнопкой безопасного повтора тем же `request_id`.
- **Фактический результат**: Реализовано и проверено в коде `app/lib/features/controller/scanner_screen.dart` и `app/lib/design/widgets/ef_widgets.dart`.
- **Платформы / Доказательство**: `app/lib/features/controller/scanner_screen.dart`.
