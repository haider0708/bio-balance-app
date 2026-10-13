import { createHash, randomUUID } from "node:crypto";
import type { Actor } from "../core/actor";
import type { Database } from "../core/database";
import { StructureService } from "../modules/directory/structure.service";
import { UsersService } from "../modules/directory/users.service";
import { RestockService } from "../modules/restock/restock.service";
import { WalletService } from "../modules/rewards/wallet.service";
import { SalesService } from "../modules/sales/sales.service";
import { adjustStock } from "../modules/stock/ledger";
import { StockService } from "../modules/stock/stock.service";

/**
 * The test region looks after itself, so a store reviewer always finds a living network:
 *  - what its people submit is approved a minute later (the admin never sees it), and a demo
 *    account a reviewer deactivated is active again a minute later,
 *  - its sellers keep selling through the day (sales of the last hours, with stock topped up),
 *  - a demonstration account deleted by a reviewer comes back a few minutes later, history intact.
 */
export interface SandboxServices {
  db: Database;
  structure: StructureService;
  users: UsersService;
  stock: StockService;
  restock: RestockService;
  wallet: WalletService;
  sales: SalesService;
}

export function sandboxServices(db: Database): SandboxServices {
  return {
    db,
    structure: new StructureService(db),
    users: new UsersService(db),
    stock: new StockService(db),
    restock: new RestockService(db),
    wallet: new WalletService(db),
    sales: new SalesService(db),
  };
}

/**
 * Held by the builder of the test region (seedDemo) for as long as it works: the worker leaves
 * the region alone meanwhile (it would otherwise sell from a shop still being stocked).
 */
export const SANDBOX_BUILD_LOCK = 20_261_013;

/** True while the test region is being built. */
async function beingBuilt(db: Database) {
  const [row] = await db.run(
    "SYSTEM",
    (tx) =>
      tx.$queryRaw<{ free: boolean }[]>`
      SELECT pg_try_advisory_xact_lock_shared(${SANDBOX_BUILD_LOCK}) AS free`,
  );
  return row?.free !== true;
}

/** Submissions wait this long before they are approved, so the reviewer sees them wait. */
const APPROVAL_DELAY_MS = 60_000;
/** A deleted demonstration account comes back after this long. */
export const RESTORE_DELAY_MS = 3 * 60_000;

/** The test region and the admin who decides in it, or null when there is no test region. */
async function sandbox(db: Database) {
  const [region, admin] = await db.run("SYSTEM", (tx) =>
    Promise.all([
      tx.region.findFirst({ where: { sandbox: true }, select: { id: true } }),
      tx.user.findFirst({
        where: { role: "ADMIN", status: "ACTIVE" },
        orderBy: { createdAt: "asc" },
        select: { id: true, name: true, email: true },
      }),
    ]),
  );
  if (!region || !admin) return null;
  const actor: Actor = {
    ...admin,
    role: "ADMIN",
    regionId: null,
    pdvId: null,
    locale: "fr",
    showSandbox: true,
    sandbox: true,
  };
  return { regionId: region.id, admin: actor };
}

async function attempt(work: () => Promise<unknown>) {
  try {
    await work();
  } catch (error) {
    console.error(
      JSON.stringify({
        level: "warn",
        event: "sandbox.skipped",
        error: error instanceof Error ? error.message.slice(0, 200) : "",
      }),
    );
  }
}

