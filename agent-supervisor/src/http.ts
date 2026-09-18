import { errorMessage, RunConflictError } from "./errors.ts";
import type { PayloadRules } from "./payload.ts";
import { isRunId, parseStartRun } from "./payload.ts";
import type { RunManager } from "./run_manager.ts";

export interface HandlerDeps {
  secret: string;
  rules: PayloadRules;
  runs: RunManager;
}

const STOP_PATH = /^\/runs\/([^/]+)\/stop$/;

const patterns: Record<string, URLPattern> = {
  health: new URLPattern({ pathname: "/health" }),
  startRun: new URLPattern({ pathname: "/runs" }),
}

export function createHandler(deps: HandlerDeps): (request: Request) => Promise<Response> {
  return async (request) => {
    const { pathname } = new URL(request.url);

    if (request.method === "GET" && patterns.health.exec(request.url)) {
      return json(200, { ok: true, active_runs: deps.runs.activeCount });
    }

    if (!await authorized(request, deps.secret)) return json(401, { error: "unauthorized" });

    if (request.method === "POST" && patterns.startRun.exec(request.url)) return startRun(request, deps);

    const stopMatch = request.method === "POST" ? STOP_PATH.exec(pathname) : null;
    if (stopMatch) return stopRun(stopMatch[1], deps);

    return json(404, { error: "not_found" });
  };
}

async function startRun(request: Request, deps: HandlerDeps): Promise<Response> {
  const body = await readJson(request);
  const parsed = parseStartRun(body, deps.rules);
  if (!parsed.ok) return json(422, { error: "invalid_payload", details: parsed.errors });

  try {
    const containerId = await deps.runs.start(parsed.value);
    return json(201, { container_id: containerId });
  } catch (error) {
    if (error instanceof RunConflictError) return json(409, { error: "already_running" });
    console.error(`run ${parsed.value.runId} failed to start: ${errorMessage(error)}`);
    return json(502, { error: "container_start_failed" });
  }
}

async function stopRun(runId: string, deps: HandlerDeps): Promise<Response> {
  if (!isRunId(runId)) return json(404, { error: "not_found" });

  try {
    const stopped = await deps.runs.stop(runId);
    return stopped ? json(200, { stopped: true }) : json(404, { error: "not_found" });
  } catch (error) {
    console.error(`run ${runId} failed to stop: ${errorMessage(error)}`);
    return json(502, { error: "container_stop_failed" });
  }
}

async function readJson(request: Request): Promise<unknown> {
  try {
    return await request.json();
  } catch (error) {
    console.warn(`rejected malformed JSON body: ${errorMessage(error)}`);
    return null;
  }
}

async function authorized(request: Request, secret: string): Promise<boolean> {
  const header = request.headers.get("authorization") ?? "";
  if (!header.startsWith("Bearer ")) return false;
  return await constantTimeEqual(header.slice("Bearer ".length).trim(), secret);
}

async function constantTimeEqual(presented: string, expected: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(presented)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const a = new Uint8Array(left);
  const b = new Uint8Array(right);
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}

function json(status: number, body: unknown): Response {
  return Response.json(body, { status });
}
