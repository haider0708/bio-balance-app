-- DESTRUCTIVE maintenance procedure. Never run automatically or through the API.
-- Stop BioBalance API/workers, verify a database+media backup, and rehearse on
-- its isolated restore first. psql variables are mandatory; any failed assertion
-- rolls back the complete transaction. Other databases are never addressed.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';
SELECT set_config('biobalance.reset_confirmation', :'reset_confirmation', true);
SELECT set_config('biobalance.reset_admin', :'admin_email', true);
SELECT set_config('biobalance.reset_backup', :'backup_id', true);
SELECT set_config('biobalance.reset_products', :'expected_products', true);
SELECT set_config('biobalance.reset_users', :'expected_users', true);
DO $$
DECLARE actual text[];
BEGIN
  IF current_setting('biobalance.reset_confirmation') <> 'RESET_BUSINESS_KEEP_ACCOUNTS' THEN
    RAISE EXCEPTION 'Explicit catalog-preserving reset confirmation required';
  END IF;
  IF current_setting('biobalance.reset_backup') !~ '^[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$' THEN
    RAISE EXCEPTION 'Supply the verified backup identifier';
  END IF;
  SELECT array_agg(tablename::text ORDER BY tablename) INTO actual
    FROM pg_tables WHERE schemaname='public';
  IF actual IS DISTINCT FROM (SELECT array_agg(x ORDER BY x) FROM unnest(ARRAY['AccessToken', 'Alert', 'Announcement', 'AuditEntry', 'Change', 'ContentSubmission', 'Delivery', 'DeliveryIssue', 'DeliveryReceipt', 'DeviceToken', 'GroupCreationGrant', 'InventoryLot', 'Job', 'LoginAttempt', 'MediaAsset', 'Membership', 'Notification', 'Organization', 'OrganizationMembership', 'PointsAccount', 'PointsEntry', 'ProcessedOperation', 'Product', 'PushDelivery', 'ReplenishmentOrder', 'ReportExport', 'ReportExportRow', 'RequestBudget', 'Reward', 'RewardClaim', 'Sale', 'SaleRevision', 'SalesContribution', 'SalesDay', 'SalesProductDay', 'Session', 'StockMovement', 'Store', 'StoreCursor', 'StoreProduct', 'SyncSnapshotPage', 'TrainingContent', 'UploadChunk', 'User', '_prisma_migrations']) x) THEN
    RAISE EXCEPTION 'Database schema changed; review the reset table inventory';
  END IF;
END $$;
LOCK TABLE "AccessToken", "Alert", "Announcement", "AuditEntry", "Change", "ContentSubmission", "Delivery", "DeliveryIssue", "DeliveryReceipt", "DeviceToken", "GroupCreationGrant", "InventoryLot", "Job", "LoginAttempt", "MediaAsset", "Membership", "Notification", "Organization", "OrganizationMembership", "PointsAccount", "PointsEntry", "ProcessedOperation", "Product", "PushDelivery", "ReplenishmentOrder", "ReportExport", "ReportExportRow", "RequestBudget", "Reward", "RewardClaim", "Sale", "SaleRevision", "SalesContribution", "SalesDay", "SalesProductDay", "Session", "StockMovement", "Store", "StoreCursor", "StoreProduct", "SyncSnapshotPage", "TrainingContent", "UploadChunk", "User", "_prisma_migrations" IN ACCESS EXCLUSIVE MODE;
CREATE TEMP TABLE reset_accounts ON COMMIT DROP AS SELECT * FROM "User";
CREATE TEMP TABLE reset_responsibles ON COMMIT DROP AS
SELECT DISTINCT u.id FROM "User" u WHERE NOT u."platformAdmin" AND (
 EXISTS (SELECT 1 FROM "OrganizationMembership" m WHERE m."userId"=u.id AND m.active)
 OR EXISTS (SELECT 1 FROM "GroupCreationGrant" g WHERE g."userId"=u.id));
CREATE TEMP TABLE reset_catalog ON COMMIT DROP AS SELECT * FROM "Product";
CREATE TEMP TABLE reset_media ON COMMIT DROP AS SELECT * FROM "MediaAsset"
  WHERE id IN (SELECT "imageId" FROM "Product" WHERE "imageId" IS NOT NULL);
CREATE TEMP TABLE reset_admin ON COMMIT DROP AS SELECT * FROM "User"
  WHERE email=current_setting('biobalance.reset_admin') AND "platformAdmin" AND NOT disabled;
