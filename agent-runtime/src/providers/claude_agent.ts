import type { McpSdkServerConfigWithInstance, SDKMessage } from "@anthropic-ai/claude-agent-sdk";
import { createSdkMcpServer, query, tool } from "@anthropic-ai/claude-agent-sdk";
import type { AgentLoop, AgentOutcome, Log, OutcomeStatus } from "../outcome.ts";
import { oneLine } from "../outcome.ts";
import type { AgentTool } from "../tools.ts";
import { invokeTool } from "../tools.ts";
import type { ClaudeCredentials } from "./claude_credentials.ts";
import { credentialEnv } from "./claude_credentials.ts";

export interface ClaudeAgentOptions extends ClaudeCredentials {
  model: string;
  workspace: string;
  processEnv: Record<string, string>;
  log: Log;
}

const KASKA_SERVER = "kaska";
const BUILT_IN_TOOLS = ["Read", "Write", "Edit", "Bash", "Glob", "Grep"];

export function claudeAgentLoop(options: ClaudeAgentOptions): AgentLoop {
  return async ({ systemPrompt, taskPrompt, tools, maxTurns }): Promise<AgentOutcome> => {
    const stream = query({
      prompt: taskPrompt,
      options: {
        cwd: options.workspace,
        model: options.model,
        tools: BUILT_IN_TOOLS,
        allowedTools: tools.map((agentTool) => `mcp__${KASKA_SERVER}__${agentTool.name}`),
        mcpServers: { [KASKA_SERVER]: kaskaServer(tools) },
        maxTurns,
        permissionMode: "bypassPermissions",
        allowDangerouslySkipPermissions: true,
        settingSources: [],
        systemPrompt: { type: "preset", preset: "claude_code", append: systemPrompt },
        env: {
          ...options.processEnv,
          ...credentialEnv(options),
          CLAUDE_AGENT_SDK_CLIENT_APP: "kaska-agent-runtime/0.1.0",
        },
        stderr: (data) => options.log(`claude: ${oneLine(data, 400)}`),
      },
    });

    for await (const message of stream) {
      logMessage(message, options.log);
      if (message.type === "result") return outcomeFor(message);
    }

    return { status: "failed", summary: "Claude Agent SDK ended without a result", turns: 0 };
  };
}

function kaskaServer(tools: AgentTool[]): McpSdkServerConfigWithInstance {
  return createSdkMcpServer({
    name: KASKA_SERVER,
    tools: tools.map((agentTool) =>
      tool(agentTool.name, agentTool.description, agentTool.shape, async (args) => {
        try {
          return { content: [{ type: "text", text: await invokeTool(agentTool, args) }] };
        } catch (error) {
          const text = `error: ${error instanceof Error ? error.message : String(error)}`;
          return { content: [{ type: "text", text }], isError: true };
        }
      })
    ),
  });
}

function outcomeFor(message: Extract<SDKMessage, { type: "result" }>): AgentOutcome {
  if (message.subtype === "success") {
    return { status: "completed", summary: message.result, turns: message.num_turns };
  }

  const statuses: Record<string, OutcomeStatus> = {
    error_max_turns: "max_turns",
    error_max_budget_usd: "budget_exceeded",
  };
  return {
    status: statuses[message.subtype] ?? "failed",
    summary: `Claude Agent SDK stopped: ${message.subtype}`,
    turns: message.num_turns,
  };
}

function logMessage(message: SDKMessage, log: Log): void {
  if (message.type !== "assistant") return;
  for (const block of message.message.content) {
    if (block.type === "text" && block.text.trim() !== "") log(`claude: ${oneLine(block.text)}`);
    if (block.type === "tool_use") {
      log(`claude: tool ${block.name} ${oneLine(JSON.stringify(block.input))}`);
    }
  }
}
