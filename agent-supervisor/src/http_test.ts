import { assertEquals } from "@std/assert";
import { createHandler } from "./http.ts";
import { RunManager } from "./run_manager.ts";
import { CALLBACK_BASE, FakeEngine, RecordingCallbacks, RUN_ID } from "./testing.ts";

const SECRET = "test-secret-test-secret";

function setup() {
  const engine = new FakeEngine();
  const runs = new RunManager(engine, new RecordingCallbacks(), {
    network: "kaska-agent-runs",
    logFlushMs: 5,
    logFlushBytes: 1_000,
  });
  const handler = createHandler({
    secret: SECRET,
    runs,
    rules: {
      allowedImages: ["kaska-agent-runtime:latest"],
      callbackBaseUrl: CALLBACK_BASE,
      caps: { memoryMb: 4096, cpus: 2, pidsLimit: 1024, walltimeSeconds: 3600 },
    },
  });
  return { engine, runs, handler };
}

function request(path: string, options: { body?: unknown; secret?: string; method?: string } = {}) {
  const headers = new Headers({ "content-type": "application/json" });
  if (options.secret !== undefined) headers.set("authorization", `Bearer ${options.secret}`);
  return new Request(`http://supervisor${path}`, {
    method: options.method ?? "POST",
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
}

const startBody = {
  run_id: RUN_ID,
  image: "kaska-agent-runtime:latest",
  env: { KASKA_PAT: "kaska_pat_x" },
  limits: { memory_mb: 1024, cpus: 1, pids_limit: 256, walltime_seconds: 600 },
  callback_url: `${CALLBACK_BASE}/agent_runs/${RUN_ID}`,
};

Deno.test("health is public, everything else needs the secret", async () => {
  const { handler } = setup();

  assertEquals((await handler(request("/health", { method: "GET" }))).status, 200);
  assertEquals((await handler(request("/runs", { body: startBody }))).status, 401);
  assertEquals((await handler(request("/runs", { body: startBody, secret: "wrong" }))).status, 401);
});

Deno.test("start, duplicate start and stop", async () => {
  const { engine, runs, handler } = setup();

  const started = await handler(request("/runs", { body: startBody, secret: SECRET }));
  assertEquals(started.status, 201);
  const { container_id: containerId } = await started.json();
  assertEquals(engine.containers.has(containerId), true);

  const duplicate = await handler(request("/runs", { body: startBody, secret: SECRET }));
  assertEquals(duplicate.status, 409);

  const stopped = await handler(request(`/runs/${RUN_ID}/stop`, { secret: SECRET }));
  assertEquals(stopped.status, 200);
  await runs.idle();

  const unknown = await handler(request(`/runs/${RUN_ID}/stop`, { secret: SECRET }));
  assertEquals(unknown.status, 404);
});

Deno.test("invalid payloads are 422 and engine failures are 502", async () => {
  const { engine, handler } = setup();

  const invalid = await handler(
    request("/runs", { body: { ...startBody, image: "alpine" }, secret: SECRET }),
  );
  assertEquals(invalid.status, 422);

  engine.failStart = true;
  const failed = await handler(request("/runs", { body: startBody, secret: SECRET }));
  assertEquals(failed.status, 502);
  assertEquals(JSON.stringify(await failed.json()).includes("kaska_pat_x"), false);
});
