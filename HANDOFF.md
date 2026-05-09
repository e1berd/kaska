# HardHat — agent handoff

Открытый трекер задач: канбан + список + карточки с tiptap-описанием и
вложениями. Любой посетитель видит проекты и доски; учётка нужна только
чтобы писать. Этот документ — то, что нужно прочесть **до** того, как
лезть в код.

> Обновляй этот файл, когда меняются конвенции, архитектура или контракты.
> Не превращай его в журнал изменений — описывай **актуальное состояние**.

---

## Стек

| Слой        | Технология                                                       |
|-------------|------------------------------------------------------------------|
| Бэкенд      | Elixir 1.15+, Phoenix v1.8, Ecto, Guardian (JWT), Phoenix Channels |
| БД          | PostgreSQL 17 (docker)                                           |
| Object store | RustFS (S3-совместимый, docker)                                 |
| Mail dev    | Swoosh local mailbox preview на `/mailbox` (без SMTP в dev)      |
| Фронт       | Vue 3 (`<script setup>` + TS), Vite 8, Pinia 3, Vue Router 4     |
| UI kit      | Vuetify 4 (с тяжёлыми кастомизациями под Material 3)             |
| Editor      | tiptap 3 (StarterKit + Link + Placeholder)                       |
| DnD         | `@atlaskit/pragmatic-drag-and-drop` + hitbox + auto-scroll       |
| Анимации    | CSS-токены (см. ниже) + `animejs` точечно                        |

Фронтовый менеджер пакетов — **pnpm** (`web/pnpm-lock.yaml`).
В корне ещё лежит `package.json` уровня монорепо, но рабочая директория
фронта — `web/`.

---

## Структура репо

```
hardhat/
├── docker-compose.yml      # postgres + rustfs
├── api/                    # Phoenix backend
│   ├── lib/hardhat/
│   │   ├── accounts/       # users, sessions, password reset
│   │   ├── projects/       # Project, Column, Task, TaskType + ranks
│   │   ├── attachments/    # presigned uploads, polymorphic owner
│   │   ├── storage/        # S3/RustFS adapters
│   │   ├── guardian.ex     # JWT issuance/verification
│   │   └── rank.ex         # лексикографический ranker для DnD
│   ├── lib/hardhat_web/channels/
│   │   ├── user_socket.ex
│   │   ├── auth_channel.ex     # login/register/refresh
│   │   ├── projects_channel.ex # projects:lobby
│   │   ├── board_channel.ex    # board:<project_id>
│   │   └── user_channel.ex     # me/profile
│   ├── priv/repo/migrations/
│   └── AGENTS.md           # Phoenix-specific правила (Phoenix v1.8)
└── web/
    ├── src/
    │   ├── App.vue                      # shell: app-bar + nav rail + main
    │   ├── main.ts
    │   ├── plugins/vuetify.ts           # тема M3, defaults, breakpoints
    │   ├── router/index.ts
    │   ├── styles/
    │   │   ├── m3-tokens.scss           # source of truth для токенов
    │   │   └── main.scss
    │   ├── stores/
    │   │   ├── socket.ts   # phoenix Socket + waitForSocketOpen
    │   │   ├── auth.ts     # JWT, профиль, аватар
    │   │   ├── projects.ts # лобби, список проектов
    │   │   └── board.ts    # snapshot + delta-events для board:*
    │   ├── components/
    │   │   ├── RichEditor.vue           # tiptap editor (writable)
    │   │   └── board/
    │   │       ├── BoardColumn.vue
    │   │       └── BoardCard.vue
    │   ├── utils/
    │   │   ├── tiptap.ts   # docPreview / docToHtml / isDocEmpty
    │   │   └── upload.ts   # presigned PUT
    │   └── views/                       # маршрутные страницы
    └── pnpm-lock.yaml
```

---

## Запуск dev

```bash
# инфраструктура (PG + RustFS)
docker compose up -d

# бэкенд
cd api
mix deps.get
mix ecto.setup
mix phx.server          # http://localhost:4000

# фронт
cd ../web
pnpm install
pnpm dev                # http://localhost:5173
```

Фронт по умолчанию подключается к `ws://localhost:4000/socket`. Переопределяется через `VITE_API_WS_URL`.

---

## Модель доступа

