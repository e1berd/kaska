# agent-supervisor

Внутренний сервис Kaska, который запускает прогоны code-capable агентов в эфемерных
Docker-контейнерах. Единственный компонент с доступом к `/var/run/docker.sock`. Решения «когда и что
запускать» принимает Phoenix (`Kaska.AgentRuntime`), супервизор только исполняет. Подробности — в
`docs/AGENT_SUPERVISOR_PLAN.md`.

## API

Все запросы, кроме `GET /health`, требуют `Authorization: Bearer $SUPERVISOR_SECRET`.

| Метод  | Путь                 | Ответ                                                                                |
| ------ | -------------------- | ------------------------------------------------------------------------------------ |
| `GET`  | `/health`            | `{ok, active_runs}`                                                                  |
| `POST` | `/runs`              | `201 {container_id}`, `409` уже идёт, `422` невалидный payload, `502` Docker не смог |
| `POST` | `/runs/:run_id/stop` | `200 {stopped}`, `404` неизвестный прогон                                            |

Тело `POST /runs`:

```json
{
  "run_id": "uuid",
  "image": "kaska-agent-runtime:latest",
  "env": { "KASKA_PAT": "..." },
  "limits": { "memory_mb": 2048, "cpus": 1, "pids_limit": 512, "walltime_seconds": 1800 },
  "callback_url": "http://api:4000/internal/agent_runs/<run_id>"
}
```

Супервизор отклоняет образы вне `ALLOWED_IMAGES`, лимиты выше своих потолков и `callback_url`, не
указывающий на этот прогон под `CALLBACK_BASE_URL`.

Обратно в Phoenix, тем же секретом:

- `POST <callback_url>/logs` `{chunk}` — вывод контейнера (stdout+stderr), батчами;
- `POST <callback_url>/exit` `{outcome: "exited" | "timed_out" | "failed", ...}` — ретраится с
  backoff, `409`/`404`/`400` считаются финальными.

## Контейнер прогона

Read-only rootfs, tmpfs на `/tmp` и `/workspace`, `CapDrop: ALL`, `no-new-privileges`, лимиты памяти
(без swap), CPU и PID, `Init`. Сеть — `RUNNER_NETWORK` (bridge с выключенным ICC, создаётся при
старте), без маршрута к `postgres`/`rustfs`/`api`. По walltime контейнер убивается, отчёт —
`timed_out`. После отчёта контейнер удаляется.

Метаданные прогона лежат в лейблах `space.kaska.*`, поэтому после рестарта супервизор подхватывает
живые контейнеры и отчитывается за завершившиеся.

## Переменные окружения

| Переменная                                                         | По умолчанию                                  |
| ------------------------------------------------------------------ | --------------------------------------------- |
| `SUPERVISOR_SECRET`                                                | обязательна, ≥ 16 символов                    |
| `CALLBACK_BASE_URL`                                                | обязательна, напр. `http://api:4000/internal` |
| `PORT`                                                             | `8080`                                        |
| `DOCKER_SOCKET`                                                    | `/var/run/docker.sock`                        |
| `RUNNER_NETWORK`                                                   | `kaska-agent-runs`                            |
| `ALLOWED_IMAGES`                                                   | `kaska-agent-runtime:latest` (через запятую)  |
| `MAX_MEMORY_MB` / `MAX_CPUS` / `MAX_PIDS` / `MAX_WALLTIME_SECONDS` | `4096` / `2` / `1024` / `3600`                |
| `LOG_FLUSH_MS` / `LOG_FLUSH_BYTES`                                 | `1000` / `16000`                              |

## Разработка

```bash
deno task test
deno task check
```

В проде включается профилем: `docker compose --profile agents up --build -d` (нужен
`AGENT_SUPERVISOR_SECRET` в `.env`).
