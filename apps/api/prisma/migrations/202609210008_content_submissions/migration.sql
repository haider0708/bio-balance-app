ALTER TABLE "Announcement" ADD COLUMN "payloadHash" TEXT, ADD COLUMN "recipientCount" INTEGER NOT NULL DEFAULT 0;
CREATE TABLE "ContentSubmission" (
  id UUID PRIMARY KEY, "actorId" UUID NOT NULL, "contentId" UUID NOT NULL, "payloadHash" TEXT NOT NULL,
  result JSONB NOT NULL, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "ContentSubmission_actorId_contentId_idx" ON "ContentSubmission"("actorId","contentId");
ALTER TABLE "ContentSubmission" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ContentSubmission" FORCE ROW LEVEL SECURITY;
CREATE POLICY "content_submission_actor" ON "ContentSubmission" USING ("actorId" = NULLIF(current_setting('app.actor_id',true),'')::uuid)
  WITH CHECK ("actorId" = NULLIF(current_setting('app.actor_id',true),'')::uuid);
