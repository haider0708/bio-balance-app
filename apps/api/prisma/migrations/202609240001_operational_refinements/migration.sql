-- Additive operational controls. Existing receipts, ledger histories and IDs remain unchanged.
ALTER TABLE "Organization" ADD COLUMN status text NOT NULL DEFAULT 'active', ADD COLUMN "statusReason" text, ADD COLUMN "statusChangedAt" timestamp(3), ADD COLUMN "statusChangedBy" uuid REFERENCES "User"(id), ADD CHECK (status IN ('active','suspended','archived'));
ALTER TABLE "Store" ADD COLUMN status text NOT NULL DEFAULT 'active', ADD COLUMN "statusReason" text, ADD COLUMN "statusChangedAt" timestamp(3), ADD COLUMN "statusChangedBy" uuid REFERENCES "User"(id), ADD CHECK (status IN ('active','suspended','archived'));
ALTER TABLE "ReplenishmentOrder" ADD COLUMN "requestedLines" jsonb NOT NULL DEFAULT '[]', ADD COLUMN "cancelledLines" jsonb NOT NULL DEFAULT '[]';
UPDATE "ReplenishmentOrder" SET "requestedLines"=lines;
-- A salesperson never receives deliveries. Do not change the identity or bytes of queued commands.
UPDATE "Membership" SET permissions=array_remove(permissions,'receive') WHERE NOT ('manage'=ANY(permissions));
UPDATE "AccessToken" SET permissions=array_remove(permissions,'receive') WHERE NOT ('manage'=ANY(permissions));
CREATE TABLE "DeliveryIssue" (
 id uuid PRIMARY KEY, "organizationId" uuid NOT NULL, "storeId" uuid NOT NULL,
 "deliveryId" uuid NOT NULL UNIQUE, "orderId" uuid NOT NULL,
 status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','resolved')),
 reason text NOT NULL, "heldLines" jsonb NOT NULL DEFAULT '[]', resolution text, "resolutionNote" text,
 "reportedBy" uuid NOT NULL REFERENCES "User"(id), "resolvedBy" uuid REFERENCES "User"(id),
 "createdAt" timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "resolvedAt" timestamp(3), version integer NOT NULL DEFAULT 1,
 FOREIGN KEY ("organizationId","storeId") REFERENCES "Store"("organizationId",id),
 FOREIGN KEY ("storeId","deliveryId") REFERENCES "Delivery"("storeId",id),
 FOREIGN KEY ("storeId","orderId") REFERENCES "ReplenishmentOrder"("storeId",id));
CREATE INDEX "DeliveryIssue_storeId_status_idx" ON "DeliveryIssue"("storeId",status);
ALTER TABLE "DeliveryIssue" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "DeliveryIssue" FORCE ROW LEVEL SECURITY;
CREATE POLICY "DeliveryIssue_scope" ON "DeliveryIssue" USING ("organizationId"::text=current_setting('app.organization_id',true) AND "storeId"::text=current_setting('app.store_id',true));
CREATE POLICY "DeliveryIssue_admin_read" ON "DeliveryIssue" FOR SELECT USING (current_setting('app.admin_read',true)='true');
CREATE POLICY "DeliveryIssue_group_read" ON "DeliveryIssue" FOR SELECT USING (current_setting('app.group_read',true)='true' AND "organizationId"::text=current_setting('app.organization_id',true) AND EXISTS (SELECT 1 FROM "OrganizationMembership" m WHERE m."organizationId"="DeliveryIssue"."organizationId" AND m."userId"::text=current_setting('app.actor_id',true) AND m.active));
