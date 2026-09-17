export interface KaskaColumn {
  id: string;
  name: string;
  description: string | null;
}

export interface KaskaProject {
  slug: string;
  name: string;
  description: string | null;
  agent_instructions: string | null;
  columns: KaskaColumn[];
}

export interface KaskaUser {
  id: string;
  display_name: string | null;
}

export interface KaskaComment {
  id: string;
  body: string;
  author: KaskaUser | null;
  guest_name: string | null;
  inserted_at: string;
}

export interface KaskaTask {
  id: string;
  title: string;
  body: string;
  column: KaskaColumn | null;
  assignees: KaskaUser[];
  comments: KaskaComment[];
}

export interface TaskUpdate {
  title?: string;
  body?: string;
}

export interface KaskaApi {
  getProject(): Promise<KaskaProject>;
  getTask(): Promise<KaskaTask>;
  postComment(body: string): Promise<void>;
  moveTask(columnId: string): Promise<KaskaTask>;
  updateTask(update: TaskUpdate): Promise<KaskaTask>;
}

export class KaskaApiError extends Error {
  readonly status: number;

  constructor(method: string, path: string, status: number, detail: string) {
    super(`Kaska API ${method} ${path} failed with ${status}: ${detail}`);
    this.status = status;
  }
}

type Fetch = typeof fetch;

const ERROR_DETAIL_LIMIT = 300;

export class KaskaClient implements KaskaApi {
  readonly #baseUrl: string;
  readonly #token: string;
  readonly #taskPath: string;
  readonly #projectPath: string;
  readonly #fetch: Fetch;

  constructor(options: {
    baseUrl: string;
    token: string;
    projectSlug: string;
    taskId: string;
    fetch?: Fetch;
  }) {
    this.#baseUrl = options.baseUrl;
    this.#token = options.token;
    this.#projectPath = `/p/${encodeURIComponent(options.projectSlug)}`;
    this.#taskPath = `${this.#projectPath}/tasks/${encodeURIComponent(options.taskId)}`;
    this.#fetch = options.fetch ?? fetch;
  }

  async getProject(): Promise<KaskaProject> {
    const response = await this.#request<{ project: KaskaProject }>("GET", this.#projectPath);
    return response.project;
  }

  async getTask(): Promise<KaskaTask> {
    const response = await this.#request<{ task: KaskaTask }>("GET", this.#taskPath);
    return response.task;
  }

  async postComment(body: string): Promise<void> {
    await this.#request("POST", `${this.#taskPath}/comments`, { body });
  }

  async moveTask(columnId: string): Promise<KaskaTask> {
    const response = await this.#request<{ task: KaskaTask }>(
      "POST",
      `${this.#taskPath}/move`,
      { column_id: columnId },
    );
    return response.task;
  }

  async updateTask(update: TaskUpdate): Promise<KaskaTask> {
    const response = await this.#request<{ task: KaskaTask }>("PATCH", this.#taskPath, update);
    return response.task;
  }

  async #request<T>(method: string, path: string, body?: unknown): Promise<T> {
    const response = await this.#fetch(`${this.#baseUrl}${path}`, {
      method,
      headers: {
        "authorization": `Bearer ${this.#token}`,
        "accept": "application/json",
        ...(body === undefined ? {} : { "content-type": "application/json" }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });

    const text = await response.text();
    if (!response.ok) {
      throw new KaskaApiError(method, path, response.status, text.slice(0, ERROR_DETAIL_LIMIT));
    }
    return (text === "" ? {} : JSON.parse(text)) as T;
  }
}