DO $$ BEGIN
  IF (SELECT count(*) FROM reset_accounts) <> current_setting('biobalance.reset_users')::integer THEN RAISE EXCEPTION 'Unexpected account count'; END IF;
  IF (SELECT count(*) FROM reset_admin) <> 1 THEN RAISE EXCEPTION 'Active administrator not found'; END IF;
  IF (SELECT count(*) FROM reset_catalog) <> current_setting('biobalance.reset_products')::integer THEN
    RAISE EXCEPTION 'Unexpected product count';
  END IF;
  IF EXISTS (SELECT 1 FROM reset_catalog p LEFT JOIN reset_media m ON m.id=p."imageId"
    WHERE p."imageId" IS NOT NULL AND (m.id IS NULL OR m.status <> 'ready'
      OR m.purpose <> 'catalog' OR m."ownerId" NOT IN (SELECT id FROM reset_accounts)
      OR m."storeId" IS NOT NULL OR m."organizationId" IS NOT NULL)) THEN
    RAISE EXCEPTION 'Review product media dependencies before reset';
  END IF;
END $$;
-- An explicit list, with RESTRICT (the default). Never CASCADE, disable triggers,
-- reset product sequences, or grant application accounts maintenance rights.
TRUNCATE TABLE
  "AccessToken",
  "Alert",
  "Announcement",
  "AuditEntry",
  "Change",
  "ContentSubmission",
  "Delivery",
  "DeliveryIssue",
  "DeliveryReceipt",
  "DeviceToken",
  "GroupCreationGrant",
  "InventoryLot",
  "Job",
  "LoginAttempt",
  "Membership",
  "Notification",
  "Organization",
  "OrganizationMembership",
  "PointsAccount",
  "PointsEntry",
  "ProcessedOperation",
  "PushDelivery",
  "ReplenishmentOrder",
  "ReportExport",
  "ReportExportRow",
  "RequestBudget",
  "Reward",
  "RewardClaim",
  "Sale",
  "SaleRevision",
  "SalesContribution",
  "SalesDay",
  "SalesProductDay",
  "Session",
  "StockMovement",
  "Store",
  "StoreCursor",
  "StoreProduct",
  "SyncSnapshotPage",
  "TrainingContent",
  "UploadChunk"
  RESTRICT;
DELETE FROM "MediaAsset" WHERE id NOT IN (SELECT id FROM reset_media);
-- Credentials, MFA and user IDs are deliberately untouched. Restore the right
-- to create a group only to accounts which already held that authority.
INSERT INTO "GroupCreationGrant" (id,"userId","createdBy")
SELECT gen_random_uuid(),r.id,a.id FROM reset_responsibles r CROSS JOIN reset_admin a;
DO $$ BEGIN
  IF EXISTS ((SELECT * FROM "Product" EXCEPT SELECT * FROM reset_catalog)
    UNION ALL (SELECT * FROM reset_catalog EXCEPT SELECT * FROM "Product")) THEN
    RAISE EXCEPTION 'Product preservation failed';
  END IF;
  IF EXISTS ((SELECT * FROM "MediaAsset" EXCEPT SELECT * FROM reset_media)
    UNION ALL (SELECT * FROM reset_media EXCEPT SELECT * FROM "MediaAsset")) THEN
    RAISE EXCEPTION 'Image preservation failed';
  END IF;
  IF EXISTS ((SELECT * FROM "User" EXCEPT SELECT * FROM reset_accounts)
    UNION ALL (SELECT * FROM reset_accounts EXCEPT SELECT * FROM "User")) THEN
    RAISE EXCEPTION 'Account/credential preservation failed';
  END IF;
END $$;
-- Record the authorized maintenance action; old business histories remain only
-- in the verified backup. The audit table's normal immutability stays enabled.
INSERT INTO "AuditEntry" (id,"actorId",action,"targetId",details)
SELECT gen_random_uuid(),id,'maintenance.account_preserving_reset',current_database(),
  jsonb_build_object('backupId',current_setting('biobalance.reset_backup'),
    'productsPreserved',(SELECT count(*) FROM "Product"),
    'mediaPreserved',(SELECT count(*) FROM "MediaAsset"),'accountsPreserved',(SELECT count(*) FROM "User"),'creationGrants',(SELECT count(*) FROM "GroupCreationGrant"),'sessionsRevoked',true)
FROM reset_admin;
SELECT (SELECT count(*) FROM "Product") products,
       (SELECT count(*) FROM "MediaAsset") product_images,
       (SELECT count(*) FROM "User") accounts,
       (SELECT count(*) FROM "Organization") groups,
       (SELECT count(*) FROM "GroupCreationGrant") creation_grants,
       (SELECT count(*) FROM "Store") stores,
       (SELECT count(*) FROM "Sale") sales,
       (SELECT count(*) FROM "Session") sessions;
COMMIT;
