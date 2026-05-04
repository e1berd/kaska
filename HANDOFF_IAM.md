# HardHat — Handoff: IAM готов, что дальше

Документ для следующего агента. Кратко: что сделано, как запускать,
куда смотреть в коде, что осталось/подводные камни.

## Что за проект

**HardHat** (рус. «Каска») — open-source трекер задач, идейно близкий к Jira / Asana, но с открытой моделью:

- **Чтение публичное.** Любой гость без логина видит проекты, доски, задачи, обсуждения.
- **Запись только для авторизованных.** Создание/редактирование задач — после регистрации.
- **1 проект = 1 канбан-доска.** Колонки = статусы задач, кастомизируются (CRUD).
- **DnD карточек между колонками** синхронизируется в realtime у всех на доске, **включая неавторизованных гостей**.
- **Админка отложена.** Поле `role :user|:admin` уже на схеме, но UI/middleware вокруг неё пока не делаем.

Архитектурные принципы (зафиксированы пользователем, не отступать без согласования):

- **Транспорт API — только Phoenix Channels.** REST в Phoenix-роутере не появляется. Исключения — `/health` и (если когда-нибудь) static assets. IAM (register/login/verify/reset) уже идёт через канал `auth:lobby`. Ссылки из писем ведут на SPA-роуты, SPA сама шлёт сообщение в socket.
- **Гость всегда подключается к сокету** (анонимный connect), мутирующие сообщения отвечают `{:error, :unauthorized}`.
- **Стек жёстко зафиксирован:**
  - Backend: Elixir, Phoenix 1.8, Guardian + guardian_db, Postgres 17, Swoosh.
  - Frontend: pnpm + Vite + Vue 3 + Vuetify 4 (без Nuxt), Pinia, клиент `phoenix`.
  - DnD: `@atlaskit/pragmatic-drag-and-drop` (механика) + `anime.js` v4 (анимация).
  - Запуск: docker-compose + dotenv (postgres + mailpit в dev).

### UI — Material Design 3 строго

UI делается на **Vuetify 4, но строго в духе Material Design 3 последней версии**, максимально близко к гайдлайну. Это не «вдохновлено M3», а целенаправленный M3 поверх Vuetify.

- **Молча можно:** править CSS-переменные / theme-токены под M3 (цвета, радиусы, типографика, state-layer opacity), добавлять отсутствующие в Vuetify M3-паттерны точечными кастомными компонентами (FAB-варианты, segmented buttons, navigation rail, container transform), брать M3 motion tokens (emphasized easing + длительности).
- **Без согласования нельзя:** ломать архитектуру компонентов Vuetify, переписывать ядро темы, подменять Vuetify сторонними M3-библиотеками. **Не предлагать Google `material-web`** — пользователь сказал, он фактически не поддерживается.

### Анимации — CSS first, anime.js точечно

Большую часть M3 motion делать через CSS-переменные + CSS transitions / Web Animations API. `anime.js` v4 — только под сложную хореографию (container transform, FLIP при DnD-drop, staggered timeline на эмпашиз-кривой). На карточках большой доски анимировать только `transform`/`opacity`, длительности и easing — из M3 motion tokens, хранить в одном CSS-файле как переменные.

**Why:** anime.js на сотнях карточек бьёт по перфу, CSS-композитор почти бесплатен.

### DnD — НЕ использовать vuedraggable / Sortable.js

Для любого DnD/sortable/reorder UI — только Pragmatic DnD + anime.js. `vuedraggable`, `sortablejs`, `vue.draggable.next` и обёртки над Sortable.js пользователь явно отверг. Если Pragmatic DnD не покрывает кейс — сначала уточнить, не подсовывать Sortable как компромисс.

## TL;DR

- Backend: Phoenix 1.8 (Bandit), Postgres 17, Guardian + Guardian.DB.
- Транспорт: всё IAM-API ходит через **Phoenix Channels**, HTTP-роутер несёт только `/health` и dev-mailbox. Это сознательно (см. `api/lib/hardhat_web/router.ex:5`).
- Frontend: Vue 3 + Pinia + Vuetify 4, клиент `phoenix` через `Socket`. Vite на `5173`.
- Почта в dev: Swoosh → Mailpit (`http://localhost:8025`). Письма верификации/сброса доходят и парсятся smoke-тестом.
- Прогон: `pnpm --dir web smoke:iam` — end-to-end путь register → verify → login → me → forgot → reset → login.

