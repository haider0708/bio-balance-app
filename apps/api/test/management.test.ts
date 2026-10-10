import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import {
  client,
  createAccount,
  owner,
  resetDatabase,
  startApi,
  type Api,
} from "./helpers";
import {
  approvedPdv,
  buildWorld,
  stockPlace,
  teamMember,
  type World,
} from "./world";
import { addDays, tunisDay } from "../src/core/dates";

let api: Api;
let w: World;
const today = () => tunisDay(new Date());
beforeAll(async () => {
  api = await startApi();
});
afterAll(() => api.close());
beforeEach(async () => {
  await resetDatabase();
  w = await buildWorld(api);
});

async function twoRegionsWithSales() {
  await w.a.post("/v1/reward-rules", {
    scope: "FAMILY",
    family: "Serums",
    amountMillimes: 500,
    startsOn: today(),
  });
  const north = await approvedPdv(w, "n", "Para Nord");
  const south = await approvedPdv(w, "s", "Para Sud");
  await stockPlace(w, north.id, w.nord, [10, 30, 30]);
  await stockPlace(w, south.id, w.sud, [30, 30, 30]);
  const a = client(api, (await teamMember(w, north.id, "Anis")).token);
  const c = client(api, (await teamMember(w, south.id, "Chiraz")).token);
  await a.post("/v1/sales", {
    id: randomUUID(),
    lines: [
      { productId: w.products[0]!.id, quantity: 5 },
      { productId: w.products[2]!.id, quantity: 1 },
    ],
  });
  await a.post("/v1/sales", {
    id: randomUUID(),
    lines: [{ productId: w.products[1]!.id, quantity: 2 }],
  });
  await c.post("/v1/sales", {
    id: randomUUID(),
    lines: [{ productId: w.products[1]!.id, quantity: 4 }],
  });
  return { north, south, a, c };
}

describe("approvals inbox", () => {
  it("lists everything waiting for the admin, by kind, and shrinks as decisions are made", async () => {
    const pdv = await approvedPdv(w);
    const group = (await w.n.post("/v1/groups", { name: "Groupe N" })).body;
    const waitingPdv = (
      await w.n.post("/v1/pdvs", {
        name: "Para 2",
        address: "1 rue",
        city: "Sfax",
      })
    ).body;
    await w.n.post(`/v1/pdvs/${pdv.id}/members`, {
      name: "Karim",
      email: "karim@example.test",
    });
    await w.n.post("/v1/stock/declarations", {
      locationId: pdv.id,
      photoId: (
        await w.n.upload("PROOF", (await import("./helpers")).fakeJpeg())
      ).body.id,
      lines: [{ productId: w.products[0]!.id, quantity: 4 }],
    });
    const req = (
      await w.n.post("/v1/restocks", {
        destId: pdv.id,
        lines: [{ productId: w.products[0]!.id, quantity: 2 }],
      })
    ).body;

    const inbox = (await w.a.get("/v1/approvals")).body;
    expect(inbox.counts).toMatchObject({
      GROUP: 1,
      PDV: 1,
      MEMBER: 1,
      STOCK: 1,
      RESTOCK_REQUEST: 1,
      RECEIPT: 0,
      PAYOUT: 0,
      total: 5,
    });
    expect(inbox.items.map((i: any) => i.type).sort()).toEqual([
      "GROUP",
      "MEMBER",
      "PDV",
      "RESTOCK_REQUEST",
      "STOCK",
    ]);
    expect(inbox.items.find((i: any) => i.type === "PDV")).toMatchObject({
      name: "Para 2",
      by: "Nora Nord",
      region: "Nord",
    });

    await w.a.post(`/v1/groups/${group.id}/approve`, {});
    await w.a.post(`/v1/pdvs/${waitingPdv.id}/approve`, {});
    await w.a.post(`/v1/restocks/${req.id}/send-direct`, {});
    expect((await w.a.get("/v1/approvals")).body.counts.total).toBe(2);
    expect(
      (await w.a.get(`/v1/approvals?regionId=${pdv.regionId}&type=MEMBER`)).body
        .items,
    ).toHaveLength(1);
    expect((await w.n.get("/v1/approvals")).status).toBe(403);
  });
});