**Public read, authed write.** Все доменные сущности видны без логина —
анонимный гость подключается к каналу как гость и получает snapshot.
Любая мутация требует `current_user`: `BoardChannel` режет `handle_in/3`
гардом до маршрутизации команды (см. `lib/hardhat_web/channels/board_channel.ex`).

На фронте ту же логику отражает `auth.isAuthed` — кнопки, формы и
редакторы должны быть **read-only** для гостей, но видимы. Не прячь
карточки/доски от неавторизованных — это полностью убивает UX.

---

## Realtime — это не «фича», это контракт

**Любая** доменная мутация идёт через Phoenix channel и распространяется
broadcast'ом всем подписчикам. REST для них нет и не должно появиться.

### Каналы

| Топик                | Snapshot reply                                          | Delta-события |
|----------------------|---------------------------------------------------------|---------------|
| `projects:lobby`     | `{ projects: [Project] }`                               | `project_created` |
| `board:<project_id>` | `{ project, columns, tasks, task_types, users, attachments }` | `column_created`, `column_updated`, `column_moved`, `column_deleted`, `task_created`, `task_updated`, `task_moved`, `task_deleted`, `task_attachment_added`, `task_attachment_removed`, `task_type_created`, `task_type_updated`, `task_type_deleted` |
| `auth`               | (login/register/refresh, не доменный)                   | — |
| `users:me`           | профиль, аватар                                          | — |

### Правила фронта

1. **Никогда не патчишь локальный store вручную после мутации.** Сделал
   `pushAsync(channel, 'create_task', ...)` — жди broadcast'а
   `task_created`, локальный upsert произойдёт сам в `board.ts`.
2. Для каждого нового события на бэке **обяззательно** добавь
   `ch.on(...)` + upsert/remove в соответствующем store, иначе клиенты
   будут расходиться, пока не F5.
3. **Realtime не опционален.** Любой новый view (таблица, дашборд,
   фильтр) обязан читать из реактивных рефов store, а не из снапшота —
   иначе при обновлении другим юзером экран замораживается.
4. `joinChannel` ждёт `socket.isConnected()` (см. `socket.ts`,
   `waitForSocketOpen`) — не убирай этот await, иначе после рестарта
   бэкенда первый join словит `{ message: 'join timeout' }` через 10с.
5. Канал доски — это **shared resource**: открыл `BoardView` или
   `TaskTypesView` — оба пользуются тем же `useBoardStore()`/каналом.
   `board.leave()` зови только в `onBeforeUnmount` той страницы,
   которая знает, что больше никто не нуждается. Сейчас обе страницы
   доски делают свой `join()`/`leave()` — не ломай этот цикл.

---

## Style guide

### Комментарии в коде — запрещены

Никаких `//` и `/* */` комментариев в TypeScript, Vue и Elixir файлах.
Код должен быть самодокументирующимся: хорошие имена функций и переменных,
маленькие функции с одной ответственностью. Если чувствуешь желание
написать комментарий — переименуй или вырази намерение через код.

---

### Material Design 3 — строго

**Дизайн-цель — последняя M3-спецификация.** Vuetify 4 даёт цветовые
роли и базовые компоненты, но в самом фреймворке много мелких
несоответствий M3 (corner-радиусы, motion, state layers). Доводим
руками.

* Мелкие правки (радиус, gap, density, типографика) — делай молча.
* Кардинальные (поменять компонент, отказаться от vuetify-варианта,
  ввести новый паттерн) — обсуждай с пользователем сначала.

### Токены — `web/src/styles/m3-tokens.scss`

CSS custom properties, **используй их вместо магических чисел**:

* Motion: `--md-duration-{short1..extra-long4}`,
  `--md-easing-{standard,emphasized,...}`
* Shape: `--md-shape-{none,xs,s,m,l,xl,full}`
* Elevation: `--md-elev-{1..5}` (двойные тени по M3)
* State opacity: `--md-state-{hover,focus,pressed,dragged}`
* Type scale: `--md-type-*` + классы `.md-display-*`, `.md-headline-*`,
  `.md-title-*`, `.md-body-*`, `.md-label-*`

### Цвет — Vuetify-роли

