# agent-runtime

Образ `kaska-agent-runtime`: один контейнер — один прогон code-capable агента на одной задаче.
Контейнер запускает `agent-supervisor`, env собирает Phoenix (`Kaska.AgentRuntime.runtime_env/4`).
Архитектура — в `docs/AGENT_SUPERVISOR_PLAN.md`.

## Что делает прогон

1. Читает проект (`agent_instructions`, колонки) и задачу с комментариями через REST своим PAT.
2. Готовит `/workspace` (git-репозиторий; клонирование привязанного репо — Phase 3).
3. Гоняет цикл LLM с инструментами до финального ответа или `MAX_TURNS`.
4. Публикует итог комментарием на задаче. Exit `0` — агент закончил, `1` — лимит ходов/бюджета или
   ошибка (текст ошибки тоже уходит комментарием).

Весь stdout — это лог прогона, который супервизор стримит в Phoenix. Секреты в лог не пишутся.

## Провайдеры

| `LLM_PROVIDER_KIND` | Цикл                                                            | Инструменты                                                   |
| ------------------- | --------------------------------------------------------------- | ------------------------------------------------------------- |
| `anthropic`         | Claude Agent SDK (`query`, `bypassPermissions`, `maxTurns`)     | встроенные `Read/Write/Edit/Bash/Glob/Grep` + Kaska через MCP |
| `openai_compatible` | свой цикл Chat Completions с `tools`/`tool_calls`               | `read_file/write_file/edit_file/list_files/bash` + Kaska      |
| `ollama_local`      | тот же цикл против `<LLM_BASE_URL>/v1` (OpenAI-совместимый API) | как у `openai_compatible`                                     |

Kaska-инструменты работают только с задачей прогона: `get_task`, `post_comment`, `move_task`,
`update_task`.

## Переменные окружения

| Переменная                                | Назначение                                          |
| ----------------------------------------- | --------------------------------------------------- |
| `KASKA_API_URL`, `KASKA_PAT`              | REST Kaska и PAT прогона (отзывается после прогона) |
| `KASKA_RUN_ID`, `TASK_ID`, `PROJECT_SLUG` | идентичность прогона                                |
| `LLM_PROVIDER_KIND`, `LLM_MODEL`          | провайдер и модель                                  |
| `LLM_BASE_URL`                            | обязателен для всех, кроме `anthropic`              |
| `LLM_API_KEY`                             | ключ провайдера (пустой для локальных моделей)      |
| `SYSTEM_PROMPT`                           | роль агента из его настроек                         |
| `MAX_TURNS`                               | лимит ходов, по умолчанию `60`                      |
| `WORKSPACE_DIR`                           | по умолчанию `/workspace`                           |

## Изоляция внутри контейнера

`KASKA_PAT` и `LLM_API_KEY` удаляются из окружения процесса сразу после чтения конфига. Команды
`bash` собственного цикла запускаются с чистым env (PATH, HOME, git-идентичность), пути файловых
инструментов не выходят за `/workspace`, включая симлинки. В цикле Claude ключ Anthropic неизбежно
есть в окружении процесса Claude Code, а значит и у его `Bash`.

Образ рассчитан на read-only rootfs: `HOME=/tmp/home`, зависимости запечены в образ, запуск с
`--cached-only`, `/tmp` и `/workspace` — tmpfs.

## Разработка

```bash
deno install
deno task test
deno task check
docker build -t kaska-agent-runtime:latest .
```

В проде образ собирается профилем: `docker compose --profile agents up --build -d`.
