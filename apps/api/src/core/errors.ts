/** A business rule the caller can fix. `code` is stable; the phone translates it. */
export class DomainError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status = 422,
    readonly details?: unknown,
  ) {
    super(message);
  }
}

export function requireRule(
  condition: unknown,
  code: string,
  message: string,
  status = 422,
): asserts condition {
  if (!condition) throw new DomainError(code, message, status);
}

export const notFound = (what: string) =>
  new DomainError("NOT_FOUND", `${what} not found.`, 404);
export const forbidden = (message = "You cannot do this.") =>
  new DomainError("FORBIDDEN", message, 403);