describe("dashboards", () => {
  it("shows the admin every region side by side", async () => {
    await twoRegionsWithSales();
    const d = (await w.a.get("/v1/dashboard")).body;
    expect(d.sales.today).toMatchObject({ sales: 3, units: 12 });
    expect(d.sales.week.units).toBe(12);
    expect(d.regions.map((r: any) => [r.code, r.units, r.pdvs])).toEqual([
      ["CENTRE", 0, 0],
      ["NORD", 8, 1],
      ["SUD", 4, 1],
    ]);
    expect(d.topProducts[0]).toMatchObject({
      name: "Serum Niacinamide",
      units: 6,
    });
    expect(d.trend).toHaveLength(14);
    expect(d.attention).toEqual({ negativeStock: 0, lowStock: 1 });
    expect(d.pdvs.active).toBe(2);
    // One line per store with something running out, not one per product.
    expect(d.lowByPlace).toEqual([
      expect.objectContaining({ place: "Para Nord", low: 1, out: 0 }),
    ]);
    expect(d.lowStock).toBeUndefined();
  });

  it("limits a responsable to their own region", async () => {
    await twoRegionsWithSales();
    const north = (await w.n.get("/v1/dashboard")).body;
    const south = (await w.s.get("/v1/dashboard")).body;
    expect(north.sales.week.units).toBe(8);
    expect(south.sales.week.units).toBe(4);
    expect(north.topPdvs.map((p: any) => p.name)).toEqual(["Para Nord"]);
    expect(north.regions).toEqual([]);
    // Even naming another region does not widen what a responsable sees.
    const sneaky = (
      await w.n.get(
        `/v1/dashboard?regionId=${(await w.s.get("/v1/me")).body.region.id}`,
      )
    ).body;
    expect(sneaky.sales.week.units).toBe(8);
  });

  it("gives a team member their own numbers", async () => {
    const { a } = await twoRegionsWithSales();
    const mine = (await a.get("/v1/dashboard")).body;
    expect(mine.week).toMatchObject({ sales: 2, units: 8 });
    expect(mine.wallet.balanceMillimes).toBe(5 * 500 + 2 * 500);
    expect(mine.latest).toHaveLength(2);
  });
});

describe("reports", () => {
  it("groups sales by region, product, family and day, with totals", async () => {
    await twoRegionsWithSales();
    const q = `from=${today()}&to=${today()}`;
    const byRegion = (await w.a.get(`/v1/reports/sales?groupBy=region&${q}`))
      .body;
    expect(byRegion.rows.map((r: any) => [r.label, r.units])).toEqual([
      ["Nord", 8],
      ["Sud", 4],
    ]);
    expect(byRegion.totals).toMatchObject({ sales: 3, units: 12 });
    const byFamily = (await w.a.get(`/v1/reports/sales?groupBy=family&${q}`))
      .body;
    expect(byFamily.rows.map((r: any) => [r.label, r.units])).toEqual([
      ["Serums", 11],
      ["Hair", 1],
    ]);
    const byProduct = (await w.a.get(`/v1/reports/sales?groupBy=product&${q}`))
      .body;
    expect(byProduct.rows[0]).toMatchObject({
      label: "Serum Niacinamide",
      units: 6,
      rewardMillimes: 3000,
    });
    const byDay = (await w.a.get(`/v1/reports/sales?groupBy=day&${q}`)).body;
    expect(byDay.rows).toEqual([
      expect.objectContaining({ label: today(), units: 12 }),
    ]);
  });

  it("never lets a responsable report on another region", async () => {
    const { south } = await twoRegionsWithSales();
    const q = `from=${today()}&to=${today()}&groupBy=region&regionId=${south.regionId}`;
    expect((await w.n.get(`/v1/reports/sales?${q}`)).body.rows).toEqual([]);
    expect(
      (
        await w.n.get(
          `/v1/reports/sales?from=${today()}&to=${today()}&groupBy=region`,
        )
      ).body.rows.map((r: any) => r.label),
    ).toEqual(["Nord"]);
    expect(
      (
        await (
          await fetch(
            `${api.url}/v1/reports/sales.csv?from=${today()}&to=${today()}`,
            { headers: { Authorization: `Bearer ${w.sud.token}` } },
          )
        ).text()
      ).includes("Para Nord"),
    ).toBe(false);
  });

  it("exports a spreadsheet and protects it against formula injection", async () => {
    const { north } = await twoRegionsWithSales();
    await w.n.patch(`/v1/pdvs/${north.id}`, { name: "=HYPERLINK(1)" });
    const res = await fetch(
      `${api.url}/v1/reports/sales.csv?from=${today()}&to=${today()}`,
      { headers: { Authorization: `Bearer ${w.admin.token}` } },
    );
    expect(res.headers.get("content-type")).toContain("text/csv");
    const text = await res.text();
    expect(text).toContain(
      "Date,Time,Region,Point of sale,Seller,Product,Family,Quantity,Reward (TND)",
    );
    expect(text).toContain("'=HYPERLINK(1)");
    expect(text).toContain("2.500");
  });

  it("flags stock that is low, and never lets a sale take it below zero", async () => {
    const { a } = await twoRegionsWithSales();
    const tooMany = await a.post("/v1/sales", {
      id: randomUUID(),
      lines: [{ productId: w.products[0]!.id, quantity: 9 }],
    }); // 10 in stock − 5 = 5 left
    expect(tooMany.status).toBe(409);
    expect(tooMany.body.code).toBe("OUT_OF_STOCK");
    const rows = (await w.a.get("/v1/reports/stock/attention")).body;
    expect(rows[0]).toMatchObject({
      place: "Para Nord",
      product: "Serum Vitamin C",
      quantity: 5,
    });
    const overview = (await w.a.get("/v1/reports/stock")).body;
    expect(overview.find((r: any) => r.name === "Para Nord")).toMatchObject({
      low: 1,
      negative: 0,
    });
    expect(
      (await w.s.get("/v1/reports/stock")).body.map((r: any) => r.name),
    ).toEqual(["Para Sud"]);
  });
});

