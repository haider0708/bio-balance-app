ALTER TABLE "DeviceToken" ADD COLUMN "sessionId" UUID;
CREATE INDEX "DeviceToken_sessionId_idx" ON "DeviceToken"("sessionId");
ALTER TABLE "DeviceToken" ADD CONSTRAINT "DeviceToken_sessionId_fkey" FOREIGN KEY ("sessionId") REFERENCES "Session"(id);
