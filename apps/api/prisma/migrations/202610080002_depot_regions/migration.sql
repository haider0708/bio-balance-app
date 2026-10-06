-- Every grossiste works for one region and is handled by that region's responsable.
ALTER TABLE "Depot" ADD COLUMN "regionId" UUID;
UPDATE "Depot" SET "regionId" = (SELECT id FROM "Region" ORDER BY code LIMIT 1) WHERE "regionId" IS NULL;
ALTER TABLE "Depot" ALTER COLUMN "regionId" SET NOT NULL;
ALTER TABLE "Depot" ADD CONSTRAINT "Depot_region_fk" FOREIGN KEY ("regionId") REFERENCES "Region"(id);
CREATE INDEX "Depot_regionId_idx" ON "Depot"("regionId");
DROP POLICY "Depot_read" ON "Depot";
CREATE POLICY "Depot_read" ON "Depot" FOR SELECT
  USING (app_is_admin() OR app_in_region("regionId") OR "userId" = app_user());
