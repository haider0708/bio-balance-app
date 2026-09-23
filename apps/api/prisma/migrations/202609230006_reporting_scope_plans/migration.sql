-- Resolve the transaction's security context once. Keep the same scoped write
-- checks and SELECT-only group/admin policies, without per-row text casts.
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['SalesDay','SalesProductDay','SalesContribution'] LOOP
  EXECUTE format('ALTER POLICY %I ON %I USING (
    "organizationId"=(SELECT NULLIF(current_setting(''app.organization_id'',true),'''')::uuid)
    AND "storeId"=(SELECT NULLIF(current_setting(''app.store_id'',true),'''')::uuid))
    WITH CHECK (
    "organizationId"=(SELECT NULLIF(current_setting(''app.organization_id'',true),'''')::uuid)
    AND "storeId"=(SELECT NULLIF(current_setting(''app.store_id'',true),'''')::uuid))',t||'_scope',t);
  EXECUTE format('ALTER POLICY %I ON %I USING ((SELECT current_setting(''app.admin_read'',true)=''true''))',t||'_admin_read',t);
 END LOOP;
 FOREACH t IN ARRAY ARRAY['SalesDay','SalesProductDay','SalesContribution','Sale','InventoryLot','ReplenishmentOrder','Delivery','Alert','RewardClaim','PointsAccount','Membership','StoreProduct','Reward'] LOOP
  EXECUTE format('ALTER POLICY %I ON %I USING (
    (SELECT current_setting(''app.group_read'',true)=''true'')
    AND "organizationId"=(SELECT NULLIF(current_setting(''app.organization_id'',true),'''')::uuid)
    AND (SELECT EXISTS(SELECT 1 FROM "OrganizationMembership" gm
      WHERE gm."organizationId"=NULLIF(current_setting(''app.organization_id'',true),'''')::uuid
      AND gm."userId"=NULLIF(current_setting(''app.actor_id'',true),'''')::uuid AND gm.active)))',t||'_group_read',t);
 END LOOP;
END $$;
