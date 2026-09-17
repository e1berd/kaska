import { dirname, isAbsolute, join, normalize, relative, SEPARATOR } from "@std/path";

export class WorkspaceEscapeError extends Error {
  constructor(path: string) {
    super(`path ${path} is outside the workspace`);
  }
}

export async function resolveInWorkspace(root: string, path: string): Promise<string> {
  const realRoot = await Deno.realPath(root);
  const candidate = normalize(isAbsolute(path) ? path : join(realRoot, path));
  const anchor = await realPathOfNearestExisting(candidate);
  const resolved = join(anchor.real, relative(anchor.path, candidate));

  if (resolved !== realRoot && !resolved.startsWith(realRoot + SEPARATOR)) {
    throw new WorkspaceEscapeError(path);
  }
  return resolved;
}

async function realPathOfNearestExisting(path: string): Promise<{ path: string; real: string }> {
  let current = path;
  while (true) {
    try {
      return { path: current, real: await Deno.realPath(current) };
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
      const parent = dirname(current);
      if (parent === current) throw error;
      current = parent;
    }
  }
}

export const WORKSPACE_GIT_CONFIG: Record<string, string> = {
  GIT_CONFIG_COUNT: "1",
  GIT_CONFIG_KEY_0: "safe.directory",
  GIT_CONFIG_VALUE_0: "*",
};

export async function prepareWorkspace(root: string): Promise<void> {
  await Deno.mkdir(root, { recursive: true });
  const gitDir = join(root, ".git");
  if (await exists(gitDir)) return;

  const init = await new Deno.Command("git", {
    args: ["init", "--quiet", "--initial-branch=main"],
    cwd: root,
    env: WORKSPACE_GIT_CONFIG,
    stdout: "null",
    stderr: "piped",
  }).output();
  if (!init.success) {
    throw new Error(`git init failed: ${new TextDecoder().decode(init.stderr).trim()}`);
  }
}

async function exists(path: string): Promise<boolean> {
  try {
    await Deno.stat(path);
    return true;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false;
    throw error;
  }
}
