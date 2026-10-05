// End-to-end simulation of a month of activity through the real services, then
// consistency checks on the resulting database. Run against an isolated,
// freshly migrated database only (see run.sh): it creates its own accounts.
//   DIST=apps/api/dist DATABASE_URL=<app role> OWNER_URL=<owner> node simulate.cjs
const D = process.env.DIST || "/app/apps/api/dist";
const { PrismaClient } = require("@prisma/client");
const { PrismaPg } = require("@prisma/adapter-pg");
const { Database } = require(D + "/shared/infrastructure/database.js");
const { PrismaUnitOfWork, lotIdentity } = require(D + "/modules/operations/infrastructure/prisma-ledger.js");
const { OperationsService } = require(D + "/modules/operations/application/operations.service.js");
const { WorkspaceService } = require(D + "/modules/tenancy/workspace.service.js");
const { PricingService } = require(D + "/modules/pricing/pricing.service.js");
const { TicketService } = require(D + "/modules/operations/http/ticket.controller.js");
const { GamificationService } = require(D + "/modules/tenancy/gamification.service.js");
const { reconcileReporting } = require(D + "/modules/reporting/backfill.js");
const { randomUUID } = require("crypto");

if (!/_test$/.test(new URL(process.env.OWNER_URL).pathname))
  throw new Error("Refusing to run outside an isolated *_test database");
const owner = new PrismaClient({ adapter: new PrismaPg({ connectionString: process.env.OWNER_URL }) });
const db = new Database();
const ops = new OperationsService(new PrismaUnitOfWork(db));
const workspace = new WorkspaceService(db);
const pricing = new PricingService(db);
const tickets = new TicketService(db);
const gamification = new GamificationService(db);

const DAY = 86400000, DAYS = Number(process.env.DAYS || 30);
let seed = 7;
const rnd = () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1));
const pick = (a) => a[Math.floor(rnd() * a.length)];
const today = () => new Date().toISOString().slice(0, 10);
const counts = {};
const count = (k) => (counts[k] = (counts[k] || 0) + 1);
const failures = [];

const person = (name, platformAdmin = false) => ({ id: randomUUID(), email: `${randomUUID()}@simulation.test`, name, platformAdmin });
const env = (place, command, expectedVersion, supplierStoreId) => ({
  operationId: randomUUID(), organizationId: place.organizationId, storeId: place.id, payloadVersion: 2, command, expectedVersion, supplierStoreId,
});
async function submit(actor, op, label) {
  const r = await ops.submit(actor, op);
  if (r.status !== "accepted") throw new Error(`${label || op.command.type}: ${r.code} ${r.message}`);
  count(label || op.command.type);
  return r;
}
async function step(label, work) {
  try { await work(); } catch (e) { failures.push(`${label}: ${e.message}`); }
}

