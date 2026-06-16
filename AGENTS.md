# AGENTS.md

Точка входа для AI-агентов (и людей), работающих с репозиторием **Kaska**.

## Правила — в CLAUDE.md

Все обязательные правила проекта живут в [`CLAUDE.md`](./CLAUDE.md) и **важнее
общих привычек**. Коротко, что там:

1. **Никаких комментариев** в `.ts/.tsx/.vue/.ex/.exs` — код самодокументируемый.
2. **Material Design 3** строго по спеке: токены `--md-*`, Vuetify-роли
   `rgb(var(--v-theme-*))`, без хардкода палитры. Tailwind — только раскладка.
3. Прочие нормы: dnd только `@atlaskit/pragmatic-drag-and-drop`; приватность по
   участию; realtime веб-фронта через Phoenix Channels (REST `/api/v1` —
   отдельный контур для агентов); `noUnusedLocals/Parameters` включены.
4. Где что лежит.
5. **Трекер задач (доска Kaska)** — как агенту вести свои карточки.

Доп. правила бэкенда (Phoenix v1.8) — в [`app/AGENTS.md`](./app/AGENTS.md).

## Структура репозитория

- `app/` — бэкенд: Phoenix v1.8, Ecto, Guardian, Phoenix Channels, REST `/api/v1`.
- `web/` — фронт: Vue 3 `<script setup>` + TS, Vite, Pinia, Vuetify 4, tiptap. pnpm.
- `mcp/` — MCP-сервер (TypeScript) поверх REST API для агентов.
- `landing/` — лендинг.
- `caddy/` — реверс-прокси (`Caddyfile`).

## Проверки перед сдачей

- Бэкенд: `cd app && mix precommit` (формат, тесты, `--warnings-as-errors`).
- Фронт: `cd web && npx vue-tsc -p tsconfig.app.json --pretty false`.

## Трекер

Свою работу веди на доске Kaska через REST API (или MCP) — подробности в
`CLAUDE.md` §5. Кратко: `todo → in progress → ready to prod → done`; берёшь
задачу — двигай в `in progress`, доделал — в `ready to prod`; в `done`
переносит только пользователь; каждое перемещение сопровождай комментарием.
