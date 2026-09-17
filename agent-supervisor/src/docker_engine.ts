import Docker from "dockerode";
import type { ContainerEngine, ContainerSpec, ManagedContainer } from "./engine.ts";
import { RUN_ID_LABEL } from "./engine.ts";

interface DockerContainer {
  start(): Promise<unknown>;
  logs(options: {
    follow: true;
    stdout: boolean;
    stderr: boolean;
    since: number;
  }): Promise<AsyncIterable<Uint8Array>>;
  wait(): Promise<{ StatusCode: number }>;
  kill(): Promise<unknown>;
  remove(options: { force: boolean; v: boolean }): Promise<unknown>;
}

interface DockerClient {
  createContainer(options: Record<string, unknown>): Promise<{ id: string }>;
  getContainer(id: string): DockerContainer;
  listNetworks(options: { filters: Record<string, string[]> }): Promise<Array<{ Name: string }>>;
  createNetwork(options: Record<string, unknown>): Promise<unknown>;
  listContainers(options: {
    all: boolean;
    filters: Record<string, string[]>;
  }): Promise<Array<{ Id: string; Labels: Record<string, string> }>>;
}

const MIB = 1024 * 1024;
const NOT_RUNNING = 409;
const NOT_FOUND = 404;

export class DockerEngine implements ContainerEngine {
  readonly #docker: DockerClient;

  constructor(socketPath: string) {
    this.#docker = new Docker({ socketPath }) as unknown as DockerClient;
  }

  async ensureNetwork(name: string): Promise<"existing" | "created"> {
    const networks = await this.#docker.listNetworks({ filters: { name: [name] } });
    if (networks.some((network) => network.Name === name)) return "existing";

    await this.#docker.createNetwork({
      Name: name,
      Driver: "bridge",
      Labels: { "space.kaska.purpose": "agent-runs" },
      Options: { "com.docker.network.bridge.enable_icc": "false" },
    });
    return "created";
  }

  async create(spec: ContainerSpec): Promise<string> {
    const container = await this.#docker.createContainer({
      name: spec.name,
      Image: spec.image,
      Env: Object.entries(spec.env).map(([key, value]) => `${key}=${value}`),
      Labels: spec.labels,
      HostConfig: {
        Memory: Math.round(spec.limits.memoryMb * MIB),
        MemorySwap: Math.round(spec.limits.memoryMb * MIB),
        NanoCpus: Math.round(spec.limits.cpus * 1e9),
        PidsLimit: Math.round(spec.limits.pidsLimit),
        ReadonlyRootfs: true,
        Tmpfs: {
          "/tmp": "rw,nosuid,nodev,mode=1777,size=512m",
          "/workspace": "rw,nosuid,nodev,exec,mode=1777,size=4g",
        },
        CapDrop: ["ALL"],
        SecurityOpt: ["no-new-privileges"],
        NetworkMode: spec.network,
        Init: true,
        LogConfig: { Type: "json-file", Config: { "max-size": "10m", "max-file": "1" } },
      },
    });
    return container.id;
  }

  async start(containerId: string): Promise<void> {
    await this.#docker.getContainer(containerId).start();
  }

  logs(containerId: string, sinceSeconds: number): Promise<AsyncIterable<Uint8Array>> {
    return this.#docker.getContainer(containerId).logs({
      follow: true,
      stdout: true,
      stderr: true,
      since: sinceSeconds,
    });
  }

  async wait(containerId: string): Promise<number> {
    const result = await this.#docker.getContainer(containerId).wait();
    return result.StatusCode;
  }

  kill(containerId: string): Promise<boolean> {
    return ignoreStatus(this.#docker.getContainer(containerId).kill(), [NOT_RUNNING, NOT_FOUND]);
  }

  async remove(containerId: string): Promise<void> {
    await ignoreStatus(
      this.#docker.getContainer(containerId).remove({ force: true, v: true }),
      [NOT_FOUND],
    );
  }

  async listManaged(): Promise<ManagedContainer[]> {
    const containers = await this.#docker.listContainers({
      all: true,
      filters: { label: [RUN_ID_LABEL] },
    });
    return containers.map((container) => ({ id: container.Id, labels: container.Labels }));
  }
}

async function ignoreStatus(operation: Promise<unknown>, statuses: number[]): Promise<boolean> {
  try {
    await operation;
    return true;
  } catch (error) {
    const status = (error as { statusCode?: number }).statusCode;
    if (status === undefined || !statuses.includes(status)) throw error;
    return false;
  }
}