(async () => {
  // ---------- people and places ----------
  const admin = person("BioBalance", true);
  const groups = [], grossistes = [];
  const users = [admin];
  for (let g = 0; g < 3; g++) {
    const responsable = person(`Responsable ${g + 1}`);
    users.push(responsable);
    const group = { id: randomUUID(), name: `Groupe ${g + 1}`, responsable, stores: [] };
    for (let s = 0; s < 2; s++) {
      const store = { id: randomUUID(), organizationId: group.id, name: `Magasin ${g + 1}.${s + 1}`, sellers: [person(`Vendeur ${g + 1}.${s + 1}.a`), person(`Vendeur ${g + 1}.${s + 1}.b`)] };
      users.push(...store.sellers);
      group.stores.push(store);
    }
    groups.push(group);
  }
  for (let w = 0; w < 2; w++) {
    const actor = person(`Grossiste ${w + 1}`);
    users.push(actor);
    grossistes.push({ actor, depot: { id: randomUUID(), organizationId: randomUUID(), name: `Dépôt ${w + 1}`, wholesale: true } });
  }
  for (const u of users)
    await owner.user.create({ data: { id: u.id, email: u.email, name: u.name, passwordHash: "simulation", platformAdmin: u.platformAdmin } });
  for (const g of groups) {
    await owner.organization.create({ data: { id: g.id, name: g.name } });
    await owner.organizationMembership.create({ data: { organizationId: g.id, userId: g.responsable.id } });
    for (const s of g.stores) {
      await owner.store.create({ data: { id: s.id, organizationId: g.id, name: s.name, nature: "pharmacie", address: "Adresse", city: "Tunis", onboardingStep: 5 } });
      for (const seller of s.sellers)
        await owner.membership.create({ data: { organizationId: g.id, storeId: s.id, userId: seller.id, permissions: ["sell"] } });
    }
  }
  for (const w of grossistes) {
    await owner.organization.create({ data: { id: w.depot.organizationId, name: w.actor.name, kind: "wholesale" } });
    await owner.store.create({ data: { id: w.depot.id, organizationId: w.depot.organizationId, name: w.depot.name, address: "Zone", city: "Sfax", onboardingStep: 5 } });
    await owner.organizationMembership.create({ data: { organizationId: w.depot.organizationId, userId: w.actor.id } });
  }
  const stores = groups.flatMap((g) => g.stores.map((s) => ({ ...s, group: g, manager: g.responsable })));
  const products = [];
  for (let i = 0; i < 40; i++) {
    const id = randomUUID();
    await owner.product.create({ data: { id, reference: `SIM-${i}-${id.slice(0, 6)}`, name: `Produit ${i + 1}`, category: pick(["Sérums", "Crèmes visage", "Nettoyants visage"]) } });
    products.push({ id, retail: (20 + int(0, 80)) * 1000 + (i % 2) * 500 });
  }
  console.log("people and places ready");

  // ---------- price chain ----------
  const round = (m) => String(Math.round(m / 100) * 100);
  for (const p of products) {
    await pricing.set(admin, { operationId: randomUUID(), level: "wholesale", productId: p.id, priceMillimes: round(p.retail * 0.5) });
    await pricing.set(admin, { operationId: randomUUID(), level: "store_supply", productId: p.id, priceMillimes: round(p.retail * 0.68) });
    for (const w of grossistes)
      await pricing.set(w.actor, { operationId: randomUUID(), level: "store_supply", productId: p.id, priceMillimes: round(p.retail * (0.6 + rnd() * 0.05)) });
  }
  for (const p of products.slice(0, 5)) {
    await pricing.set(admin, { operationId: randomUUID(), level: "wholesale", productId: p.id, organizationId: grossistes[0].depot.organizationId, priceMillimes: round(p.retail * 0.45) });
    await pricing.set(admin, { operationId: randomUUID(), level: "store_supply", productId: p.id, organizationId: stores[0].organizationId, storeId: stores[0].id, priceMillimes: round(p.retail * 0.64) });
  }
  // One exception is withdrawn: that store follows the default again.
  await step("price clear", () => pricing.set(admin, { operationId: randomUUID(), level: "store_supply", productId: products[0].id, organizationId: stores[0].organizationId, storeId: stores[0].id, clear: true }));
  const retail = new Map(); // storeId -> productId -> price
  for (const s of stores) {
    retail.set(s.id, new Map());
    for (const p of products) {
      const price = String(p.retail + (s.name.endsWith(".2") ? 1000 : 0));
      await workspace.configureProduct(s.manager, s.organizationId, s.id, p.id, { priceMillimes: price, threshold: int(4, 10), pointsPerUnit: 0 });
      retail.get(s.id).set(p.id, price);
    }
  }
  // ---------- default points and rewards, with exceptions ----------
  for (const p of products) {
    await gamification.setPointsDefault(admin, { audience: "retail", productId: p.id, pointsPerUnit: Math.max(1, Math.round(p.retail / 10000)) });
    await gamification.setPointsDefault(admin, { audience: "wholesale", productId: p.id, pointsPerUnit: 1 });
  }
  await gamification.setStorePoints(admin, stores[1].organizationId, stores[1].id, { productId: products[1].id, pointsPerUnit: 20 });
  await gamification.setStorePoints(admin, stores[2].organizationId, stores[2].id, { productId: products[2].id, pointsPerUnit: 30 });
  await gamification.setStorePoints(admin, stores[2].organizationId, stores[2].id, { productId: products[2].id, reset: true });
  for (const r of [{ title: "Coffret", cost: 30 }, { title: "Bon d’achat", cost: 120 }])
    await gamification.saveRewardTemplate(admin, { audience: "retail", description: "", quantity: 1, active: true, ...r });
  await gamification.saveRewardTemplate(admin, { audience: "wholesale", title: "Remise", description: "", cost: 50, quantity: 1, active: true });
  console.log("prices, points and rewards ready");

  // ---------- opening stock ----------
  const expiries = ["2027-06-30", "2027-12-31", "2028-06-30"];
  const opening = async (place, actor, take, qty) => {
    const lines = products.filter((_, i) => take(i)).flatMap((p, i) =>
      Array.from({ length: i % 3 === 0 ? 2 : 1 }, (_, k) => ({ productId: p.id, batch: `B${i}${k}`, expiry: expiries[(i + k) % 3], quantity: qty() })));
    await submit(actor, env(place, { type: "stock.receive", reason: "opening", lines }), "opening");
  };
  for (const w of grossistes) await opening(w.depot, w.actor, () => true, () => int(300, 600));
  for (const s of stores) await opening(s, s.manager, (i) => i % 4 !== 3, () => int(20, 50));
  console.log("opening stock declared");

  // ---------- helpers ----------
  const lotsOf = (storeId) => owner.inventoryLot.findMany({ where: { storeId, sellable: { gt: 0 }, expiry: { gt: new Date(Date.now() + 30 * DAY) } }, orderBy: { expiry: "asc" } });
  const saleLog = [];
  async function sale(store, seller, when) {
    const lots = await lotsOf(store.id);
    if (!lots.length) return;
    const lines = [], used = new Set();
    for (let k = int(1, 3); k > 0; k--) {
      const lot = pick(lots);
      if (used.has(lot.productId)) continue;
      used.add(lot.productId);
      const quantity = Math.min(lot.sellable, int(1, 3));
      lines.push({ id: randomUUID(), productId: lot.productId, quantity, unitPriceMillimes: retail.get(store.id).get(lot.productId), allocations: [{ lotId: lot.id, quantity }], ...(rnd() < 0.05 ? { note: "Remarque du vendeur" } : {}) });
    }
    if (!lines.length) return;
    const saleId = randomUUID();
    await step("sale", async () => {
      await submit(seller, env(store, { type: "sale.create", saleId, occurredAt: new Date(when).toISOString(), lines }), "sale.create");
      saleLog.push({ store, seller, saleId, lines, when });
    });
  }
  const orderVersion = async (id) => (await owner.replenishmentOrder.findUniqueOrThrow({ where: { id } })).version;
  const delivery = (id) => owner.delivery.findUniqueOrThrow({ where: { id } });
  async function depotAllocations(depotId, productId, quantity) {
    const lots = await owner.inventoryLot.findMany({ where: { storeId: depotId, productId, sellable: { gt: 0 } }, orderBy: { expiry: "asc" } });
    const allocations = [];
    let left = quantity;
    for (const lot of lots) {
      if (left <= 0) break;
      const q = Math.min(left, lot.sellable);
      allocations.push({ lotId: lot.id, quantity: q });
      left -= q;
    }
    return { allocations, shipped: quantity - left };
  }
  async function restock(store) {
    const supplier = pick([null, grossistes[0], grossistes[1]]);
    const orderId = randomUUID(), deliveryId = randomUUID();
    const chosen = [...new Set(Array.from({ length: int(3, 7) }, () => pick(products).id))];
    await submit(store.manager, env(store, { type: "order.create", orderId, lines: chosen.map((productId) => ({ productId, quantity: int(5, 20) })) }), "order.create");
    if (rnd() < 0.08) return count("order left requested");
    if (supplier) await submit(admin, env(store, { type: "order.assign", orderId, supplierStoreId: supplier.depot.id }, 1), "order.assign");
    const actor = supplier ? supplier.actor : admin;
    const via = supplier ? supplier.depot.id : undefined;
    await submit(actor, env(store, { type: "order.prepare", orderId }, await orderVersion(orderId), via), "order.prepare");
    const order = await owner.replenishmentOrder.findUniqueOrThrow({ where: { id: orderId } });
    const lines = [];
    for (const l of order.lines) {
      if (supplier) {
        const { allocations, shipped } = await depotAllocations(supplier.depot.id, l.productId, l.quantity);
        if (shipped > 0) lines.push({ productId: l.productId, quantity: shipped, allocations });
      } else lines.push({ productId: l.productId, quantity: l.quantity, allocations: [{ batch: `BB${int(100, 999)}`, expiry: pick(expiries), quantity: l.quantity }] });
    }
    if (!lines.length) return;
    await submit(actor, env(store, { type: "delivery.dispatch", orderId, deliveryId, lines }, await orderVersion(orderId), via), "delivery.dispatch");
    const shipped = await delivery(deliveryId);
    const code = (await tickets.ticket(admin, deliveryId, {})).qr.split(".")[2];
    const outcome = rnd();
    const receive = (extra) => submit(store.manager, env(store, { type: "delivery.receive", deliveryId, lines: [], note: "", ...extra }, shipped.version), "delivery.receive");
    if (outcome < 0.5) return receive({ ticketCode: code });
    if (outcome < 0.65) {
      const first = shipped.lines[0], lot = first.allocations[0];
      const damaged = Math.min(lot.quantity, int(0, 2)), refused = Math.min(lot.quantity - damaged, int(1, 2));
      return receive({ ticketCode: code, note: "Colis abîmé", flags: [{ productId: first.productId, batch: lot.batch, damaged, refused }] });
    }
    if (outcome < 0.77) {
      await submit(store.manager, env(store, { type: "delivery.refuse", deliveryId, reason: "Ne correspond pas au bon" }, shipped.version), "delivery.refuse");
      const decision = rnd() < 0.7 ? "returned" : "reopen";
      await submit(admin, env(store, { type: "delivery.resolve", deliveryId, decision, reason: "Vérifié" }, (await delivery(deliveryId)).version), `resolve ${decision}`);
      if (decision === "reopen") await submit(store.manager, env(store, { type: "delivery.receive", deliveryId, lines: [], note: "", ticketCode: code }, (await delivery(deliveryId)).version), "delivery.receive");
      return;
    }
    if (outcome < 0.95) {
      // Without the QR: the store's claim may be wrong; BioBalance retains one figure per lot.
      const claim = shipped.lines.flatMap((l) => l.allocations.map((a) => ({ productId: l.productId, batch: a.batch, expiry: a.expiry, quantity: Math.max(1, a.quantity + int(-3, 1)) })));
      await submit(store.manager, env(store, { type: "delivery.receive", deliveryId, manualReason: "QR illisible", note: "Écart constaté", lines: claim }, shipped.version), "delivery.receive (claim)");
      const retained = shipped.lines.flatMap((l) => l.allocations.map((a) => ({ productId: l.productId, batch: a.batch, expiry: a.expiry, quantity: rnd() < 0.5 ? a.quantity : Math.max(1, a.quantity - 1) })));
      return submit(admin, env(store, { type: "delivery.validate", deliveryId, lines: retained, note: "Arbitrage", responsibility: pick(["shipper", "store", "carrier", "none"]) }, (await delivery(deliveryId)).version), "delivery.validate");
    }
    count("delivery left in transit");
  }

  // ---------- a month of activity ----------
  for (let d = DAYS - 1; d >= 0; d--) {
    for (const store of stores) {
      for (let n = int(3, 7); n > 0; n--) {
        const seller = rnd() < 0.1 ? store.manager : pick(store.sellers);
        const when = Date.now() - d * DAY - int(1, 8) * 3600000;
        await sale(store, seller, when);
      }
      if (d % 6 === 0) await step(`restock ${store.name}`, () => restock(store));
      if (d === 15 && store === stores[0])
        // A price change mid-month: earlier sales keep the old price.
        for (const p of products.slice(0, 3)) {
          const cfg = await owner.storeProduct.findUniqueOrThrow({ where: { storeId_productId: { storeId: store.id, productId: p.id } } });
          const next = String(Number(cfg.priceMillimes) + 2000);
          await workspace.configureProduct(store.manager, store.organizationId, store.id, p.id, { priceMillimes: next, threshold: cfg.threshold, pointsPerUnit: cfg.pointsPerUnit, expectedVersion: cfg.version });
          retail.get(store.id).set(p.id, next);
        }
    }
  }
  console.log("activity simulated", counts["sale.create"], "sales");

  // ---------- returns and corrections ----------
  for (const entry of saleLog.filter(() => rnd() < 0.04)) {
    const line = entry.lines[0];
    await step("return", async () => {
      const s = await owner.sale.findUniqueOrThrow({ where: { id: entry.saleId } });
      await submit(entry.store.manager, env(entry.store, { type: "sale.return", saleId: entry.saleId, reason: "Retour client", lines: [{ lineId: line.id, lotId: line.allocations[0].lotId, quantity: 1, sellable: rnd() < 0.7 }] }, s.version), "sale.return");
    });
  }
  for (const entry of saleLog.filter(() => rnd() < 0.02)) {
    await step("correction", async () => {
      const s = await owner.sale.findUniqueOrThrow({ where: { id: entry.saleId } });
      const lines = s.lines.map(({ pointsPerUnit, listPriceMillimes, ...l }) => l);
      const l = lines[0];
      const lot = await owner.inventoryLot.findUniqueOrThrow({ where: { id: l.allocations[0].lotId } });
      if (lot.sellable < 1 || Object.keys(s.returned).length) return;
      l.quantity += 1;
      l.allocations[0].quantity += 1;
      await submit(entry.seller, env(entry.store, { type: "sale.correct", saleId: s.id, occurredAt: s.occurredAt.toISOString(), reason: "Quantité corrigée", lines }, s.version), "sale.correct");
    });
  }
  // ---------- quality ----------
  for (const store of stores) {
    await step("quality", async () => {
      const lot = (await lotsOf(store.id)).find((l) => l.sellable >= 4);
      if (!lot) return;
      const flagId = randomUUID();
      await submit(store.manager, env(store, { type: "quality.flag", flagId, lotId: lot.id, quantity: 3, kind: "damaged", note: "Emballage abîmé" }, lot.version), "quality.flag");
      const r = rnd();
      if (r < 0.6) await submit(admin, env(store, { type: "quality.resolve", flagId, decision: "confirm", quantity: int(1, 3), responsibility: pick(["shipper", "store", "carrier", "none"]), note: "Constat" }, 1), "quality.resolve confirm");
      else if (r < 0.85) await submit(admin, env(store, { type: "quality.resolve", flagId, decision: "reject", note: "Produit conforme" }, 1), "quality.resolve reject");
    });
  }
  // ---------- reward claims ----------
  // Rates were set when the simulation started: sales made from now on earn points.
  for (const store of stores)
    for (const seller of store.sellers)
      for (let n = 0; n < 6; n++) await sale(store, seller, Date.now());
  for (const store of stores)
    for (const seller of store.sellers)
      await step("claim", async () => {
        const account = await owner.pointsAccount.findUnique({ where: { storeId_userId: { storeId: store.id, userId: seller.id } } });
        const rewards = await owner.reward.findMany({ where: { storeId: store.id, active: true }, orderBy: { cost: "asc" } });
        if (!account || !rewards.length || account.balance - account.reserved < BigInt(rewards[0].cost)) return count("claim skipped (points)");
        const claimId = randomUUID();
        await submit(seller, env(store, { type: "reward.request", claimId, rewardId: rewards[0].id }), "reward.request");
        if (rnd() < 0.6) await submit(admin, env(store, { type: "reward.resolve", claimId, decision: "fulfilled" }, 1), "reward.resolve");
      });

  // ---------- consistency checks ----------
  const checks = {};
  const check = async (name, sql) => {
    const rows = await owner.$queryRawUnsafe(sql);
    checks[name] = rows.length === 0 ? "ok" : `${rows.length} problem(s): ${JSON.stringify(rows.slice(0, 3), (_, v) => (typeof v === "bigint" ? v.toString() : v))}`;
  };
  await check("lot stock equals its movements", `
    SELECT l.id, l.sellable, l.damaged, COALESCE(m.s,0) s, COALESCE(m.d,0) d FROM "InventoryLot" l
    LEFT JOIN (SELECT "lotId", SUM(quantity) FILTER (WHERE bucket='sellable') s, SUM(quantity) FILTER (WHERE bucket='damaged') d FROM "StockMovement" GROUP BY "lotId") m ON m."lotId"=l.id
    WHERE l.sellable <> COALESCE(m.s,0) OR l.damaged <> COALESCE(m.d,0)`);
  await check("no negative damaged stock", `SELECT id FROM "InventoryLot" WHERE damaged < 0`);
  await check("negative sellable stock is flagged", `
    SELECT l.id FROM "InventoryLot" l WHERE l.sellable < 0 AND NOT EXISTS (
      SELECT 1 FROM "Alert" a WHERE a."storeId"=l."storeId" AND a."productId"=l."productId" AND a.kind='discrepancy' AND a.active)`);
  await check("points balance equals its entries", `
    SELECT a."storeId", a."userId", a.balance, COALESCE(SUM(e.amount),0) total FROM "PointsAccount" a
    LEFT JOIN "PointsEntry" e ON e."storeId"=a."storeId" AND e."userId"=a."userId"
    GROUP BY a."storeId", a."userId", a.balance HAVING a.balance <> COALESCE(SUM(e.amount),0)`);
  await check("reserved points equal open claims", `
    SELECT a."storeId", a."userId" FROM "PointsAccount" a
    WHERE a.reserved <> COALESCE((SELECT SUM(c.cost) FROM "RewardClaim" c WHERE c."storeId"=a."storeId" AND c."userId"=a."userId" AND c.status='requested'),0)`);
  await check("sale total equals its lines", `
    SELECT s.id FROM "Sale" s WHERE s."totalMillimes" <> (
      SELECT COALESCE(SUM((l->>'quantity')::bigint*(l->>'unitPriceMillimes')::bigint),0) FROM jsonb_array_elements(s.lines) l)`);
  await check("received deliveries have one receipt, others none", `
    SELECT d.id, d.status FROM "Delivery" d LEFT JOIN "DeliveryReceipt" r ON r."deliveryId"=d.id
    WHERE (d.status='received') <> (r.id IS NOT NULL)`);
  await check("a seller's price is a price of the store", `
    SELECT s.id FROM "Sale" s JOIN "Membership" m ON m."storeId"=s."storeId" AND m."userId"=s."sellerId" AND NOT ('manage' = ANY(m.permissions)),
      jsonb_array_elements(s.lines) l
    WHERE NOT EXISTS (SELECT 1 FROM "PriceVersion" p WHERE p.level='retail' AND p."storeId"=s."storeId"
      AND p."productId"=(l->>'productId')::uuid AND p."priceMillimes"=(l->>'unitPriceMillimes')::bigint)`);
  await check("depot settles every received delivery (shipped = kept + returned - extra)", `
    WITH shipped AS (SELECT d.id, SUM((a->>'quantity')::int) q FROM "Delivery" d, jsonb_array_elements(d.lines) l, jsonb_array_elements(l->'allocations') a
                     WHERE d."sourceStoreId" IS NOT NULL AND d.status='received' GROUP BY d.id),
    kept AS (SELECT r."deliveryId" id, SUM((x->>'quantity')::int) FILTER (WHERE COALESCE(x->>'condition','sellable')<>'refused') q FROM "DeliveryReceipt" r, jsonb_array_elements(r.lines) x GROUP BY 1),
    moved AS (SELECT "sourceId" id, SUM(quantity) FILTER (WHERE reason='delivery.return') back, SUM(-quantity) FILTER (WHERE reason='delivery.correction') extra FROM "StockMovement" GROUP BY 1)
    SELECT s.id, s.q, k.q kept, m.back, m.extra FROM shipped s JOIN kept k ON k.id=s.id LEFT JOIN moved m ON m.id=s.id
    WHERE s.q <> k.q + COALESCE(m.back,0) - COALESCE(m.extra,0)`);
  await check("returned parcels went back to the depot in full", `
    WITH shipped AS (SELECT d.id, SUM((a->>'quantity')::int) q FROM "Delivery" d, jsonb_array_elements(d.lines) l, jsonb_array_elements(l->'allocations') a
                     WHERE d."sourceStoreId" IS NOT NULL AND d.status='returned' GROUP BY d.id)
    SELECT s.id FROM shipped s WHERE s.q <> (SELECT COALESCE(SUM(quantity),0) FROM "StockMovement" m WHERE m."sourceId"=s.id AND m.reason='delivery.return')`);
  await check("received orders have nothing left on the road", `
    SELECT o.id FROM "ReplenishmentOrder" o WHERE o.status='received' AND EXISTS (
      SELECT 1 FROM "Delivery" d WHERE d."orderId"=o.id AND d.status IN ('dispatched','pending_review','refused'))`);
  await check("every place has every default reward", `
    SELECT s.id, t.id FROM "Store" s JOIN "Organization" o ON o.id=s."organizationId"
    JOIN "RewardTemplate" t ON t.audience=(CASE WHEN o.kind='wholesale' THEN 'wholesale' ELSE 'retail' END)
    WHERE NOT EXISTS (SELECT 1 FROM "Reward" r WHERE r."storeId"=s.id AND r."templateId"=t.id)`);
  await check("places without an exception follow the default rate", `
    SELECT sp."storeId", sp."productId" FROM "StoreProduct" sp JOIN "Store" s ON s.id=sp."storeId" JOIN "Organization" o ON o.id=s."organizationId"
    JOIN LATERAL (SELECT "pointsPerUnit" FROM "PointsDefault" d WHERE d."productId"=sp."productId"
      AND d.audience=(CASE WHEN o.kind='wholesale' THEN 'wholesale' ELSE 'retail' END) ORDER BY "createdAt" DESC, id DESC LIMIT 1) d ON true
    WHERE NOT sp."pointsException" AND sp."pointsPerUnit" <> d."pointsPerUnit"`);
  await check("decided quality flags left nothing on hold", `
    SELECT f.id FROM "QualityFlag" f WHERE f.status='confirmed' AND (f."confirmedQuantity" IS NULL OR f."confirmedQuantity" > f.quantity)`);
  try { checks["reporting projections match sales"] = JSON.stringify(await reconcileReporting(owner)); }
  catch (e) { checks["reporting projections match sales"] = `FAILED ${e.message}`; }

  console.log(JSON.stringify({ counts, failures: failures.slice(0, 20), failureCount: failures.length, checks }, null, 1));
  await db.$disconnect();
  await owner.$disconnect();
  process.exit(failures.length || Object.values(checks).some((v) => !String(v).startsWith("ok") && !String(v).startsWith("{")) ? 1 : 0);
})().catch(async (e) => { console.error("SIMULATION FAILED", e); process.exit(2); });