/** Approve what the test region submitted more than a minute ago, as the admin would. */
export async function approveSandbox(s: SandboxServices, now = new Date()) {
  const box = await sandbox(s.db);
  if (!box || (await beingBuilt(s.db))) return 0;
  const before = new Date(now.getTime() - APPROVAL_DELAY_MS);
  const regionId = box.regionId;
  const waiting = await s.db.run("SYSTEM", (tx) =>
    Promise.all([
      tx.group.findMany({
        where: { regionId, status: "PENDING", createdAt: { lt: before } },
      }),
      tx.pdv.findMany({
        where: { regionId, status: "PENDING", createdAt: { lt: before } },
      }),
      tx.user.findMany({
        where: { regionId, status: "PENDING", createdAt: { lt: before } },
      }),
      tx.stockDeclaration.findMany({
        where: { regionId, status: "PENDING", createdAt: { lt: before } },
      }),
      tx.stockRecount.findMany({
        where: { regionId, status: "PENDING", createdAt: { lt: before } },
      }),
      tx.restockOrder.findMany({
        where: {
          regionId,
          status: { in: ["REQUESTED", "RECEIVED"] },
          updatedAt: { lt: before },
        },
      }),
      tx.payoutRequest.findMany({
        where: { regionId, status: "PENDING", createdAt: { lt: before } },
      }),
      // A reviewer signed in as the responsable may deactivate the demo seller: the account comes
      // back, so the next reviewer can still sign in with it (deleted accounts have no password
      // and come back through their own restore job).
      tx.user.findMany({
        where: {
          regionId,
          status: "SUSPENDED",
          passwordHash: { not: null },
          decidedAt: { lt: before },
        },
      }),
    ]),
  );
  const [
    groups,
    pdvs,
    members,
    declarations,
    recounts,
    orders,
    payouts,
    suspended,
  ] = waiting;
  const admin = box.admin;
  for (const g of groups)
    await attempt(() => s.structure.decideGroup(admin, g.id, "approve"));
  for (const p of pdvs)
    await attempt(() => s.structure.decidePdv(admin, p.id, "approve"));
  // Approved members are invited as usual; the email itself never leaves the test region.
  for (const m of members)
    await attempt(() => s.users.decide(admin, m.id, "approve"));
  for (const d of declarations)
    await attempt(() => s.stock.approve(admin, d.id, {}));
  for (const r of recounts)
    await attempt(() => s.stock.decideRecount(admin, r.id, "approve"));
  for (const o of orders)
    await attempt(() =>
      o.status === "REQUESTED"
        ? s.restock.sendDirect(admin, o.id, {})
        : s.restock.approve(admin, o.id, {}),
    );
  for (const p of payouts)
    await attempt(() =>
      s.wallet.approve(admin, p.id, { paidAt: now, reference: "DEMO" }),
    );
  for (const u of suspended)
    await attempt(() => s.users.decide(admin, u.id, "reactivate"));
  return waiting.reduce((sum, list) => sum + list.length, 0);
}

/** The share of a day's sales in each hour (Tunis time): busiest around noon and early evening. */
const HOURS: Record<number, number> = {
  9: 3,
  10: 6,
  11: 9,
  12: 10,
  13: 7,
  14: 5,
  15: 5,
  16: 7,
  17: 9,
  18: 10,
  19: 7,
  20: 3,
};
const HOUR_TOTAL = Object.values(HOURS).reduce((a, b) => a + b, 0);
/** Sales a seller makes on an ordinary day; Sunday is quieter. */
const DAILY_SALES = 9;
const WEEKDAY = [0.5, 1, 1, 1.05, 1.1, 1.2, 1.15];
/** Never fill more than this much missed time (the worker may have been stopped). */
const MAX_CATCH_UP_MS = 24 * 3_600_000;
const HOUR_MS = 3_600_000;
const TUNIS_OFFSET_MS = HOUR_MS;

/** Sales the keeper makes start with this, so the history built at the start can be told apart. */
const KEEPER_ID_PREFIX = "dec0de00";

/** A random generator fixed by a text: the same hour always plans the same sales. */
function seeded(text: string) {
  let n = 0;
  const next = () =>
    parseInt(
      createHash("sha256").update(`${text}:${n++}`).digest("hex").slice(0, 8),
      16,
    ) / 0x100000000;
  return next;
}

/** A sale id fixed by the seller, the hour and the sale's rank in it (so it is made once). */
function keeperSaleId(sellerId: string, hour: number, rank: number) {
  const h = createHash("sha256")
    .update(`${sellerId}:${hour}:${rank}`)
    .digest("hex");
  return `${KEEPER_ID_PREFIX}-${h.slice(8, 12)}-4${h.slice(13, 16)}-a${h.slice(17, 20)}-${h.slice(20, 32)}`;
}

