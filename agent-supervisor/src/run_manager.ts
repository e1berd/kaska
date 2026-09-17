import type { CallbackSender, ExitReport } from "./callbacks.ts";
import { DockerFrameDecoder } from "./docker_frames.ts";
import type { ContainerEngine } from "./engine.ts";
import { CALLBACK_LABEL, DEADLINE_LABEL, RUN_ID_LABEL } from "./engine.ts";
import { errorMessage, RunConflictError } from "./errors.ts";
import { LogBatcher } from "./log_batcher.ts";
import type { StartRunRequest } from "./payload.ts";
import { isRunId } from "./payload.ts";

export interface RunManagerOptions {
  network: string;
  logFlushMs: number;
  logFlushBytes: number;
  now?: () => number;
}

interface SupervisedRun {
  runId: string;
  containerId: string;
  callbackUrl: string;
  deadline: number;
  expiry: Promise<boolean> | null;
  done: Promise<void>;
}

const WALLTIME_EXCEEDED = "walltime exceeded";

export class RunManager {
  readonly #runs = new Map<string, SupervisedRun>();
  readonly #starting = new Set<string>();
  readonly #stopRequested = new Set<string>();
  readonly #engine: ContainerEngine;
  readonly #callbacks: CallbackSender;
  readonly #options: RunManagerOptions;
  readonly #now: () => number;

  constructor(engine: ContainerEngine, callbacks: CallbackSender, options: RunManagerOptions) {
    this.#engine = engine;
    this.#callbacks = callbacks;
    this.#options = options;
    this.#now = options.now ?? Date.now;
  }

  get activeCount(): number {
    return this.#runs.size + this.#starting.size;
  }

  async start(request: StartRunRequest): Promise<string> {
    if (this.#runs.has(request.runId) || this.#starting.has(request.runId)) {
      throw new RunConflictError(request.runId);
    }

    this.#starting.add(request.runId);
    try {
      return await this.#createAndStart(request);
    } finally {
      this.#starting.delete(request.runId);
      this.#stopRequested.delete(request.runId);
    }
  }

  async #createAndStart(request: StartRunRequest): Promise<string> {
    const deadline = this.#now() + request.limits.walltimeSeconds * 1000;
    const containerId = await this.#engine.create({
      name: `kaska-run-${request.runId}`,
      image: request.image,
      env: request.env,
      labels: {
        [RUN_ID_LABEL]: request.runId,
        [CALLBACK_LABEL]: request.callbackUrl,
        [DEADLINE_LABEL]: String(deadline),
      },
      limits: request.limits,
      network: this.#options.network,
    });

    try {
      await this.#engine.start(containerId);
    } catch (error) {
      await this.#removeQuietly(containerId);
      throw error;
    }

    this.#supervise({
      runId: request.runId,
      containerId,
      callbackUrl: request.callbackUrl,
      deadline,
      sinceSeconds: 0,
    });

    if (this.#stopRequested.has(request.runId)) await this.#engine.kill(containerId);
    return containerId;
  }

  async stop(runId: string): Promise<boolean> {
    if (this.#starting.has(runId)) {
      this.#stopRequested.add(runId);
      return true;
    }

    const run = this.#runs.get(runId);
    if (!run) return false;
    await this.#engine.kill(run.containerId);
    return true;
  }

  async recover(): Promise<number> {
    const containers = await this.#engine.listManaged();
    const nowSeconds = Math.floor(this.#now() / 1000);
    let recovered = 0;

    for (const container of containers) {
      const runId = container.labels[RUN_ID_LABEL];
      const callbackUrl = container.labels[CALLBACK_LABEL];
      const deadline = Number(container.labels[DEADLINE_LABEL]);

      if (!isRunId(runId) || !callbackUrl || !Number.isFinite(deadline)) {
        console.error(`removing unrecognised managed container ${container.id}`);
        await this.#removeQuietly(container.id);
        continue;
      }
      if (this.#runs.has(runId)) continue;

      this.#supervise({
        runId,
        containerId: container.id,
        callbackUrl,
        deadline,
        sinceSeconds: nowSeconds,
      });
      recovered++;
    }

    return recovered;
  }

  async idle(): Promise<void> {
    await Promise.all([...this.#runs.values()].map((run) => run.done));
  }

  #supervise(target: {
    runId: string;
    containerId: string;
    callbackUrl: string;
    deadline: number;
    sinceSeconds: number;
  }): void {
    const run: SupervisedRun = { ...target, expiry: null, done: Promise.resolve() };
    this.#runs.set(run.runId, run);
    run.done = this.#watch(run, target.sinceSeconds).finally(() => this.#runs.delete(run.runId));
  }

  async #watch(run: SupervisedRun, sinceSeconds: number): Promise<void> {
    const logs = this.#pumpLogs(run, sinceSeconds);
    const timer = setTimeout(
      () => this.#expire(run),
      Math.max(0, run.deadline - this.#now()),
    );

    let report: ExitReport;
    try {
      const exitCode = await this.#engine.wait(run.containerId);
      report = await this.#killedOnWalltime(run)
        ? { outcome: "timed_out", exit_code: exitCode, reason: WALLTIME_EXCEEDED }
        : { outcome: "exited", exit_code: exitCode };
    } catch (error) {
      report = { outcome: "failed", reason: `container wait failed: ${errorMessage(error)}` };
    } finally {
      clearTimeout(timer);
    }

    await logs;
    await this.#reportExit(run, report);
    await this.#removeQuietly(run.containerId);
  }

  #expire(run: SupervisedRun): void {
    run.expiry = this.#engine.kill(run.containerId).catch((error) => {
      console.error(`run ${run.runId} kill on walltime failed: ${errorMessage(error)}`);
      return false;
    });
  }

  async #killedOnWalltime(run: SupervisedRun): Promise<boolean> {
    return run.expiry !== null && await run.expiry;
  }

  async #pumpLogs(run: SupervisedRun, sinceSeconds: number): Promise<void> {
    const batcher = new LogBatcher(
      (chunk) => this.#callbacks.sendLogs(run.callbackUrl, chunk),
      { flushMs: this.#options.logFlushMs, flushBytes: this.#options.logFlushBytes },
    );
    const decoder = new DockerFrameDecoder();
    const text = new TextDecoder();

    try {
      const stream = await this.#engine.logs(run.containerId, sinceSeconds);
      for await (const chunk of stream) {
        for (const frame of decoder.push(chunk)) {
          batcher.push(text.decode(frame.payload, { stream: true }));
        }
      }
      batcher.push(text.decode());
    } catch (error) {
      console.error(`run ${run.runId} log stream failed: ${errorMessage(error)}`);
    } finally {
      await batcher.close();
    }
  }

  async #reportExit(run: SupervisedRun, report: ExitReport): Promise<void> {
    try {
      await this.#callbacks.reportExit(run.callbackUrl, report);
    } catch (error) {
      console.error(`run ${run.runId} exit report lost: ${errorMessage(error)}`);
    }
  }

  async #removeQuietly(containerId: string): Promise<void> {
    try {
      await this.#engine.remove(containerId);
    } catch (error) {
      console.error(`container ${containerId} removal failed: ${errorMessage(error)}`);
    }
  }
}
