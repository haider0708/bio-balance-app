-- Existing invitation timestamps are unknown; do not invent historical dates.
ALTER TABLE "AccessToken" ADD COLUMN "createdAt" TIMESTAMP(3),
  ADD COLUMN "acceptedAt" TIMESTAMP(3),
  ADD COLUMN "closedReason" TEXT,
  ADD COLUMN "archivedAt" TIMESTAMP(3),
  ADD COLUMN "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "AccessToken" ALTER COLUMN "createdAt" SET DEFAULT CURRENT_TIMESTAMP;
CREATE INDEX "AccessToken_invitation_history" ON "AccessToken" ("organizationId",purpose,"expiresAt",id);
-- Fail rather than silently remove an existing seller assignment.
CREATE UNIQUE INDEX "Membership_one_active_seller_store" ON "Membership" ("userId")
  WHERE active AND NOT (permissions @> ARRAY['manage']::TEXT[]);
ALTER TABLE "AccessToken" ADD CONSTRAINT "AccessToken_one_seller_store"
  CHECK (purpose <> 'invite' OR kind <> 'salesperson' OR "usedAt" IS NOT NULL OR cardinality("storeIds") = 1);
CREATE UNIQUE INDEX "AuditEntry_invitation_operation_key" ON "AuditEntry"("operationId")
  WHERE action='invitation.action';
