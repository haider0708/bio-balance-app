ALTER TABLE "Notification" ADD COLUMN "kind" TEXT NOT NULL DEFAULT 'operational', ADD COLUMN "audience" TEXT NOT NULL DEFAULT 'managers';
UPDATE "Notification" n SET kind='announcement', audience=a.audience FROM "Announcement" a WHERE n."eventKey"=a.id::text AND n."storeId"=a."storeId";
ALTER TABLE "Notification" ADD CONSTRAINT "Notification_kind_check" CHECK (kind IN ('operational','announcement')), ADD CONSTRAINT "Notification_audience_check" CHECK (audience IN ('managers','all','salespeople'));
ALTER TABLE "Job" ADD COLUMN "leaseToken" UUID;
CREATE TABLE "PushDelivery" (id UUID PRIMARY KEY, "notificationId" UUID NOT NULL REFERENCES "Notification"(id), "deviceId" UUID NOT NULL, "sessionId" UUID NOT NULL, "deliveredAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP);
CREATE UNIQUE INDEX "PushDelivery_notificationId_deviceId_sessionId_key" ON "PushDelivery"("notificationId","deviceId","sessionId");
