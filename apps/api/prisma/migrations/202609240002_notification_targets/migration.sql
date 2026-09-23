ALTER TABLE "Notification" ADD COLUMN "targetType" text, ADD COLUMN "targetId" uuid;
CREATE INDEX "Notification_unread_user_idx" ON "Notification"("userId","createdAt" DESC,id DESC) WHERE "readAt" IS NULL;
-- Group reports retain archived stores' history, but suspended groups lose access.
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['SalesDay','SalesProductDay','SalesContribution','Sale','InventoryLot','ReplenishmentOrder','Delivery','Alert','RewardClaim','PointsAccount','Membership','StoreProduct','Reward','DeliveryIssue'] LOOP
  EXECUTE format('ALTER POLICY %I ON %I USING (
    (SELECT current_setting(''app.group_read'',true)=''true'')
    AND "organizationId"=(SELECT NULLIF(current_setting(''app.organization_id'',true),'''')::uuid)
    AND (SELECT EXISTS(SELECT 1 FROM "OrganizationMembership" gm JOIN "Organization" g ON g.id=gm."organizationId"
      WHERE gm."organizationId"=NULLIF(current_setting(''app.organization_id'',true),'''')::uuid
      AND gm."userId"=NULLIF(current_setting(''app.actor_id'',true),'''')::uuid AND gm.active AND g.status=''active'')))',t||'_group_read',t);
 END LOOP;
END $$;
