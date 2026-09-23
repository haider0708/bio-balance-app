ALTER TABLE "Organization" ADD COLUMN "imageId" uuid, ADD COLUMN phone text, ADD COLUMN version integer NOT NULL DEFAULT 1;
ALTER TABLE "AccessToken" ADD COLUMN kind text NOT NULL DEFAULT 'legacy', ADD COLUMN "storeIds" uuid[] NOT NULL DEFAULT '{}';
CREATE TABLE "GroupCreationGrant" (
 id uuid PRIMARY KEY, "userId" uuid NOT NULL REFERENCES "User"(id), "createdBy" uuid NOT NULL REFERENCES "User"(id),
 "organizationId" uuid UNIQUE REFERENCES "Organization"(id), "creationOperationId" uuid UNIQUE, "creationPayloadHash" text, "createdAt" timestamp(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "GroupCreationGrant_userId_idx" ON "GroupCreationGrant"("userId");
ALTER TABLE "Product" ADD COLUMN category text NOT NULL DEFAULT '', ADD COLUMN range text NOT NULL DEFAULT '',
 ADD COLUMN "packageSize" text NOT NULL DEFAULT '', ADD COLUMN instructions text NOT NULL DEFAULT '',
 ADD COLUMN ingredients text NOT NULL DEFAULT '', ADD COLUMN precautions text NOT NULL DEFAULT '',
 ADD COLUMN "referencePriceMillimes" bigint, ADD COLUMN "priceStatus" text NOT NULL DEFAULT 'missing',
 ADD COLUMN "sourceUrls" text[] NOT NULL DEFAULT '{}',
 ADD CONSTRAINT "Product_reference_price" CHECK ("referencePriceMillimes" IS NULL OR "referencePriceMillimes">=0),
 ADD CONSTRAINT "Product_price_status" CHECK ("priceStatus" IN ('missing','verified','sample'));
ALTER TABLE "StoreProduct" ADD COLUMN "priceConfigured" boolean NOT NULL DEFAULT false;
UPDATE "StoreProduct" SET "priceConfigured"=true WHERE "priceMillimes">0;
ALTER TABLE "MediaAsset" DROP CONSTRAINT "MediaAsset_scope_check";
ALTER TABLE "MediaAsset" ADD CONSTRAINT "MediaAsset_scope_check" CHECK (
 (purpose IN ('store','reward') AND "organizationId" IS NOT NULL AND "storeId" IS NOT NULL)
 OR (purpose='group' AND "organizationId" IS NOT NULL AND "storeId" IS NULL)
 OR (purpose IN ('training','catalog') AND "organizationId" IS NULL AND "storeId" IS NULL));

CREATE TABLE "SalesDay" (
 "organizationId" uuid NOT NULL, "storeId" uuid NOT NULL, "sellerId" uuid NOT NULL REFERENCES "User"(id), day date NOT NULL,
 "saleCount" integer NOT NULL DEFAULT 0, "netUnits" bigint NOT NULL DEFAULT 0, "netMillimes" bigint NOT NULL DEFAULT 0,
 PRIMARY KEY ("storeId","sellerId",day), FOREIGN KEY ("organizationId","storeId") REFERENCES "Store"("organizationId",id)
);
CREATE INDEX "SalesDay_organizationId_day_idx" ON "SalesDay"("organizationId",day);
CREATE INDEX "SalesDay_storeId_day_idx" ON "SalesDay"("storeId",day);
CREATE TABLE "SalesProductDay" (
 "organizationId" uuid NOT NULL, "storeId" uuid NOT NULL, "sellerId" uuid NOT NULL REFERENCES "User"(id), "productId" uuid NOT NULL REFERENCES "Product"(id), day date NOT NULL,
 "netUnits" bigint NOT NULL DEFAULT 0, "netMillimes" bigint NOT NULL DEFAULT 0,
 PRIMARY KEY ("storeId","sellerId","productId",day), FOREIGN KEY ("organizationId","storeId") REFERENCES "Store"("organizationId",id)
);
CREATE INDEX "SalesProductDay_organizationId_day_idx" ON "SalesProductDay"("organizationId",day);
CREATE TABLE "SalesContribution" (
 "saleId" uuid PRIMARY KEY REFERENCES "Sale"(id), "organizationId" uuid NOT NULL, "storeId" uuid NOT NULL,
 "sellerId" uuid NOT NULL REFERENCES "User"(id), day date NOT NULL, version integer NOT NULL,
 "netUnits" bigint NOT NULL, "netMillimes" bigint NOT NULL, products jsonb NOT NULL,
 FOREIGN KEY ("organizationId","storeId") REFERENCES "Store"("organizationId",id)
);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['SalesDay','SalesProductDay','SalesContribution'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY %I ON %I USING ("organizationId"::text=current_setting(''app.organization_id'',true) AND "storeId"::text=current_setting(''app.store_id'',true)) WITH CHECK ("organizationId"::text=current_setting(''app.organization_id'',true) AND "storeId"::text=current_setting(''app.store_id'',true))',t||'_scope',t);
  EXECUTE format('CREATE POLICY %I ON %I FOR SELECT USING (current_setting(''app.admin_read'',true)=''true'')',t||'_admin_read',t);
 END LOOP;
 FOREACH t IN ARRAY ARRAY['SalesDay','SalesProductDay','SalesContribution','Sale','InventoryLot','ReplenishmentOrder','Delivery','Alert','RewardClaim','PointsAccount','Membership','StoreProduct','Reward'] LOOP
  EXECUTE format('CREATE POLICY %I ON %I FOR SELECT USING (current_setting(''app.group_read'',true)=''true'' AND "organizationId"::text=current_setting(''app.organization_id'',true) AND EXISTS (SELECT 1 FROM "OrganizationMembership" gm WHERE gm."organizationId"=%I."organizationId" AND gm."userId"::text=current_setting(''app.actor_id'',true) AND gm.active))',t||'_group_read',t,t);
 END LOOP;
END $$;

-- One contribution per sale makes live updates and resumable historical backfill
-- share exactly the same projection, including updates from older API binaries.
CREATE FUNCTION project_biobalance_sale(target uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE s "Sale"%ROWTYPE; old "SalesContribution"%ROWTYPE; d date; line jsonb; item jsonb;
 qty bigint; total_qty bigint:=0; total_amount bigint:=0; amount bigint; products jsonb:='[]';
BEGIN
 SELECT * INTO s FROM "Sale" WHERE id=target FOR UPDATE;
 IF NOT FOUND THEN RETURN; END IF;
 SELECT * INTO old FROM "SalesContribution" WHERE "saleId"=target;
 IF FOUND AND old.version=s.version THEN RETURN; END IF;
 d:=((s."occurredAt" AT TIME ZONE 'UTC') AT TIME ZONE (SELECT timezone FROM "Store" WHERE id=s."storeId"))::date;
 FOR line IN SELECT value FROM jsonb_array_elements(s.lines) LOOP
  SELECT (line->>'quantity')::bigint-COALESCE(SUM(value::bigint),0) INTO qty
   FROM jsonb_each_text(s.returned) WHERE split_part(key,':',1)=line->>'id';
  amount:=qty*(line->>'unitPriceMillimes')::bigint;
  total_qty:=total_qty+qty; total_amount:=total_amount+amount;
  products:=products||jsonb_build_array(jsonb_build_object('productId',line->>'productId','units',qty,'amount',amount));
 END LOOP;
 IF old."saleId" IS NOT NULL THEN
  UPDATE "SalesDay" SET "saleCount"="saleCount"-1,"netUnits"="netUnits"-old."netUnits","netMillimes"="netMillimes"-old."netMillimes"
   WHERE "storeId"=old."storeId" AND "sellerId"=old."sellerId" AND day=old.day;
  FOR item IN SELECT value FROM jsonb_array_elements(old.products) LOOP
   UPDATE "SalesProductDay" SET "netUnits"="netUnits"-(item->>'units')::bigint,"netMillimes"="netMillimes"-(item->>'amount')::bigint
    WHERE "storeId"=old."storeId" AND "sellerId"=old."sellerId" AND "productId"=(item->>'productId')::uuid AND day=old.day;
  END LOOP;
 END IF;
 INSERT INTO "SalesDay" VALUES(s."organizationId",s."storeId",s."sellerId",d,1,total_qty,total_amount)
 ON CONFLICT ("storeId","sellerId",day) DO UPDATE SET "saleCount"="SalesDay"."saleCount"+1,"netUnits"="SalesDay"."netUnits"+EXCLUDED."netUnits","netMillimes"="SalesDay"."netMillimes"+EXCLUDED."netMillimes";
 FOR item IN SELECT value FROM jsonb_array_elements(products) LOOP
  INSERT INTO "SalesProductDay" VALUES(s."organizationId",s."storeId",s."sellerId",(item->>'productId')::uuid,d,(item->>'units')::bigint,(item->>'amount')::bigint)
  ON CONFLICT ("storeId","sellerId","productId",day) DO UPDATE SET "netUnits"="SalesProductDay"."netUnits"+EXCLUDED."netUnits","netMillimes"="SalesProductDay"."netMillimes"+EXCLUDED."netMillimes";
 END LOOP;
 INSERT INTO "SalesContribution" VALUES(s.id,s."organizationId",s."storeId",s."sellerId",d,s.version,total_qty,total_amount,products)
 ON CONFLICT ("saleId") DO UPDATE SET version=EXCLUDED.version,"netUnits"=EXCLUDED."netUnits","netMillimes"=EXCLUDED."netMillimes",products=EXCLUDED.products;
END $$;
CREATE FUNCTION biobalance_sale_projection_trigger() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN PERFORM project_biobalance_sale(NEW.id); RETURN NEW; END $$;
CREATE TRIGGER "Sale_reporting" AFTER INSERT OR UPDATE ON "Sale" FOR EACH ROW EXECUTE FUNCTION biobalance_sale_projection_trigger();
