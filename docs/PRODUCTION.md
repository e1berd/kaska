# Деплой HardHat в production

Полный гайд по разворачиванию HardHat на одном сервере с автоматическим SSL
через Caddy + Let's Encrypt. Всё крутится в Docker Compose, никаких
ручных правок конфигов на хосте.

## Содержание

1. [Архитектура](#1-архитектура)
2. [Требования](#2-требования)
3. [DNS](#3-dns)
4. [Подготовка сервера](#4-подготовка-сервера)
5. [Файрвол и порты](#5-файрвол-и-порты)
6. [Клонирование и секреты](#6-клонирование-и-секреты)
7. [Первый запуск](#7-первый-запуск)
8. [Создание первого администратора](#8-создание-первого-администратора)
9. [SSL-сертификаты (как это работает)](#9-ssl-сертификаты-как-это-работает)
10. [Бэкапы](#10-бэкапы)
11. [Обновление приложения](#11-обновление-приложения)
12. [Логи и наблюдаемость](#12-логи-и-наблюдаемость)
13. [Troubleshooting](#13-troubleshooting)
14. [Замена лендинга](#14-замена-лендинга)
15. [Опционально: Caddy на хосте](#15-опционально-caddy-на-хосте)

---

## 1. Архитектура

В production используется три домена:

| Домен | Что отдаётся | Куда проксируется |
|---|---|---|
| `example.com` | Лендинг (статика) | Caddy → `/srv/landing` |
| `app.example.com` | SPA + WebSocket API | Caddy → SPA из `/srv/app`, `/socket` и `/health` → `api:4000` |
| `s3.example.com` | RustFS S3 (для pre-signed URL) | Caddy → `rustfs:9000` |

Сервисы в `docker-compose.yml`:

- `postgres` — БД (Postgres 17), без публикации портов наружу.
- `rustfs` — S3-совместимое хранилище, без публикации портов наружу.
- `api` — Phoenix release (prod), без публикации портов наружу.
- `web` — **publisher**: собирает SPA, кладёт `dist/` в named volume `web-dist` и завершается с кодом 0. Caddy монтирует этот volume read-only.
- `caddy` — реверс-прокси и TLS-терминатор. Единственный сервис, который слушает 80/443.

Внутри docker-сети `hardhat-net` сервисы общаются по именам контейнеров. Снаружи доступ только через Caddy.

```
                ┌─────────────────────────────────────┐
  Internet ───▶ │  Caddy (80/443/443-udp)             │
                │  ├─ example.com      → /srv/landing │
                │  ├─ app.example.com  → SPA + api    │
                │  └─ s3.example.com   → rustfs:9000  │
                └──────┬──────────────────────────────┘
                       │  hardhat-net (docker)
       ┌───────────────┼─────────────────┐
       ▼               ▼                 ▼
   ┌────────┐     ┌─────────┐      ┌──────────┐
   │  api   │ ──▶ │ postgres│      │  rustfs  │
   │ :4000  │     │ :5432   │      │  :9000   │
   └────────┘     └─────────┘      └──────────┘
```

---

## 2. Требования

- Сервер с публичным IPv4 (Linux, x86_64). Минимум 2 vCPU / 2 GB RAM / 20 GB диска. Рекомендуется 4 GB RAM.
- Свободные порты `80/tcp`, `443/tcp` и `443/udp` (HTTP/3) на публичном интерфейсе.
- Docker Engine ≥ 24 и Docker Compose v2 (`docker compose ...`).
- Зарегистрированный домен и доступ к управлению DNS-записями.
- SMTP-аккаунт для отправки писем (приглашения, восстановление пароля и т.д.).

> **Важно**: ACME-вызов (HTTP-01) требует, чтобы порт 80 был доступен извне для каждого домена. Если перед сервером CDN или другой прокси — отключи проксирование (oранжевое облачко в Cloudflare → серое) на время первого выпуска сертификатов.

---

## 3. DNS

Создай **три A-записи** (или AAAA, если используешь IPv6), указывающие на публичный IP сервера:

| Тип | Имя | Значение | TTL |
|---|---|---|---|
| A | `@` (или `example.com`) | `203.0.113.10` | 300 |
| A | `app` | `203.0.113.10` | 300 |
| A | `s3` | `203.0.113.10` | 300 |

Проверь, что записи распространились:

```bash
dig +short example.com
dig +short app.example.com
dig +short s3.example.com
```

Все три должны отдавать один и тот же IP. Не двигайся дальше, пока DNS не работает — Caddy не сможет получить сертификат.

---

## 4. Подготовка сервера

### Установка Docker (Ubuntu/Debian, для других дистрибутивов см. [docs.docker.com](https://docs.docker.com/engine/install/))

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"
```

Перелогинься, чтобы изменение группы вступило в силу. Проверка:

```bash
docker --version
docker compose version
```

### Настройка времени

Для корректной валидации TLS-сертификатов часы должны идти точно:

```bash
sudo timedatectl set-ntp true
timedatectl status
```

---

## 5. Файрвол и порты

Открой **только** 80, 443 (TCP) и 443 (UDP, для HTTP/3). Остальное — закрыто. Пример с `ufw`:

```bash
sudo ufw allow 22/tcp           # SSH (не забыть!)
sudo ufw allow 80/tcp           # Caddy ACME challenge + HTTP→HTTPS redirect
sudo ufw allow 443/tcp          # HTTPS
sudo ufw allow 443/udp          # HTTP/3 (QUIC)
sudo ufw enable
sudo ufw status
```

Postgres (`5432`), RustFS (`9000`/`9001`) и Phoenix (`4000`) **не публикуются** наружу — они доступны только из docker-сети.

---

## 6. Клонирование и секреты

```bash
sudo mkdir -p /opt/hardhat
sudo chown $USER:$USER /opt/hardhat
cd /opt/hardhat
git clone https://github.com/<your-org>/hardhat.git .
```

Скопируй шаблон env и заполни:

```bash
cp .env.example .env
$EDITOR .env
```

> В репозитории два шаблона env — `.env.example` для production (этот гайд) и `.env.dev.example` для локальной разработки. Compose в production режиме (`docker-compose.yml`) автоматически подхватывает `.env`; для dev — `docker compose --env-file .env.dev -f docker-compose.dev.yml up -d`.

Сгенерируй секреты:

```bash
# SECRET_KEY_BASE (минимум 64 байта)
openssl rand -base64 64 | tr -d '\n'; echo

# GUARDIAN_SECRET_KEY
openssl rand -base64 64 | tr -d '\n'; echo

# Сильные пароли для Postgres и RustFS
openssl rand -base64 32 | tr -d '\n'; echo
openssl rand -base64 32 | tr -d '\n'; echo
```

Подставь полученные значения в `.env`. **Не коммить этот файл в git.**

Минимум что нужно поменять относительно `*.example`:

- `LANDING_DOMAIN`, `APP_DOMAIN`, `S3_DOMAIN` — твои реальные домены.
- `ACME_EMAIL` — твой email.
- `POSTGRES_PASSWORD`, `RUSTFS_ROOT_PASSWORD` — сильные пароли.
- `SECRET_KEY_BASE`, `GUARDIAN_SECRET_KEY` — сгенерированные секреты.
- Все `MAIL_*` — данные SMTP.
- `WEB_BASE_URL=https://app.example.com`, `S3_PUBLIC_ENDPOINT=https://s3.example.com`, `VITE_API_WS_URL=wss://app.example.com/socket` — без `http://` и `localhost`.

Защити файл от чужих глаз:

```bash
chmod 600 .env
```

---

## 7. Первый запуск

```bash
docker compose up -d --build
```

Что произойдёт по шагам:

1. Соберутся образы `hardhat-api` и `hardhat-web` (это долго — 5–15 минут на первом проходе).
2. Запустятся `postgres` и `rustfs`, дождутся healthcheck.
3. Запустится `api`, выполнит `Hardhat.Release.migrate()` (накатит миграции БД), запустит Phoenix release.
4. Запустится `web` (publisher), скопирует собранные SPA-файлы в named volume `web-dist` и завершится с кодом 0.
5. Запустится `caddy`, увидит SPA в `/srv/app`, лендинг в `/srv/landing`, поднимет три HTTPS-сайта и запросит сертификаты у Let's Encrypt.

Следи за логами:

```bash
docker compose logs -f caddy
```

В логах Caddy ищи строки вида `certificate obtained successfully` для каждого из трёх доменов. Если видишь ошибки про DNS / `connection refused` — см. [Troubleshooting](#13-troubleshooting).

Проверка:

```bash
curl -I https://example.com
curl -I https://app.example.com
curl -I https://app.example.com/health   # должно вернуть 200 от Phoenix
curl -I https://s3.example.com           # ответ от RustFS, обычно 403/AccessDenied — это норм
```

---

## 8. Создание первого администратора

В системе действует bootstrap-правило: **первый зарегистрированный пользователь автоматически получает роль `superadmin` и считается подтверждённым** (без email-верификации).

1. Открой `https://app.example.com`, нажми «Регистрация», заполни форму. Этот пользователь сразу станет суперадмином.
2. Дальнейших пользователей создавай через приглашения (доступно `admin`/`superadmin`).

Если нужно вручную повысить роль уже существующего пользователя:

```bash
docker compose exec api \
  bin/hardhat eval 'Hardhat.Release.promote("user@example.com", "superadmin")'
```

(Если такого release-helper нет, используй mix-таску из контейнера с MIX_ENV=prod, как описано в `README.md` → `mix users.promotion`.)

---

## 9. SSL-сертификаты (как это работает)

Caddy автоматически получает и продлевает Let's Encrypt-сертификаты для **каждого** домена, перечисленного в `Caddyfile`, через ACME HTTP-01 challenge. Никакого `certbot`, никаких cron-задач.

Что нужно:

- Порт 80 открыт извне → Caddy проходит HTTP-01 challenge.
- DNS указывает на сервер для всех трёх доменов.
- `ACME_EMAIL` валидный (на него Let's Encrypt пришлёт уведомления о просрочке).

Сертификаты хранятся в named volume `caddy-data` (внутри `/data/caddy/certificates/...`). При перезапуске контейнера ничего не теряется. Обновление автоматическое за ~30 дней до истечения.

### Лимиты Let's Encrypt

LE считает «issuance» по top-level domain: 50 сертификатов на регистрируемый домен в неделю, 5 повторных выпусков за то же имя в неделю. Если экспериментируешь с конфигом, сначала переключи Caddy на staging:

```caddyfile
{
    email {$ACME_EMAIL}
    acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
}
```

Затем `docker compose restart caddy`. Когда конфиг устаканен — убери эту строку, удали тестовые сертификаты:

```bash
docker compose exec caddy rm -rf /data/caddy/certificates/acme-staging-v02.api.letsencrypt.org-directory
docker compose restart caddy
```

### Принудительное продление / повторный выпуск

```bash
docker compose exec caddy \
  caddy reload --config /etc/caddy/Caddyfile
```

Полная очистка сертификатов (только в крайнем случае):

```bash
docker compose down
docker volume rm hardhat_caddy-data
docker compose up -d
```

---

## 10. Бэкапы

### Postgres

Снэпшот:

```bash
docker compose exec -T postgres \
  pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB" \
  > /opt/hardhat/backups/db-$(date +%Y%m%d-%H%M%S).dump
```

Восстановление:

```bash
cat backup.dump | docker compose exec -T postgres \
  pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists
```

### RustFS (S3 объекты)

Файлы лежат в named volume `rustfs-data`. Простейший снэпшот:

```bash
docker run --rm \
  -v hardhat_rustfs-data:/data:ro \
  -v /opt/hardhat/backups:/out \
  alpine:3 tar czf /out/rustfs-$(date +%Y%m%d-%H%M%S).tar.gz -C /data .
```

Можно также делать `aws s3 sync` через S3 API на внешний бакет — это надёжнее (off-site).

### Cron на сервере

```cron
0 3 * * * cd /opt/hardhat && docker compose exec -T postgres pg_dump -U hardhat -Fc hardhat | gzip > /opt/hardhat/backups/db-$(date +\%Y\%m\%d).dump.gz
15 3 * * 0 docker run --rm -v hardhat_rustfs-data:/data:ro -v /opt/hardhat/backups:/out alpine:3 tar czf /out/rustfs-$(date +\%Y\%m\%d).tar.gz -C /data .
30 3 * * * find /opt/hardhat/backups -mtime +30 -delete
```

Обязательно копируй `/opt/hardhat/backups/` куда-то наружу (S3, второй сервер, NAS).

---

## 11. Обновление приложения

```bash
cd /opt/hardhat
git pull
docker compose up -d --build
```

Что важно:

- `web` — пересоберётся, заново запустится publisher, новый `dist/` положит в `web-dist` (старые файлы удаляются `find /export -mindepth 1 -delete`).
- `api` — пересоберётся, при старте контейнер выполнит `Hardhat.Release.migrate()`. Миграции должны быть обратно совместимыми (forward-only); если ломаешь схему — сделай blue/green вручную.
- `caddy` — перезапустится только если поменялся образ/конфиг. Сертификаты остаются в `caddy-data`.
- `postgres`, `rustfs` — не пересобираются, работают как есть.

Проверь после обновления:

```bash
docker compose ps
docker compose logs --tail 100 api caddy
```

Откат:

```bash
git checkout <previous-tag>
docker compose up -d --build
```

(Если миграция была ломающая, откат БД — отдельный квест: восстанови дамп.)

---

## 12. Логи и наблюдаемость

```bash
# Все сервисы (Ctrl+C чтобы выйти)
docker compose logs -f

# Только api
docker compose logs -f api

# Последние 200 строк caddy
docker compose logs --tail 200 caddy
```

Caddy access-логи по умолчанию не пишутся. Если хочешь — добавь в каждый блок `Caddyfile`:

```caddyfile
{$APP_DOMAIN} {
    log {
        output file /var/log/caddy/app.log {
            roll_size 10mb
            roll_keep 5
        }
        format json
    }
    ...
}
```

И смонтируй `caddy-logs:/var/log/caddy` в `docker-compose.yml`.

---

## 13. Troubleshooting

### Caddy не получает сертификат

```
[ERROR] obtaining certificate: solving challenge: ... 403 Forbidden
[ERROR] obtaining certificate: solving challenge: connection refused
```

Чек-лист:

1. DNS реально указывает на сервер? `dig +short app.example.com`
2. Порт 80 открыт извне? Проверь с другого хоста: `curl -I http://app.example.com/.well-known/acme-challenge/test`. Если timeout — файрвол / провайдер блокирует.
3. Перед сервером нет CDN с проксированием? Если есть — отключи проксирование на время выпуска.
4. Не упёрся в rate limit Let's Encrypt? Смотри логи: `docker compose logs caddy | grep -i rate`.
5. Попробуй staging (см. [секцию SSL](#9-ssl-сертификаты-как-это-работает)) для отладки.

### WebSocket не подключается (SPA не получает realtime-обновления)

В консоли браузера:

```
WebSocket connection to 'wss://app.example.com/socket/websocket' failed: 403
```

→ Phoenix отклоняет origin. Проверь:

- В `.env`: `WEB_BASE_URL=https://app.example.com` (точно тот же origin что у браузера).
- В сборке web использовался `VITE_API_WS_URL=wss://app.example.com/socket` (build-arg, фигурирует в bundled JS — значит надо пересобрать `web` если меняешь).

После правки:

```bash
docker compose up -d --build web caddy
```

### S3 pre-signed URL отдаёт 403 / SignatureDoesNotMatch

Pre-signed URL содержит подпись host'а. Если `S3_PUBLIC_ENDPOINT` не совпадает с тем, что реально отдаёт RustFS наружу — подпись инвалидируется.

Проверь:

- `S3_PUBLIC_ENDPOINT=https://s3.example.com` (со схемой и без слеша в конце).
- Caddy форвардит `Host` в `rustfs:9000` (`header_up Host {upstream_hostport}` — это уже в Caddyfile).

### `api` падает с `DATABASE_URL is missing`

`.env` либо не существует, либо лежит не в той директории. Compose автоматически читает `.env` из той же папки, где находится `docker-compose.yml`. Проверь:

```bash
ls -la .env
docker compose config | grep DATABASE_URL   # должен показать собранный URL
```

Если `.env` есть, но переменные пустые — там не заполнены значения, переписанные с `*.example`.

### `web` контейнер постоянно перезапускается

Не должно — у него `restart: "no"`. Если ты видишь в `ps` статус `Restarting` — значит ты используешь старый docker-compose.yml. Проверь:

```bash
grep -A1 'web:' docker-compose.yml | grep restart
# должно показать: restart: "no"
```

### Caddy логирует «hostname not in Caddyfile»

Запрос пришёл на домен, который не описан в `Caddyfile`. Если это «мусорный» трафик от ботов — игнорируй. Если это твой домен, который ты ожидаешь видеть — добавь в `Caddyfile` и `.env`.

---

## 14. Замена лендинга

Заглушка лежит в `landing/index.html` репозитория. Это **не реальный лендинг**, замени его на свой:

- Положи готовый билд (HTML/CSS/JS, или собранный Astro/Next/Hugo) в `landing/`.
- Caddy монтирует `./landing:/srv/landing:ro` — никакой пересборки контейнера не нужно. Достаточно:
  ```bash
  docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
  ```
  (или вообще ничего, статика читается с диска при каждом запросе).

Если хочешь собирать лендинг как отдельный сервис (например, Astro) — сделай по аналогии с `web`: builder-стадия → publisher-стадия → отдельный named volume `landing-dist`, который Caddy монтирует в `/srv/landing`.

---

## 15. Опционально: Caddy на хосте

Если на сервере несколько проектов и хочется один общий Caddy на хосте (а не в docker-compose):

1. Убери сервис `caddy` из `docker-compose.yml`.
2. Опубликуй порты сервисов наружу (на `127.0.0.1` чтобы их не было видно из инета):
   ```yaml
   api:
     ports:
       - "127.0.0.1:4000:4000"
   rustfs:
     ports:
       - "127.0.0.1:9000:9000"
   ```
3. Также понадобится отдать SPA-статику. Простейший вариант — добавить ещё одну publisher-цель в Caddy на хосте через bind mount, либо положить `dist/` куда-то на хост (например, `/var/www/hardhat/dist`) и указать в host-Caddyfile `root * /var/www/hardhat/dist`.
4. Установи Caddy системно (`apt install caddy`), скопируй `caddy/Caddyfile` в `/etc/caddy/Caddyfile`, поправь `reverse_proxy api:4000` → `reverse_proxy 127.0.0.1:4000` и `rustfs:9000` → `127.0.0.1:9000`.
5. `systemctl restart caddy`.

Вариант с Caddy в compose проще и рекомендуется по умолчанию — он самодостаточен и переезжает между серверами одной командой.
