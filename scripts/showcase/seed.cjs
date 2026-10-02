const D = process.env.DIST || "/app/apps/api/dist";
const { Database } = require(D + "/shared/infrastructure/database.js");
const { PrismaUnitOfWork, lotIdentity } = require(D + "/modules/operations/infrastructure/prisma-ledger.js");
const { OperationsService } = require(D + "/modules/operations/application/operations.service.js");
const { WorkspaceService } = require(D + "/modules/tenancy/workspace.service.js");
const { PricingService } = require(D + "/modules/pricing/pricing.service.js");
const { TicketService } = require(D + "/modules/operations/http/ticket.controller.js");
const { randomUUID } = require("crypto");

const db = new Database();
const ops = new OperationsService(new PrismaUnitOfWork(db));
const workspace = new WorkspaceService(db);
const pricing = new PricingService(db);
const tickets = new TicketService(db);
const DAY = 86400000;
let seed = 20261002;
const rnd = () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const pick = (a) => a[Math.floor(rnd() * a.length)];
const int = (lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1));
const stats = { sales: 0, returns: 0, orders: 0, deliveries: 0, receipts: 0, failures: [] };

const actorOf = async (email) => {
  const u = await db.user.findFirstOrThrow({ where: { email } });
  return { id: u.id, email: u.email, name: u.name, platformAdmin: u.platformAdmin };
};
const env = (org, store, command, expectedVersion, supplierStoreId) => ({
  operationId: randomUUID(), organizationId: org, storeId: store, payloadVersion: 2, command, expectedVersion, supplierStoreId,
});
async function accepted(actor, op, label) {
  const r = await ops.submit(actor, op);
  if (r.status !== "accepted") throw new Error(`${label || op.command.type}: ${r.code} ${r.message}`);
  return r;
}
const dateOnly = (ms) => new Date(ms).toISOString().slice(0, 10);