interface PlannedSale {
  id: string;
  occurredAt: Date;
  lines: { productId: string; quantity: number }[];
}

/**
 * The sales a seller makes in one Tunis hour: always the same for the same seller and hour, so
 * the keeper can run as often as it likes and never adds a sale twice (nor rolls the dice twice
 * for a quiet hour).
 */
function planHour(
  sellerId: string,
  hourStart: number,
  products: string[],
): PlannedSale[] {
  const local = new Date(hourStart + TUNIS_OFFSET_MS);
  const share = HOURS[local.getUTCHours()];
  if (!share || !products.length) return [];
  const random = seeded(`${sellerId}:${hourStart}`);
  const expected =
    (DAILY_SALES * WEEKDAY[local.getUTCDay()]! * share) / HOUR_TOTAL;
  const count = Math.floor(expected + random());
  const plan: PlannedSale[] = [];
  for (let rank = 0; rank < count; rank++) {
    const lines = new Map<string, number>();
    for (let l = 1 + Math.floor(random() * 3); l > 0; l--) {
      // Earlier products sell more, the way a few products make most of a shelf's sales.
      const productId = products[Math.floor(random() ** 2 * products.length)]!;
      lines.set(
        productId,
        (lines.get(productId) ?? 0) + 1 + Math.floor(random() * 3),
      );
    }
    plan.push({
      id: keeperSaleId(sellerId, hourStart, rank),
      occurredAt: new Date(hourStart + random() * HOUR_MS),
      lines: [...lines].map(([productId, quantity]) => ({
        productId,
        quantity,
      })),
    });
  }
  return plan;
}

/**
 * The test region's sellers keep selling through the day: each hour since the history built at
 * the start (at most a day back) brings its planned sales, at believable times, with the store's
 * stock topped up when it runs low. Their responsable finds them in the inbox; nothing is pushed.
 */
export async function keepSandboxSelling(s: SandboxServices, now = new Date()) {
  const box = await sandbox(s.db);
  if (!box || (await beingBuilt(s.db))) return 0;
  const sellers = await s.db.run("SYSTEM", (tx) =>
    tx.user.findMany({
      where: {
        regionId: box.regionId,
        role: "VENDEUR",
        status: "ACTIVE",
        passwordHash: { not: null },
        pdvId: { not: null },
      },
    }),
  );
  const end = now.getTime() - 2 * 60_000;
  let made = 0;
  for (const seller of sellers) {
    const pdv = await s.db.run("SYSTEM", (tx) =>
      tx.pdv.findUnique({ where: { id: seller.pdvId! } }),
    );
    if (pdv?.status !== "ACTIVE") continue;
    // The keeper takes over where the history built at the start (or recorded by hand) ends.
    const [built] = await s.db.run(
      "SYSTEM",
      (tx) =>
        tx.$queryRaw<{ last: Date | null }[]>`
        SELECT max("occurredAt") AS last FROM "Sale"
        WHERE "sellerId" = ${seller.id}::uuid AND id::text NOT LIKE ${`${KEEPER_ID_PREFIX}%`}`,
    );
    const start = Math.max(
      built?.last?.getTime() ?? end - HOUR_MS,
      end - MAX_CATCH_UP_MS,
    );
    // What the store carries, best sellers first.
    const products = (
      await s.db.run(
        "SYSTEM",
        (tx) =>
          tx.$queryRaw<{ productId: string }[]>`
          SELECT st."productId" FROM "Stock" st JOIN "Product" p ON p.id = st."productId"
          LEFT JOIN (SELECT l."productId", SUM(l.quantity) AS sold FROM "SaleLine" l JOIN "Sale" x ON x.id = l."saleId"
                     WHERE x."pdvId" = ${pdv.id}::uuid GROUP BY l."productId") v ON v."productId" = st."productId"
          WHERE st."locationId" = ${pdv.id}::uuid AND p.active
          ORDER BY COALESCE(v.sold, 0) DESC, p.name, st."productId"`,
      )
    ).map((p) => p.productId);
    const due: PlannedSale[] = [];
    for (
      let hour = Math.floor(start / HOUR_MS) * HOUR_MS;
      hour < end;
      hour += HOUR_MS
    )
      for (const sale of planHour(seller.id, hour, products))
        if (
          sale.occurredAt.getTime() > start &&
          sale.occurredAt.getTime() < end
        )
          due.push(sale);
    if (!due.length) continue;
    const done = new Set(
      (
        await s.db.run("SYSTEM", (tx) =>
          tx.sale.findMany({
            where: { id: { in: due.map((d) => d.id) } },
            select: { id: true },
          }),
        )
      ).map((d) => d.id),
    );
    const actor: Actor = {
      id: seller.id,
      name: seller.name,
      email: seller.email,
      role: "VENDEUR",
      regionId: seller.regionId,
      pdvId: seller.pdvId,
      locale: seller.locale === "en" ? "en" : "fr",
      sandbox: true,
      quietAlerts: true,
    };
    for (const sale of due.sort(
      (a, b) => a.occurredAt.getTime() - b.occurredAt.getTime(),
    )) {
      if (done.has(sale.id)) continue;
      await topUp(s, box.admin, pdv, sale.lines);
      await s.sales.create(actor, sale);
      made++;
    }
  }
  return made;
}

