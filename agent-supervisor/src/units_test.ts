import { assertEquals, assertRejects } from "@std/assert";
import { CallbackClient } from "./callbacks.ts";
import { loadConfig } from "./config.ts";
import { DockerFrameDecoder } from "./docker_frames.ts";
import { LogBatcher } from "./log_batcher.ts";
import { parseStartRun } from "./payload.ts";
import { CALLBACK_BASE, dockerFrame, RUN_ID } from "./testing.ts";

const rules = {
  allowedImages: ["kaska-agent-runtime:latest"],
  callbackBaseUrl: CALLBACK_BASE,
  caps: { memoryMb: 4096, cpus: 2, pidsLimit: 1024, walltimeSeconds: 3600 },
};

function validBody(): Record<string, unknown> {
  return {
    run_id: RUN_ID,
    image: "kaska-agent-runtime:latest",
    env: { KASKA_PAT: "kaska_pat_x", LLM_MODEL: "deepseek-chat" },
    limits: { memory_mb: 2048, cpus: 1, pids_limit: 512, walltime_seconds: 1800 },
    callback_url: `${CALLBACK_BASE}/agent_runs/${RUN_ID}`,
  };
}

Deno.test("frame decoder reassembles frames split across chunks", () => {
  const decoder = new DockerFrameDecoder();
  const bytes = new Uint8Array([...dockerFrame(1, "out"), ...dockerFrame(2, "err")]);

  const first = decoder.push(bytes.slice(0, 5));
  const rest = decoder.push(bytes.slice(5));

  assertEquals(first, []);
  assertEquals(
    rest.map((frame) => [frame.stream, new TextDecoder().decode(frame.payload)]),
    [["stdout", "out"], ["stderr", "err"]],
  );
});

Deno.test("log batcher flushes by size and on close, in order", async () => {
  const sent: string[] = [];
  const batcher = new LogBatcher((chunk) => {
    sent.push(chunk);
    return Promise.resolve();
  }, { flushMs: 60_000, flushBytes: 4 });

  batcher.push("ab");
  batcher.push("cd");
  batcher.push("e");
  await batcher.close();

  assertEquals(sent, ["abcd", "e"]);
});

Deno.test("parseStartRun accepts a valid payload", () => {
  const parsed = parseStartRun(validBody(), rules);
  assertEquals(parsed.ok, true);
  if (parsed.ok) {
    assertEquals(parsed.value.limits, {
      memoryMb: 2048,
      cpus: 1,
      pidsLimit: 512,
      walltimeSeconds: 1800,
    });
  }
});

Deno.test("parseStartRun rejects foreign images, over-cap limits, bad env and callbacks", () => {
  const cases: Array<[Record<string, unknown>, string]> = [
    [{ ...validBody(), image: "alpine:latest" }, "image is not allowed"],
    [
      { ...validBody(), limits: { ...validBody().limits as object, memory_mb: 99_999 } },
      "limits.memory_mb exceeds the supervisor cap of 4096",
    ],
    [{ ...validBody(), env: { "bad-key": "x" } }, "env entry (invalid key) must be a string"],
    [
      { ...validBody(), callback_url: "http://evil.example/agent_runs/x" },
      "callback_url must point at this run under the configured callback base",
    ],
    [{ ...validBody(), run_id: "nope" }, "run_id must be a UUID"],
  ];

  for (const [body, expected] of cases) {
    const parsed = parseStartRun(body, rules);
    assertEquals(parsed.ok ? [] : parsed.errors.includes(expected), true, expected);
  }
});

Deno.test("callback client retries server errors and stops on conflict", async () => {
  const statuses = [500, 503, 409];
  const calls: Array<{ url: string; auth: string | null }> = [];
  const client = new CallbackClient(
    "secret-secret-secret",
    (input, init) => {
      calls.push({ url: String(input), auth: new Headers(init?.headers).get("authorization") });
      return Promise.resolve(new Response(null, { status: statuses.shift() }));
    },
    () => Promise.resolve(),
  );

  await client.reportExit("http://api/internal/agent_runs/x", { outcome: "exited", exit_code: 0 });

  assertEquals(calls.length, 3);
  assertEquals(calls[0].url, "http://api/internal/agent_runs/x/exit");
  assertEquals(calls[0].auth, "Bearer secret-secret-secret");
});

Deno.test("callback client gives up after its attempts", async () => {
  const client = new CallbackClient(
    "secret-secret-secret",
    () => Promise.reject(new TypeError("connection refused")),
    () => Promise.resolve(),
  );

  await assertRejects(
    () => client.sendLogs("http://api/internal/agent_runs/x", "line"),
    Error,
    "failed after 3 attempts",
  );
});

Deno.test("config requires a strong secret and a callback base", () => {
  const env = (values: Record<string, string | undefined>) => ({
    get: (key: string) => values[key],
  });

  assertEquals(
    loadConfig(
      env({ SUPERVISOR_SECRET: "x".repeat(32), CALLBACK_BASE_URL: "http://api/internal/" }),
    )
      .callbackBaseUrl,
    "http://api/internal",
  );
  for (const values of [{ CALLBACK_BASE_URL: "http://api" }, { SUPERVISOR_SECRET: "short" }]) {
    let failed = false;
    try {
      loadConfig(env(values));
    } catch (error) {
      failed = error instanceof Error;
    }
    assertEquals(failed, true);
  }
});
