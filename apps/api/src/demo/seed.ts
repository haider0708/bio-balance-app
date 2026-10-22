import { randomUUID } from "node:crypto";
import { Readable } from "node:stream";
import argon2 from "argon2";
import type { Client } from "pg";
import type { Actor } from "../core/actor";
import { Database } from "../core/database";
import { addDays, tunisDay } from "../core/dates";
import { RegionsService } from "../modules/directory/regions.service";
import { DepotsService } from "../modules/directory/depots.service";
import { StructureService } from "../modules/directory/structure.service";
import { UsersService } from "../modules/directory/users.service";
import { MediaService } from "../modules/media/media.service";
import { MessagingService } from "../modules/messaging/messaging.service";
import { RestockService } from "../modules/restock/restock.service";
import { RewardsService } from "../modules/rewards/rewards.service";
import { WalletService } from "../modules/rewards/wallet.service";
import { SalesService } from "../modules/sales/sales.service";
import { StockService } from "../modules/stock/stock.service";
import { proofPhoto } from "./proof-photo";
import { SANDBOX_BUILD_LOCK } from "./sandbox";

/** The name every demonstration photo and reward period carries, so they can be found and removed. */
export const DEMO_FILE = "demo-proof.jpg";
export const DEMO_NOTE = "Historique de démonstration";
/** The demonstration region: its internal code is the upper-case slug of its name. */
export const DEMO_REGION_CODE = "DEMO";
export const DEMO_REGION_NAME = "Démo";

/** The services the demonstration is built with: the real ones, so every rule is applied. */
export interface DemoServices {
  db: Database;
  regions: RegionsService;
  structure: StructureService;
  users: UsersService;
  depots: DepotsService;
  stock: StockService;
  restock: RestockService;
  rewards: RewardsService;
  wallet: WalletService;
  sales: SalesService;
  messaging: MessagingService;
  media: MediaService;
}

export function demoServices(app: {
  get<T>(token: new (...args: never[]) => T): T;
}): DemoServices {
  return {
    db: app.get(Database),
    regions: app.get(RegionsService),
    structure: app.get(StructureService),
    users: app.get(UsersService),
    depots: app.get(DepotsService),
    stock: app.get(StockService),
    restock: app.get(RestockService),
    rewards: app.get(RewardsService),
    wallet: app.get(WalletService),
    sales: app.get(SalesService),
    messaging: app.get(MessagingService),
    media: app.get(MediaService),
  };
}

export interface DemoOptions {
  /** How many days of sales, ending today. */
  days: number;
  /** The password of the demo responsable and of the demo team member... */
  passwords?: { responsable: string; vendeur: string };
  /** ...or the password hashes they already have (rebuilding keeps what the stores were given). */
  passwordHashes?: { responsable: string; vendeur: string };
  log?: (message: string) => void;
}

export interface DemoAccount {
  role: "RESPONSABLE" | "VENDEUR";
  name: string;
  email: string;
  store: string | null;
}

export interface DemoResult {
  regionId: string;
  accounts: DemoAccount[];
  sales: number;
  units: number;
  from: string;
  to: string;
}

/** A small deterministic random generator: the same demonstration every time. */
function generator(seed: number) {
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return {
    next,
    int: (low: number, high: number) =>
      low + Math.floor(next() * (high - low + 1)),
    pick: <T>(items: readonly T[]) => items[Math.floor(next() * items.length)]!,
  };
}

/** The test shop: its one seller is the account the reviewers sign in with. */
const STORES = [
  {
    name: "Para Démo Lac",
    city: "Les Berges du Lac, Tunis",
    address: "12 rue du Lac Léman",
    weight: 1.3,
    sellers: ["Amine Trabelsi"],
  },
];

/** The team member and the responsable the reviewers sign in with. */
const REVIEW_VENDEUR = {
  name: "Amine Trabelsi",
  email: "demo-vendeur@galylio.com",
};
const REVIEW_RESPONSABLE = {
  name: "Nadia Ben Salem",
  email: "demo-responsable@galylio.com",
};

