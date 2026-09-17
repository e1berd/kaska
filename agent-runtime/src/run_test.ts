import { assertEquals, assertStringIncludes } from "@std/assert";
import { loadConfig } from "./config.ts";
import type { KaskaApi, KaskaProject, KaskaTask, TaskUpdate } from "./kaska.ts";
import { KaskaApiError, KaskaClient } from "./kaska.ts";
import type { LoopInput } from "./outcome.ts";
import { buildSystemPrompt, buildTaskPrompt } from "./prompt.ts";
import { credentialEnv } from "./providers/claude_credentials.ts";
import { openAiCompatibleLoop } from "./providers/openai_compatible.ts";
import { runAgent } from "./run.ts";
import { kaskaTools } from "./tools.ts";

const project: KaskaProject = {
  slug: "kaska",
  name: "Kaska",
  description: null,
  agent_instructions: "Move finished tasks to ready to prod.",
  columns: [
    { id: "col-todo", name: "todo", description: "waiting" },
    { id: "col-ready", name: "ready to prod", description: null },
  ],
};

const task: KaskaTask = {
  id: "task-1",
  title: "Add health check",
  body: "Please add /health.",
  column: project.columns[0],
  assignees: [],
  comments: [{
    id: "c1",
    body: "Remember the tests",
    author: { id: "u1", display_name: "Owner" },
    guest_name: null,
    inserted_at: "2026-09-17T10:00:00Z",
  }],
};

class FakeKaska implements KaskaApi {
  comments: string[] = [];
  moves: string[] = [];
  updates: TaskUpdate[] = [];
  failTask = false;

  getProject() {
    return Promise.resolve(project);
  }
  getTask() {
    return this.failTask
      ? Promise.reject(new KaskaApiError("GET", "/p/kaska/tasks/task-1", 404, "not_found"))
      : Promise.resolve(task);
  }
  postComment(body: string) {
    this.comments.push(body);
    return Promise.resolve();
  }
  moveTask(columnId: string) {
    this.moves.push(columnId);
    return Promise.resolve({ ...task, column: project.columns[1] });
  }
  updateTask(update: TaskUpdate) {
    this.updates.push(update);
    return Promise.resolve(task);
  }
}

function completion(message: Record<string, unknown>): Response {
  return Response.json({ choices: [{ message }] });
}

Deno.test("prompts carry agent role, project instructions, columns and comments", () => {
  const system = buildSystemPrompt("You are a careful backend engineer.", project);
  assertStringIncludes(system, "careful backend engineer");
  assertStringIncludes(system, "Move finished tasks to ready to prod.");
  assertStringIncludes(system, "- ready to prod (id: col-ready)");

  const prompt = buildTaskPrompt(task);
  assertStringIncludes(prompt, "# Task: Add health check");
  assertStringIncludes(prompt, "### Owner, 2026-09-17T10:00:00Z\n\nRemember the tests");
});

Deno.test("openai-compatible loop executes tool calls and returns the final text", async () => {
  const kaska = new FakeKaska();
  const requests: Array<Record<string, unknown>> = [];
  const responses = [
    completion({
      content: null,
      tool_calls: [
        {
          id: "call_1",
          type: "function",
          function: { name: "move_task", arguments: '{"column_id":"col-ready"}' },
        },
        { id: "call_2", type: "function", function: { name: "nope", arguments: "{}" } },
      ],
    }),
    new Response("overloaded", { status: 503 }),
    completion({ content: "Done: moved the task." }),
  ];

  const loop = openAiCompatibleLoop({
    baseUrl: "https://llm.example/v1",
    apiKey: "sk-test",
    model: "deepseek-chat",
    log: () => {},
    sleep: () => Promise.resolve(),
    fetch: async (input, init) => {
      assertEquals(String(input), "https://llm.example/v1/chat/completions");
      assertEquals(new Headers(init?.headers).get("authorization"), "Bearer sk-test");
      requests.push(JSON.parse(String(init?.body)));
      return await Promise.resolve(responses.shift() as Response);
    },
  });

  const outcome = await loop({
    systemPrompt: "system",
    taskPrompt: "task",
    tools: kaskaTools(kaska),
    maxTurns: 5,
  });

  assertEquals(outcome, { status: "completed", summary: "Done: moved the task.", turns: 2 });
  assertEquals(kaska.moves, ["col-ready"]);

  const toolMessages = (requests[2].messages as Array<Record<string, unknown>>)
    .filter((message) => message.role === "tool");
  assertEquals(toolMessages.map((message) => message.content), [
    "task moved to ready to prod",
    "error: unknown tool nope",
  ]);
  assertEquals((requests[0].tools as unknown[]).length, 4);
});

Deno.test("openai-compatible loop stops at max turns", async () => {
  const loop = openAiCompatibleLoop({
    baseUrl: "https://llm.example/v1",
    apiKey: "",
    model: "m",
    log: () => {},
    fetch: () =>
      Promise.resolve(completion({
        content: "still working",
        tool_calls: [{ id: "c", type: "function", function: { name: "get_task", arguments: "" } }],
      })),
  });

  const outcome = await loop({
    systemPrompt: "s",
    taskPrompt: "t",
    tools: kaskaTools(new FakeKaska()),
    maxTurns: 2,
  });
  assertEquals(outcome, { status: "max_turns", summary: "still working", turns: 2 });
});

