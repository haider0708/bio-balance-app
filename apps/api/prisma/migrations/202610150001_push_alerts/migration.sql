-- Apple push alerts. A phone is registered for one signed-in session: signing out, a new
-- password or a deleted account ends the session, and the phone stops receiving alerts.
CREATE TABLE "PushDevice" (
  "token" TEXT NOT NULL,
  "userId" UUID NOT NULL,
  "sessionId" UUID NOT NULL,
  "platform" TEXT NOT NULL,
  "sandbox" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PushDevice_pkey" PRIMARY KEY ("token"),
  CONSTRAINT "PushDevice_platform_check" CHECK ("platform" IN ('IOS')),
  CONSTRAINT "PushDevice_token_check" CHECK ("token" ~ '^[0-9a-f]{32,200}$')
);
CREATE INDEX "PushDevice_userId_idx" ON "PushDevice"("userId");
CREATE INDEX "PushDevice_sessionId_idx" ON "PushDevice"("sessionId");
ALTER TABLE "PushDevice" ADD CONSTRAINT "PushDevice_session_fk"
  FOREIGN KEY ("sessionId") REFERENCES "Session"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PushDevice" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "PushDevice" FORCE ROW LEVEL SECURITY;
CREATE POLICY "PushDevice_own" ON "PushDevice"
  USING (app_is_admin() OR "userId" = app_user())
  WITH CHECK (app_is_admin() OR "userId" = app_user());

-- Each notification is pushed once. What already exists is never pushed.
ALTER TABLE "Notification" ADD COLUMN "pushedAt" TIMESTAMP(3);
UPDATE "Notification" SET "pushedAt" = "createdAt";
CREATE INDEX "Notification_unpushed_idx" ON "Notification"("createdAt") WHERE "pushedAt" IS NULL;