/** 1 for a quiet day, up to 1.2 for the busiest (Sunday is the quietest). */
const WEEKDAY = [0.5, 1, 1, 1.05, 1.1, 1.2, 1.15];
/** The share of sales in each hour of the day (Tunis time), busiest around noon and early evening. */
const HOURS = [
  [9, 3],
  [10, 6],
  [11, 9],
  [12, 10],
  [13, 7],
  [14, 5],
  [15, 5],
  [16, 7],
  [17, 9],
  [18, 10],
  [19, 7],
  [20, 3],
] as const;
const HOUR_TOTAL = HOURS.reduce((sum, [, w]) => sum + w, 0);

/** Tunis is UTC+1 all year. */
const at = (day: string, hour: number, minute: number, second: number) => {
  const [y, m, d] = day.split("-").map(Number) as [number, number, number];
  return new Date(Date.UTC(y, m - 1, d, hour - 1, minute, second));
};

interface PlannedSale {
  id: string;
  store: number;
  seller: number;
  occurredAt: Date;
  lines: { productId: string; quantity: number }[];
}

/**
 * The admin building the test region: they see it while it is built (it is hidden otherwise), and
 * hear nothing of what the build does there.
 */
function adminActor(admin: { id: string; name: string; email: string }): Actor {
  return {
    ...admin,
    role: "ADMIN",
    regionId: null,
    pdvId: null,
    locale: "fr",
    showSandbox: true,
    sandbox: true,
  };
}

/**
 * Builds the test region for the store reviewers: a region with its responsable, a group, a shop
 * and its team member, a grossiste, stock, restocks, payouts, an announcement and `days` days of
 * sales with the rewards they earned. It is made with the real services (so stock, wallets and
 * rewards add up), then its dates are put where they belong and it becomes the test region, which
 * the admin does not see (docs/runbook.md, "The test region").
 * `owner` is a connection as the database owner, needed to move dates in the append-only history.
 */
export async function seedDemo(
  s: DemoServices,
  owner: Client,
  options: DemoOptions,
): Promise<DemoResult> {
  // The worker leaves the test region alone until it is built (SANDBOX_BUILD_LOCK).
  await owner.query(`SELECT pg_advisory_lock($1)`, [SANDBOX_BUILD_LOCK]);
  try {
    return await build(s, owner, options);
  } finally {
    await owner.query(`SELECT pg_advisory_unlock($1)`, [SANDBOX_BUILD_LOCK]);
  }
}

