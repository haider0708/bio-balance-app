-- A year of synthetic sales for load tests: 300 stores, 600 team members, 51 products,
-- 300 000 sales. Never run on a real database. See docs/runbook.md, "Load test".
INSERT INTO "Region"(id, code, name) SELECT gen_random_uuid(), c, initcap(c) FROM unnest(ARRAY['NORD','CENTRE','SUD']) c ON CONFLICT DO NOTHING;
INSERT INTO "User"(id,email,name,role,status) VALUES ('00000000-0000-0000-0000-00000000a001','admin@perf.test','Admin','ADMIN','ACTIVE');
INSERT INTO "Product"(id, reference, name, family, active, "updatedAt")
  SELECT gen_random_uuid(), 'P'||g, 'Product '||g, (ARRAY['Serums','Hair','Face','Body','Sun'])[1+g%5], true, now() FROM generate_series(1,51) g;
INSERT INTO "Pdv"(id,"regionId",name,address,city,status,"createdById")
  SELECT gen_random_uuid(), (SELECT id FROM "Region" ORDER BY code OFFSET g%3 LIMIT 1), 'Store '||g, 'addr', 'City '||(g%20), 'ACTIVE', '00000000-0000-0000-0000-00000000a001' FROM generate_series(1,300) g;
INSERT INTO "User"(id,email,name,role,status,"regionId","pdvId")
  SELECT gen_random_uuid(), 'seller'||g||'@perf.test', 'Seller '||g, 'VENDEUR','ACTIVE', p."regionId", p.id
  FROM generate_series(1,600) g JOIN LATERAL (SELECT * FROM "Pdv" ORDER BY name OFFSET (g%300) LIMIT 1) p ON true;
CREATE TEMP TABLE s AS
  SELECT gen_random_uuid() id, u."pdvId", u."regionId", u.id seller, (now() - (random()*365)*interval '1 day') at
  FROM generate_series(1,300000) g JOIN LATERAL (SELECT * FROM "User" WHERE role='VENDEUR' OFFSET (g%600) LIMIT 1) u ON true;
INSERT INTO "Sale"(id,"pdvId","regionId","sellerId","occurredAt",day,units,"rewardMillimes",status,"createdAt")
  SELECT id,"pdvId","regionId",seller,at,(at AT TIME ZONE 'Africa/Tunis')::date,0,0,'ACTIVE',at FROM s;
INSERT INTO "SaleLine"(id,"saleId","productId",quantity,"unitRewardMillimes")
  SELECT gen_random_uuid(), s.id, p.id, 1+(random()*3)::int, 500
  FROM s JOIN LATERAL (SELECT id FROM "Product" ORDER BY random() LIMIT 1+(abs(hashtext(s.id::text))%3)) p ON true;
UPDATE "Sale" x SET units=t.u, "rewardMillimes"=t.r FROM (SELECT "saleId", SUM(quantity) u, SUM(quantity*"unitRewardMillimes") r FROM "SaleLine" GROUP BY 1) t WHERE t."saleId"=x.id;
INSERT INTO "Stock"("locationId","productId","locationKind","regionId",quantity)
  SELECT pd.id, p.id, 'PDV', pd."regionId", (random()*40)::int FROM "Pdv" pd CROSS JOIN "Product" p;
ANALYZE;
SELECT (SELECT count(*) FROM "Sale") sales, (SELECT count(*) FROM "SaleLine") lines;
