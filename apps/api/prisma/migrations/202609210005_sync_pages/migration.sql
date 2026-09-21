CREATE TABLE "SyncSnapshotPage" (
  "id" UUID NOT NULL PRIMARY KEY, "organizationId" UUID NOT NULL,
  "storeId" UUID NOT NULL, "actorId" UUID NOT NULL,
  "permissions" TEXT NOT NULL, "expiresAt" TIMESTAMP(3) NOT NULL, "payload" JSONB NOT NULL,
  FOREIGN KEY ("storeId", "organizationId") REFERENCES "Store"("id", "organizationId")
);
CREATE INDEX "SyncSnapshotPage_expiresAt_idx" ON "SyncSnapshotPage"("expiresAt");
CREATE INDEX "SyncSnapshotPage_storeId_actorId_idx" ON "SyncSnapshotPage"("storeId", "actorId");
ALTER TABLE "SyncSnapshotPage" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "SyncSnapshotPage" FORCE ROW LEVEL SECURITY;
CREATE POLICY snapshot_scope ON "SyncSnapshotPage" USING (
  "storeId"::text = current_setting('app.store_id', true) AND
  "organizationId"::text = current_setting('app.organization_id', true) AND
  "actorId"::text = current_setting('app.actor_id', true)
);