Deno.test("runAgent posts the summary and exits 0 on completion", async () => {
  const kaska = new FakeKaska();
  const seen: LoopInput[] = [];

  const code = await runAgent({
    kaska,
    loop: (input) => {
      seen.push(input);
      return Promise.resolve({ status: "completed", summary: "Added /health.", turns: 3 });
    },
    tools: [],
    agentPrompt: "",
    maxTurns: 7,
    prepareWorkspace: () => Promise.resolve(),
    log: () => {},
  });

  assertEquals(code, 0);
  assertEquals(kaska.comments, ["Added /health."]);
  assertEquals(seen[0].maxTurns, 7);
  assertStringIncludes(seen[0].taskPrompt, "Add health check");
});

Deno.test("runAgent reports max turns and failures with exit 1", async () => {
  const limited = new FakeKaska();
  const limitedCode = await runAgent({
    kaska: limited,
    loop: () => Promise.resolve({ status: "max_turns", summary: "half done", turns: 7 }),
    tools: [],
    agentPrompt: "",
    maxTurns: 7,
    prepareWorkspace: () => Promise.resolve(),
    log: () => {},
  });
  assertEquals(limitedCode, 1);
  assertEquals(limited.comments, [
    "Прогон остановлен: исчерпан лимит ходов (7).\n\nhalf done",
  ]);

  const broken = new FakeKaska();
  broken.failTask = true;
  const brokenCode = await runAgent({
    kaska: broken,
    loop: () => Promise.reject(new Error("must not run")),
    tools: [],
    agentPrompt: "",
    maxTurns: 7,
    prepareWorkspace: () => Promise.resolve(),
    log: () => {},
  });
  assertEquals(brokenCode, 1);
  assertStringIncludes(broken.comments[0], "Прогон завершился с ошибкой.");
  assertStringIncludes(broken.comments[0], "404");
});

Deno.test("KaskaClient scopes requests to the run's task and surfaces API errors", async () => {
  const calls: string[] = [];
  const client = new KaskaClient({
    baseUrl: "https://app.kaska.space/api/v1",
    token: "kaska_pat_x",
    projectSlug: "kaska",
    taskId: "task-1",
    fetch: (input, init) => {
      calls.push(`${init?.method} ${input} ${init?.body ?? ""}`);
      assertEquals(new Headers(init?.headers).get("authorization"), "Bearer kaska_pat_x");
      return Promise.resolve(
        String(input).endsWith("/move")
          ? new Response("forbidden", { status: 403 })
          : Response.json({ task }),
      );
    },
  });

  await client.postComment("hi");
  let error: unknown;
  try {
    await client.moveTask("col-ready");
  } catch (caught) {
    error = caught;
  }

  assertEquals(calls, [
    'POST https://app.kaska.space/api/v1/p/kaska/tasks/task-1/comments {"body":"hi"}',
    'POST https://app.kaska.space/api/v1/p/kaska/tasks/task-1/move {"column_id":"col-ready"}',
  ]);
  assertEquals((error as KaskaApiError).status, 403);
});

Deno.test("loadConfig validates the provider and requires base urls for non-anthropic", () => {
  const base: Record<string, string> = {
    KASKA_API_URL: "https://app.kaska.space/api/v1/",
    KASKA_PAT: "kaska_pat_x",
    KASKA_RUN_ID: "run",
    TASK_ID: "task",
    PROJECT_SLUG: "kaska",
    LLM_PROVIDER_KIND: "anthropic",
    LLM_MODEL: "claude-opus-5",
    LLM_API_KEY: "sk-ant",
    LLM_BASE_URL: "",
    MAX_TURNS: "40",
  };
  const env = (values: Record<string, string>) => ({ get: (key: string) => values[key] });

  const config = loadConfig(env(base));
  assertEquals(config.kaskaApiUrl, "https://app.kaska.space/api/v1");
  assertEquals(config.provider.baseUrl, null);
  assertEquals(config.provider.authMethod, "api_key");
  assertEquals(config.maxTurns, 40);

  const subscription = loadConfig(env({ ...base, LLM_AUTH_METHOD: "subscription" }));
  assertEquals(subscription.provider.authMethod, "subscription");

  for (
    const broken of <Record<string, string>[]> [
      { LLM_PROVIDER_KIND: "openai_compatible" },
      { LLM_PROVIDER_KIND: "x" },
      { LLM_AUTH_METHOD: "cookie" },
      { LLM_AUTH_METHOD: "subscription", LLM_API_KEY: "" },
      {
        LLM_AUTH_METHOD: "subscription",
        LLM_PROVIDER_KIND: "openai_compatible",
        LLM_BASE_URL: "https://x",
      },
    ]
  ) {
    let failed = false;
    try {
      loadConfig(env({ ...base, ...broken }));
    } catch (caught) {
      failed = caught instanceof Error;
    }
    assertEquals(failed, true);
  }
});

Deno.test("claude credentials go to the api key or the subscription oauth token", () => {
  assertEquals(
    credentialEnv({ apiKey: "sk-ant", authMethod: "api_key", baseUrl: "https://proxy" }),
    { ANTHROPIC_API_KEY: "sk-ant", ANTHROPIC_BASE_URL: "https://proxy" },
  );
  assertEquals(
    credentialEnv({ apiKey: "sk-ant-oat", authMethod: "subscription", baseUrl: "https://proxy" }),
    { CLAUDE_CODE_OAUTH_TOKEN: "sk-ant-oat" },
  );
});
