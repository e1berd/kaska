import { errorMessage } from "./errors.ts";

export type ChunkSink = (chunk: string) => Promise<void>;

export interface LogBatcherOptions {
  flushMs: number;
  flushBytes: number;
}

export class LogBatcher {
  #pending = "";
  #timer: ReturnType<typeof setTimeout> | null = null;
  #queue: Promise<void> = Promise.resolve();
  readonly #sink: ChunkSink;
  readonly #options: LogBatcherOptions;

  constructor(sink: ChunkSink, options: LogBatcherOptions) {
    this.#sink = sink;
    this.#options = options;
  }

  push(text: string): void {
    if (text === "") return;
    this.#pending += text;

    if (this.#pending.length >= this.#options.flushBytes) {
      this.#enqueueFlush();
    } else if (this.#timer === null) {
      this.#timer = setTimeout(() => this.#enqueueFlush(), this.#options.flushMs);
    }
  }

  async close(): Promise<void> {
    this.#enqueueFlush();
    await this.#queue;
  }

  #enqueueFlush(): void {
    if (this.#timer !== null) {
      clearTimeout(this.#timer);
      this.#timer = null;
    }
    if (this.#pending === "") return;

    const chunk = this.#pending;
    this.#pending = "";
    this.#queue = this.#queue.then(() => this.#sink(chunk)).catch((error) => {
      console.error(`log chunk delivery failed: ${errorMessage(error)}`);
    });
  }
}
