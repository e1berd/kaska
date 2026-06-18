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
5. **Трекер задач (доска Kaska)** — перед работой читай
   [`clerk-briefing.md`](./app/priv/static/clerk-briefing.md).

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

Свою работу веди на доске Kaska через REST API или MCP. Перед любыми правками
обязательно прочитай briefing для клерков:
[`app/priv/static/clerk-briefing.md`](./app/priv/static/clerk-briefing.md)
(на проде: `https://app.kaska.space/clerk-briefing.md`).

Если пользователь дал ссылку или id задачи Kaska, сначала прочитай задачу,
`agent_instructions` проекта и описания колонок. Не хардкодь названия колонок:
на разных досках они могут называться по-разному. Взял задачу — перемести её в
колонку со смыслом «в работе» и оставь комментарий. Доделал и проверил —
перемести в колонку со смыслом «готово к проверке/деплою» и оставь комментарий.
В финальную колонку завершённых задач переносит только пользователь, если он не
сказал обратное явно.

`clerks.yml`: предпочтительно `clerks:` + `tokens:` + dotenv-подстановки.
Личность определяется PAT. Помогаешь Мо/Зусу — всё равно пиши своим токеном и
своим именем, если пользователь явно не сказал переключиться.