## Запуск с нуля

```bash
docker compose up
# первый раз контейнер api сам выполнит mix deps.get + ecto.create + ecto.migrate
# web: http://localhost:5173
# api: http://localhost:4000/health
# mailpit UI: http://localhost:8025
```

`.env` лежит в репо (dev-секреты не настоящие). Все сервисы читают переменные оттуда через `docker-compose.yml`.

Smoke-тест IAM (после того как контейнеры подняты и здоровы):

```bash
pnpm --dir web smoke:iam
```

## Архитектура IAM

### Каналы

Сокет-роут: `/socket` (`api/lib/hardhat_web/endpoint.ex:14`).

`UserSocket` (`api/lib/hardhat_web/channels/user_socket.ex`):
- `connect` без `token` — анонимное подключение, `current_user = nil` (для register/login/forgot).
- `connect` с `token` — Guardian верифицирует JWT, кладёт `current_user` в `socket.assigns`.

Топики:
- `auth:lobby` → `HardhatWeb.AuthChannel` — все unauthed-флоу.
- `user:<id>` → `HardhatWeb.UserChannel` — только для соответствующего юзера, остальным `error: "forbidden"`.

### `auth:lobby` события (`api/lib/hardhat_web/channels/auth_channel.ex`)

| event | payload | ok-reply | error |
|---|---|---|---|
| `register` | `{email, password}` | `{message, user}` (письмо верификации шлётся) | `{errors: <changeset>}` |
| `login` | `{email, password}` | `{access, refresh, user}` | `{message, code?}` (`email_not_verified` если не подтверждён) |
| `verify_email` | `{token}` | `{message, user}` | `{message: "invalid or expired token"}` |
| `forgot_password` | `{email}` | `{message}` (всегда одинаковый, антиэнумерация) | — |
| `reset_password` | `{token, password}` | `{message}` | `{message: "invalid or expired token"}` |
| `refresh` | `{refresh}` | `{access, refresh, user}` (старый refresh ревокается) | `{message: "invalid refresh token"}` |

Access TTL — 15 минут, refresh — 30 дней.

### `user:<id>` события (`api/lib/hardhat_web/channels/user_channel.ex`)

| event | reply |
|---|---|
| `me` | `{id, email, role, confirmed_at}` |

Join возвращает того же юзера сразу.

### Данные

Миграции (`api/priv/repo/migrations/`):
- `20260504030000_create_users_auth.exs` — `users` (binary_id, citext email, role enum) + `users_tokens` (verify/reset, hash-токены).
- `20260504030100_create_guardian_tokens.exs` — `guardian_tokens` для Guardian.DB (только refresh, см. `config/config.exs:36`).

Схемы:
- `Hardhat.Accounts.User` — bcrypt, `role :user|:admin`, валидации почты/пароля (8..72).
- `Hardhat.Accounts.UserToken` — sha256-hash plaintext-токена в БД, plaintext летит в письмо (стандартный Phoenix-паттерн).

### Auth-стек

- Guardian (`api/lib/hardhat/guardian.ex`) — HS512, `subject_for_token`/`resource_from_claims` через UUID.
- Guardian.DB sweeper в supervisor tree (`api/lib/hardhat/application.ex:15`), `sweep_interval: 60`.
- Refresh-токены персистятся, access — стейтлесс. На `refresh` старый токен явно ревокается.

### Mailer

- `Hardhat.Mailer` (`Swoosh`).
- В dev `runtime.exs` переключает адаптер на SMTP к `MAIL_HOST` (mailpit).
- `UserNotifier` шлёт текстовые письма на русском с ссылками вида `WEB_BASE_URL/verify/<token>` и `/reset/<token>`.

## Frontend (актуальное состояние)

