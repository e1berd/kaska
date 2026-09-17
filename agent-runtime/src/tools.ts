import { dirname } from "@std/path";
import { z } from "zod";
import type { KaskaApi } from "./kaska.ts";
import { resolveInWorkspace } from "./workspace.ts";

export interface AgentTool<Shape extends z.ZodRawShape = z.ZodRawShape> {
  name: string;
  description: string;
  shape: Shape;
  run(args: z.infer<z.ZodObject<Shape>>): Promise<string>;
}

export function defineTool<Shape extends z.ZodRawShape>(tool: AgentTool<Shape>): AgentTool {
  return tool as unknown as AgentTool;
}

export class ToolInputError extends Error {}

export async function invokeTool(tool: AgentTool, rawArgs: unknown): Promise<string> {
  const parsed = z.object(tool.shape).safeParse(rawArgs);
  if (!parsed.success) {
    throw new ToolInputError(
      `invalid arguments for ${tool.name}: ${z.prettifyError(parsed.error)}`,
    );
  }
  return await tool.run(parsed.data);
}

export function toJsonSchema(tool: AgentTool): Record<string, unknown> {
  return z.toJSONSchema(z.object(tool.shape)) as Record<string, unknown>;
}

const OUTPUT_LIMIT = 30_000;
const DEFAULT_READ_LINES = 2_000;
const DEFAULT_BASH_TIMEOUT_SECONDS = 120;
const MAX_BASH_TIMEOUT_SECONDS = 900;
const LIST_LIMIT = 500;
const SKIPPED_DIRECTORIES = new Set([".git", "node_modules", "_build", "deps"]);

export function truncate(text: string, limit = OUTPUT_LIMIT): string {
  if (text.length <= limit) return text;
  const omitted = text.length - limit;
  return `${text.slice(0, limit / 2)}\n… [${omitted} characters omitted] …\n${
    text.slice(-limit / 2)
  }`;
}

export function workspaceTools(root: string, commandEnv: Record<string, string>): AgentTool[] {
  return [
    defineTool({
      name: "read_file",
      description: "Read a UTF-8 text file from the workspace. Returns numbered lines.",
      shape: {
        path: z.string().describe("Path relative to the workspace root."),
        offset: z.number().int().min(1).optional().describe("First line to read (1-based)."),
        limit: z.number().int().min(1).optional().describe("Maximum number of lines."),
      },
      run: async ({ path, offset, limit }) => {
        const text = await Deno.readTextFile(await resolveInWorkspace(root, path));
        const start = (offset ?? 1) - 1;
        const lines = text.split("\n").slice(start, start + (limit ?? DEFAULT_READ_LINES));
        return truncate(lines.map((line, index) => `${start + index + 1}\t${line}`).join("\n"));
      },
    }),
    defineTool({
      name: "write_file",
      description: "Create or overwrite a file in the workspace, creating parent directories.",
      shape: {
        path: z.string().describe("Path relative to the workspace root."),
        content: z.string().describe("Full file content."),
      },
      run: async ({ path, content }) => {
        const target = await resolveInWorkspace(root, path);
        await Deno.mkdir(dirname(target), { recursive: true });
        await Deno.writeTextFile(target, content);
        return `wrote ${content.length} characters to ${path}`;
      },
    }),
    defineTool({
      name: "edit_file",
      description:
        "Replace an exact string in a workspace file. old_string must match exactly once unless replace_all is true.",
      shape: {
        path: z.string(),
        old_string: z.string().min(1),
        new_string: z.string(),
        replace_all: z.boolean().optional(),
      },
      run: async ({ path, old_string, new_string, replace_all }) => {
        const target = await resolveInWorkspace(root, path);
        const text = await Deno.readTextFile(target);
        const occurrences = text.split(old_string).length - 1;
        if (occurrences === 0) throw new ToolInputError(`old_string not found in ${path}`);
        if (occurrences > 1 && !replace_all) {
          throw new ToolInputError(
            `old_string occurs ${occurrences} times in ${path}; add context or set replace_all`,
          );
        }
        await Deno.writeTextFile(target, text.split(old_string).join(new_string));
        return `replaced ${replace_all ? occurrences : 1} occurrence(s) in ${path}`;
      },
    }),
    defineTool({
      name: "list_files",
      description:
        "List files under a workspace directory recursively (skips .git, node_modules, _build, deps).",
      shape: {
        path: z.string().optional().describe("Directory relative to the workspace root."),
      },
      run: async ({ path }) => {
        const start = await resolveInWorkspace(root, path ?? ".");
        const entries: string[] = [];
        await collectEntries(start, start, entries);
        const shown = entries.sort().slice(0, LIST_LIMIT);
        const more = entries.length > LIST_LIMIT ? `\n… ${entries.length - LIST_LIMIT} more` : "";
        return shown.length === 0 ? "(empty)" : shown.join("\n") + more;
      },
    }),
    defineTool({
      name: "bash",
      description:
        "Run a bash command in the workspace root (git, tests, package managers). Returns exit code and combined output.",
      shape: {
        command: z.string().min(1),
        timeout_seconds: z.number().int().min(1).max(MAX_BASH_TIMEOUT_SECONDS).optional(),
      },
      run: ({ command, timeout_seconds }) =>
        runBash(root, command, commandEnv, timeout_seconds ?? DEFAULT_BASH_TIMEOUT_SECONDS),
    }),
  ];
}

