import type { AuthMethod } from "../config.ts";

export interface ClaudeCredentials {
  apiKey: string;
  authMethod: AuthMethod;
  baseUrl: string | null;
}

export function credentialEnv(credentials: ClaudeCredentials): Record<string, string> {
  if (credentials.authMethod === "subscription") {
    return { CLAUDE_CODE_OAUTH_TOKEN: credentials.apiKey };
  }
  return {
    ANTHROPIC_API_KEY: credentials.apiKey,
    ...(credentials.baseUrl ? { ANTHROPIC_BASE_URL: credentials.baseUrl } : {}),
  };
}