describe("audit log", () => {
  it("records decisions and is readable by the admin only", async () => {
    const pdv = await approvedPdv(w);
    const log = (await w.a.get(`/v1/audit?entityId=${pdv.id}`)).body;
    expect(log.items.map((i: any) => i.action)).toEqual([
      "pdv.approve",
      "pdv.created",
    ]);
    expect(log.items[0].actor).toMatchObject({ name: "Admin" });
    expect((await w.n.get("/v1/audit")).status).toBe(403);
  });

  it("cannot be rewritten", async () => {
    await approvedPdv(w);
    const db = await owner();
    await expect(db.query(`DELETE FROM "AuditEntry"`)).rejects.toThrow(
      /append-only/,
    );
    await expect(
      db.query(`UPDATE "WalletEntry" SET "amountMillimes" = 1`),
    ).resolves.toBeDefined();
    await db.end();
  });
});

describe("announcements", () => {
  async function people() {
    const pdv = await approvedPdv(w);
    const other = await approvedPdv(w, "s", "Para Sud");
    return {
      pdv,
      other,
      v1: await teamMember(w, pdv.id, "Anis"),
      v2: await teamMember(w, other.id, "Chiraz"),
    };
  }
  const inbox = async (who: { token: string }) =>
    (await client(api, who.token).get("/v1/notifications")).body;

  it("reach exactly the chosen audience", async () => {
    const { v1, v2 } = await people();
    const audience = {
      roles: ["VENDEUR"],
      regionIds: [(await w.n.get("/v1/me")).body.region.id],
    };
    const preview = await w.a.post("/v1/messages/preview", { audience });
    expect(preview.body).toEqual({ recipients: 1, byRole: { VENDEUR: 1 } });
    const sent = await w.a.post("/v1/messages", {
      title: "New serum",
      body: "Try the new serum this week.",
      audience,
      pinned: true,
    });
    expect(sent.body).toMatchObject({
      status: "SENT",
      recipientCount: 1,
      readCount: 0,
    });
    expect((await inbox(v1)).items[0]).toMatchObject({
      kind: "MESSAGE",
      title: "New serum",
      pinned: true,
    });
    expect((await inbox(v2)).items).toHaveLength(0);
    expect(
      (await inbox(w.nord)).items.filter((n: any) => n.kind === "MESSAGE"),
    ).toHaveLength(0);
  });

  it("can target everyone, a role, a point of sale or named people", async () => {
    const { pdv, v1, v2 } = await people();
    expect(
      (await w.a.post("/v1/messages/preview", { audience: { all: true } })).body
        .recipients,
    ).toBe(4); // 2 responsables + 2 team members
    expect(
      (
        await w.a.post("/v1/messages/preview", {
          audience: { roles: ["RESPONSABLE"] },
        })
      ).body.recipients,
    ).toBe(2);
    expect(
      (
        await w.a.post("/v1/messages/preview", {
          audience: { pdvIds: [pdv.id] },
        })
      ).body.recipients,
    ).toBe(1);
    expect(
      (
        await w.a.post("/v1/messages/preview", {
          audience: { userIds: [v1.id, v2.id, w.nord.id] },
        })
      ).body.recipients,
    ).toBe(3);
    expect(
      (
        await w.a.post("/v1/messages", {
          title: "Hi",
          body: "Nobody here",
          audience: { roles: ["VENDEUR"], pdvIds: [randomUUID()] },
        })
      ).body.code,
    ).toBe("NO_RECIPIENTS");
  });

  it("track who has read them, and let people mark them read", async () => {
    const { v1 } = await people();
    const sent = (
      await w.a.post("/v1/messages", {
        title: "Meeting",
        body: "Friday at ten.",
        audience: { roles: ["VENDEUR"] },
      })
    ).body;
    const first = (await inbox(v1)).items[0];
    expect((await inbox(v1)).unread).toBe(1);
    expect(
      (await client(api, v1.token).post(`/v1/notifications/${first.id}/read`))
        .status,
    ).toBe(201);
    expect((await inbox(v1)).unread).toBe(0);
    const detail = (await w.a.get(`/v1/messages/${sent.id}/recipients`)).body;
    expect(detail.message.readCount).toBe(1);
    expect(detail.recipients.map((r: any) => [r.name, !!r.readAt])).toEqual([
      ["Anis", true],
      ["Chiraz", false],
    ]);
    // Nobody can read or mark somebody else's notification.
    expect(
      (
        await client(api, w.nord.token).post(
          `/v1/notifications/${first.id}/read`,
        )
      ).status,
    ).toBe(404);
    expect((await w.n.get("/v1/messages")).status).toBe(403);
  });

  it("can be scheduled and withdrawn before they go out", async () => {
    await people();
    const later = new Date(Date.now() + 3600_000).toISOString();
    const scheduled = (
      await w.a.post("/v1/messages", {
        title: "Soon",
        body: "See you tomorrow.",
        audience: { roles: ["VENDEUR"] },
        scheduledFor: later,
      })
    ).body;
    expect(scheduled).toMatchObject({ status: "SCHEDULED", sentAt: null });
    expect((await w.a.get("/v1/messages")).body[0].status).toBe("SCHEDULED");
    expect((await w.a.delete(`/v1/messages/${scheduled.id}`)).status).toBe(200);
    expect((await w.a.get("/v1/messages")).body).toHaveLength(0);
  });

  it("deliver a scheduled message when the worker runs it", async () => {
    const { v1 } = await people();
    const later = new Date(Date.now() + 3600_000).toISOString();
    const scheduled = (
      await w.a.post("/v1/messages", {
        title: "Soon",
        body: "See you tomorrow.",
        audience: { roles: ["VENDEUR"] },
        scheduledFor: later,
      })
    ).body;
    const { MessagingService } =
      await import("../src/modules/messaging/messaging.service");
    const { Database } = await import("../src/core/database");
    const db = new Database();
    await new MessagingService(db).deliverScheduled(scheduled.id);
    await new MessagingService(db).deliverScheduled(scheduled.id); // safe to repeat
    await db.$disconnect();
    expect((await inbox(v1)).items).toHaveLength(1);
  });
});

