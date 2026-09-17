# Kaska — правила для Claude

Эти правила обязательны при любой работе с этим репозиторием. Они
важнее общих привычек — если что-то противоречит этим правилам, делай
по правилам.

---

## 1. Никаких комментариев в коде

В `.ts`, `.tsx`, `.vue`, `.ex`, `.exs` файлах **запрещены**:

- `//` однострочные комментарии
- `/* ... */` блочные комментарии
- `<!-- ... -->` в `<template>` секциях `.vue`
- `#` пояснительные комментарии в Elixir (кроме shebang)

Код должен быть самодокументирующимся: ясные имена, маленькие функции,
выражение намерения через структуру. Если хочется написать «зачем» —
переименуй переменную/функцию или вынеси в отдельную функцию с
говорящим именем.

**Исключения** (это документация, не комментарии):

- `@moduledoc`/`@doc` в Elixir
- TypeScript-директивы вроде `// @ts-expect-error`, `// eslint-disable-next-line`
  если нет другого способа подавить ложноположительное предупреждение
- `<!--#-->`-комментарии в HTML-шаблонах для Vue не считаются нужными —
  обычно вместо них берутся `v-if`/имена компонентов

Отсутствие комментариев — это контракт. Любая правка, добавляющая
комментарий «для ясности», должна быть отвергнута и переписана через
имена/структуру.

---

## 2. Material Design 3 — строго по последней спецификации

**Источник правды** — текущая спецификация на `m3.material.io`.
Vuetify 4 и его дефолты — лишь стартовая точка; в фреймворке есть
мелкие отклонения от M3 (corner-радиусы, motion duration/easing,
state layers, типографика). Доводим руками.

### Когда сомневаешься в дизайне

1. Открой соответствующий раздел m3.material.io и сверь токен в спеке.
2. Используй существующие токены из `web/src/styles/m3-tokens.scss`
   (CSS custom properties: `--md-shape-*`, `--md-duration-*`,
   `--md-easing-*`, `--md-elev-*`, `--md-state-*`, `--md-type-*` и
   утилитарные классы `.md-display-*`, `.md-headline-*`, `.md-title-*`,
   `.md-body-*`, `.md-label-*`).
3. Цвета — только Vuetify-роли через `rgb(var(--v-theme-<role>))`:
   `primary[-container]`, `secondary[-container]`, `tertiary[-container]`,
   `surface[-container[-low|-high|-lowest|-highest]]`, `outline[-variant]`,
   `error[-container]`, `inverse-*` и их `on-*` пары.
4. Хардкод hex/rgb/hsl в компонентах — запрещён. Единственное
   исключение — пользовательские цвета, которые юзер сам выбирает
   (например, цвет типа задачи).

### Объём правок

- Мелкие правки (радиус, gap, density, типографика, motion-токены) —
  делай молча.
- Кардинальные (заменить компонент, отказаться от Vuetify-варианта,
  ввести новый паттерн) — обсуди с пользователем сначала.

### Tailwind CSS

Tailwind 4 подключён (`@tailwindcss/vite`, точка входа
`web/src/styles/tailwind.css` — импортируются только `theme` и `utilities`,
**без preflight**, чтобы не ломать ресет Vuetify). Область применения строго
ограничена:

- **Можно** — утилиты раскладки и spacing: `flex`/`grid`/`gap`/`p*`/`m*`/
  `justify-*`/`items-*`/`self-*`/`w-*`/`h-*`/`hidden` и т.п., в т.ч.
  arbitrary-значения (`[grid-column:-2/-1]`). Это замена мелким scoped-CSS на
  раскладку.
- **Нельзя** — цвета, типографику, радиусы, тени, motion через Tailwind. Для
  них только Vuetify-роли и M3-токены (`--md-*`, `.md-*`,
  `rgb(var(--v-theme-*))`). Никаких `text-*`/`bg-*`-цветов Tailwind,
  никакого хардкода палитры.
- Компоненты — по-прежнему Vuetify, а не Tailwind-вёрстка с нуля.

### Анимации