async function build(
  s: DemoServices,
  owner: Client,
  options: DemoOptions,
): Promise<DemoResult> {
  const log = options.log ?? (() => undefined);
  const { rows: clock } = await owner.query<{ now: Date }>(
    `SELECT (now() AT TIME ZONE 'UTC') AS now`,
  );
  const seedStart = clock[0]!.now;
  const now = new Date();
  const today = tunisDay(now);
  const firstDay = addDays(today, -(options.days - 1));

  const adminRow = await s.db.run("SYSTEM", (tx) =>
    tx.user.findFirst({ where: { role: "ADMIN", status: "ACTIVE" } }),
  );
  if (!adminRow) throw new Error("There is no active administrator.");
  const admin = adminActor(adminRow);
  const existing = await s.db.run("SYSTEM", (tx) =>
    tx.region.findFirst({
      where: { OR: [{ code: DEMO_REGION_CODE }, { name: DEMO_REGION_NAME }] },
    }),
  );
  if (existing)
    throw new Error("The demonstration region already exists: purge it first.");

  // The products that sell: a few of every family, the way a pharmacy shelf looks.
  const catalogue = await s.db.run("SYSTEM", (tx) =>
    tx.product.findMany({
      where: { active: true },
      orderBy: [{ family: "asc" }, { name: "asc" }],
      select: { id: true, name: true, family: true },
    }),
  );
  if (catalogue.length < 6)
    throw new Error("The catalogue needs at least 6 products.");
  const byFamily = new Map<string, typeof catalogue>();
  for (const p of catalogue)
    byFamily.set(p.family, [...(byFamily.get(p.family) ?? []), p]);
  const picks: typeof catalogue = [];
  for (let round = 0; picks.length < 24 && round < 24; round++)
    for (const list of byFamily.values()) {
      const p = list[round];
      if (p && picks.length < 24) picks.push(p);
    }

  // ── The place ────────────────────────────────────────────────────────────
  const region = await s.regions.create(admin, DEMO_REGION_NAME);
  // The test region from its first moment: nothing built here alerts or mails the real people.
  await owner.query(`UPDATE "Region" SET sandbox = true WHERE id = $1`, [
    region.id,
  ]);
  log(`region ${region.code}`);
  const group = (await s.structure.createGroup(admin, {
    name: "Groupe Démo",
    regionId: region.id,
  })) as { id: string };
  const stores: { id: string; name: string }[] = [];
  for (const store of STORES) {
    const pdv = (await s.structure.createPdv(admin, {
      name: store.name,
      address: store.address,
      city: store.city,
      phone: null,
      groupId: group.id,
      regionId: region.id,
    })) as { id: string; name: string };
    stores.push({ id: pdv.id, name: store.name });
  }

  const accounts: DemoAccount[] = [];
  const hash = (password: string) =>
    argon2.hash(password, { type: argon2.argon2id });
  const hashes = options.passwordHashes ?? {
    responsable: await hash(options.passwords!.responsable),
    vendeur: await hash(options.passwords!.vendeur),
  };
  const createUser = async (
    role: "RESPONSABLE" | "VENDEUR",
    name: string,
    email: string,
    placeId: string,
    passwordHash: string,
    storeName: string | null,
  ) => {
    const created = (await s.users.createByAdmin(
      admin,
      role === "RESPONSABLE"
        ? { role, regionId: placeId, name, email, phone: "20 000 000" }
        : { role, pdvId: placeId, name, email, phone: "20 000 000" },
    )) as { id: string };
    // They sign in with the password given here: no invitation is sent or kept.
    await s.db.run("SYSTEM", (tx) =>
      tx.user.update({ where: { id: created.id }, data: { passwordHash } }),
    );
    accounts.push({ role, name, email, store: storeName });
    return created.id;
  };
  await createUser(
    "RESPONSABLE",
    REVIEW_RESPONSABLE.name,
    REVIEW_RESPONSABLE.email,
    region.id,
    hashes.responsable,
    null,
  );
  const sellers: { id: string; storeIndex: number }[][] = STORES.map(() => []);
  for (const [i, store] of STORES.entries())
    for (const name of store.sellers) {
      const id = await createUser(
        "VENDEUR",
        name,
        REVIEW_VENDEUR.email,
        stores[i]!.id,
        hashes.vendeur,
        store.name,
      );
      sellers[i]!.push({ id, storeIndex: i });
    }
  const responsableRow = await s.db.run("SYSTEM", (tx) =>
    tx.user.findFirstOrThrow({ where: { email: REVIEW_RESPONSABLE.email } }),
  );
  const responsable: Actor = {
    id: responsableRow.id,
    name: responsableRow.name,
    email: responsableRow.email,
    role: "RESPONSABLE",
    regionId: region.id,
    pdvId: null,
    locale: "fr",
  };
  const actorOfSeller = async (id: string): Promise<Actor> => {
    const u = await s.db.run("SYSTEM", (tx) =>
      tx.user.findUniqueOrThrow({ where: { id } }),
    );
    return {
      id: u.id,
      name: u.name,
      email: u.email,
      role: "VENDEUR",
      regionId: u.regionId,
      pdvId: u.pdvId,
      locale: "fr",
    };
  };

  const upload = async (actor: Actor) =>
    (
      await s.media.upload(
        actor,
        "PROOF",
        DEMO_FILE,
        Readable.from([proofPhoto]),
      )
    ).id;

  // ── Rewards: the rates already set are given the same history, so old sales earned too ──
  const live = await s.db.run("SYSTEM", (tx) =>
    tx.rewardRule.findMany({
      where: { cancelledAt: null },
      select: {
        scope: true,
        productId: true,
        family: true,
        amountMillimes: true,
        startsOn: true,
      },
    }),
  );
  const families = new Set(picks.map((p) => p.family));
  const pickIds = new Set(picks.map((p) => p.id));
  let history = 0;
  for (const rule of live) {
    const first = rule.startsOn.toISOString().slice(0, 10);
    const relevant = rule.productId
      ? pickIds.has(rule.productId)
      : families.has(rule.family ?? "");
    if (!relevant || first <= firstDay) continue;
    await s.rewards.create(admin, {
      scope: rule.scope,
      ...(rule.productId && { productId: rule.productId }),
      ...(rule.family && { family: rule.family }),
      amountMillimes: Number(rule.amountMillimes),
      startsOn: addDays(firstDay, -1),
      endsOn: addDays(first, -1),
      note: DEMO_NOTE,
    });
    history++;
  }
  log(`${history} reward periods before the current rates`);

  // ── The sales to make, planned first so each store's stock can be sized to them ──
  const random = generator(20261012);
  const popularity = picks.map((_, i) => 1 / (i + 2));
  const popTotal = popularity.reduce((a, b) => a + b, 0);
  const planned: PlannedSale[] = [];
  for (let d = 0; d < options.days; d++) {
    const day = addDays(firstDay, d);
    const weekday = new Date(`${day}T12:00:00Z`).getUTCDay();
    const trend = 0.8 + (0.4 * d) / Math.max(1, options.days - 1);
    for (const [i, store] of STORES.entries()) {
      const count = Math.round(
        7 *
          store.weight *
          WEEKDAY[weekday]! *
          trend *
          (0.75 + random.next() * 0.5),
      );
      for (let n = 0; n < count; n++) {
        let pickHour = random.next() * HOUR_TOTAL;
        let hour: number = HOURS[0][0];
        for (const [h, w] of HOURS) {
          hour = h;
          if ((pickHour -= w) < 0) break;
        }
        const occurredAt = at(day, hour, random.int(0, 59), random.int(0, 59));
        if (occurredAt.getTime() > now.getTime() - 10 * 60_000) continue;
        const lines = new Map<string, number>();
        for (let l = random.int(1, 3); l > 0; l--) {
          let r = random.next() * popTotal;
          let index = 0;
          for (const [k, w] of popularity.entries()) {
            index = k;
            if ((r -= w) < 0) break;
          }
          const p = picks[index]!;
          lines.set(p.id, (lines.get(p.id) ?? 0) + random.int(1, 3));
        }
        planned.push({
          id: randomUUID(),
          store: i,
          seller: random.int(0, sellers[i]!.length - 1),
          occurredAt,
          lines: [...lines].map(([productId, quantity]) => ({
            productId,
            quantity,
          })),
        });
      }
    }
  }
  planned.sort((a, b) => a.occurredAt.getTime() - b.occurredAt.getTime());

  // ── Stock: counted by the admin, enough for every planned sale and a little more ──
  const sold = STORES.map(() => new Map<string, number>());
  for (const sale of planned)
    for (const l of sale.lines)
      sold[sale.store]!.set(
        l.productId,
        (sold[sale.store]!.get(l.productId) ?? 0) + l.quantity,
      );
  const counted = async (
    placeId: string,
    quantities: (productId: string) => number,
  ) => {
    const declaration = (await s.stock.declare(admin, {
      locationId: placeId,
      photoIds: [await upload(admin)],
      note: "Premier comptage",
      lines: picks.map((p) => ({
        productId: p.id,
        quantity: quantities(p.id),
      })),
    })) as { id: string; status?: string };
    if (declaration.status === "PENDING")
      await s.stock.approve(admin, declaration.id, {});
  };
  for (const [i, store] of stores.entries())
    await counted(
      store.id,
      (id) => (sold[i]!.get(id) ?? 0) + random.int(4, 60),
    );
  const depot = (await s.depots.create(admin, {
    regionId: region.id,
    name: "Dépôt Démo",
    address: "Zone industrielle, Ben Arous",
    city: "Ben Arous",
    phone: null,
    photoIds: [await upload(admin)],
  })) as { id: string };
  await counted(depot.id, () => 600);
  log("stock counted");

  // ── The sales ────────────────────────────────────────────────────────────
  const actors = new Map<string, Actor>();
  const record = s.sales as unknown as {
    record(
      actor: Actor,
      input: { id: string; lines: PlannedSale["lines"] },
      occurredAt: Date,
    ): Promise<unknown>;
  };
  let units = 0;
  for (const [n, sale] of planned.entries()) {
    const sellerId = sellers[sale.store]![sale.seller]!.id;
    if (!actors.has(sellerId))
      actors.set(sellerId, await actorOfSeller(sellerId));
    // The public route refuses sales older than a month; the history is built with the same
    // rules underneath it (stock, rewards of that day, wallet).
    await record.record(
      actors.get(sellerId)!,
      { id: sale.id, lines: sale.lines },
      sale.occurredAt,
    );
    units += sale.lines.reduce((sum, l) => sum + l.quantity, 0);
    if ((n + 1) % 250 === 0) log(`${n + 1} / ${planned.length} sales`);
  }

  // ── A restock, a pending request, payouts and an announcement, all recent ──
  const lac = stores[0]!;
  const order = (await s.restock.create(responsable, {
    destId: lac.id,
    note: "Réassort de la semaine",
    lines: picks.slice(0, 6).map((p) => ({ productId: p.id, quantity: 40 })),
  })) as { id: string };
  await s.restock.sendDirect(admin, order.id, {});
  await s.restock.receive(responsable, order.id, {
    photoIds: [await upload(responsable)],
    lines: picks.slice(0, 6).map((p) => ({ productId: p.id, quantity: 40 })),
    note: "Reçu complet",
  });
  await s.restock.approve(admin, order.id, {});
  await s.restock.create(responsable, {
    destId: lac.id,
    note: "Rupture sur les sérums",
    lines: picks.slice(2, 7).map((p) => ({ productId: p.id, quantity: 25 })),
  });

  // A payout paid last week and a smaller one waiting.
  const seller = await actorOfSeller(sellers[0]![0]!.id);
  const wallet = (await s.wallet.mine(seller)) as {
    availableMillimes: number | bigint;
  };
  const balance = Number(wallet.availableMillimes);
  const paid = Math.floor((balance * 0.35) / 1000) * 1000;
  if (paid >= 1000) {
    const request = (await s.wallet.request(seller, paid)) as { id: string };
    await s.wallet.approve(admin, request.id, {
      paidAt: new Date(now.getTime() - 6 * 86_400_000),
      reference: "DEMO-1",
    });
  }
  const left = Math.floor((balance * 0.1) / 1000) * 1000;
  if (left >= 1000) await s.wallet.request(seller, left);
  await s.messaging.send(admin, {
    title: "Bienvenue dans la région Démo",
    body: "Voici une région d'exemple : un point de vente et son équipe, des ventes sur deux mois, des récompenses et des réassorts. Explorez librement.",
    audience: { regionIds: [region.id] },
    pinned: true,
  });
  log("restock, payouts and announcement done");

  await tidy(owner, region.id, seedStart, firstDay);
  log("dates aligned and noise removed");
  return {
    regionId: region.id,
    accounts,
    sales: planned.length,
    units,
    from: firstDay,
    to: today,
  };
}

