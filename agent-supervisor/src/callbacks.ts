import { errorMessage } from "./errors.ts";

export type ExitReport =
  | { outcome: "exited"; exit_code: number }
  | { outcome: "timed_out"; exit_code: number | null; reason: string }
  | { outcome: "failed"; reason: string };

export interface CallbackSender {
  sendLogs(callbackUrl: string, chunk: string): Promise<void>;
  reportExit(callbackUrl: string, report: ExitReport): Promise<void>;
}

export interface RetryPolicy {
  attempts: number;
  baseDelayMs: number;
  maxDelayMs: number;
}

type Fetch = typeof fetch;
type Delivery = "delivered" | "retry";

const LOG_RETRY: RetryPolicy = { attempts: 3, baseDelayMs: 500, maxDelayMs: 2_000 };
const EXIT_RETRY: RetryPolicy = { attempts: 10, baseDelayMs: 1_000, maxDelayMs: 30_000 };

export class CallbackClient implements CallbackSender {
  readonly #secret: string;
  readonly #fetch: Fetch;
  readonly #sleep: (ms: number) => Promise<void>;

  constructor(
    secret: string,
    fetchImpl: Fetch = fetch,
    sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms)),
  ) {
    this.#secret = secret;
    this.#fetch = fetchImpl;
    this.#sleep = sleep;
  }

  sendLogs(callbackUrl: string, chunk: string): Promise<void> {
    return this.#deliver(`${callbackUrl}/logs`, { chunk }, LOG_RETRY);
  }

  reportExit(callbackUrl: string, report: ExitReport): Promise<void> {
    return this.#deliver(`${callbackUrl}/exit`, report, EXIT_RETRY);
  }

  async #deliver(url: string, body: unknown, policy: RetryPolicy): Promise<void> {
    for (let attempt = 1; attempt <= policy.attempts; attempt++) {
      if (await this.#post(url, body) === "delivered") return;
      if (attempt < policy.attempts) await this.#sleep(backoff(policy, attempt));
    }
    throw new Error(`callback ${url} failed after ${policy.attempts} attempts`);
  }

  async #post(url: string, body: unknown): Promise<Delivery> {
    try {
      const response = await this.#fetch(url, {
        method: "POST",
        headers: {
          "authorization": `Bearer ${this.#secret}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(body),
      });
      await response.body?.cancel();
      return isFinal(response.status) ? "delivered" : "retry";
    } catch (error) {
      console.error(`callback ${url} transport error: ${errorMessage(error)}`);
      return "retry";
    }
  }
}

function isFinal(status: number): boolean {
  return (status >= 200 && status < 300) || status === 404 || status === 409 ||
    status === 400;
}

function backoff(policy: RetryPolicy, attempt: number): number {
  return Math.min(policy.baseDelayMs * 2 ** (attempt - 1), policy.maxDelayMs);
}
