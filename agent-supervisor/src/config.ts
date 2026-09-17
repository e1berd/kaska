export interface SupervisorConfig {
  port: number;
  secret: string;
  dockerSocket: string;
  runnerNetwork: string;
  allowedImages: string[];
  callbackBaseUrl: string;
  caps: LimitCaps;
  logFlushMs: number;
  logFlushBytes: number;
}

export interface LimitCaps {
  memoryMb: number;
  cpus: number;
  pidsLimit: number;
  walltimeSeconds: number;
}

type Env = { get(key: string): string | undefined };

const MIN_SECRET_LENGTH = 16;

export function loadConfig(env: Env = Deno.env): SupervisorConfig {
  const secret = required(env, "SUPERVISOR_SECRET");
  if (secret.length < MIN_SECRET_LENGTH) {
    throw new Error(`SUPERVISOR_SECRET must be at least ${MIN_SECRET_LENGTH} characters`);
  }

  return {
    port: positiveNumber(env, "PORT", 8080),
    secret,
    dockerSocket: env.get("DOCKER_SOCKET") ?? "/var/run/docker.sock",
    runnerNetwork: env.get("RUNNER_NETWORK") ?? "kaska-agent-runs",
    allowedImages: list(env.get("ALLOWED_IMAGES") ?? "kaska-agent-runtime:latest"),
    callbackBaseUrl: required(env, "CALLBACK_BASE_URL").replace(/\/+$/, ""),
    caps: {
      memoryMb: positiveNumber(env, "MAX_MEMORY_MB", 4096),
      cpus: positiveNumber(env, "MAX_CPUS", 2),
      pidsLimit: positiveNumber(env, "MAX_PIDS", 1024),
      walltimeSeconds: positiveNumber(env, "MAX_WALLTIME_SECONDS", 3600),
    },
    logFlushMs: positiveNumber(env, "LOG_FLUSH_MS", 1000),
    logFlushBytes: positiveNumber(env, "LOG_FLUSH_BYTES", 16_000),
  };
}

function required(env: Env, key: string): string {
  const value = env.get(key)?.trim();
  if (!value) throw new Error(`environment variable ${key} is missing`);
  return value;
}

function positiveNumber(env: Env, key: string, fallback: number): number {
  const raw = env.get(key);
  if (raw === undefined || raw.trim() === "") return fallback;
  const value = Number(raw);
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`environment variable ${key} must be a positive number`);
  }
  return value;
}

function list(raw: string): string[] {
  return raw.split(",").map((item) => item.trim()).filter((item) => item !== "");
}
