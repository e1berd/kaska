FROM elixir:1.18-alpine AS builder

RUN apk add --no-cache build-base git

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./

RUN MIX_ENV=prod mix deps.get --only prod

COPY lib ./lib
COPY config ./config
COPY priv ./priv

RUN MIX_ENV=prod mix compile

RUN MIX_ENV=prod mix release


FROM elixir:1.18-alpine AS runner

RUN apk add --no-cache libstdc++ openssl ncurses-libs

RUN adduser -u 1000 -D app

WORKDIR /app

COPY --from=builder --chown=app:app /app/_build/prod/rel/kaska ./

USER app

ENV PHX_SERVER=true

EXPOSE 4000

ENTRYPOINT ["sh", "-c", "bin/kaska eval \"Kaska.Release.migrate()\" && bin/kaska start"]
