export type ProviderKind = "anthropic" | "openai_compatible" | "ollama_local";

export type AuthMethod = "api_key" | "subscription";

export interface ProviderConfig {
  kind: ProviderKind;
  authMethod: AuthMethod;
  baseUrl: string | null;
  model: string;
  apiKey: string;
}

export interface RuntimeConfig {
  kaskaApiUrl: string;
  kaskaPat: string;
  runId: string;
  taskId: string;
  projectSlug: string;
  provider: ProviderConfig;
  systemPrompt: string;
  maxTurns: number;
  workspace: string;
}

type Env = { get(key: string): string | undefined };

const PROVIDER_KINDS: ProviderKind[] = ["anthropic", "openai_compatible", "ollama_local"];
const AUTH_METHODS: AuthMethod[] = ["api_key", "subscription"];

export const SECRET_ENV_KEYS = ["KASKA_PAT", "LLM_API_KEY"] as const;

export function loadConfig(env: Env = Deno.env): RuntimeConfig {
  const kind = required(env, "LLM_PROVIDER_KIND");
  if (!PROVIDER_KINDS.includes(kind as ProviderKind)) {
    throw new Error(`LLM_PROVIDER_KIND must be one of ${PROVIDER_KINDS.join(", ")}`);
  }

  const authMethod = optional(env, "LLM_AUTH_METHOD") ?? "api_key";
  if (!AUTH_METHODS.includes(authMethod as AuthMethod)) {
    throw new Error(`LLM_AUTH_METHOD must be one of ${AUTH_METHODS.join(", ")}`);
  }
  if (authMethod === "subscription" && kind !== "anthropic") {
    throw new Error("LLM_AUTH_METHOD subscription is only supported for anthropic");
  }
  if (authMethod === "subscription" && !optional(env, "LLM_API_KEY")) {
    throw new Error("LLM_API_KEY must hold the Claude OAuth token for subscription auth");
  }

  const baseUrl = optional(env, "LLM_BASE_URL");
  if (kind !== "anthropic" && !baseUrl) {
    throw new Error(`LLM_BASE_URL is required for ${kind}`);
  }

  return {
    kaskaApiUrl: required(env, "KASKA_API_URL").replace(/\/+$/, ""),
    kaskaPat: required(env, "KASKA_PAT"),
    runId: required(env, "KASKA_RUN_ID"),
    taskId: required(env, "TASK_ID"),
    projectSlug: required(env, "PROJECT_SLUG"),
    provider: {
      kind: kind as ProviderKind,
      authMethod: authMethod as AuthMethod,
      baseUrl: baseUrl?.replace(/\/+$/, "") ?? null,
      model: required(env, "LLM_MODEL"),
      apiKey: optional(env, "LLM_API_KEY") ?? "",
    },
    systemPrompt: optional(env, "SYSTEM_PROMPT") ?? "",
    maxTurns: positiveInteger(env, "MAX_TURNS", 60),
    workspace: optional(env, "WORKSPACE_DIR") ?? "/workspace",
  };
}

function required(env: Env, key: string): string {
  const value = optional(env, key);
  if (!value) throw new Error(`environment variable ${key} is missing`);
  return value;
}

function optional(env: Env, key: string): string | undefined {
  const value = env.get(key)?.trim();
  return value ? value : undefined;
}

function positiveInteger(env: Env, key: string, fallback: number): number {
  const raw = optional(env, key);
  if (raw === undefined) return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`environment variable ${key} must be a positive integer`);
  }
  return value;
}
