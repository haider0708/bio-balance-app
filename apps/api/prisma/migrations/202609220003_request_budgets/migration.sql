-- Global abuse counters only; never contain business payloads or credentials.
CREATE TABLE "RequestBudget" (
  key TEXT PRIMARY KEY,
  count INTEGER NOT NULL CHECK (count >= 0),
  "windowStart" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "RequestBudget_windowStart_idx" ON "RequestBudget"("windowStart");
