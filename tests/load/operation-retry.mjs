/** Exercise the public sync protocol without hiding terminal or exhausted failures. */
export function submitSale(
  submit,
  pause,
  operationId,
  observeRetry = () => {},
) {
  for (let attempt = 1; attempt <= 3; attempt++) {
    const response = submit();
    let body;
    try {
      body = response.json();
    } catch {
      body = undefined;
    }
    const result = body?.results?.[0];
    const matches =
      response.status === 201 && result?.operationId === operationId;
    const accepted = matches && result.status === "accepted";
    const code = accepted
      ? "none"
      : String(result?.code || body?.code || `http_${response.status}`);
    if (accepted || !matches || result.status !== "retryable" || attempt === 3)
      return { response, accepted, attempts: attempt, code };
    observeRetry(code);
    const requested = Number(result.retryAfterMs);
    const delay =
      Number.isFinite(requested) && requested >= 0
        ? Math.min(requested, 5000)
        : 100 * 2 ** (attempt - 1);
    pause(delay / 1000);
  }
  throw Error("Unreachable retry state");
}
