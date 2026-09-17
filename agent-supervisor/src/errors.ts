export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export class RunConflictError extends Error {
  constructor(runId: string) {
    super(`run ${runId} is already supervised`);
  }
}
