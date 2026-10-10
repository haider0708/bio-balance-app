/**
 * A busy month across the three regions, then a check that the books balance:
 * stock equals the sum of its movements, wallets equal the sum of their entries,
 * every sale's reward equals its lines, and nothing leaks between regions.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import {
  client,
  createAccount,
  fakeJpeg,
  owner,
  regionId,
  resetDatabase,
  startApi,
  type Account,
  type Api,
} from "./helpers";
import { tunisDay } from "../src/core/dates";

let api: Api;
beforeAll(async () => {
  api = await startApi();
  await resetDatabase();
});
afterAll(() => api.close());

/** A small deterministic generator, so a failure can be replayed. */
function random(seed: number) {
  let s = seed;
  return () => (s = (s * 1664525 + 1013904223) % 4294967296) / 4294967296;
}

describe("a month of activity", () => {
  it("keeps stock, wallets, rewards and regions consistent", async () => {
    const rnd = random(2026);
    const pick = <T>(list: T[]) => list[Math.floor(rnd() * list.length)]!;

    const admin = await createAccount({ role: "ADMIN" });
    const a = client(api, admin.token);
    const products: string[] = [];
    for (let i = 1; i <= 8; i++)
      products.push(
        (
          await a.post("/v1/products", {
            reference: `S${i}`,
            name: `Product ${i}`,
            family: i <= 4 ? "Serums" : "Hair",
          })
        ).body.id,
      );
    const today = tunisDay(new Date());
    await a.post("/v1/reward-rules", {
      scope: "FAMILY",
      family: "Serums",
      amountMillimes: 500,
      startsOn: today,
    });
    await a.post("/v1/reward-rules", {
      scope: "FAMILY",
      family: "Hair",
      amountMillimes: 300,
      startsOn: today,
    });
    await a.post("/v1/reward-rules", {
      scope: "PRODUCT",
      productId: products[0],
      amountMillimes: 900,
      startsOn: today,
    });

    const photo = async (who: Account) =>
      (await client(api, who.token).upload("PROOF", fakeJpeg())).body
        .id as string;
    const lines = (qty: (i: number) => number) =>
      products
        .map((productId, i) => ({ productId, quantity: qty(i) }))
        .filter((l) => l.quantity > 0);

    // One grossiste (warehouse) per region, counted by the admin with a photo.
    const grossistes: { depotId: string; code: string }[] = [];
    for (const [name, code] of [
      ["Hedi", "NORD"],
      ["Mounir", "CENTRE"],
      ["Slim", "SUD"],
    ] as const) {
      const depotId = (
        await a.post("/v1/depots", {
          regionId: await regionId(code),
          name: `Depot ${name}`,
          address: "ZI",
          city: "Tunis",
        })
      ).body.id as string;
      const counted = await a.post("/v1/stock/declarations", {
        locationId: depotId,
        photoIds: [await photo(admin)],
        lines: lines(() => 400),
      });
      if (counted.status !== 201)
        throw new Error(`count failed: ${JSON.stringify(counted.body)}`);
      grossistes.push({ depotId, code });
    }

    // Three regions, two points of sale each, three vendeurs per point of sale.
    interface Shop {
      pdvId: string;
      code: string;
      resp: Account;
      vendeurs: Account[];
    }
    const shops: Shop[] = [];
    for (const code of ["NORD", "CENTRE", "SUD"]) {
      const resp = await createAccount({
        role: "RESPONSABLE",
        regionCode: code,
        name: `Resp ${code}`,
      });
      const r = client(api, resp.token);
      for (let p = 1; p <= 2; p++) {
        const pdv = (
          await r.post("/v1/pdvs", {
            name: `${code} ${p}`,
            address: "1 rue",
            city: code,
          })
        ).body;
        await a.post(`/v1/pdvs/${pdv.id}/approve`, {});
        const decl = (
          await r.post("/v1/stock/declarations", {
            locationId: pdv.id,
            photoId: await photo(resp),
            lines: lines(() => 400),
          })
        ).body;
        await a.post(`/v1/stock/declarations/${decl.id}/approve`, {});
        const vendeurs = [];
        for (let v = 1; v <= 3; v++)
          vendeurs.push(
            await createAccount({
              role: "VENDEUR",
              pdvId: pdv.id,
              name: `${code}-${p}-${v}`,
            }),
          );
        shops.push({ pdvId: pdv.id, code, resp, vendeurs });
      }
    }

    // Thirty days of selling, correcting, restocking and paying out.
    const sales: { id: string; shop: Shop; seller: Account }[] = [];
    for (let day = 0; day < 30; day++) {
      for (const shop of shops) {
        for (const seller of shop.vendeurs) {
          if (rnd() < 0.6) continue;
          const id = randomUUID();
          const chosen = new Set<number>();
          while (chosen.size < 1 + Math.floor(rnd() * 3))
            chosen.add(Math.floor(rnd() * products.length));
          const res = await client(api, seller.token).post("/v1/sales", {
            id,
            lines: [...chosen].map((i) => ({
              productId: products[i],
              quantity: 1 + Math.floor(rnd() * 3),
            })),
          });
          expect(res.status).toBe(201);
          sales.push({ id, shop, seller });
        }
      }
      // A few corrections and cancellations.
      for (const s of [pick(sales), pick(sales)]) {
        const current = (
          await client(api, s.seller.token).get(`/v1/sales/${s.id}`)
        ).body;
        if (current.status === "VOIDED") continue;
        const keep = current.lines
          .slice(0, rnd() < 0.3 ? 0 : 1)
          .map((l: any) => ({
            productId: l.productId,
            quantity: Math.max(1, l.quantity - 1),
          }));
        await client(api, s.shop.resp.token).post(`/v1/sales/${s.id}/correct`, {
          reason: "Recount",
          lines: keep,
        });
      }
      // Weekly restock for a random shop, through a grossiste or directly.
      if (day % 5 === 0) {
        const shop = pick(shops);
        const r = client(api, shop.resp.token);
        const order = (
          await r.post("/v1/restocks", {
            destId: shop.pdvId,
            lines: lines((i) => 3 + (i % 4)),
          })
        ).body;
        const viaGrossiste = rnd() < 0.6;
        if (viaGrossiste) {
          const g = grossistes.find((x) => x.code === shop.code)!;
          await a.post(`/v1/restocks/${order.id}/assign`, {
            depotId: g.depotId,
          });
          await r.post(`/v1/restocks/${order.id}/ship`, {
            lines: lines((i) => 3 + (i % 4)),
          });
        } else await a.post(`/v1/restocks/${order.id}/send-direct`, {});
        const receiver = rnd() < 0.5 ? shop.vendeurs[0]! : shop.resp;
        if (receiver !== shop.resp)
          await r.put(`/v1/restocks/${order.id}/receiver`, {
            userId: receiver.id,
          });
        await client(api, receiver.token).post(
          `/v1/restocks/${order.id}/receipt`,
          {
            photoId: await photo(receiver),
            lines: lines((i) => 3 + (i % 4) - (rnd() < 0.2 ? 1 : 0)),
          },
        );
        const amend = rnd() < 0.3 ? { lines: lines(() => 3).slice(0, 2) } : {};
        await a.post(`/v1/restocks/${order.id}/approve`, amend);
      }
      // A payout request now and then, decided by the admin.
      if (day % 7 === 6) {
        const seller = pick(sales).seller;
        const wallet = (await client(api, seller.token).get("/v1/wallet")).body;
        if (wallet.availableMillimes > 1000) {
          const payout = (
            await client(api, seller.token).post("/v1/payouts", {
              amountMillimes: 1000,
            })
          ).body;
          await a.post(
            `/v1/payouts/${payout.id}/${rnd() < 0.7 ? "approve" : "reject"}`,
            rnd() < 0.5 ? {} : { note: "Later" },
          );
        }
      }
    }
    expect(sales.length).toBeGreaterThan(200);

    // ───────────── The books must balance ─────────────
    const db = await owner();
    const one = async (sql: string) => (await db.query(sql)).rows;
    try {
      expect(
        await one(`SELECT s."locationId", s."productId", s.quantity, m.total FROM "Stock" s
        LEFT JOIN (SELECT "locationId","productId",SUM(delta)::int AS total FROM "StockMovement" GROUP BY 1,2) m USING ("locationId","productId")
        WHERE s.quantity IS DISTINCT FROM COALESCE(m.total,0)`),
      ).toEqual([]);

      expect(
        await one(`SELECT s.id FROM "Sale" s JOIN (SELECT "saleId", SUM(quantity) AS units, SUM(quantity*"unitRewardMillimes") AS reward FROM "SaleLine" GROUP BY 1) l ON l."saleId"=s.id
        WHERE s.units <> l.units OR s."rewardMillimes" <> l.reward`),
      ).toEqual([]);
      expect(
        await one(
          `SELECT id FROM "Sale" WHERE status='VOIDED' AND (units<>0 OR "rewardMillimes"<>0)`,
        ),
      ).toEqual([]);

      // Each person's wallet is exactly what their sales earned, minus what was paid.
      expect(
        await one(`SELECT u.id FROM "User" u
        LEFT JOIN (SELECT "sellerId", SUM("rewardMillimes") AS earned FROM "Sale" GROUP BY 1) s ON s."sellerId"=u.id
        LEFT JOIN (SELECT "userId", SUM("amountMillimes") FILTER (WHERE kind IN ('SALE','CORRECTION')) AS credited,
                   SUM(-"amountMillimes") FILTER (WHERE kind='PAYOUT') AS paid FROM "WalletEntry" GROUP BY 1) w ON w."userId"=u.id
        WHERE u.role='VENDEUR' AND COALESCE(s.earned,0) <> COALESCE(w.credited,0)`),
      ).toEqual([]);
      expect(
        await one(`SELECT p.id FROM "PayoutRequest" p LEFT JOIN "WalletEntry" w ON w."payoutId"=p.id
        WHERE (p.status='APPROVED' AND (w."amountMillimes" IS NULL OR w."amountMillimes" <> -p."amountMillimes")) OR (p.status<>'APPROVED' AND w.id IS NOT NULL)`),
      ).toEqual([]);

      // Every completed restock moved exactly its approved quantities into the store,
      // and a grossiste's depot gave exactly what it shipped.
      expect(
        await one(`SELECT o.id FROM "RestockOrder" o JOIN "RestockLine" l ON l."orderId"=o.id
        LEFT JOIN (SELECT "refId","productId", SUM(delta) AS credited FROM "StockMovement" WHERE reason='RECEIPT' GROUP BY 1,2) c ON c."refId"=o.id AND c."productId"=l."productId"
        WHERE o.status='COMPLETED' AND COALESCE(c.credited,0) <> COALESCE(l.approved,0)`),
      ).toEqual([]);
      expect(
        await one(`SELECT o.id FROM "RestockOrder" o JOIN "RestockLine" l ON l."orderId"=o.id
        LEFT JOIN (SELECT "refId","productId", SUM(-delta) AS debited FROM "StockMovement" WHERE reason='SHIPMENT' GROUP BY 1,2) d ON d."refId"=o.id AND d."productId"=l."productId"
        WHERE o.status='COMPLETED' AND ((o.source='GROSSISTE' AND COALESCE(d.debited,0) <> COALESCE(l.shipped,0)) OR (o.source='BIOBALANCE' AND d.debited IS NOT NULL))`),
      ).toEqual([]);
      expect(
        await one(
          `SELECT id FROM "RestockOrder" WHERE status NOT IN ('COMPLETED','CANCELLED')`,
        ),
      ).toEqual([]);

      // Nothing belongs to the wrong region.
      expect(
        await one(
          `SELECT s.id FROM "Sale" s JOIN "Pdv" p ON p.id=s."pdvId" WHERE p."regionId" <> s."regionId"`,
        ),
      ).toEqual([]);
      expect(
        await one(
          `SELECT s."locationId" FROM "Stock" s JOIN "Pdv" p ON p.id=s."locationId" WHERE p."regionId" <> s."regionId"`,
        ),
      ).toEqual([]);
      expect(
        await one(
          `SELECT u.id FROM "User" u JOIN "Pdv" p ON p.id=u."pdvId" WHERE p."regionId" <> u."regionId"`,
        ),
      ).toEqual([]);

      const totals = (
        await one(
          `SELECT count(*)::int AS sales, COALESCE(sum(units),0)::int AS units FROM "Sale"`,
        )
      )[0];
      expect(totals.sales).toBe(sales.length);
    } finally {
      await db.end();
    }

    // And each responsable sees only their own region, however busy it got.
    const nordResp = client(api, shops[0]!.resp.token);
    const visible = (await nordResp.get("/v1/pdvs")).body.map(
      (p: any) => p.name,
    );
    expect(visible).toEqual(["NORD 1", "NORD 2"]);
    const regionIds = new Set(
      (await nordResp.get("/v1/sales?limit=100")).body.items.map(
        (s: any) => s.pdv.name.split(" ")[0],
      ),
    );
    expect([...regionIds]).toEqual(["NORD"]);
  }, 300_000);
});
