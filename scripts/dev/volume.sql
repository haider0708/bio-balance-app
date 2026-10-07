-- Fills the LOCAL development database with a year of heavy activity, to measure how the
-- server behaves with real volume: 60 stores, 240 sellers, 300 000 sales, 600 000 lines.
-- Run after scripts/dev/reset-dev-world.sh:  docker exec -i biobalance-dev-postgres-1 psql -U biobalance -d biobalance < scripts/dev/volume.sql
\timing off
BEGIN;
ALTER TABLE "WalletEntry" DISABLE TRIGGER USER;
INSERT INTO "Pdv"(id,name,address,city,"regionId",status,"createdById","decidedById","decidedAt")
SELECT gen_random_uuid(), 'Volume store '||g, g||' rue du Test', 'City '||(g%12), r.id, 'ACTIVE',
       (SELECT id FROM "User" WHERE role='ADMIN' LIMIT 1), (SELECT id FROM "User" WHERE role='ADMIN' LIMIT 1), now()
FROM generate_series(1,60) g JOIN LATERAL (SELECT id FROM "Region" ORDER BY code OFFSET (g%3) LIMIT 1) r ON true;
INSERT INTO "User"(id,email,name,role,status,"regionId","pdvId","passwordHash")
SELECT gen_random_uuid(), 'volume'||row_number() over()||'@example.test', 'Volume seller '||row_number() over(), 'VENDEUR','ACTIVE', p."regionId", p.id, 'x'
FROM "Pdv" p CROSS JOIN generate_series(1,4) WHERE p.name LIKE 'Volume store%';
CREATE TEMP TABLE sellers AS SELECT u.id, u."pdvId", u."regionId", row_number() over() AS n FROM "User" u WHERE u.email LIKE 'volume%';
CREATE TEMP TABLE prods AS SELECT id, row_number() over() AS n FROM "Product" WHERE active;
INSERT INTO "Sale"(id,"pdvId","regionId","sellerId","occurredAt",day,units,"rewardMillimes",status,version,"createdAt")
SELECT gen_random_uuid(), s."pdvId", s."regionId", s.id,
       t.ts, t.ts::date, 3, 1500, 'ACTIVE', 1, t.ts
FROM generate_series(1,300000) g
JOIN sellers s ON s.n = 1 + (g % (SELECT count(*) FROM sellers))
JOIN LATERAL (SELECT now() - (random()*365) * interval '1 day' AS ts) t ON true;
INSERT INTO "SaleLine"(id,"saleId","productId",quantity,"unitRewardMillimes")
SELECT gen_random_uuid(), sa.id, p.id, 1 + (k % 2), 500
FROM (SELECT id, row_number() over() AS rn FROM "Sale" WHERE "sellerId" IN (SELECT id FROM sellers)) sa
CROSS JOIN generate_series(1,2) k
JOIN prods p ON p.n = 1 + ((sa.rn + k * 7) % (SELECT count(*) FROM prods));
INSERT INTO "WalletEntry"(id,"userId",kind,"amountMillimes","saleId")
SELECT gen_random_uuid(), "sellerId", 'SALE', "rewardMillimes", id FROM "Sale" WHERE "sellerId" IN (SELECT id FROM sellers) LIMIT 300000;
ALTER TABLE "WalletEntry" ENABLE TRIGGER USER;
COMMIT;
ANALYZE;
SELECT 'sales', count(*) FROM "Sale" UNION ALL SELECT 'lines', count(*) FROM "SaleLine" UNION ALL SELECT 'wallet', count(*) FROM "WalletEntry";
