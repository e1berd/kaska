import type { CallbackSender, ExitReport } from "./callbacks.ts";
import type { ContainerEngine, ContainerSpec, ManagedContainer } from "./engine.ts";
import type { StartRunRequest } from "./payload.ts";

export const RUN_ID = "5d0f6c7e-2a55-4d8e-9f1b-0c3f7f3b8a11";
export const CALLBACK_BASE = "http://api:4000/internal";

export function startRequest(overrides: Partial<StartRunRequest> = {}): StartRunRequest {
  return {
    runId: RUN_ID,
    image: "kaska-agent-runtime:latest",
    env: { KASKA_PAT: "kaska_pat_x" },
    limits: { memoryMb: 512, cpus: 1, pidsLimit: 128, walltimeSeconds: 60 },
    callbackUrl: `${CALLBACK_BASE}/agent_runs/${RUN_ID}`,
    ...overrides,
  };
}

export function dockerFrame(stream: 1 | 2, text: string): Uint8Array {
  const payload = new TextEncoder().encode(text);
  const frame = new Uint8Array(8 + payload.length);
  frame[0] = stream;
  new DataView(frame.buffer).setUint32(4, payload.length);
  frame.set(payload, 8);
  return frame;
}

interface FakeContainer {
  spec: ContainerSpec | null;
  labels: Record<string, string>;
  running: boolean;
  exitCode: number;
  logChunks: Uint8Array[];
  exited: PromiseWithResolvers<number>;
}

export class FakeEngine implements ContainerEngine {
  readonly containers = new Map<string, FakeContainer>();
  readonly removed: string[] = [];
  readonly killed: string[] = [];
  failStart = false;
  #nextId = 1;

  create(spec: ContainerSpec): Promise<string> {
    const id = `c-${this.#nextId++}`;
    this.containers.set(id, this.#container(spec, spec.labels, false));
    return Promise.resolve(id);
  }

  adopt(labels: Record<string, string>, running: boolean): string {
    const id = `c-${this.#nextId++}`;
    const container = this.#container(null, labels, running);
    if (!running) container.exited.resolve(0);
    this.containers.set(id, container);
    return id;
  }

  start(containerId: string): Promise<void> {
    if (this.failStart) return Promise.reject(new Error("no such image"));
    this.#get(containerId).running = true;
    return Promise.resolve();
  }

  emitLogs(containerId: string, ...chunks: Uint8Array[]): void {
    this.#get(containerId).logChunks.push(...chunks);
  }

  exit(containerId: string, code: number): void {
    const container = this.#get(containerId);
    container.running = false;
    container.exited.resolve(code);
  }

  logs(containerId: string): Promise<AsyncIterable<Uint8Array>> {
    const container = this.#get(containerId);
    async function* stream(): AsyncGenerator<Uint8Array> {
      await container.exited.promise;
      yield* container.logChunks;
    }
    return Promise.resolve(stream());
  }

  wait(containerId: string): Promise<number> {
    return this.#get(containerId).exited.promise;
  }

  kill(containerId: string): Promise<boolean> {
    const container = this.#get(containerId);
    if (!container.running) return Promise.resolve(false);
    this.killed.push(containerId);
    this.exit(containerId, 137);
    return Promise.resolve(true);
  }

  remove(containerId: string): Promise<void> {
    this.removed.push(containerId);
    this.containers.delete(containerId);
    return Promise.resolve();
  }

  listManaged(): Promise<ManagedContainer[]> {
    return Promise.resolve(
      [...this.containers.entries()].map(([id, container]) => ({ id, labels: container.labels })),
    );
  }

  #container(
    spec: ContainerSpec | null,
    labels: Record<string, string>,
    running: boolean,
  ): FakeContainer {
    return {
      spec,
      labels,
      running,
      exitCode: 0,
      logChunks: [],
      exited: Promise.withResolvers<number>(),
    };
  }

  #get(containerId: string): FakeContainer {
    const container = this.containers.get(containerId);
    if (!container) throw new Error(`unknown container ${containerId}`);
    return container;
  }
}

export class RecordingCallbacks implements CallbackSender {
  readonly logs: Array<{ url: string; chunk: string }> = [];
  readonly exits: Array<{ url: string; report: ExitReport }> = [];

  sendLogs(url: string, chunk: string): Promise<void> {
    this.logs.push({ url, chunk });
    return Promise.resolve();
  }

  reportExit(url: string, report: ExitReport): Promise<void> {
    this.exits.push({ url, report });
    return Promise.resolve();
  }
}
