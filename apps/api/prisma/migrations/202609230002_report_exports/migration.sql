CREATE TABLE "ReportExport" (
 id uuid PRIMARY KEY,"actorId" uuid NOT NULL REFERENCES "User"(id),"sessionId" uuid REFERENCES "Session"(id),
 query jsonb NOT NULL,status text NOT NULL DEFAULT 'pending',rows integer NOT NULL DEFAULT 0,
 generation uuid,error text,"createdAt" timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,"expiresAt" timestamp(3) NOT NULL,
 CONSTRAINT "ReportExport_status" CHECK(status IN ('pending','processing','ready','failed'))
);
CREATE INDEX "ReportExport_actorId_createdAt_idx" ON "ReportExport"("actorId","createdAt");
CREATE INDEX "ReportExport_expiresAt_idx" ON "ReportExport"("expiresAt");
CREATE TABLE "ReportExportRow" (
 "exportId" uuid NOT NULL REFERENCES "ReportExport"(id) ON DELETE CASCADE,"saleId" uuid NOT NULL,
 cells jsonb NOT NULL,PRIMARY KEY("exportId","saleId")
);
ALTER TABLE "ReportExportRow" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ReportExportRow" FORCE ROW LEVEL SECURITY;
CREATE POLICY report_export_owner ON "ReportExportRow" USING (
 EXISTS(SELECT 1 FROM "ReportExport" e WHERE e.id="exportId" AND e."actorId"=NULLIF(current_setting('app.actor_id',true),'')::uuid)
) WITH CHECK (
 EXISTS(SELECT 1 FROM "ReportExport" e WHERE e.id="exportId" AND e."actorId"=NULLIF(current_setting('app.actor_id',true),'')::uuid)
);
