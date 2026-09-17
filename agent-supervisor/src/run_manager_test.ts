import { assert, assertEquals, assertRejects } from "@std/assert";
import { CALLBACK_LABEL, DEADLINE_LABEL, RUN_ID_LABEL } from "./engine.ts";
import { RunConflictError } from "./errors.ts";
import { RunManager } from "./run_manager.ts";
import { dockerFrame, FakeEngine, RecordingCallbacks, RUN_ID, startRequest } from "./testing.ts";

function setup(now = () => 1_000_000) {
  const engine = new FakeEngine();
  const callbacks = new RecordingCallbacks();
  const runs = new RunManager(engine, callbacks, {
    network: "kaska-agent-runs",
    logFlushMs: 5,
    logFlushBytes: 1_000_000,
    now,
  });
  return { engine, callbacks, runs };
}

Deno.test("start creates a labelled, limited container on the runner network", async () => {
  const { engine, runs } = setup();
  const containerId = await runs.start(startRequest());

  const spec = engine.containers.get(containerId)?.spec;
  assertEquals(spec?.network, "kaska-agent-runs");
  assertEquals(spec?.name, `kaska-run-${RUN_ID}`);
  assertEquals(spec?.labels[RUN_ID_LABEL], RUN_ID);
  assertEquals(spec?.labels[DEADLINE_LABEL], String(1_000_000 + 60_000));
  assertEquals(spec?.limits.memoryMb, 512);

  engine.exit(containerId, 0);
  await runs.idle();
});

Deno.test("forwards logs, reports the exit code and removes the container", async () => {
  const { engine, callbacks, runs } = setup();
  const containerId = await runs.start(startRequest());

  engine.emitLogs(containerId, dockerFrame(1, "hello "), dockerFrame(2, "world\n"));
  engine.exit(containerId, 3);
  await runs.idle();

  assertEquals(callbacks.logs.map((entry) => entry.chunk).join(""), "hello world\n");
  assertEquals(callbacks.exits, [{
    url: startRequest().callbackUrl,
    report: { outcome: "exited", exit_code: 3 },
  }]);
  assertEquals(engine.removed, [containerId]);
  assertEquals(runs.activeCount, 0);
});

Deno.test("kills the container on walltime and reports timed_out", async () => {
  const { engine, callbacks, runs } = setup();
  await runs.start(startRequest({ limits: { ...startRequest().limits, walltimeSeconds: 0.01 } }));
  await runs.idle();

  assertEquals(engine.killed.length, 1);
  assertEquals(callbacks.exits[0].report, {
    outcome: "timed_out",
    exit_code: 137,
    reason: "walltime exceeded",
  });
});

Deno.test("a duplicate start for a supervised run conflicts", async () => {
  const { engine, runs } = setup();
  const containerId = await runs.start(startRequest());

  await assertRejects(() => runs.start(startRequest()), RunConflictError);

  engine.exit(containerId, 0);
  await runs.idle();
});

Deno.test("a failed start removes the created container and supervises nothing", async () => {
  const { engine, callbacks, runs } = setup();
  engine.failStart = true;

  await assertRejects(() => runs.start(startRequest()), Error, "no such image");
  assertEquals(engine.removed.length, 1);
  assertEquals(runs.activeCount, 0);
  assertEquals(callbacks.exits, []);
});

Deno.test("stop kills a running container and unknown runs are reported", async () => {
  const { engine, callbacks, runs } = setup();
  const containerId = await runs.start(startRequest());

  assert(await runs.stop(RUN_ID));
  await runs.idle();

  assertEquals(engine.killed, [containerId]);
  assertEquals(callbacks.exits[0].report, { outcome: "exited", exit_code: 137 });
  assertEquals(await runs.stop(RUN_ID), false);
});

Deno.test("a stop that arrives while the container is starting still kills it", async () => {
  const { engine, runs } = setup();
  const starting = runs.start(startRequest());

  assert(await runs.stop(RUN_ID));
  const containerId = await starting;
  await runs.idle();

  assertEquals(engine.killed, [containerId]);
});

Deno.test("recover resumes running containers and reports ones that already exited", async () => {
  const { engine, callbacks, runs } = setup();
  const otherRunId = "0b9c2c55-7f9e-4c55-8f53-6f2d2b0f7f01";
  const labels = (runId: string, deadline: number) => ({
    [RUN_ID_LABEL]: runId,
    [CALLBACK_LABEL]: `http://api:4000/internal/agent_runs/${runId}`,
    [DEADLINE_LABEL]: String(deadline),
  });

  const running = engine.adopt(labels(RUN_ID, 1_000_000 + 60_000), true);
  engine.adopt(labels(otherRunId, 1_000_000 - 1), false);
  const stray = engine.adopt({ [RUN_ID_LABEL]: "garbage" }, false);

  assertEquals(await runs.recover(), 2);
  assert(engine.removed.includes(stray));

  engine.exit(running, 0);
  await runs.idle();

  assertEquals(
    callbacks.exits.map((entry) => entry.report.outcome).sort(),
    ["exited", "exited"],
  );
  assertEquals(engine.killed, []);
});
