import { assert, assertEquals, assertRejects, assertStringIncludes } from "@std/assert";
import { join } from "@std/path";
import type { AgentTool } from "./tools.ts";
import { invokeTool, toJsonSchema, ToolInputError, truncate, workspaceTools } from "./tools.ts";
import { prepareWorkspace, resolveInWorkspace, WorkspaceEscapeError } from "./workspace.ts";

async function withWorkspace(fn: (root: string, tools: AgentTool[]) => Promise<void>) {
  const root = await Deno.makeTempDir({ prefix: "kaska-ws-" });
  try {
    await fn(root, workspaceTools(root, { PATH: Deno.env.get("PATH") ?? "", VISIBLE: "yes" }));
  } finally {
    await Deno.remove(root, { recursive: true });
  }
}

function byName(tools: AgentTool[], name: string): AgentTool {
  const tool = tools.find((candidate) => candidate.name === name);
  if (!tool) throw new Error(`no tool ${name}`);
  return tool;
}

Deno.test("resolveInWorkspace rejects traversal, absolute paths and symlink escapes", async () => {
  await withWorkspace(async (root) => {
    const realRoot = await Deno.realPath(root);
    assertEquals(await resolveInWorkspace(root, "a/b.txt"), join(realRoot, "a/b.txt"));

    await assertRejects(() => resolveInWorkspace(root, "../outside"), WorkspaceEscapeError);
    await assertRejects(() => resolveInWorkspace(root, "/etc/passwd"), WorkspaceEscapeError);

    await Deno.symlink("/etc", join(root, "link"));
    await assertRejects(() => resolveInWorkspace(root, "link/passwd"), WorkspaceEscapeError);
  });
});

Deno.test("write, read and edit files inside the workspace", async () => {
  await withWorkspace(async (root, tools) => {
    await invokeTool(byName(tools, "write_file"), { path: "src/app.txt", content: "a\nb\na" });

    assertEquals(
      await invokeTool(byName(tools, "read_file"), { path: "src/app.txt", offset: 2 }),
      "2\tb\n3\ta",
    );

    await assertRejects(
      () =>
        invokeTool(byName(tools, "edit_file"), {
          path: "src/app.txt",
          old_string: "a",
          new_string: "c",
        }),
      ToolInputError,
      "occurs 2 times",
    );

    await invokeTool(byName(tools, "edit_file"), {
      path: "src/app.txt",
      old_string: "a",
      new_string: "c",
      replace_all: true,
    });
    assertEquals(await Deno.readTextFile(join(root, "src/app.txt")), "c\nb\nc");

    assertEquals(await invokeTool(byName(tools, "list_files"), {}), "src/\nsrc/app.txt");
  });
});

Deno.test("bash runs in the workspace with only the given environment", async () => {
  Deno.env.set("KASKA_PAT", "kaska_pat_leak");
  try {
    await withWorkspace(async (root, tools) => {
      const output = await invokeTool(byName(tools, "bash"), {
        command: 'pwd; echo "pat=${KASKA_PAT:-none} visible=$VISIBLE"; exit 3',
      });
      assertStringIncludes(output, "exit code 3");
      assertStringIncludes(output, await Deno.realPath(root));
      assertStringIncludes(output, "pat=none visible=yes");
    });
  } finally {
    Deno.env.delete("KASKA_PAT");
  }
});

Deno.test("bash is killed after its timeout", async () => {
  await withWorkspace(async (_root, tools) => {
    const output = await invokeTool(byName(tools, "bash"), {
      command: "sleep 5",
      timeout_seconds: 1,
    });
    assertStringIncludes(output, "timed out after 1s");
  });
});

Deno.test("invalid tool arguments are reported, schemas are JSON Schema objects", async () => {
  await withWorkspace(async (_root, tools) => {
    await assertRejects(
      () => invokeTool(byName(tools, "write_file"), { path: 1 }),
      ToolInputError,
      "invalid arguments for write_file",
    );
    const schema = toJsonSchema(byName(tools, "edit_file"));
    assertEquals(schema.type, "object");
    assertEquals((schema.required as string[]).sort(), ["new_string", "old_string", "path"]);
  });
});

Deno.test("prepareWorkspace initialises a git repository once", async () => {
  await withWorkspace(async (root) => {
    await prepareWorkspace(root);
    await prepareWorkspace(root);
    assert((await Deno.stat(join(root, ".git"))).isDirectory);
  });
});

Deno.test("truncate keeps both ends of long output", () => {
  const text = "a".repeat(50) + "b".repeat(50);
  const result = truncate(text, 20);
  assert(result.startsWith("a".repeat(10)));
  assert(result.endsWith("b".repeat(10)));
  assertStringIncludes(result, "80 characters omitted");
});