Тема в `plugins/vuetify.ts`, baseline-палитра M3 (primary `#6750A4`).
Все цвета берём через `rgb(var(--v-theme-<role>))`:
`primary`, `on-primary`, `primary-container`, `on-primary-container`,
`secondary*`, `tertiary*`, `surface`, `surface-container[-low|-high|-lowest|-highest]`,
`outline`, `outline-variant`, `error*`, `inverse-*`. Никаких хардкодов хексов в компонентах (исключение — task type colors, выбираемые пользователем).

### State layers

`.md-state-layer` из `m3-tokens.scss` — переиспользуемый overlay для
hover/focus/pressed. Хост должен быть `position`-эд и иметь
`--md-state-color` (по умолчанию currentColor).

### Анимации

* **CSS first.** Большинство M3 motion (page transitions, state-layer
  fades, ripple-замены, transform-hover) — через CSS-transition с
  токенами `--md-duration-*` и `--md-easing-*`.
* **anime.js — только для сложной хореографии** (последовательность,
  ключевые кадры, физика). Не пиши `anime({ targets, opacity })` там,
  где справится `transition: opacity var(--md-duration-short3)
  var(--md-easing-standard)`.
* **Никаких `vuedraggable` / `Sortable.js`.** DnD только через Pragmatic
  DnD. Custom ghost (см. `BoardCard.vue`) — нативный drag-image
  блюрится на hi-DPI, поэтому заменён на DOM-клон, следующий за
  курсором.

### Vuetify defaults

Заданы в `plugins/vuetify.ts` — не дублируй в каждом компоненте:

* `VBtn`: `rounded: 'pill'`, `class: 'md-label-large'` (M3 кнопки —
  пиллы; чтобы вернуть угол — задай `rounded` явно).
* `VTextField`/`VTextarea`/`VSelect`: `variant: 'filled'`.
* `VCard`: `rounded: 'lg'`.
* `display.mobileBreakpoint: 'sm'` — иначе `useDisplay().mobile`
  считает `true` для всех ноутбуков (<1280px) и сайдбар уходит в
  temporary mode.

### Tiptap

* Редактор: `web/src/components/RichEditor.vue`. StarterKit (heading
  только h2/h3) + Link + Placeholder.
* Просмотр: `docToHtml(doc)` из `web/src/utils/tiptap.ts` (использует
  `generateHTML` из `@tiptap/vue-3`). **Тот же набор расширений.**
  Если добавляешь новое расширение — обнови **обе** стороны.
* Пустота: `isDocEmpty(doc)` (по факту нет извлекаемого текста). Если
  карточка только что создана или описания нет — открывается сразу
  редактор; если есть — viewer + кнопка «Редактировать».

---

## UI conventions

* **Сайдбар** = M3 NavigationRail (80dp, иконка в pill 56×32 + label
  снизу). На десктопе `permanent`, на мобильном `temporary` +
  `<v-app-bar-nav-icon>` бургер. Скрыт целиком на маршруте `home`
  (`route.name === 'home'`). Никакого toggle expand/collapse — текст и
  иконка влезают, тултипы не нужны.
* **Диалоги** закрываются по клику вне (никакого `persistent`) —
  единственное исключение — confirm-удаление, где нужен явный выбор.
  Диалог карточки задачи на мобильном — `:fullscreen="mobile"`.
* **Карточка задачи**: viewer-описание по умолчанию, кнопка
  «Редактировать» открывает tiptap. Для пустого описания → сразу
  редактор (без кнопки). Сохранение сбрасывает диалог; realtime
  обновит карточку у других через `task_updated`.
* **Список задач** (`viewMode='list'` в BoardView) — `v-data-table`,
  inline `v-select` для смены колонки (`@click.stop` чтобы не открыть
  карточку), клик по строке открывает диалог. Смена колонки — через
  `board.moveTask(...)` с `beforeId` = последний таск новой колонки.
* **Колонки** — горизонтальный скролл с auto-scroll при DnD у краёв
  (`autoScrollForElements`). Не превращай в обёртку с фиксированной
  шириной.

---

## Pitfalls / готовые грабли

* **`useDisplay().mobile`** — мы установили `mobileBreakpoint: 'sm'`
  (600px). Не возвращай дефолт `'lg'` (1280px) — поломается layout.
* **`v-navigation-drawer permanent` + `v-model`** — авто-init `isActive`
  работает только когда `modelValue == null`. Если передаёшь v-model
  со значением `false` И `permanent=true`, drawer стартует hidden и
  watcher не подхватит. Решение: `drawer = ref(!mobile.value)` (см.
  `App.vue`).