describe("training", () => {
  const course = async (extra: object = {}) =>
    (
      await w.a.post("/v1/courses", {
        title: "Selling serums",
        summary: "The basics",
        ...extra,
      })
    ).body;
  const lesson = async (courseId: string, extra: object = {}) =>
    (
      await w.a.post(`/v1/courses/${courseId}/lessons`, {
        title: "Intro",
        kind: "ARTICLE",
        body: "Welcome.",
        minutes: 5,
        ...extra,
      })
    ).body;

  it("stays hidden until published, and a course needs a lesson first", async () => {
    const c = await course();
    const member = client(
      api,
      (
        await createAccount({
          role: "VENDEUR",
          pdvId: (await approvedPdv(w)).id,
        })
      ).token,
    );
    expect((await w.a.post(`/v1/courses/${c.id}/publish`)).body.code).toBe(
      "EMPTY_COURSE",
    );
    await lesson(c.id);
    expect((await member.get("/v1/courses")).body).toHaveLength(0);
    await w.a.post(`/v1/courses/${c.id}/publish`);
    expect((await member.get("/v1/courses")).body).toEqual([
      expect.objectContaining({
        title: "Selling serums",
        lessonCount: 1,
        completedCount: 0,
        minutes: 5,
      }),
    ]);
    expect((await w.a.get("/v1/courses")).body).toHaveLength(1);
  });

  it("is published to a chosen audience only", async () => {
    const north = (await w.n.get("/v1/me")).body.region.id;
    const c = await course({
      audience: { roles: ["VENDEUR"], regionIds: [north] },
    });
    await lesson(c.id);
    await w.a.post(`/v1/courses/${c.id}/publish`);
    const pdvN = await approvedPdv(w, "n", "Para N");
    const pdvS = await approvedPdv(w, "s", "Para S");
    const inNorth = client(
      api,
      (await createAccount({ role: "VENDEUR", pdvId: pdvN.id })).token,
    );
    const inSouth = client(
      api,
      (await createAccount({ role: "VENDEUR", pdvId: pdvS.id })).token,
    );
    expect((await inNorth.get("/v1/courses")).body).toHaveLength(1);
    expect((await inSouth.get("/v1/courses")).body).toHaveLength(0);
    expect((await inSouth.get(`/v1/courses/${c.id}`)).status).toBe(404);
  });

  it("tracks each person's progress for the admin", async () => {
    const c = await course();
    const l1 = await lesson(c.id);
    const l2 = await lesson(c.id, { title: "Second", body: "More." });
    await w.a.post(`/v1/courses/${c.id}/publish`);
    const pdv = await approvedPdv(w);
    const a = client(
      api,
      (await createAccount({ role: "VENDEUR", pdvId: pdv.id, name: "Anis" }))
        .token,
    );
    await createAccount({ role: "VENDEUR", pdvId: pdv.id, name: "Bilel" });
    await a.post(`/v1/lessons/${l1.id}/complete`);
    expect((await a.get("/v1/courses")).body[0]).toMatchObject({
      completedCount: 1,
      done: false,
    });
    await a.post(`/v1/lessons/${l2.id}/complete`);
    expect(
      (await a.get(`/v1/courses/${c.id}`)).body.lessons.every(
        (l: any) => l.completedAt,
      ),
    ).toBe(true);
    const progress = (await w.a.get(`/v1/courses/${c.id}/progress`)).body;
    expect(progress).toMatchObject({ total: 2, finished: 1 });
    expect(progress.rows.find((r: any) => r.name === "Bilel").completed).toBe(
      0,
    );
    await a.delete(`/v1/lessons/${l2.id}/complete`);
    expect((await w.a.get(`/v1/courses/${c.id}/progress`)).body.finished).toBe(
      0,
    );
  });

  it("checks each kind of lesson has what it needs", async () => {
    const c = await course();
    expect(
      (
        await w.a.post(`/v1/courses/${c.id}/lessons`, {
          title: "Text",
          kind: "ARTICLE",
        })
      ).body.code,
    ).toBe("BODY_REQUIRED");
    expect(
      (
        await w.a.post(`/v1/courses/${c.id}/lessons`, {
          title: "Clip",
          kind: "VIDEO",
        })
      ).body.code,
    ).toBe("VIDEO_REQUIRED");
    expect(
      (
        await w.a.post(`/v1/courses/${c.id}/lessons`, {
          title: "Clip",
          kind: "VIDEO",
          videoUrl: "http://insecure.test/v.mp4",
        })
      ).body.code,
    ).toBe("VIDEO_URL");
    expect(
      (
        await w.a.post(`/v1/courses/${c.id}/lessons`, {
          title: "Clip",
          kind: "VIDEO",
          videoUrl: "https://videos.test/v.mp4",
        })
      ).status,
    ).toBe(201);
    expect(
      (
        await w.a.post(`/v1/courses/${c.id}/lessons`, {
          title: "Doc",
          kind: "PDF",
        })
      ).body.code,
    ).toBe("PDF_REQUIRED");
    expect((await w.n.post("/v1/courses", { title: "Nope" })).status).toBe(403);
  });

  it("reorders lessons", async () => {
    const c = await course();
    const a = await lesson(c.id, { title: "Lesson A" });
    const b = await lesson(c.id, { title: "Lesson B" });
    await w.a.put(`/v1/courses/${c.id}/lessons/order`, { ids: [b.id, a.id] });
    expect(
      (await w.a.get(`/v1/courses/${c.id}`)).body.lessons.map(
        (l: any) => l.title,
      ),
    ).toEqual(["Lesson B", "Lesson A"]);
    expect(
      (await w.a.put(`/v1/courses/${c.id}/lessons/order`, { ids: [a.id] })).body
        .code,
    ).toBe("ORDER_INVALID");
  });
});

