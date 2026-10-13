import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import {
  client,
  createAccount,
  owner,
  resetDatabase,
  startApi,
  type Account,
  type Api,
} from "./helpers";
import { approvedPdv, buildWorld, stockPlace, type World } from "./world";
import { Database } from "../src/core/database";
import { addDays, tunisDay } from "../src/core/dates";
import { noticeText } from "../src/core/notice-text";
import { scheduleDaySummary, sendDaySummaries } from "../src/jobs/day-summary";

/** Who hears about what (docs/notifications.md): the parts added for the real launch. */
let api: Api;
let w: World;
let db: Database;
let seller: Account;
const today = () => tunisDay(new Date());

async function inbox(account: Account) {
  const ownerDb = await owner();
  try {
    return (
      await ownerDb.query<{ key: string; params: any; pushed: boolean }>(
        `SELECT key, params, "pushedAt" IS NOT NULL AS pushed FROM "Notification"
         WHERE "userId" = $1 ORDER BY "createdAt"`,
        [account.id],
      )
    ).rows;
  } finally {
    await ownerDb.end();
  }
}

beforeAll(async () => {
  api = await startApi();
  db = api.app.get(Database);
});
afterAll(() => api?.close());
beforeEach(async () => {
  await resetDatabase();
  w = await buildWorld(api);
  await w.a.post("/v1/reward-rules", {
    scope: "FAMILY",
    family: "Serums",
    amountMillimes: 500,
    startsOn: today(),
  });
  const pdv = await approvedPdv(w, "n", "Para Nord");
  await stockPlace(w, pdv.id, w.nord, [3, 50, 50]);
  seller = await createAccount({ role: "VENDEUR", pdvId: pdv.id });
  const ownerDb = await owner();
  await ownerDb.query(`DELETE FROM "Notification"`);
  await ownerDb.end();
});

describe("each sale", () => {
  it("is in the responsable's inbox, without waking their phone", async () => {
    await client(api, seller.token).post("/v1/sales", {
      id: randomUUID(),
      lines: [{ productId: w.products[0]!.id, quantity: 1 }],
    });
    expect(await inbox(w.nord)).toEqual([
      expect.objectContaining({ key: "sale.recorded", pushed: true }),
    ]);
  });
});

describe("the evening summary", () => {
  it("gives each responsable their region's day and the admin the network's", async () => {
    await client(api, seller.token).post("/v1/sales", {
      id: randomUUID(),
      lines: [{ productId: w.products[0]!.id, quantity: 3 }],
    });
    await sendDaySummaries(db, today());
    const nord = (await inbox(w.nord)).find((n) => n.key.startsWith("day."));
    // The only serum in stock was sold: the summary says so.
    expect(nord).toMatchObject({
      key: "day.summary_stock",
      pushed: false,
      params: { sales: 1, units: 3, amountMillimes: 1500, outOfStock: 1 },
    });
    expect(noticeText("en", nord!.key, nord!.params)).toBe(
      "Today in Nord: 1 sale, 3 units, 1.500 TND in rewards. 1 product is out of stock in its stores.",
    );
    // Sud has no store: nothing for it.
    expect(await inbox(w.sud)).toEqual([]);
    expect(await inbox(w.admin)).toEqual([
      expect.objectContaining({
        key: "day.network",
        params: { sales: 1, units: 3, amountMillimes: 1500 },
      }),
    ]);
  });

  it("says when a region sold nothing, and leaves out the test region", async () => {
    await sendDaySummaries(db, today());
    expect((await inbox(w.nord))[0]?.key).toBe("day.summary_none");
    const ownerDb = await owner();
    await ownerDb.query(`DELETE FROM "Notification"`);
    await ownerDb.query(
      `UPDATE "Region" SET sandbox = true WHERE code = 'NORD'`,
    );
    await ownerDb.end();
    await sendDaySummaries(db, today());
    expect(await inbox(w.nord)).toEqual([]);
    expect(await inbox(w.admin)).toEqual([]);
  });

  it("goes out once a day, from 20:30 Tunis time", async () => {
    const day = today();
    const at = (time: string) => new Date(`${day}T${time}+01:00`);
    await scheduleDaySummary(db, at("20:29:00"));
    await scheduleDaySummary(db, at("20:30:00"));
    await scheduleDaySummary(db, at("22:00:00"));
    const ownerDb = await owner();
    const { rows } = await ownerDb.query(
      `SELECT key FROM "Job" WHERE kind = 'day-summary'`,
    );
    await ownerDb.end();
    expect(rows).toEqual([{ key: `day-summary:${day}` }]);
  });
});

describe("what sellers want to know", () => {
  it("a new reward rate is announced to every seller, a past one is not", async () => {
    await w.a.post("/v1/reward-rules", {
      scope: "PRODUCT",
      productId: w.products[2]!.id,
      amountMillimes: 750,
      startsOn: addDays(today(), 1),
    });
    await w.a.post("/v1/reward-rules", {
      scope: "FAMILY",
      family: "Hair",
      amountMillimes: 100,
      startsOn: addDays(today(), -20),
      endsOn: addDays(today(), -10),
    });
    const got = await inbox(seller);
    expect(got).toHaveLength(1);
    expect(noticeText("fr", got[0]!.key, got[0]!.params)).toBe(
      `Nouvelle récompense à partir du ${addDays(today(), 1).split("-").reverse().join("/")} : 0,750 TND par unité de Shampoo Argan.`,
    );
    expect(await inbox(w.nord)).toEqual([]);
  });

  it("a training that becomes available is announced to the people it is for, once", async () => {
    const course = (
      await w.a.post("/v1/courses", {
        title: "Selling serums",
        summary: "The basics",
        audience: { roles: ["VENDEUR"] },
      })
    ).body;
    await w.a.post(`/v1/courses/${course.id}/lessons`, {
      title: "Introduction",
      kind: "ARTICLE",
      body: "Welcome.",
    });
    await w.a.post(`/v1/courses/${course.id}/publish`, {});
    await w.a.post(`/v1/courses/${course.id}/publish`, {});
    expect(await inbox(seller)).toEqual([
      expect.objectContaining({
        key: "course.published",
        params: { title: "Selling serums" },
      }),
    ]);
    expect(await inbox(w.nord)).toEqual([]);
  });
});

describe("the words", () => {
  it("say one unit, zero unité, and dates the Tunisian way", () => {
    const sold = (units: number) => ({
      seller: "Amine",
      units,
      place: "Lac",
      amountMillimes: 500,
    });
    expect(noticeText("en", "sale.recorded", sold(1))).toBe(
      "Amine sold 1 unit at Lac · 0.500 TND earned.",
    );
    expect(noticeText("en", "sale.recorded", sold(1200))).toContain(
      "sold 1,200 units",
    );
    expect(noticeText("fr", "sale.recorded", sold(0))).toContain(
      "a vendu 0 unité à",
    );
    expect(noticeText("fr", "day.summary_none", { region: "Nord" })).toBe(
      "Aucune vente enregistrée aujourd’hui, région Nord.",
    );
  });
});
