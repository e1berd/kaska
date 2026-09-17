import type { RuntimeConfig } from "./config.ts";
import { loadConfig, SECRET_ENV_KEYS } from "./config.ts";
import { KaskaClient } from "./kaska.ts";
import type { AgentLoop, Log } from "./outcome.ts";
import { claudeAgentLoop } from "./providers/claude_agent.ts";
import { openAiCompatibleLoop } from "./providers/openai_compatible.ts";
import { runAgent } from "./run.ts";
import type { AgentTool } from "./tools.ts";
import { kaskaTools, workspaceTools } from "./tools.ts";
import { prepareWorkspace, WORKSPACE_GIT_CONFIG } from "./workspace.ts";

const log: Log = (line) => console.log(line);

const config = loadConfig();
for (const key of SECRET_ENV_KEYS) Deno.env.delete(key);

const home = Deno.env.get("HOME") ?? "/tmp/home";
await Deno.mkdir(home, { recursive: true });

const childEnv: Record<string, string> = {
  PATH: Deno.env.get("PATH") ?? "/usr/local/bin:/usr/bin:/bin",
  HOME: home,
  LANG: "C.UTF-8",
  TERM: "dumb",
  GIT_AUTHOR_NAME: "Kaska agent",
  GIT_AUTHOR_EMAIL: "agent@kaska.local",
  GIT_COMMITTER_NAME: "Kaska agent",
  GIT_COMMITTER_EMAIL: "agent@kaska.local",
  ...WORKSPACE_GIT_CONFIG,
};

const kaska = new KaskaClient({
  baseUrl: config.kaskaApiUrl,
  token: config.kaskaPat,
  projectSlug: config.projectSlug,
  taskId: config.taskId,
});

const { loop, tools } = providerSetup(config);

Deno.exit(
  await runAgent({
    kaska,
    loop,
    tools,
    agentPrompt: config.systemPrompt,
    maxTurns: config.maxTurns,
    prepareWorkspace: () => prepareWorkspace(config.workspace),
    log,
  }),
);

function providerSetup(config: RuntimeConfig): { loop: AgentLoop; tools: AgentTool[] } {
  const { provider } = config;
  log(`run: ${config.runId} with ${provider.kind} ${provider.model} via ${provider.authMethod}`);

  if (provider.kind === "anthropic") {
    return {
      loop: claudeAgentLoop({
        model: provider.model,
        apiKey: provider.apiKey,
        authMethod: provider.authMethod,
        baseUrl: provider.baseUrl,
        workspace: config.workspace,
        processEnv: childEnv,
        log,
      }),
      tools: kaskaTools(kaska),
    };
  }

  const baseUrl = provider.kind === "ollama_local" ? `${provider.baseUrl}/v1` : provider.baseUrl;
  return {
    loop: openAiCompatibleLoop({
      baseUrl: baseUrl ?? "",
      apiKey: provider.apiKey,
      model: provider.model,
      log,
    }),
    tools: [...workspaceTools(config.workspace, childEnv), ...kaskaTools(kaska)],
  };
}