describe("insights", () => {
  it("explains the numbers: comparison, mix, ranking, stock pace, plain sentences", async () => {
    await twoRegionsWithSales();
    const from = addDays(tunisDay(new Date()), -13);
    const to = tunisDay(new Date());
    const r = (await w.a.get(`/v1/reports/insights?from=${from}&to=${to}`))
      .body;
    expect(r.totals).toMatchObject({
      units: 12,
      sales: 3,
      activeStores: 2,
      activeSellers: 2,
    });
    expect(r.totals.previousUnits).toBe(0);
    expect(r.totals.unitsChange).toBeNull();
    expect(r.families.map((f: any) => [f.name, f.units])).toEqual([
      ["Serums", 11],
      ["Hair", 1],
    ]);
    expect(r.stores.map((s: any) => [s.name, s.units, s.share])).toEqual([
      ["Para Nord", 8, 67],
      ["Para Sud", 4, 33],
    ]);
    expect(r.products[0]).toMatchObject({
      name: "Serum Niacinamide",
      units: 6,
    });
    expect(r.sellers[0]).toMatchObject({ name: "Anis", units: 8 });
    expect(r.weekdays.reduce((t: number, d: any) => t + d.units, 0)).toBe(12);
    expect(r.bestDay.units).toBe(12);
    // 5 left at about 0.2 a day is nearly a month of stock.
    expect(r.stock.runningOut).toEqual([]);
    expect(r.insights.map((i: any) => i.key)).toEqual(
      expect.arrayContaining([
        "TOP_FAMILY",
        "BEST_WEEKDAY",
        "TOP_SELLER",
        "REWARD_PER_UNIT",
      ]),
    );
    // A responsable only gets their own region.
    const mine = (await w.n.get(`/v1/reports/insights?from=${from}&to=${to}`))
      .body;
    expect(mine.totals.units).toBe(8);
    expect(mine.stores.map((s: any) => s.name)).toEqual(["Para Nord"]);
    expect(
      (
        await w.s.get(`/v1/reports/insights?from=${from}&to=${to}`)
      ).body.stores.map((s: any) => s.name),
    ).toEqual(["Para Sud"]);
  });

  it("warns when a product will run out within a week at its current pace", async () => {
    const { a } = await twoRegionsWithSales();
    await a.post("/v1/sales", {
      id: randomUUID(),
      lines: [{ productId: w.products[0]!.id, quantity: 5 }],
    }); // the last five of Vitamin C in Nord
    const from = addDays(tunisDay(new Date()), -13);
    const r = (
      await w.n.get(
        `/v1/reports/insights?from=${from}&to=${tunisDay(new Date())}`,
      )
    ).body;
    expect(r.stock.runningOut[0]).toMatchObject({
      name: "Serum Vitamin C",
      stock: 0,
      days: 0,
    });
    expect(r.insights.some((i: any) => i.key === "RUNNING_OUT")).toBe(true);
  });
});

describe("report limits", () => {
  it("refuses a range longer than 400 days and a backwards one, cleanly", async () => {
    const long = await w.a.get(
      "/v1/reports/insights?from=2020-01-01&to=2026-12-31",
    );
    expect(long.status).toBe(400);
    const back = await w.a.get(
      "/v1/reports/sales?groupBy=day&from=2026-10-01&to=2026-09-01",
    );
    expect(back.status).toBe(400);
    const ok = await w.a.get(
      "/v1/reports/insights?from=2026-01-01&to=2026-12-31",
    );
    expect(ok.status).toBe(200);
  });
});