async function collectEntries(base: string, directory: string, entries: string[]): Promise<void> {
  for await (const entry of Deno.readDir(directory)) {
    if (entries.length > LIST_LIMIT * 4) return;
    const full = `${directory}/${entry.name}`;
    const relativePath = full.slice(base.length + 1);
    if (entry.isDirectory) {
      if (SKIPPED_DIRECTORIES.has(entry.name)) continue;
      entries.push(`${relativePath}/`);
      await collectEntries(base, full, entries);
    } else {
      entries.push(relativePath);
    }
  }
}

export async function runBash(
  cwd: string,
  command: string,
  env: Record<string, string>,
  timeoutSeconds: number,
): Promise<string> {
  const child = new Deno.Command("bash", {
    args: ["-c", command],
    cwd,
    env,
    clearEnv: true,
    stdin: "null",
    stdout: "piped",
    stderr: "piped",
  }).spawn();

  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    child.kill("SIGKILL");
  }, timeoutSeconds * 1000);

  const output = await child.output();
  clearTimeout(timer);

  const decoder = new TextDecoder();
  const combined = [decoder.decode(output.stdout), decoder.decode(output.stderr)]
    .filter((part) => part !== "")
    .join("\n");
  const status = timedOut ? `timed out after ${timeoutSeconds}s` : `exit code ${output.code}`;
  return truncate(`${status}\n${combined}`);
}

export function kaskaTools(kaska: KaskaApi): AgentTool[] {
  return [
    defineTool({
      name: "get_task",
      description: "Fetch the current task: title, markdown body, column and comments.",
      shape: {},
      run: async () => JSON.stringify(await kaska.getTask(), null, 2),
    }),
    defineTool({
      name: "post_comment",
      description:
        "Post a markdown comment on the current task, e.g. progress, questions or findings.",
      shape: { body: z.string().min(1) },
      run: async ({ body }) => {
        await kaska.postComment(body);
        return "comment posted";
      },
    }),
    defineTool({
      name: "move_task",
      description: "Move the current task to another column of the board by column id.",
      shape: { column_id: z.string().min(1) },
      run: async ({ column_id }) => {
        const task = await kaska.moveTask(column_id);
        return `task moved to ${task.column?.name ?? column_id}`;
      },
    }),
    defineTool({
      name: "update_task",
      description: "Update the current task's title and/or markdown body.",
      shape: { title: z.string().min(1).optional(), body: z.string().optional() },
      run: async ({ title, body }) => {
        if (title === undefined && body === undefined) {
          throw new ToolInputError("provide title or body");
        }
        await kaska.updateTask({ title, body });
        return "task updated";
      },
    }),
  ];
}
