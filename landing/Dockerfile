FROM node:24-alpine AS builder

RUN corepack enable && corepack prepare pnpm@11 --activate

WORKDIR /app

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./

RUN pnpm install --frozen-lockfile

COPY . .

RUN pnpm build


FROM alpine:3 AS dist

COPY --from=builder /app/dist /dist

CMD ["sh", "-c", "set -e; find /export -mindepth 1 -delete 2>/dev/null || true; cp -a /dist/. /export/; echo 'landing assets published to /export'"]