/** Put enough stock in the store for a sale (a delivery the test region never has to wait for). */
async function topUp(
  s: SandboxServices,
  admin: Actor,
  pdv: { id: string; regionId: string },
  lines: PlannedSale["lines"],
) {
  await s.db.run("SYSTEM", async (tx) => {
    for (const { productId, quantity } of lines) {
      const row = await tx.stock.findUnique({
        where: { locationId_productId: { locationId: pdv.id, productId } },
        select: { quantity: true },
      });
      if ((row?.quantity ?? 0) >= quantity + 5) continue;
      await adjustStock(
        tx,
        { id: pdv.id, kind: "PDV", regionId: pdv.regionId },
        productId,
        60,
        {
          reason: "ADJUSTMENT",
          refType: "SandboxRestock",
          refId: randomUUID(),
          actorId: admin.id,
        },
      );
    }
  });
}

export interface RestorePayload {
  userId: string;
  name: string;
  email: string;
  phone: string | null;
  passwordHash: string;
  locale: string;
}

/** Bring back a demonstration account a reviewer deleted: same person, same history. */
export async function restoreDemoAccount(
  db: Database,
  payload: RestorePayload,
) {
  await db.run("SYSTEM", async (tx) => {
    const user = await tx.user.findUnique({ where: { id: payload.userId } });
    if (!user?.regionId || user.status !== "SUSPENDED") return;
    const region = await tx.region.findUnique({
      where: { id: user.regionId },
      select: { sandbox: true },
    });
    if (!region?.sandbox) return;
    await tx.user.update({
      where: { id: user.id },
      data: {
        name: payload.name,
        email: payload.email,
        phone: payload.phone,
        passwordHash: payload.passwordHash,
        locale: payload.locale,
        status: "ACTIVE",
        decisionNote: null,
      },
    });
  });
}

/** Ask the worker to look after the test region: approvals every minute, sales every 15 minutes. */
export async function scheduleSandbox(db: Database, now = new Date()) {
  const exists = await db.run("SYSTEM", (tx) =>
    tx.region.count({ where: { sandbox: true } }),
  );
  if (!exists) return;
  const minute = now.toISOString().slice(0, 16);
  const quarter = `${now.toISOString().slice(0, 14)}${String(Math.floor(now.getUTCMinutes() / 15) * 15).padStart(2, "0")}`;
  await db.job.createMany({
    data: [
      {
        kind: "sandbox-approve",
        key: `sandbox-approve:${minute}`,
        payload: {},
      },
      { kind: "sandbox-sell", key: `sandbox-sell:${quarter}`, payload: {} },
    ],
    skipDuplicates: true,
  });
}
