import type { AgentLoop, AgentOutcome, Log } from "../outcome.ts";
import { oneLine } from "../outcome.ts";
import type { AgentTool } from "../tools.ts";
import { invokeTool, toJsonSchema } from "../tools.ts";

export interface OpenAiCompatibleOptions {
  baseUrl: string;
  apiKey: string;
  model: string;
  log: Log;
  fetch?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
}

interface ToolCall {
  id: string;
  type: "function";
  function: { name: string; arguments: string };
}

type ChatMessage =
  | { role: "system" | "user"; content: string }
  | { role: "assistant"; content: string | null; tool_calls?: ToolCall[] }
  | { role: "tool"; tool_call_id: string; content: string };

interface ChatCompletion {
  choices?: Array<{
    finish_reason?: string | null;
    message?: { content?: string | null; tool_calls?: ToolCall[] | null };
  }>;
}

const REQUEST_ATTEMPTS = 4;
const RETRY_BASE_MS = 2_000;
const ERROR_DETAIL_LIMIT = 500;

export class LlmRequestError extends Error {}

export function openAiCompatibleLoop(options: OpenAiCompatibleOptions): AgentLoop {
  const request = options.fetch ?? fetch;
  const sleep = options.sleep ?? ((ms: number) => new Promise((r) => setTimeout(r, ms)));

  async function complete(messages: ChatMessage[], tools: AgentTool[]): Promise<ChatCompletion> {
    const body = JSON.stringify({
      model: options.model,
      messages,
      tools: tools.map((tool) => ({
        type: "function",
        function: {
          name: tool.name,
          description: tool.description,
          parameters: toJsonSchema(tool),
        },
      })),
      tool_choice: "auto",
    });

    for (let attempt = 1; attempt <= REQUEST_ATTEMPTS; attempt++) {
      const response = await request(`${options.baseUrl}/chat/completions`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          ...(options.apiKey ? { "authorization": `Bearer ${options.apiKey}` } : {}),
        },
        body,
      });

      if (response.ok) return await response.json() as ChatCompletion;

      const detail = (await response.text()).slice(0, ERROR_DETAIL_LIMIT);
      const retryable = response.status === 429 || response.status >= 500;
      if (!retryable || attempt === REQUEST_ATTEMPTS) {
        throw new LlmRequestError(`LLM request failed with ${response.status}: ${detail}`);
      }
      options.log(`llm: ${response.status}, retrying (attempt ${attempt + 1})`);
      await sleep(RETRY_BASE_MS * 2 ** (attempt - 1));
    }
    throw new LlmRequestError("LLM request retries exhausted");
  }

  async function executeCall(call: ToolCall, tools: AgentTool[]): Promise<string> {
    const tool = tools.find((candidate) => candidate.name === call.function.name);
    if (!tool) return `error: unknown tool ${call.function.name}`;

    let args: unknown;
    try {
      args = call.function.arguments.trim() === "" ? {} : JSON.parse(call.function.arguments);
    } catch (error) {
      return `error: arguments are not valid JSON (${(error as Error).message})`;
    }

    try {
      return await invokeTool(tool, args);
    } catch (error) {
      return `error: ${error instanceof Error ? error.message : String(error)}`;
    }
  }

  return async ({ systemPrompt, taskPrompt, tools, maxTurns }): Promise<AgentOutcome> => {
    const messages: ChatMessage[] = [
      { role: "system", content: systemPrompt },
      { role: "user", content: taskPrompt },
    ];
    let lastText = "";

    for (let turn = 1; turn <= maxTurns; turn++) {
      const completion = await complete(messages, tools);
      const message = completion.choices?.[0]?.message;
      if (!message) throw new LlmRequestError("LLM response has no choices");

      const text = message.content ?? "";
      const calls = message.tool_calls ?? [];
      if (text.trim() !== "") {
        lastText = text;
        options.log(`turn ${turn}: ${oneLine(text)}`);
      }

      messages.push({
        role: "assistant",
        content: message.content ?? null,
        ...(calls.length > 0 ? { tool_calls: calls } : {}),
      });

      if (calls.length === 0) return { status: "completed", summary: text, turns: turn };

      for (const call of calls) {
        options.log(`turn ${turn}: tool ${call.function.name} ${oneLine(call.function.arguments)}`);
        const result = await executeCall(call, tools);
        messages.push({ role: "tool", tool_call_id: call.id, content: result });
      }
    }

    return { status: "max_turns", summary: lastText, turns: maxTurns };
  };
}
