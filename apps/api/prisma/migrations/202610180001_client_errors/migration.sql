-- Errors the app met on phones and in the console (diagnostics, not linked to anyone), one row per
-- kind with a count. Kept 30 days (the worker's cleanup).
CREATE TABLE "ClientError" (
  "id" UUID NOT NULL,
  "fingerprint" TEXT NOT NULL,
  "platform" TEXT NOT NULL,
  "appVersion" TEXT NOT NULL,
  "message" TEXT NOT NULL,
  "stack" TEXT NOT NULL,
  "count" INTEGER NOT NULL DEFAULT 1,
  "firstSeen" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "lastSeen" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ClientError_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "ClientError_fingerprint_key" ON "ClientError"("fingerprint");
CREATE INDEX "ClientError_lastSeen_idx" ON "ClientError"("lastSeen");
