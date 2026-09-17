import type { AgentTool } from "./tools.ts";

export type OutcomeStatus = "completed" | "max_turns" | "budget_exceeded" | "failed";

export interface AgentOutcome {
  status: OutcomeStatus;
  summary: string;
  turns: number;
}

export interface LoopInput {
  systemPrompt: string;
  taskPrompt: string;
  tools: AgentTool[];
  maxTurns: number;
}

export type AgentLoop = (input: LoopInput) => Promise<AgentOutcome>;

export type Log = (line: string) => void;

export function oneLine(text: string, limit = 160): string {
  const flat = text.replace(/\s+/g, " ").trim();
  return flat.length <= limit ? flat : `${flat.slice(0, limit)}…`;
}
