# Kaska

Kaska — open source трекер задач с realtime-обновлениями на Phoenix Channels.

## Что это

Kaska — kanban/board-система с публичным чтением и авторизованной записью:
- любой посетитель может смотреть проекты, доски и задачи;
- писать/редактировать могут только авторизованные пользователи;
- все изменения синхронизируются в реальном времени через Phoenix Channels.

## Стек

- Backend: Elixir, Phoenix, Ecto, Guardian (JWT), Phoenix Channels
- Frontend: Vue 3, TypeScript, Pinia, Vue Router, Vuetify 4
- БД: PostgreSQL
- Object storage: S3-совместимое хранилище (RustFS)
- Почта (dev): Swoosh local mailbox preview на `/mailbox`. Prod — SMTP через env (`MAIL_HOST`, `MAIL_USERNAME`, `MAIL_PASSWORD`, `MAIL_PORT`, `MAIL_SSL`, `MAIL_FROM_ADDRESS`, `MAIL_FROM_NAME`).

## Быстрый старт (dev)

### 1. Поднять инфраструктуру

```bash
docker compose up -d
```

### 2. Backend

```bash
cd api
mix deps.get
mix ecto.setup
mix phx.server
```

Backend по умолчанию: `http://localhost:4000`.

### 3. Frontend

```bash
cd web
pnpm install
pnpm dev
```

Frontend по умолчанию: `http://localhost:5173`.

## Модель доступа

- Public read / Auth write.
- Гость может читать данные.
- Любые мутации требуют авторизации.

## Роли

Поддерживаются роли:
- `user`
- `admin`
- `superadmin`

### Bootstrap первого пользователя

Если в системе ещё нет пользователей, первый зарегистрированный пользователь:
- автоматически получает роль `superadmin`;
- автоматически считается подтверждённым (без email-подтверждения).

## Приглашения

Создание приглашений доступно `admin` и `superadmin`.

## CLI: повышение роли пользователя

Добавлен mix task для изменения роли по email.

Примеры:

```bash
cd api
mix users.promotion --email user@example.com --rank superadmin
```

или в формате `key:value`:

```bash
cd api
mix users.promotion email:user@example.com rank:admin
```

Допустимые значения `rank`:
- `user`
- `admin`
- `superadmin`

### Запуск внутри Docker-контейнера

```bash
docker exec <container_id> mix users.promotion --email user@example.com --rank superadmin
```

## Структура репозитория

```text
kaska/
├── app/   # Phoenix backend
├── web/   # Vue frontend
└── docker-compose.yml
```

## Лицензия

Проект распространяется под лицензией MIT. См. файл [LICENSE](./LICENSE).