/**
 * The services stamp everything with the time they ran. Put the history where it belongs: each
 * sale, its stock movement, wallet entry, audit line and alert at the sale's own moment, the first
 * counts and the people before the first sale. And remove what building this told the real
 * people (alerts, invitation emails) so nothing reaches them.
 */
async function tidy(
  owner: Client,
  regionId: string,
  seedStart: Date,
  firstDay: string,
) {
  const demoUsers = `(SELECT id FROM "User" WHERE "regionId" = $1)`;
  await owner.query("BEGIN");
  try {
    // Nothing built here is told to the real administrator or responsables, nor mailed.
    await owner.query(
      `DELETE FROM "Notification" WHERE "createdAt" >= $2 AND "userId" NOT IN ${demoUsers}`,
      [regionId, seedStart],
    );
    await owner.query(
      `DELETE FROM "Job" WHERE "createdAt" >= $1 AND kind IN ('email', 'whatsapp')`,
      [seedStart],
    );
    await owner.query(
      `DELETE FROM "AccessToken" WHERE "userId" IN ${demoUsers}`,
      [regionId],
    );
    // The history is append-only: moving its dates needs the owner and the triggers off.
    await owner.query(`SET LOCAL session_replication_role = replica`);
    const opening = `('${firstDay}'::date - 1)::timestamp + interval '8 hours'`;
    await owner.query(
      `UPDATE "Sale" SET "createdAt" = "occurredAt" + interval '25 seconds' WHERE "regionId" = $1`,
      [regionId],
    );
    await owner.query(
      `UPDATE "StockMovement" m SET "createdAt" = s."occurredAt" + interval '25 seconds'
       FROM "Sale" s WHERE m."refType" = 'Sale' AND m."refId" = s.id AND s."regionId" = $1`,
      [regionId],
    );
    await owner.query(
      `UPDATE "WalletEntry" w SET "createdAt" = s."occurredAt" + interval '25 seconds'
       FROM "Sale" s WHERE w."saleId" = s.id AND s."regionId" = $1`,
      [regionId],
    );
    await owner.query(
      `UPDATE "AuditEntry" a SET "createdAt" = s."occurredAt" + interval '25 seconds'
       FROM "Sale" s WHERE a.entity = 'Sale' AND a."entityId" = s.id::text AND s."regionId" = $1`,
      [regionId],
    );
    await owner.query(
      `UPDATE "Notification" n SET "createdAt" = s."occurredAt" + interval '25 seconds',
         "readAt" = CASE WHEN s."occurredAt" < (now() AT TIME ZONE 'UTC') - interval '2 days'
                    THEN s."occurredAt" + interval '2 hours' END
       FROM "Sale" s WHERE n."entityType" = 'Sale' AND n."entityId" = s.id AND s."regionId" = $1`,
      [regionId],
    );
    // The paid payout was asked for the day before it was paid, and decided then.
    await owner.query(
      `UPDATE "PayoutRequest" SET "createdAt" = "paidAt" - interval '1 day', "decidedAt" = "paidAt"
       WHERE "regionId" = $1 AND "paidAt" IS NOT NULL`,
      [regionId],
    );
    // The first counts, the people and the places come before the first sale.
    await owner.query(
      `UPDATE "StockMovement" SET "createdAt" = ${opening} WHERE reason = 'DECLARATION' AND "createdAt" >= $2
         AND ("regionId" = $1 OR "locationId" IN (SELECT id FROM "Depot" WHERE "regionId" = $1))`,
      [regionId, seedStart],
    );
    await owner.query(
      `UPDATE "StockDeclaration" SET "createdAt" = ${opening}, "decidedAt" = ${opening}
       WHERE "createdAt" >= $2 AND ("regionId" = $1 OR "locationId" IN (SELECT id FROM "Depot" WHERE "regionId" = $1))`,
      [regionId, seedStart],
    );
    await owner.query(
      `UPDATE "Pdv" SET "createdAt" = ${opening} - interval '1 day', "decidedAt" = ${opening} - interval '1 day' WHERE "regionId" = $1`,
      [regionId],
    );
    await owner.query(
      `UPDATE "Group" SET "createdAt" = ${opening} - interval '1 day', "decidedAt" = ${opening} - interval '1 day' WHERE "regionId" = $1`,
      [regionId],
    );
    await owner.query(
      `UPDATE "Depot" SET "createdAt" = ${opening} - interval '1 day' WHERE "regionId" = $1`,
      [regionId],
    );
    await owner.query(
      `UPDATE "User" SET "createdAt" = ${opening} - interval '1 day', "decidedAt" = ${opening} - interval '1 day' WHERE "regionId" = $1`,
      [regionId],
    );
    await owner.query("COMMIT");
  } catch (error) {
    await owner.query("ROLLBACK");
    throw error;
  }
}