`web/src/`:
- `stores/socket.ts` — обёртка над `phoenix.Socket`, `joinChannel(topic)`, `pushAsync(channel, event, payload)`.
- `stores/auth.ts` — Pinia store: `register/login/verifyEmail/forgotPassword/resetPassword/refreshTokens/fetchMe/logout`. Токены и user в `localStorage`. После login сокет ре-коннектится с `token` параметром.
- `router/index.ts` — маршруты под все флоу + `meta.requiresAuth` гард.
- `views/` — `Home/Login/Register/Verify/Forgot/Reset/Me/NotFound`. Это пока минимум, не финальный UX.

Стек договорённости (важны для правок UI):
- DnD только Pragmatic DnD + anime.js, **не** vuedraggable / Sortable.
- M3 поверх Vuetify — мелкие правки молча, кардинальные — уточнять.
- Анимации — CSS first, anime.js точечно для сложной хореографии.

## Что было пофикшено в инфре (для контекста)

- Web port: `WEB_PORT=5173` в `.env`, vite слушает 5173, compose маппит 5173:5173.
- mint в `mix.lock` — устаревшая запись (deps/mint лежит как кэш). На запуск **не влияет** в офлайне, потому что mix берёт из `_build`/`deps`, но при `mix deps.get` с интернетом упадёт. Если будешь дёргать deps.get — сделай сначала `mix deps.unlock mint`.
- Postgres healthcheck (`docker-compose.yml:16`) шумит `FATAL: database "hardhat" does not exist`, потому что `pg_isready -U hardhat` идёт в БД с именем юзера, а у нас `hardhat_dev`. Healthcheck всё равно проходит. Косметика, чинится добавлением `-d $${POSTGRES_DB}`.
- DNS внутри контейнера api — была проблема с `nxdomain repo.hex.pm`. Если повторится — добавить в сервис `api` секцию `dns: [1.1.1.1, 8.8.8.8]`.

## Что осталось / следующие шаги

Backend:
- Тестов на `AuthChannel`/`UserChannel` сейчас нет (`api/test/` почти пустой). Покрыть happy path и негативы (неверный пароль, неподтверждённая почта, истёкший токен, чужой `user:<id>`).
- Rate limiting на `register`/`login`/`forgot_password` (например, hammer + per-IP/per-email).
- Решить про logout: сейчас на бэке нет события `logout` — клиент просто чистит localStorage. Если нужна явная ревокация refresh, добавить `auth:lobby` → `logout`.
- Решить про **rotation reuse detection** для refresh-токенов (если refresh используется дважды — отозвать всю цепочку юзера).
- Политика confirmed_at: сейчас login блокируется если `confirmed_at == nil`. Подтвердить, что это требуется для всех ролей, в т.ч. seed-админов.
- `seeds.exs` пустой — добавить дефолтного админа для дев-окружения.

Frontend:
- Views — каркас, нужен дизайн под M3. На login обработать `code: "email_not_verified"` явно (предложить переотправить письмо — для этого нужен ивент на бэке).
- Авто-refresh access-токена при его истечении (сейчас `refreshTokens` есть, но никто его автоматически не дёргает).
- Глобальный `bootstrap()` сокета на старте приложения (`auth.ts:116` есть, но вызов из `main.ts` стоит проверить).
- Тосты/ошибки — единый формат отображения ошибок канала.

DevEx:
- Прибрать mint из mix.lock и deps (когда будет интернет в контейнере).
- Поправить healthcheck postgres (косметика).
- Подумать про `mix precommit` в CI.

## Полезные пути

- API entrypoint: `api/lib/hardhat/application.ex`
- Endpoint: `api/lib/hardhat_web/endpoint.ex`
- Router (только health): `api/lib/hardhat_web/router.ex`
- Channels: `api/lib/hardhat_web/channels/`
- Accounts context: `api/lib/hardhat/accounts.ex`
- Guardian: `api/lib/hardhat/guardian.ex`
- Migrations: `api/priv/repo/migrations/`
- Конфиг: `api/config/{config,dev,runtime}.exs`
- Frontend stores: `web/src/stores/{auth,socket}.ts`
- Smoke: `web/scripts/smoke_iam.mjs`
- AGENTS.md (правила Phoenix/Ecto): `api/AGENTS.md`
