import type { LimitCaps } from "./config.ts";

export interface RunLimits {
  memoryMb: number;
  cpus: number;
  pidsLimit: number;
  walltimeSeconds: number;
}

export interface StartRunRequest {
  runId: string;
  image: string;
  env: Record<string, string>;
  limits: RunLimits;
  callbackUrl: string;
}

export interface PayloadRules {
  allowedImages: string[];
  callbackBaseUrl: string;
  caps: LimitCaps;
}

export type Validation<T> = { ok: true; value: T } | { ok: false; errors: string[] };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ENV_KEY = /^[A-Z_][A-Z0-9_]*$/;

export function isRunId(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}

export function parseStartRun(body: unknown, rules: PayloadRules): Validation<StartRunRequest> {
  if (!isRecord(body)) return { ok: false, errors: ["body must be a JSON object"] };

  const errors: string[] = [];
  const runId = body.run_id;
  if (!isRunId(runId)) errors.push("run_id must be a UUID");

  const image = body.image;
  if (typeof image !== "string" || !rules.allowedImages.includes(image)) {
    errors.push("image is not allowed");
  }

  const env = parseEnv(body.env, errors);
  const limits = parseLimits(body.limits, rules.caps, errors);

  const callbackUrl = body.callback_url;
  const expectedCallback = isRunId(runId) ? `${rules.callbackBaseUrl}/agent_runs/${runId}` : null;
  if (callbackUrl !== expectedCallback) {
    errors.push("callback_url must point at this run under the configured callback base");
  }

  if (errors.length > 0 || !env || !limits) return { ok: false, errors };

  return {
    ok: true,
    value: {
      runId: runId as string,
      image: image as string,
      env,
      limits,
      callbackUrl: callbackUrl as string,
    },
  };
}

function parseEnv(raw: unknown, errors: string[]): Record<string, string> | null {
  if (!isRecord(raw)) {
    errors.push("env must be an object");
    return null;
  }

  const env: Record<string, string> = {};
  for (const [key, value] of Object.entries(raw)) {
    if (!ENV_KEY.test(key) || typeof value !== "string") {
      errors.push(`env entry ${ENV_KEY.test(key) ? key : "(invalid key)"} must be a string`);
      continue;
    }
    env[key] = value;
  }
  return env;
}

function parseLimits(raw: unknown, caps: LimitCaps, errors: string[]): RunLimits | null {
  if (!isRecord(raw)) {
    errors.push("limits must be an object");
    return null;
  }

  const limits = {
    memoryMb: boundedNumber(raw.memory_mb, "limits.memory_mb", caps.memoryMb, errors),
    cpus: boundedNumber(raw.cpus, "limits.cpus", caps.cpus, errors),
    pidsLimit: boundedNumber(raw.pids_limit, "limits.pids_limit", caps.pidsLimit, errors),
    walltimeSeconds: boundedNumber(
      raw.walltime_seconds,
      "limits.walltime_seconds",
      caps.walltimeSeconds,
      errors,
    ),
  };

  return Object.values(limits).every((value) => value !== null) ? limits as RunLimits : null;
}

function boundedNumber(value: unknown, name: string, max: number, errors: string[]): number | null {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    errors.push(`${name} must be a positive number`);
    return null;
  }
  if (value > max) {
    errors.push(`${name} exceeds the supervisor cap of ${max}`);
    return null;
  }
  return value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
