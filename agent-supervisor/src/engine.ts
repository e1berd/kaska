import type { RunLimits } from "./payload.ts";

export const RUN_ID_LABEL = "space.kaska.run-id";
export const CALLBACK_LABEL = "space.kaska.callback-url";
export const DEADLINE_LABEL = "space.kaska.deadline";

export interface ContainerSpec {
  name: string;
  image: string;
  env: Record<string, string>;
  labels: Record<string, string>;
  limits: RunLimits;
  network: string;
}

export interface ManagedContainer {
  id: string;
  labels: Record<string, string>;
}

export interface ContainerEngine {
  create(spec: ContainerSpec): Promise<string>;
  start(containerId: string): Promise<void>;
  logs(containerId: string, sinceSeconds: number): Promise<AsyncIterable<Uint8Array>>;
  wait(containerId: string): Promise<number>;
  kill(containerId: string): Promise<boolean>;
  remove(containerId: string): Promise<void>;
  listManaged(): Promise<ManagedContainer[]>;
}
