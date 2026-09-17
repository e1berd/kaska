# AGENTS.md

Точка входа для AI-агентов (и людей), работающих с репозиторием **Kaska**.

## Правила — в CLAUDE.md

Все обязательные правила проекта живут в [`CLAUDE.md`](./CLAUDE.md) и **важнее
общих привычек**. Коротко, что там:

1. **Никаких комментариев** в `.ts/.tsx/.vue/.ex/.exs` — код самодокументируемый.
2. **Material Design 3** строго по спеке: токены `--md-*`, Vuetify-роли
   `rgb(var(--v-theme-*))`, без хардкода палитры. Tailwind — только раскладка.
3. Прочие нормы: dnd только `@atlaskit/pragmatic-drag-and-drop`; приватность по
   участию; всё API веб-фронта — Phoenix Channels (REST `/api/v1` — только
   внутренний канал раннера агентов); `noUnusedLocals/Parameters` включены.
4. Где что лежит.
5. **Агенты Kaska** — серверные прогоны в контейнерах, без внешних токенов.

Доп. правила бэкенда (Phoenix v1.8) — в [`app/AGENTS.md`](./app/AGENTS.md).

## Структура репозитория

- `app/` — бэкенд: Phoenix v1.8, Ecto, Guardian, Phoenix Channels.
- `web/` — фронт: Vue 3 `<script setup>` + TS, Vite, Pinia, Vuetify 4, tiptap. pnpm.
- `agent-supervisor/` — Deno-сервис, запускает контейнеры прогонов агентов.
- `agent-runtime/` — образ раннера: один контейнер = один прогон агента на задаче.
- `landing/` — лендинг.
- `caddy/` — реверс-прокси (`Caddyfile`).

## Проверки перед сдачей

- Бэкенд: `cd app && mix precommit` (формат, тесты, `--warnings-as-errors`).
- Фронт: `cd web && npx vue-tsc -p tsconfig.app.json --pretty false`.
- Агенты: `deno task check && deno task test` в `agent-supervisor/` и `agent-runtime/`.
