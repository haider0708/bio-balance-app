import { DeliveryIssueRecord } from "../domain/contracts";
import { orderFulfillment } from "./order-fulfillment-query";
import { createHash, randomUUID } from "node:crypto";
import { Prisma } from "@prisma/client";
import { Database, json } from "../../../shared/infrastructure/database";
import { requireRule } from "../../../shared/domain/errors";
import { localDate } from "../../../shared/domain/money";
import {
  Actor,
  Scope,
  SaleRecord,
  AcceptedLine,
  ClaimRecord,
  OrderRecord,
  DeliveryRecord,
  OperationResult,
} from "../domain/contracts";
import { UnitOfWork, Ledger } from "../application/ports";
export class PrismaUnitOfWork extends UnitOfWork {
  constructor(private readonly db: Database) {
    super();
  }
  run<T>(
    actor: Actor,
    organizationId: string,
    storeId: string,
    work: (ledger: Ledger) => Promise<T>,
  ): Promise<T> {
    return this.db.scoped(actor, organizationId, storeId, async (tx, scope) => {
      await tx.storeCursor.upsert({
        where: { storeId },
        create: { storeId, organizationId },
        update: {},
      });
      await tx.$queryRaw`SELECT "storeId" FROM "StoreCursor" WHERE "storeId"=${storeId}::uuid FOR UPDATE`;
      return work(new PrismaLedger(tx, scope));
    });
  }
}
export class PrismaLedger implements Ledger {
  private readonly context: { organizationId: string; storeId: string };
  constructor(
    private readonly tx: Prisma.TransactionClient,
    readonly scope: Scope,
  ) {
    this.context = {
      organizationId: scope.organizationId,
      storeId: scope.storeId,
    };
  }
  async cursor() {
    return (
      await this.tx.storeCursor.findUniqueOrThrow({
        where: { storeId: this.scope.storeId },
      })
    ).value.toString();
  }
  async dependenciesAccepted(ids: string[]) {
    if (!ids.length) return true;
    const accepted = await this.tx.processedOperation.count({
      where: {
        ...this.context,
        actorId: this.scope.actor.id,
        id: { in: [...new Set(ids)] },
      },
    });
    return accepted === new Set(ids).size;
  }
  async prior(id: string, hash: string) {
    const value = await this.tx.processedOperation.findUnique({
      where: { id },
    });
    if (!value) return null;
    requireRule(
      value.actorId === this.scope.actor.id && value.payloadHash === hash,
      "OPERATION_REUSED",
      "Cet identifiant d’opération a déjà été utilisé différemment.",
      409,
    );
    return value.result as unknown as OperationResult;
  }
  async finish(
    id: string,
    hash: string,
    result: OperationResult,
    entity: string,
    entityId: string,
    details: unknown,
  ) {
    const targetType = entity.split(".")[0];
    if (["order", "delivery", "reward", "sale"].includes(targetType!)) {
      const targetId =
        targetType === "delivery"
          ? (
              await this.tx.delivery.findUniqueOrThrow({
                where: { id: entityId },
              })
            ).orderId
          : entityId;
      await this.tx.notification.updateMany({
        where: { ...this.context, eventKey: id },
        data: {
          targetType: targetType === "delivery" ? "order" : targetType,
          targetId,
        },
      });
    }
    await this.tx.auditEntry.create({
      data: {
        ...this.context,
        actorId: this.scope.actor.id,
        action: entity,
        targetId: entityId,
        operationId: id,
        details: json(details),
      },
    });
    const cursor = await this.tx.storeCursor.update({
      where: { storeId: this.scope.storeId },
      data: { value: { increment: 1 } },
    });
    const movements = await this.tx.stockMovement.findMany({
      where: { ...this.context, operationId: id },
      select: { lotId: true },
      distinct: ["lotId"],
    });
    const lots = await this.tx.inventoryLot.findMany({
      where: { ...this.context, id: { in: movements.map((m) => m.lotId) } },
      select: { id: true, version: true },
    });
    result.committedCursor = cursor.value.toString();
    result.affectedVersions = lots.map((l) => ({ resource: "lots", ...l }));
    if (
      entity.startsWith("sale.") &&
      typeof result.data?.version === "number"
    ) {
      result.affectedVersions.push({
        resource: "sales",
        id: entityId,
        version: result.data.version,
      });
    }
    if (entity.startsWith("order.")) {
      const order = await this.tx.replenishmentOrder.findUniqueOrThrow({
        where: { id: entityId },
        select: { id: true, version: true },
      });
      result.affectedVersions.push({ resource: "orders", ...order });
    }
    if (entity.startsWith("delivery.")) {
      const delivery = await this.tx.delivery.findUniqueOrThrow({
        where: { id: entityId },
        select: { id: true, version: true, orderId: true },
      });
      const order = await this.tx.replenishmentOrder.findUniqueOrThrow({
        where: { id: delivery.orderId },
        select: { id: true, version: true },
      });
      result.affectedVersions.push(
        { resource: "deliveries", id: delivery.id, version: delivery.version },
        { resource: "orders", ...order },
      );
    }
    if (entity.startsWith("reward.")) {
      const claim = await this.tx.rewardClaim.findUniqueOrThrow({
        where: { id: entityId },
        select: { id: true, version: true },
      });
      result.affectedVersions.push({ resource: "claims", ...claim });
    }
    await this.tx.processedOperation.create({
      data: {
        id,
        ...this.context,
        actorId: this.scope.actor.id,
        payloadHash: hash,
        result: json(result),
      },
    });
    await this.tx.change.create({
      data: { id, ...this.context, cursor: cursor.value, entity, entityId },
    });
  }
  async lot(id: string) {
    const lot = await this.tx.inventoryLot.findFirst({
      where: { id, ...this.context },
    });
    requireRule(lot, "LOT_NOT_FOUND", "Lot introuvable dans ce magasin.", 404);
    return lot;
  }
  lotsForProduct(productId: string, requiredUnits: number) {
    return this.tx.inventoryLot.findMany({
      where: {
        ...this.context,
        productId,
        sellable: { gt: 0 },
        expiry: {
          gte: new Date(
            `${localDate(new Date(), this.scope.timezone)}T00:00:00Z`,
          ),
        },
      },
      orderBy: [{ expiry: "asc" }, { id: "asc" }],
      take: requiredUnits,
    });
  }
  async declareBatch(
    lotId: string,
    productId: string,
    batch: string,
    expiry: string,
  ) {
    requireRule(
      lotId === lotIdentity(this.scope.storeId, productId, batch, expiry),
      "INVALID_LOT_IDENTITY",
      "L’identifiant du lot ne correspond pas à ses informations.",
    );
    await this.rate(productId);
    const lot = await this.tx.inventoryLot.upsert({
      where: {
        storeId_productId_batch_expiry: {
          storeId: this.scope.storeId,
          productId,
          batch,
          expiry: new Date(`${expiry}T00:00:00Z`),
        },
      },
      create: {
        id: lotId,
        ...this.context,
        productId,
        batch,
        expiry: new Date(`${expiry}T00:00:00Z`),
      },
      update: {},
    });
    requireRule(
      lot.id === lotId,
      "LOT_IDENTITY_CONFLICT",
      "Ce lot existe déjà. Actualisez ses informations.",
      409,
    );
    // Metadata only: the sale's stock movement records the real outgoing units.
    return lot;
  }
  async receive(
    productId: string,
    batch: string,
    expiry: string,
    quantity: number,
    sourceId: string,
    operationId: string,
    reason: string,
    bucket: "sellable" | "damaged" = "sellable",
  ) {
    await this.rate(productId);
    const date = new Date(`${expiry}T00:00:00Z`);
    const lot = await this.tx.inventoryLot.upsert({
      where: {
        storeId_productId_batch_expiry: {
          storeId: this.scope.storeId,
          productId,
          batch,
          expiry: date,
        },
      },
      create: {
        id: lotIdentity(this.scope.storeId, productId, batch, expiry),
        ...this.context,
        productId,
        batch,
        expiry: date,
      },
      update: {},
    });
    await this.move(lot.id, quantity, sourceId, operationId, reason, bucket);
    return this.lot(lot.id);
  }
  async move(
    lotId: string,
    quantity: number,
    sourceId: string,
    operationId: string,
    reason: string,
    bucket: "sellable" | "damaged" = "sellable",
  ) {
    await this.lot(lotId);
    await this.tx.stockMovement.create({
      data: {
        ...this.context,
        lotId,
        quantity,
        sourceId,
        operationId,
        reason,
        bucket,
        actorId: this.scope.actor.id,
      },
    });
    await this.tx.inventoryLot.update({
      where: { id: lotId },
      data: { [bucket]: { increment: quantity }, version: { increment: 1 } },
    });
  }
  async rate(productId: string) {
    const product = await this.tx.product.findUnique({
      where: { id: productId },
    });
    requireRule(product, "PRODUCT_NOT_FOUND", "Produit introuvable.", 404);
    const config = await this.tx.storeProduct.findUnique({
      where: { storeId_productId: { storeId: this.scope.storeId, productId } },
    });
    return config?.pointsPerUnit ?? 0;
  }
  async sale(id: string): Promise<SaleRecord | null> {
    const value = await this.tx.sale.findFirst({
      where: { id, ...this.context },
    });
    if (!value) return null;
    return {
      ...value,
      lines: value.lines as unknown as AcceptedLine[],
      returned: value.returned as Record<string, number>,
    };
  }
  async saveSale(
    value: SaleRecord,
    previous: SaleRecord | undefined,
    reason: string,
    operationId: string,
  ) {
    const data = {
      ...value,
      lines: json(value.lines),
      returned: json(value.returned),
    };
    if (previous) await this.tx.sale.update({ where: { id: value.id }, data });
    else await this.tx.sale.create({ data: { ...data, ...this.context } });
    await this.tx.saleRevision.create({
      data: {
        ...this.context,
        saleId: value.id,
        version: value.version,
        editorId: this.scope.actor.id,
        reason,
        operationId,
        before: previous ? json(previous) : Prisma.DbNull,
        after: json(value),
      },
    });
  }
  async points(userId: string) {
    return this.tx.pointsAccount.upsert({
      where: { storeId_userId: { storeId: this.scope.storeId, userId } },
      create: { ...this.context, userId },
      update: {},
    });
  }
  async credit(
    userId: string,
    amount: bigint,
    kind: string,
    sourceId: string,
    operationId: string,
  ) {
    await this.points(userId);
    await this.tx.pointsEntry.create({
      data: { ...this.context, userId, amount, kind, sourceId, operationId },
    });
    await this.tx.pointsAccount.update({
      where: { storeId_userId: { storeId: this.scope.storeId, userId } },
      data: { balance: { increment: amount } },
    });
  }
  async reserve(userId: string, delta: bigint) {
    const account = await this.points(userId);
    requireRule(
      account.reserved + delta >= 0,
      "RESERVATION_INVALID",
      "Réservation incohérente.",
      409,
    );
    await this.tx.pointsAccount.update({
      where: { storeId_userId: { storeId: this.scope.storeId, userId } },
      data: { reserved: { increment: delta } },
    });
  }
  async reward(id: string) {
    const item = await this.tx.reward.findFirst({
      where: { ...this.context, id },
    });
    requireRule(item, "NOT_FOUND", "Récompense introuvable.", 404);
    return item;
  }
  async claim(id: string) {
    const item = await this.tx.rewardClaim.findFirst({
      where: { ...this.context, id },
    });
    requireRule(item, "NOT_FOUND", "Demande introuvable.", 404);
    return item;
  }
  async saveClaim(value: ClaimRecord) {
    const {
      id,
      rewardId,
      title,
      cost,
      productId,
      quantity,
      userId,
      status,
      version,
    } = value;
    const data = {
      rewardId,
      title,
      cost,
      productId,
      quantity,
      userId,
      status,
      version,
    };
    if (version === 1)
      await this.tx.rewardClaim.create({
        data: { id, ...this.context, ...data },
      });
    else
      await this.tx.rewardClaim.update({
        where: { id },
        data: {
          ...data,
          resolvedAt: new Date(),
          fulfilledBy: status === "fulfilled" ? this.scope.actor.id : null,
        },
      });
  }
  async order(id: string): Promise<OrderRecord> {
    const item = await this.tx.replenishmentOrder.findFirst({
      where: { ...this.context, id },
    });
    requireRule(item, "NOT_FOUND", "Commande introuvable.", 404);
    return {
      ...item,
      lines: item.lines as OrderRecord["lines"],
      requestedLines: item.requestedLines as OrderRecord["lines"],
      cancelledLines: item.cancelledLines as OrderRecord["lines"],
    };
  }
  async saveOrder(value: OrderRecord) {
    const data = {
      ...value,
      lines: json(value.lines),
      requestedLines: json(value.requestedLines ?? value.lines),
      cancelledLines: json(value.cancelledLines ?? []),
    };
    if (value.version === 1)
      await this.tx.replenishmentOrder.create({
        data: { ...data, ...this.context, createdBy: this.scope.actor.id },
      });
    else
      await this.tx.replenishmentOrder.update({
        where: { id: value.id },
        data,
      });
  }
  async delivery(id: string): Promise<DeliveryRecord> {
    const item = await this.tx.delivery.findFirst({
      where: { ...this.context, id },
    });
    requireRule(item, "NOT_FOUND", "Livraison introuvable.", 404);
    return { ...item, lines: item.lines as OrderRecord["lines"] };
  }
  async fulfillment(order: OrderRecord) {
    const result = await orderFulfillment(
      this.tx,
      this.scope.organizationId,
      this.scope.storeId,
      [order],
    );
    return result.get(order.id)!;
  }
  async saveDelivery(value: DeliveryRecord) {
    const data = { ...value, lines: json(value.lines) };
    if (value.version === 1)
      await this.tx.delivery.create({ data: { ...data, ...this.context } });
    else
      await this.tx.delivery.update({
        where: { id: value.id },
        data: {
          ...data,
          ...(value.status === "received" &&
          !(
            await this.tx.delivery.findUniqueOrThrow({
              where: { id: value.id },
            })
          ).receivedAt
            ? { receivedAt: new Date() }
            : {}),
        },
      });
  }
  async orderProblemActive(orderId: string) {
    return !!(await this.tx.alert.findFirst({
      where: {
        ...this.context,
        key: `order:${orderId}`,
        kind: "order_problem",
        active: true,
      },
    }));
  }
  async setOrderProblem(orderId: string, reason: string, active: boolean) {
    // Alert is the current problem projection; operation audit retains every report and resolution.
    await this.tx.alert.upsert({
      where: {
        storeId_key: { storeId: this.scope.storeId, key: `order:${orderId}` },
      },
      create: {
        ...this.context,
        key: `order:${orderId}`,
        kind: "order_problem",
        message: reason,
        active,
      },
      update: active
        ? {
            message: reason,
            active: true,
            resolvedAt: null,
            createdAt: new Date(),
          }
        : { active: false, resolvedAt: new Date() },
    });
  }
  async issue(deliveryId: string): Promise<DeliveryIssueRecord | null> {
    const row = await this.tx.deliveryIssue.findFirst({
      where: { ...this.context, deliveryId },
    });
    return row
      ? { ...row, heldLines: row.heldLines as DeliveryIssueRecord["heldLines"] }
      : null;
  }
  async hasIssues(orderId: string) {
    return (
      (await this.tx.deliveryIssue.count({
        where: { ...this.context, orderId, status: { not: "resolved" } },
      })) > 0
    );
  }
  async saveIssue(issue: DeliveryIssueRecord) {
    const data = { ...issue, heldLines: json(issue.heldLines) };
    if (issue.version === 1)
      await this.tx.deliveryIssue.create({
        data: { ...data, ...this.context, reportedBy: this.scope.actor.id },
      });
    else
      await this.tx.deliveryIssue.update({
        where: { id: issue.id },
        data: {
          ...data,
          ...(issue.status === "resolved"
            ? { resolvedBy: this.scope.actor.id, resolvedAt: new Date() }
            : {}),
        },
      });
    await this.tx.alert.upsert({
      where: {
        storeId_key: {
          storeId: this.scope.storeId,
          key: `delivery:${issue.deliveryId}`,
        },
      },
      create: {
        ...this.context,
        kind: "delivery_issue",
        key: `delivery:${issue.deliveryId}`,
        message: issue.reason,
        active: issue.status !== "resolved",
      },
      update: {
        message: issue.reason,
        active: issue.status !== "resolved",
        resolvedAt: issue.status === "resolved" ? new Date() : null,
      },
    });
  }
  async receipt(
    deliveryId: string,
    lines: unknown,
    differences: unknown,
    operationId: string,
  ) {
    await this.tx.deliveryReceipt.create({
      data: {
        ...this.context,
        deliveryId,
        lines: json(lines),
        differences: json(differences),
        operationId,
        actorId: this.scope.actor.id,
      },
    });
  }
  async checkInventory(id = randomUUID()) {
    if (await this.prior(id, "scheduled")) return;
    const configured = await this.tx.storeProduct.findMany({
      where: this.context,
      select: { productId: true },
    });
    const stocked = await this.tx.inventoryLot.findMany({
      where: this.context,
      select: { productId: true },
      distinct: ["productId"],
    });
    await this.alerts([
      ...new Set([...configured, ...stocked].map((p) => p.productId)),
    ]);
    await this.finish(
      id,
      "scheduled",
      { operationId: id, status: "accepted" },
      "inventory.check",
      this.scope.storeId,
      { scheduled: true },
    );
  }
  async alerts(productIds: string[]) {
    const ids = [...new Set(productIds)];
    if (!ids.length) return;
    const configurations = await this.tx.storeProduct.findMany({
      where: { ...this.context, productId: { in: ids } },
    });
    const inventory = await this.tx.inventoryLot.findMany({
      where: { ...this.context, productId: { in: ids } },
    });
    const existing = await this.tx.alert.findMany({
      where: { ...this.context, productId: { in: ids } },
    });
    const byProduct = new Map(
      configurations.map((config) => [config.productId, config]),
    );
    const oldAlerts = new Map(existing.map((alert) => [alert.key, alert]));
    const lotsByProduct = new Map<string, typeof inventory>();
    for (const lot of inventory) {
      const group = lotsByProduct.get(lot.productId) ?? [];
      group.push(lot);
      lotsByProduct.set(lot.productId, group);
    }
    const today = localDate(new Date(), this.scope.timezone);
    for (const productId of ids) {
      const config = byProduct.get(productId);
      const lots = lotsByProduct.get(productId) ?? [];
      const stock = lots
        .filter((l) => l.expiry.toISOString().slice(0, 10) >= today)
        .reduce((sum, l) => sum + Math.max(0, l.sellable), 0);
      const soon = new Date(`${today}T00:00:00Z`);
      soon.setUTCDate(soon.getUTCDate() + 30);
      const states = [
        [
          "expired",
          lots.some(
            (l) =>
              l.sellable > 0 && l.expiry.toISOString().slice(0, 10) < today,
          ),
          "Lots périmés à isoler",
        ],
        [
          "expiring",
          lots.some(
            (l) =>
              l.sellable > 0 &&
              l.expiry.toISOString().slice(0, 10) >= today &&
              l.expiry <= soon,
          ),
          "Lots arrivant à péremption",
        ],
        ["low", stock > 0 && stock <= (config?.threshold ?? 5), "Stock faible"],
        ["zero", stock === 0, "Rupture de stock"],
        [
          "discrepancy",
          lots.some((l) => l.sellable < 0),
          "Écart de stock à vérifier",
        ],
      ] as const;
      for (const [kind, active, message] of states) {
        const key = `${productId}:${kind}`;
        const old = oldAlerts.get(key);
        if (active && !old?.active) {
          const alert = await this.tx.alert.upsert({
            where: { storeId_key: { storeId: this.scope.storeId, key } },
            create: { ...this.context, productId, key, kind, message },
            update: { active: true, resolvedAt: null, createdAt: new Date() },
          });
          await this.notify(
            `${alert.id}:${alert.createdAt.toISOString()}`,
            message,
            "Consultez le stock du magasin.",
            { type: "alert", id: alert.id },
          );
        }
        if (!active && old?.active)
          await this.tx.alert.update({
            where: { id: old.id },
            data: { active: false, resolvedAt: new Date() },
          });
      }
    }
  }
  async notify(
    key: string,
    title: string,
    body: string,
    target?: { type: string; id: string },
  ) {
    const members = await this.tx.membership.findMany({
      where: {
        ...this.context,
        active: true,
        permissions: { has: "manage" },
      },
    });
    const owners = await this.tx.organizationMembership.findMany({
      where: { organizationId: this.scope.organizationId, active: true },
    });
    const admins = await this.tx.user.findMany({
      where: { platformAdmin: true, disabled: false },
      select: { id: true },
    });
    const users = new Set([
      ...members.map((m) => m.userId),
      ...owners.map((m) => m.userId),
      ...admins.map((u) => u.id),
    ]);
    const enabled = await this.tx.user.findMany({
      where: { id: { in: [...users] }, disabled: false },
      select: { id: true },
    });
    for (const { id: userId } of enabled) {
      await this.tx.notification.upsert({
        where: { userId_eventKey: { userId, eventKey: key } },
        create: {
          ...this.context,
          userId,
          eventKey: key,
          title,
          body,
          targetType: target?.type,
          targetId: target?.id,
        },
        update: {},
      });
    }
  }
}

export function lotIdentity(
  store: string,
  product: string,
  batch: string,
  expiry: string,
): string {
  const namespace = Buffer.from("40cdd460fdea4c8f953351a0843ecfff", "hex");
  const hash = createHash("sha1")
    .update(namespace)
    .update(`${store}|${product}|${batch}|${expiry}`)
    .digest();
  hash[6] = (hash[6]! & 15) | 80;
  hash[8] = (hash[8]! & 63) | 128;
  const h = hash.subarray(0, 16).toString("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