(async () => {
  const admin = await actorOf("boudhriwa.haydar@gmail.com");
  const manager = await actorOf("haydar.boudhrioua@gmail.com");
  const samir = await actorOf("hayder.boudhrioua@gmail.com");
  const imed = await actorOf("besel62147@caps7.com");
  const hedi = await actorOf("hayder@tanpony.com");
  const stores = await workspace.stores(admin);
  const byName = (n) => stores.find((s) => s.name === n);
  const PARA = byName("PARAHOUSE"), PHARMA = byName("PHARMAHOUSE"), DEPOT = byName("HEDI");
  const asAdmin = (fn, place) => db.authenticated(admin, async (tx) => {
    await tx.$executeRawUnsafe("SELECT set_config($1,$2,true)", "app.admin_read", "true");
    await tx.$executeRawUnsafe("SELECT set_config($1,$2,true)", "app.price_access", "true");
    if (place) {
      await tx.$executeRawUnsafe("SELECT set_config($1,$2,true)", "app.organization_id", place.organizationId);
      await tx.$executeRawUnsafe("SELECT set_config($1,$2,true)", "app.store_id", place.id);
    }
    return fn(tx);
  }, true);
  const products = await asAdmin((tx) => tx.product.findMany({ where: { active: true }, orderBy: { reference: "asc" } }));
  const retailOf = {};
  for (const s of [PARA, PHARMA]) {
    const rows = await asAdmin((tx) => tx.storeProduct.findMany({ where: { storeId: s.id } }), s);
    retailOf[s.id] = new Map(rows.map((r) => [r.productId, r.priceMillimes.toString()]));
  }
  console.log("products", products.length, "stores", stores.map((s) => s.name).join(","));

  // ---------- stock: each place declares what it holds ----------
  const yearMonth = ["2027-03-31", "2027-06-30", "2027-09-30", "2027-12-31", "2028-03-31", "2028-06-30", "2028-11-30"];
  const lotsOf = { [PARA.id]: [], [PHARMA.id]: [], [DEPOT.id]: [] };
  async function openingStock(place, actor, take, qty) {
    const lines = [];
    products.forEach((p, i) => {
      if (!take(i)) return;
      const n = rnd() < 0.35 ? 2 : 1;
      for (let k = 0; k < n; k++) {
        const near = place.id !== DEPOT.id && i % 17 === 3 && k === 0;
        const expiry = near ? dateOnly(Date.now() + 19 * DAY) : yearMonth[(i * 3 + k * 2 + place.name.length) % yearMonth.length];
        const batch = `${place.id === DEPOT.id ? "H" : place.name[0]}${String(24 + (i % 2)).padStart(2, "0")}${String(1 + ((i + k) % 12)).padStart(2, "0")}${"ABC"[(i + k) % 3]}`;
        const quantity = qty(i, k);
        lines.push({ productId: p.id, batch, expiry, quantity });
      }
    });
    await accepted(actor, env(place.organizationId, place.id, { type: "stock.receive", reason: "opening", lines }), "opening " + place.name);
    for (const l of lines) lotsOf[place.id].push({ ...l, id: lotIdentity(place.id, l.productId, l.batch, l.expiry), left: l.quantity });
  }
  await openingStock(DEPOT, hedi, (i) => i % 8 !== 7, (i, k) => int(160, 420) - k * 40);
  await openingStock(PARA, manager, (i) => i % 3 !== 2, (i, k) => int(24, 60) - k * 6);
  await openingStock(PHARMA, manager, (i) => i % 7 !== 6 && i % 5 !== 4, (i, k) => int(22, 56) - k * 6);
  console.log("stock declared");

  // ---------- sales over the last two weeks ----------
  const saleLog = [];
  async function sale(place, seller, whenMs) {
    const stocked = lotsOf[place.id].filter((l) => l.left > 0 && l.expiry > dateOnly(Date.now() + 25 * DAY));
    const byProduct = new Map();
    for (const l of stocked) { if (!byProduct.has(l.productId)) byProduct.set(l.productId, []); byProduct.get(l.productId).push(l); }
    const ids = [...byProduct.keys()];
    if (!ids.length) return;
    const lines = [], used = new Set();
    for (let k = int(1, 3); k > 0; k--) {
      const pid = pick(ids);
      if (used.has(pid)) continue;
      used.add(pid);
      const lot = byProduct.get(pid).sort((a, b) => a.expiry.localeCompare(b.expiry)).find((l) => l.left > 0);
      if (!lot) continue;
      const quantity = Math.min(lot.left, int(1, 3));
      lines.push({ id: randomUUID(), productId: pid, quantity, unitPriceMillimes: retailOf[place.id].get(pid), allocations: [{ lotId: lot.id, quantity }], ...(rnd() < 0.05 ? { note: pick(["Cliente fidèle", "Échantillon offert", "Conseil du pharmacien"]) } : {}), _lot: lot });
    }
    if (!lines.length) return;
    const saleId = randomUUID();
    const command = { type: "sale.create", saleId, occurredAt: new Date(whenMs).toISOString(), lines: lines.map(({ _lot, ...l }) => l) };
    try {
      await accepted(seller, env(place.organizationId, place.id, command), "sale");
      for (const l of lines) l._lot.left -= l.quantity;
      stats.sales++;
      saleLog.push({ place, saleId, lines: lines.map((l) => ({ lineId: l.id, lotId: l._lot.id, productId: l.productId, quantity: l.quantity })) });
    } catch (e) { stats.failures.push(e.message); }
  }
  for (let d = 13; d >= 0; d--) {
    const weekend = [0, 6].includes(new Date(Date.now() - d * DAY).getUTCDay());
    for (const [place, seller] of [[PARA, imed], [PHARMA, samir]]) {
      const n = (weekend ? int(2, 4) : int(5, 9)) + (d < 4 ? 1 : 0);
      for (let i = 0; i < n; i++) {
        const who = rnd() < 0.12 ? manager : seller;
        const ago = d === 0 ? int(30, 420) * 60000 : d * DAY + int(0, 9) * 3600000 + int(0, 59) * 60000;
        await sale(place, who, Date.now() - ago);
      }
    }
  }
  console.log("sales", stats.sales);

  // ---------- returns ----------
  for (const entry of saleLog.filter((_, i) => i % 23 === 5).slice(0, 7)) {
    const line = entry.lines[0];
    const damaged = stats.returns % 3 === 2;
    try {
      const row = await asAdmin((tx) => tx.sale.findFirstOrThrow({ where: { id: entry.saleId } }), entry.place);
      await accepted(manager, env(entry.place.organizationId, entry.place.id, { type: "sale.return", saleId: entry.saleId, reason: damaged ? "Produit abîmé à l’ouverture" : "Client ayant changé d’avis", lines: [{ lineId: line.lineId, lotId: line.lotId, quantity: 1, sellable: !damaged }] }, row.version), "return");
      stats.returns++;
    } catch (e) { stats.failures.push(e.message); }
  }
  console.log("returns", stats.returns);

  // ---------- orders and deliveries ----------
  const depotLot = (pid) => lotsOf[DEPOT.id].find((l) => l.productId === pid && l.left > 0);
  let cur = null;
  const orderVersion = (id) => asAdmin((tx) => tx.replenishmentOrder.findUniqueOrThrow({ where: { id } }), cur).then((o) => o.version);
  const deliveryOf = (id) => asAdmin((tx) => tx.delivery.findUniqueOrThrow({ where: { id } }), cur);
  async function order(place, wanted, mode, until, flags) {
    cur = place;
    const orderId = randomUUID(), deliveryId = randomUUID();
    const ids = products.filter((_, i) => wanted(i)).map((p) => p.id).filter((pid) => mode !== "hedi" || depotLot(pid));
    const lines = ids.slice(0, int(5, 9)).map((productId) => ({ productId, quantity: int(6, 18) }));
    await accepted(manager, env(place.organizationId, place.id, { type: "order.create", orderId, lines }), "order.create");
    stats.orders++;
    if (until === "requested") return;
    let supplier;
    if (mode === "hedi") {
      await accepted(admin, env(place.organizationId, place.id, { type: "order.assign", orderId, supplierStoreId: DEPOT.id }, 1), "assign");
      supplier = DEPOT.id;
    }
    const actor = mode === "hedi" ? hedi : admin;
    await accepted(actor, env(place.organizationId, place.id, { type: "order.prepare", orderId }, await orderVersion(orderId), supplier), "prepare");
    if (until === "preparing") return;
    const shipped = lines.map((l) => {
      if (mode === "hedi") { const lot = depotLot(l.productId); const q = Math.min(l.quantity, lot.left); lot.left -= q; return { productId: l.productId, quantity: q, allocations: [{ lotId: lot.id, quantity: q }] }; }
      return { productId: l.productId, quantity: l.quantity, allocations: [{ batch: "BB" + String(2500 + int(1, 99)), expiry: yearMonth[int(2, 6)], quantity: l.quantity }] };
    }).filter((l) => l.quantity > 0);
    await accepted(actor, env(place.organizationId, place.id, { type: "delivery.dispatch", orderId, deliveryId, lines: shipped }, await orderVersion(orderId), supplier), "dispatch");
    stats.deliveries++;
    if (until === "transit") return;
    const t = mode === "hedi"
      ? await tickets.ticket(hedi, deliveryId, { organizationId: DEPOT.organizationId, supplierStoreId: DEPOT.id })
      : await tickets.ticket(admin, deliveryId, {});
    const code = t.qr.split(".")[2];
    const d = await deliveryOf(deliveryId);
    const cmd = { type: "delivery.receive", deliveryId, ticketCode: code, lines: [], note: "", flags: [] };
    if (flags) {
      const first = (await deliveryOf(deliveryId)).lines[0], lot = first.allocations[0];
      cmd.flags = [{ productId: first.productId, batch: lot.batch, damaged: 2, refused: 1 }];
      cmd.note = "Deux flacons cassés et un carton refusé à la livraison";
    }
    await accepted(manager, env(place.organizationId, place.id, cmd, d.version), "receive");
    stats.receipts++;
  }
  const attempt = async (fn, label) => { try { await fn(); } catch (e) { stats.failures.push(label + ": " + e.message); } };
  await attempt(() => order(PARA, (i) => i % 3 === 0, "hedi", "received"), "order 1");
  await attempt(() => order(PHARMA, (i) => i % 2 === 0, "hedi", "received", true), "order 2");
  await attempt(() => order(PARA, (i) => i % 4 === 1, "bio", "received"), "order 3");
  await attempt(() => order(PHARMA, (i) => i % 5 === 1, "hedi", "transit"), "order 4");
  await attempt(() => order(PARA, (i) => i % 4 === 3, "hedi", "requested"), "order 5");
  await attempt(() => order(PHARMA, (i) => i % 3 === 1, "bio", "preparing"), "order 6");
  console.log("orders", stats.orders, "deliveries", stats.deliveries, "receipts", stats.receipts);

  // ---------- rewards ----------
  const rewardsOf = {};
  for (const place of [PARA, PHARMA]) {
    rewardsOf[place.id] = [];
    for (const r of [
      { title: "Coffret soin visage", description: "Un coffret de soins visage au choix", cost: 250, quantity: 12 },
      { title: "Bon d’achat 50 TND", description: "Bon d’achat utilisable en magasin", cost: 600, quantity: 8 },
      { title: "Trousse de voyage", description: "Trousse avec miniatures de la gamme", cost: 120, quantity: 20 },
    ]) await attempt(async () => rewardsOf[place.id].push(await workspace.reward(admin, place.organizationId, place.id, { ...r, active: true })), "reward");
  }
  for (const [place, seller] of [[PARA, imed], [PHARMA, samir]]) {
    await attempt(async () => {
      const list = await asAdmin((tx) => tx.reward.findMany({ where: { storeId: place.id }, orderBy: { cost: "asc" } }), place);
      const cheap = list[0];
      const a = randomUUID(), b = randomUUID();
      await accepted(seller, env(place.organizationId, place.id, { type: "reward.request", claimId: a, rewardId: cheap.id }), "claim");
      const claim = await asAdmin((tx) => tx.rewardClaim.findFirstOrThrow({ where: { id: a } }), place);
      await accepted(admin, env(place.organizationId, place.id, { type: "reward.resolve", claimId: a, decision: "fulfilled" }, claim.version), "claim resolve");
      await accepted(seller, env(place.organizationId, place.id, { type: "reward.request", claimId: b, rewardId: list[1].id }), "claim 2");
    }, "claims " + place.name);
  }

  // ---------- quality ----------
  await attempt(async () => {
    const lot = lotsOf[PARA.id].find((l) => l.left > 3 && l.expiry > dateOnly(Date.now() + 60 * DAY));
    const f1 = randomUUID(), f2 = randomUUID();
    const v1 = (await asAdmin((tx) => tx.inventoryLot.findUniqueOrThrow({ where: { id: lot.id } }), PARA)).version;
    await accepted(manager, env(PARA.organizationId, PARA.id, { type: "quality.flag", flagId: f1, lotId: lot.id, quantity: 2, kind: "damaged", note: "Emballages écrasés au rayon" }, v1), "flag");
    const fv = (await asAdmin((tx) => tx.qualityFlag.findUniqueOrThrow({ where: { id: f1 } }), PARA)).version;
    await accepted(admin, env(PARA.organizationId, PARA.id, { type: "quality.resolve", flagId: f1, decision: "confirm", note: "Constat confirmé, unités retirées du stock" }, fv), "flag resolve");
    const lot2 = lotsOf[PHARMA.id].find((l) => l.left > 3 && l.expiry > dateOnly(Date.now() + 60 * DAY));
    const v2 = (await asAdmin((tx) => tx.inventoryLot.findUniqueOrThrow({ where: { id: lot2.id } }), PHARMA)).version;
    await accepted(manager, env(PHARMA.organizationId, PHARMA.id, { type: "quality.flag", flagId: f2, lotId: lot2.id, quantity: 1, kind: "damaged", note: "Flacon fissuré" }, v2), "flag 2");
  }, "quality");

  // ---------- a recent price change, with its history ----------
  await attempt(async () => {
    const p = products[3];
    await pricing.set(admin, { operationId: randomUUID(), level: "store_supply", productId: p.id, priceMillimes: String(Math.round(Number(retailOf[PARA.id].get(p.id)) * 0.70 / 100) * 100), reason: "Ajustement des tarifs" });
    const cfg = await asAdmin((tx) => tx.storeProduct.findFirstOrThrow({ where: { storeId: PARA.id, productId: p.id } }), PARA);
    await workspace.configureProduct(manager, PARA.organizationId, PARA.id, p.id, { priceMillimes: String(Number(cfg.priceMillimes) + 2000), threshold: cfg.threshold, pointsPerUnit: cfg.pointsPerUnit, expectedVersion: cfg.version, reason: "Nouveau tarif fournisseur" });
  }, "price change");

  console.log(JSON.stringify({ ...stats, failures: stats.failures.slice(0, 15), failureCount: stats.failures.length }, null, 1));
  await db.$disconnect();
})().catch(async (e) => { console.error("FAILED", e); await db.$disconnect(); process.exit(1); });