* **`v-select` slot types** — в Vuetify 4 в slot'ах `item`/`selection`
  параметр `item` это **raw item** типизированный как `unknown` (не
  wrapper с `.raw`/`.title`). Касти через `(item as TaskType).color`,
  не пиши `item.raw.color`.
* **Socket join после рестарта бэкенда** — `joinChannel` вызывает
  `waitForSocketOpen`, которая через `watch(socket, ...)` реактивно
  следит за заменой сокета. Это покрывает три случая: бэкенд ещё
  стартует, Vite HMR пересоздаёт модуль, `bootstrap()` делает
  reconnect с новым токеном. Не добавляй таймаут — Phoenix.js сам
  переподключается с exponential backoff; таймаут нужен только на
  `join` (10 с, уже в `ch.join()`).
* **`check_origin` в dev** — `runtime.exs` выставляет `check_origin:
  false` для всех окружений кроме `:prod`. Не меняй на
  `check_origin: [web_base_url]` в dev — браузер идёт на порт 4000,
  а фронт живёт на 5173, origin не совпадёт и `join` молча
  отвалится (в логах будет `CONNECTED`, но `JOINED` — никогда).
* **Vite HMR `WebSocket closed without opened`** — это не баг
  приложения, это HMR-клиент vite пытается переподключиться к
  пересоздающемуся dev-серверу. Игнорируй или подави overlay через
  `hmr.overlay: false`.
* **Selection slot v-select c кастомным item** — обязательно
  кастуй типы. Не выводи `item.title` (его там нет на тип-уровне) —
  делай `(item as TaskType).name`.
* **Layout `v-app`**: `<v-app-bar>`, `<v-navigation-drawer>` и
  `<v-main>` должны быть прямыми детьми `<v-app>`. Не оборачивай их в
  кастомный wrapper — поломаешь auto-offset для `v-main`.
* **Permissions для node_modules**: если `pnpm install` не может
  пересоздать `.pnpm/*` (EACCES), это порча владельца файлов. Чини
  через `chown` снаружи; не пытайся sudo'ом изнутри agent'а.

---

## Минимальный TypeScript-полис

* Комментарии в коде не пишем (см. Style guide выше).
* `noUnusedLocals` и `noUnusedParameters` включены — не оставляй
  «висячих» функций, удаляй.
* Для интерфейсов из stores импортируй типы явно: `import type { Task,
  Column, TaskType, TiptapDoc } from '../stores/board'`,
  `import type { User } from '../stores/auth'`.
* `vue-tsc -p tsconfig.app.json --pretty false` — это локальная команда
  правды. Просто `vue-tsc --noEmit` иногда возвращает 0 даже при
  ошибках из-за кеша билд-инфо.

---

## Бэкенд — мини-памятка

* Phoenix v1.8 правила лежат в `api/AGENTS.md` (LiveView не используется
  в этом проекте, но HEEx/`<.input>` правила полезны для админки в
  будущем).
* Ranks (`api/lib/hardhat/rank.ex`) — лексикографические строки между
  предыдущим и следующим элементом. Все DnD-операции (`move_task`,
  `move_column`) фронт шлёт `before_id`/`after_id`, а сервер
  пересчитывает rank.
* Аплоады: фронт зовёт `request_task_attachment_upload` →
  `confirm_task_attachment_upload`. Между ними — `PUT` напрямую в
  RustFS по presigned URL (см. `web/src/utils/upload.ts`). Никаких
  multipart через Phoenix.
* Любой новый mutation event: `handle_in("xxx", ...)` + broadcast +
  view-функция (для shape ответа) + клиентский `pushAsync` + `ch.on(...)`
  + upsert в store. Половинчатого realtime не бывает.

---

## Что важно держать в голове

1. **Public-read** — всегда. Не пиши `requiresAuth: true` на
   просмотровые маршруты.
2. **Realtime — всегда.** Любой новый view читает реактивный store; любая
   мутация уходит через канал и возвращается broadcast'ом.
3. **Material 3 — строго.** Сомневаешься в дизайне — открывай
   `m3.material.io` и сверяй token-by-token.
4. **DnD — только Pragmatic.**
5. **Анимации — CSS первым делом.**
