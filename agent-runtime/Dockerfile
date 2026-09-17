FROM denoland/deno:debian-2.9.4

RUN apt-get update \
  && apt-get install -y --no-install-recommends bash ca-certificates curl git ripgrep \
  && rm -rf /var/lib/apt/lists/*

ENV DENO_DIR=/opt/deno-dir \
  DENO_NO_UPDATE_CHECK=1 \
  HOME=/tmp/home \
  WORKSPACE_DIR=/workspace

WORKDIR /app

COPY deno.json deno.lock ./
RUN deno install --frozen

COPY src ./src
RUN deno cache --frozen src/main.ts \
  && chmod -R a+rX /app /opt/deno-dir

USER deno
WORKDIR /workspace

ENTRYPOINT []

CMD ["deno", "run", "--allow-all", "--cached-only", "--frozen", "--no-prompt", "/app/src/main.ts"]