- **CSS first.** Большая часть M3 motion (page transitions, state-layer
  fade'ы, transform-hover) — через `transition` с токенами
  `--md-duration-*` и `--md-easing-*`.
- **Никаких JS-анимационных библиотек** (`animejs`, `gsap`, etc) —
  они в проекте не нужны и не желательны. Если без JS никак (сложная
  хореография, физика) — сначала обсуди необходимость.

---

## 3. Прочие сильные нормы проекта

Эти не требуют обсуждения, нарушать нельзя:

- **Drag-and-drop** — только `@atlaskit/pragmatic-drag-and-drop`. Никаких
  `vuedraggable` / `Sortable.js`.
- **Приватность по участию** — проект видят только его участники: владелец
  (`owner`) и приглашённые (`member`). Список проектов — per-user топик
  `projects:user:<id>`. Доска (`board:*`) открыта участникам на чтение+запись;
  не-участникам и анонимам — только если у проекта включён `public_link`
  (тогда read-only). Доступ к доске проверяется на join канала
  (`Projects.board_accessible?/2`), запись — по членству (`can_write` /
  `Projects.member?/2`) в `handle_in/3`, а на фронте через `board.canWrite`
  (`:readonly`/`:disabled`). Управление участниками/приглашениями и
  `public_link` — только владелец. Приглашают по email или ссылкой-токеном
  (`project_invites`); принятие (`/invite/:token`) добавляет в `member`.
- **Realtime через Phoenix Channels** — любая доменная мутация веб-фронта
  отправляется через канал и обновление приходит broadcast-событием. Веб-фронт
  ходит только через каналы; локальный store не патчим вручную после
  `pushAsync` — ждём broadcast. **Единственное исключение** — внутренний REST
  `/api/v1` раннера агентов (см. §5): он работает поверх тех же контекстов и
  после записи делает broadcast в `board:*` (через `KaskaWeb.BoardBroadcast`).
  Новые доменные операции для фронта — каналы, не REST. Внешнего публичного API,
  MCP и личных токенов (PAT) в проекте нет.
- **TypeScript**: `noUnusedLocals` и `noUnusedParameters` включены.
  Висячие переменные/импорты удаляй.
- **Ошибки не глотаем**: пустые `catch`/`rescue` запрещены. Обработай,
  залогируй или верни явный результат.
- **Type-check**: проверочная команда —
  `vue-tsc -p tsconfig.app.json --pretty false` (просто `--noEmit`
  иногда даёт false-negative из-за кеша build-info).

---

## 4. Где что лежит

- Бэкенд: `app/` (Phoenix v1.8, Ecto, Guardian, Phoenix Channels). Свои
  правила Phoenix v1.8 — в `app/AGENTS.md`.
- Фронт: `web/` (Vue 3 `<script setup>` + TS, Vite, Pinia, Vuetify 4,
  tiptap 3 collab). Менеджер пакетов — pnpm.
- M3-токены: `web/src/styles/m3-tokens.scss`.
- Vuetify-конфиг с дефолтами: `web/src/plugins/vuetify.ts`.
- Каналы: `app/lib/kaska_web/channels/`.
- Алиас импортов на фронте: `@/` → `web/src/`.
- Агенты: контекст `app/lib/kaska/agent_runtime*` и `app/lib/kaska/agents.ex`,
  каналы `agents:user:*` и `agent_run:*`, runner REST
  `app/lib/kaska_web/controllers/api/`, internal callback
  `app/lib/kaska_web/controllers/internal/`. Сервисы: `agent-supervisor/`,
  `agent-runtime/`. Архитектура — `docs/AGENT_SUPERVISOR_PLAN.md`.

---

## 5. Агенты Kaska

Агент — bot-пользователь владельца, который работает над задачей в эфемерном
Docker-контейнере на сервере Kaska (Claude Agent SDK или OpenAI-совместимый
цикл). Внешних клиентов нет: ни MCP, ни публичного REST, ни личных токенов.

- Настройки агента (провайдер, модель, ключ, инструкции) — страница `/agents`,
  канал `agents:user:<id>`. Ключ LLM хранится зашифрованным (`Kaska.Vault`,
  `AGENT_SECRETS_KEY`), наружу отдаются только `api_key_set` и последние символы.
- Прогон запускается с карточки задачи (`start_agent_run` в `board:*`) для
  агента-исполнителя. Не больше одного активного прогона на задачу и
  `AGENT_MAX_ACTIVE_RUNS_PER_OWNER` на владельца.
- Раннер ходит в `/api/v1` только токеном своего активного прогона и только к
  своей задаче (`KaskaWeb.Plugs.RunnerAuth`); токен отзывается по завершении.
  WebSocket такие токены не принимает.
- Docker-сокет есть только у `agent-supervisor`; `api` общается с ним по
  внутреннему HTTP с общим секретом (`AGENT_SUPERVISOR_SECRET`), обратно —
  `/internal/agent_runs/:id/{logs,exit}`, наружу Caddy его не проксирует.

## 6. Прод и деплой

- Перед деплоем: merge в `master` без конфликтов, проверки зелёные, миграции
  работают на продовой базе и fresh DB.
- Не удаляй уже применённые миграции. Для старой схемы добавляй новую
  миграцию-конвертацию/alter.
- Деплой через SSH делай только после явного запроса пользователя. Типичный
  порядок на проде: `git pull`, затем `docker compose down`, затем
  `docker compose up --build -d`. После этого проверь `docker compose ps`,
  `/health` и логи API. Если API уходит в restart loop или Caddy отдаёт 502,
  откати на последний рабочий `origin/master` и сообщи пользователю причину.
