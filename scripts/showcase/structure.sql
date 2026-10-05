\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE ids AS SELECT
  gen_random_uuid() grp, gen_random_uuid() wh, gen_random_uuid() sp, gen_random_uuid() sph, gen_random_uuid() depot;
INSERT INTO "Organization"(id,name,kind,phone) SELECT grp,'PARAHOUSE GROUPE','retail','+216 71 560 120' FROM ids;
INSERT INTO "Organization"(id,name,kind,phone) SELECT wh,'HEDI','wholesale','+216 72 285 340' FROM ids;
INSERT INTO "Store"(id,"organizationId",name,nature,address,city,phone,"onboardingStep","workingAlone")
  SELECT sp,grp,'PARAHOUSE','parapharmacie','Avenue Habib Bourguiba, Le Bardo','Tunis','+216 71 560 121',5,false FROM ids;
INSERT INTO "Store"(id,"organizationId",name,nature,address,city,phone,"onboardingStep","workingAlone")
  SELECT sph,grp,'PHARMAHOUSE','pharmacie','12 rue de Marseille','Tunis','+216 71 560 122',5,false FROM ids;
INSERT INTO "Store"(id,"organizationId",name,nature,address,city,phone,"onboardingStep")
  SELECT depot,wh,'HEDI',NULL,'Zone industrielle Korba','Nabeul','+216 72 285 341',5 FROM ids;
-- accounts -> places
INSERT INTO "OrganizationMembership"(id,"organizationId","userId")
  SELECT gen_random_uuid(),grp,u.id FROM ids, "User" u WHERE u.email='haydar.boudhrioua@gmail.com';
INSERT INTO "OrganizationMembership"(id,"organizationId","userId")
  SELECT gen_random_uuid(),wh,u.id FROM ids, "User" u WHERE u.email='hayder@tanpony.com';
INSERT INTO "Membership"(id,"organizationId","storeId","userId",permissions)
  SELECT gen_random_uuid(),grp,s,u.id,ARRAY['manage','sell','receive'] FROM ids, unnest(ARRAY[sp,sph]) s, "User" u WHERE u.email='haydar.boudhrioua@gmail.com';
INSERT INTO "Membership"(id,"organizationId","storeId","userId",permissions)
  SELECT gen_random_uuid(),grp,sph,u.id,ARRAY['sell'] FROM ids, "User" u WHERE u.email='hayder.boudhrioua@gmail.com';
INSERT INTO "Membership"(id,"organizationId","storeId","userId",permissions)
  SELECT gen_random_uuid(),grp,sp,u.id,ARRAY['sell'] FROM ids, "User" u WHERE u.email='besel62147@caps7.com';
INSERT INTO "Membership"(id,"organizationId","storeId","userId",permissions)
  SELECT gen_random_uuid(),wh,depot,u.id,ARRAY['manage','receive'] FROM ids, "User" u WHERE u.email='hayder@tanpony.com';
-- price chain, recorded 20 days ago
CREATE TEMP TABLE pr AS
SELECT p.id pid, p.category,
  (CASE p.category WHEN 'Sérums' THEN 52 WHEN 'Crèmes visage' THEN 42 WHEN 'Nettoyants visage' THEN 26 WHEN 'Maquillage' THEN 24
     WHEN 'Soins capillaires' THEN 28 WHEN 'Soins personnels' THEN 17 ELSE 46 END
   + (row_number() OVER (ORDER BY p.reference) * 37) % (CASE p.category WHEN 'Sérums' THEN 58 WHEN 'Crèmes visage' THEN 40 WHEN 'Nettoyants visage' THEN 20 WHEN 'Maquillage' THEN 38
     WHEN 'Soins capillaires' THEN 24 WHEN 'Soins personnels' THEN 16 ELSE 10 END))::bigint * 1000
   + (row_number() OVER (ORDER BY p.reference) % 2) * 500 AS retail,
  row_number() OVER (ORDER BY p.reference) idx
FROM "Product" p WHERE p.active;
INSERT INTO "PriceVersion"(id,level,"productId","priceMillimes",reason,"createdAt")
  SELECT gen_random_uuid(),'wholesale',pid,round(retail*0.50/100)*100,'Tarif initial',now()-interval '20 days' FROM pr;
INSERT INTO "PriceVersion"(id,level,"productId","priceMillimes",reason,"createdAt")
  SELECT gen_random_uuid(),'store_supply',pid,round(retail*0.68/100)*100,'Tarif initial',now()-interval '20 days' FROM pr;
INSERT INTO "PriceVersion"(id,level,"productId","supplierOrganizationId","priceMillimes",reason,"createdAt")
  SELECT gen_random_uuid(),'store_supply',pid,wh,round(retail*0.62/100)*100,'Tarif initial',now()-interval '20 days' FROM pr, ids;
INSERT INTO "PriceVersion"(id,level,"productId","organizationId","storeId","priceMillimes",reason,"createdAt")
  SELECT gen_random_uuid(),'retail',pid,grp,s,retail,'Prix de lancement',now()-interval '20 days' FROM pr, ids, unnest(ARRAY[sp,sph]) s;
INSERT INTO "StoreProduct"(id,"organizationId","storeId","productId","priceMillimes","priceConfigured",threshold,"pointsPerUnit","pointsConfigured")
  SELECT gen_random_uuid(),grp,s,pid,retail,true,(ARRAY[5,8,10,12])[1+idx%4],greatest(1,round(retail/10000.0))::int,true FROM pr, ids, unnest(ARRAY[sp,sph]) s;
INSERT INTO "StoreProduct"(id,"organizationId","storeId","productId","priceMillimes","priceConfigured",threshold,"pointsPerUnit","pointsConfigured")
  SELECT gen_random_uuid(),wh,depot,pid,0,false,20,1,true FROM pr, ids;
-- BioBalance's default rates: the stores' and the depot's values above.
INSERT INTO "PointsDefault"(id,audience,"productId","pointsPerUnit",reason,"createdAt")
  SELECT gen_random_uuid(),'retail',pid,greatest(1,round(retail/10000.0))::int,'Barème initial',now()-interval '20 days' FROM pr;
INSERT INTO "PointsDefault"(id,audience,"productId","pointsPerUnit",reason,"createdAt")
  SELECT gen_random_uuid(),'wholesale',pid,1,'Barème initial',now()-interval '20 days' FROM pr;
INSERT INTO "PointsRateVersion"(id,"organizationId","storeId","productId","pointsPerUnit",reason,"createdAt")
  SELECT gen_random_uuid(),organizationId,"storeId","productId","pointsPerUnit",'Barème initial',now()-interval '20 days'
  FROM (SELECT "organizationId" organizationId,"storeId","productId","pointsPerUnit" FROM "StoreProduct") x;
-- a few store-specific supply prices from BioBalance
INSERT INTO "PriceVersion"(id,level,"productId","organizationId","storeId","priceMillimes",reason,"createdAt")
  SELECT gen_random_uuid(),'store_supply',pid,grp,sph,round(retail*0.64/100)*100,'Tarif négocié',now()-interval '15 days'
  FROM pr, ids WHERE idx%9=0;
SELECT (SELECT count(*) FROM "Organization") orgs,(SELECT count(*) FROM "Store") stores,(SELECT count(*) FROM "Membership") m,(SELECT count(*) FROM "PriceVersion") prices,(SELECT count(*) FROM "StoreProduct") sp;
COMMIT;
