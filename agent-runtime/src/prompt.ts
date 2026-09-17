import type { KaskaProject, KaskaTask } from "./kaska.ts";

const RECENT_COMMENTS = 20;

const RUNNER_INSTRUCTIONS =
  `You are an autonomous agent working on one task from a Kaska project board.
You run inside a disposable container. Your working directory is a git repository at the workspace root;
change files only inside it. Nobody watches the run live, so do not ask for confirmation — make reasonable
decisions, verify your work (run the relevant commands or tests), and record what you did.

Use the Kaska tools to talk to the board: post a comment when you reach a meaningful milestone, hit a blocker,
or need a human decision; move the task between columns only as the project instructions describe.
Write comments in the language the task is written in.

When you are done, reply with a concise final summary: what changed, how you verified it, and what is left.
That summary is posted on the task automatically, so do not post it as a separate comment.`;

export function buildSystemPrompt(agentPrompt: string, project: KaskaProject): string {
  const sections = [RUNNER_INSTRUCTIONS];

  if (agentPrompt.trim() !== "") {
    sections.push(`## Your role\n\n${agentPrompt.trim()}`);
  }

  sections.push(
    `## Project "${project.name}" (${project.slug})${
      project.description ? `\n\n${project.description}` : ""
    }`,
  );

  if (project.agent_instructions?.trim()) {
    sections.push(`## Project instructions for agents\n\n${project.agent_instructions.trim()}`);
  }

  const columns = project.columns
    .map((column) =>
      `- ${column.name} (id: ${column.id})${column.description ? ` — ${column.description}` : ""}`
    )
    .join("\n");
  sections.push(`## Board columns, left to right\n\n${columns}`);

  return sections.join("\n\n");
}

export function buildTaskPrompt(task: KaskaTask): string {
  const comments = task.comments.slice(-RECENT_COMMENTS).map((comment) => {
    const author = comment.author?.display_name ?? comment.guest_name ?? "unknown";
    return `### ${author}, ${comment.inserted_at}\n\n${comment.body}`;
  });

  return [
    `# Task: ${task.title}`,
    `Column: ${task.column?.name ?? "unknown"}`,
    task.body.trim() === "" ? "(the task has no description)" : task.body.trim(),
    comments.length === 0 ? "## Comments\n\n(none)" : `## Comments\n\n${comments.join("\n\n")}`,
    "Work on this task now.",
  ].join("\n\n");
}
