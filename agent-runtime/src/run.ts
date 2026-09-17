import type { KaskaApi } from "./kaska.ts";
import type { AgentLoop, AgentOutcome, Log } from "./outcome.ts";
import { buildSystemPrompt, buildTaskPrompt } from "./prompt.ts";
import type { AgentTool } from "./tools.ts";

export interface RunDeps {
  kaska: KaskaApi;
  loop: AgentLoop;
  tools: AgentTool[];
  agentPrompt: string;
  maxTurns: number;
  prepareWorkspace: () => Promise<void>;
  log: Log;
}

export const EXIT_SUCCESS = 0;
export const EXIT_FAILURE = 1;

export async function runAgent(deps: RunDeps): Promise<number> {
  let outcome: AgentOutcome;
  try {
    const [project, task] = await Promise.all([deps.kaska.getProject(), deps.kaska.getTask()]);
    deps.log(`run: task "${task.title}" in ${project.slug}`);
    await deps.prepareWorkspace();

    outcome = await deps.loop({
      systemPrompt: buildSystemPrompt(deps.agentPrompt, project),
      taskPrompt: buildTaskPrompt(task),
      tools: deps.tools,
      maxTurns: deps.maxTurns,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    deps.log(`run: failed: ${message}`);
    outcome = { status: "failed", summary: message, turns: 0 };
  }

  deps.log(`run: ${outcome.status} after ${outcome.turns} turn(s)`);
  await postFinalComment(deps, outcome);
  return outcome.status === "completed" ? EXIT_SUCCESS : EXIT_FAILURE;
}

async function postFinalComment(deps: RunDeps, outcome: AgentOutcome): Promise<void> {
  try {
    await deps.kaska.postComment(finalComment(outcome));
  } catch (error) {
    deps.log(`run: final comment failed: ${error instanceof Error ? error.message : error}`);
  }
}

export function finalComment(outcome: AgentOutcome): string {
  const summary = outcome.summary.trim();

  switch (outcome.status) {
    case "completed":
      return summary === "" ? "Прогон завершён, итогового сообщения агент не оставил." : summary;
    case "max_turns":
      return withSummary(`Прогон остановлен: исчерпан лимит ходов (${outcome.turns}).`, summary);
    case "budget_exceeded":
      return withSummary("Прогон остановлен: исчерпан бюджет.", summary);
    case "failed":
      return withSummary("Прогон завершился с ошибкой.", summary);
  }
}

function withSummary(headline: string, summary: string): string {
  return summary === "" ? headline : `${headline}\n\n${summary}`;
}
