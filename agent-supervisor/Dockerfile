FROM denoland/deno:alpine-2.9.4

WORKDIR /app

COPY deno.json deno.lock* ./
COPY src ./src

RUN deno cache src/main.ts

EXPOSE 8080

CMD ["deno", "run", "--allow-net", "--allow-env", "--allow-read", "--allow-write=/var/run/docker.sock", "--allow-sys", "src/main.ts"]
