-- Grossistes become warehouses: a record with its info, photos and stock, and no account.
-- The admin and the responsable of the region manage them; the admin approves what a responsable submits.

-- 1. A grossiste's count waiting for the responsable's check no longer exists: send those counts to the admin.
UPDATE "StockDeclaration" SET "status" = 'PENDING' WHERE "status" = 'REVIEW';
ALTER TABLE "StockDeclaration" DROP COLUMN "reviewedById", DROP COLUMN "reviewedAt", DROP COLUMN "reviewNote";

-- 2. Orders to a grossiste belong to its region (so its responsable sees them).
UPDATE "RestockOrder" o SET "regionId" = d."regionId" FROM "Depot" d WHERE o."destKind" = 'DEPOT' AND o."destId" = d.id AND o."regionId" IS NULL;

-- 3. What the old grossiste accounts owned goes to the first admin, then the accounts go.
DO $$
DECLARE admin_id uuid := (SELECT id FROM "User" WHERE role = 'ADMIN' ORDER BY "createdAt" LIMIT 1);
BEGIN
  IF admin_id IS NOT NULL THEN
    UPDATE "MediaAsset" SET "ownerId" = admin_id WHERE "ownerId" IN (SELECT id FROM "User" WHERE role = 'GROSSISTE');
    UPDATE "StockRecount" SET "requestedById" = admin_id WHERE "requestedById" IN (SELECT id FROM "User" WHERE role = 'GROSSISTE');
  END IF;
END $$;
-- Its policy mentioned the account, so it is replaced first.
DROP POLICY "Depot_read" ON "Depot";
CREATE POLICY "Depot_read" ON "Depot" FOR SELECT USING (app_is_admin() OR app_in_region("regionId"));
ALTER TABLE "Depot" ADD COLUMN "photoIds" UUID[] NOT NULL DEFAULT ARRAY[]::UUID[];
ALTER TABLE "Depot" DROP CONSTRAINT "Depot_user_fk";
DROP INDEX "Depot_userId_key";
ALTER TABLE "Depot" DROP COLUMN "userId";
DELETE FROM "User" WHERE role = 'GROSSISTE';

-- 4. Nobody addresses grossistes any more.
UPDATE "Message" SET audience = jsonb_set(audience, '{roles}',
  COALESCE((SELECT jsonb_agg(r) FROM jsonb_array_elements(audience -> 'roles') r WHERE r <> '"GROSSISTE"'), '[]'::jsonb))
  WHERE audience ? 'roles';
UPDATE "Course" SET audience = jsonb_set(audience, '{roles}',
  COALESCE((SELECT jsonb_agg(r) FROM jsonb_array_elements(audience -> 'roles') r WHERE r <> '"GROSSISTE"'), '[]'::jsonb))
  WHERE audience ? 'roles';

-- 5. Drop the two enum values that are gone.
-- The rules written in terms of the role are dropped, then restored around the new type.
ALTER TABLE "User" DROP CONSTRAINT "User_scope_check";
DROP INDEX "User_one_responsable_per_region";
ALTER TYPE "Role" RENAME TO "Role_old";
CREATE TYPE "Role" AS ENUM ('ADMIN', 'RESPONSABLE', 'VENDEUR');
ALTER TABLE "User" ALTER COLUMN "role" TYPE "Role" USING "role"::text::"Role";
DROP TYPE "Role_old";
ALTER TABLE "User" ADD CONSTRAINT "User_scope_check" CHECK (
  (role IN ('RESPONSABLE','VENDEUR')) = ("regionId" IS NOT NULL)
  AND (role = 'VENDEUR') = ("pdvId" IS NOT NULL));
CREATE UNIQUE INDEX "User_one_responsable_per_region" ON "User"("regionId")
  WHERE role = 'RESPONSABLE' AND status IN ('PENDING','ACTIVE');

DROP INDEX "StockDeclaration_one_pending";
ALTER TYPE "Approval" RENAME TO "Approval_old";
CREATE TYPE "Approval" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');
ALTER TABLE "StockDeclaration" ALTER COLUMN "status" DROP DEFAULT;
ALTER TABLE "StockDeclaration" ALTER COLUMN "status" TYPE "Approval" USING "status"::text::"Approval";
ALTER TABLE "StockDeclaration" ALTER COLUMN "status" SET DEFAULT 'PENDING';
ALTER TABLE "StockRecount" ALTER COLUMN "status" DROP DEFAULT;
ALTER TABLE "StockRecount" ALTER COLUMN "status" TYPE "Approval" USING "status"::text::"Approval";
ALTER TABLE "StockRecount" ALTER COLUMN "status" SET DEFAULT 'PENDING';
DROP TYPE "Approval_old";
CREATE UNIQUE INDEX "StockDeclaration_one_pending" ON "StockDeclaration"("locationId") WHERE status = 'PENDING';

-- 6. Row-level security without the grossiste's own context.
-- A responsable may add stock to the grossistes of their region.
DROP POLICY "Stock_rls" ON "Stock";
CREATE POLICY "Stock_rls" ON "Stock"
  USING (app_is_admin() OR app_in_region("regionId") OR ("locationKind" = 'PDV' AND "locationId" = app_pdv()))
  WITH CHECK (app_is_admin() OR app_in_region("regionId") OR ("locationKind" = 'PDV' AND "locationId" = app_pdv()));
DROP POLICY "StockMovement_rls" ON "StockMovement";
CREATE POLICY "StockMovement_rls" ON "StockMovement"
  USING (app_is_admin() OR app_in_region("regionId"))
  WITH CHECK (app_is_admin() OR app_in_region("regionId") OR ("locationKind" = 'PDV' AND "locationId" = app_pdv()));
DROP POLICY "StockDeclaration_rls" ON "StockDeclaration";
CREATE POLICY "StockDeclaration_rls" ON "StockDeclaration"
  USING (app_is_admin() OR app_in_region("regionId"))
  WITH CHECK (app_is_admin() OR app_in_region("regionId"));
DROP POLICY "StockRecount_rls" ON "StockRecount";
CREATE POLICY "StockRecount_rls" ON "StockRecount"
  USING (app_is_admin() OR app_in_region("regionId"))
  WITH CHECK (app_is_admin() OR app_in_region("regionId"));

DROP POLICY "RestockOrder_rls" ON "RestockOrder";
DROP POLICY "RestockLine_rls" ON "RestockLine";
DROP FUNCTION app_sees_order(uuid, uuid, "LocationKind", uuid, uuid);
CREATE FUNCTION app_sees_order(region uuid, receiver uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT app_is_admin() OR app_in_region(region) OR (receiver IS NOT NULL AND receiver = app_user()) $$;
CREATE POLICY "RestockOrder_rls" ON "RestockOrder"
  USING (app_sees_order("regionId", "receiverId")) WITH CHECK (app_sees_order("regionId", "receiverId"));
CREATE POLICY "RestockLine_rls" ON "RestockLine"
  USING (EXISTS (SELECT 1 FROM "RestockOrder" o WHERE o.id = "orderId"))
  WITH CHECK (EXISTS (SELECT 1 FROM "RestockOrder" o WHERE o.id = "orderId"));

DROP FUNCTION app_depot();
