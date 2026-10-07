import type { LocationKind } from "@prisma/client";
import type { Tx } from "../../core/database";
import { notFound, requireRule } from "../../core/errors";

export interface Location {
  id: string;
  kind: LocationKind;
  /** Null for depots. */
  regionId: string | null;
  /** The region that owns the stock rows: a depot's is its grossiste's region. */
  stockRegionId: string | null;
  name: string;
  status: string;
}

/** Find a point of sale or a depot by id (row-level security hides what the caller may not see). */
export async function findLocation(tx: Tx, id: string): Promise<Location> {
  const pdv = await tx.pdv.findUnique({ where: { id } });
  if (pdv)
    return {
      id,
      kind: "PDV",
      regionId: pdv.regionId,
      stockRegionId: pdv.regionId,
      name: pdv.name,
      status: pdv.status,
    };
  const depot = await tx.depot.findUnique({ where: { id } });
  if (depot)
    return {
      id,
      kind: "DEPOT",
      regionId: null,
      stockRegionId: depot.regionId,
      name: depot.name,
      status: depot.status,
    };
  throw notFound("Location");
}

export interface MovementRef {
  reason:
    | "DECLARATION"
    | "RECEIPT"
    | "SHIPMENT"
    | "SALE"
    | "SALE_CORRECTION"
    | "ADJUSTMENT";
  refType: string;
  refId: string;
  actorId: string | null;
}

/**
 * Add `delta` to a product's quantity and record why. One atomic statement,
 * so two phones selling the same product at once never lose an update.
 * A sale can never take a point of sale below zero: the whole transaction
 * is refused, so two phones selling the last unit cannot both succeed.
 */
export async function adjustStock(
  tx: Tx,
  location: Pick<Location, "id" | "kind" | "regionId"> & {
    stockRegionId?: string | null;
  },
  productId: string,
  delta: number,
  ref: MovementRef,
): Promise<number> {
  if (delta === 0) return currentQuantity(tx, location.id, productId);
  const stockRegion = location.stockRegionId ?? location.regionId;
  const [row] = await tx.$queryRaw<{ quantity: number }[]>`
    INSERT INTO "Stock" ("locationId","productId","locationKind","regionId",quantity,"updatedAt")
    VALUES (${location.id}::uuid, ${productId}::uuid, ${location.kind}::"LocationKind", ${stockRegion}::uuid, ${delta}, now())
    ON CONFLICT ("locationId","productId") DO UPDATE
      SET quantity = "Stock".quantity + ${delta}, "updatedAt" = now()
    RETURNING quantity`;
  requireRule(
    row!.quantity >= 0 || delta > 0 || !ref.reason.startsWith("SALE"),
    "OUT_OF_STOCK",
    "Not enough stock for this sale.",
    409,
  );
  await tx.stockMovement.createMany({
    data: [
      {
        locationId: location.id,
        productId,
        locationKind: location.kind,
        regionId: stockRegion,
        delta,
        reason: ref.reason,
        refType: ref.refType,
        refId: ref.refId,
        actorId: ref.actorId,
      },
    ],
  });
  return row!.quantity;
}

export async function currentQuantity(
  tx: Tx,
  locationId: string,
  productId: string,
) {
  const row = await tx.stock.findUnique({
    where: { locationId_productId: { locationId, productId } },
    select: { quantity: true },
  });
  return row?.quantity ?? 0;
}

/** Make the quantity exactly `target`, recording the difference. */
export async function setStock(
  tx: Tx,
  location: Pick<Location, "id" | "kind" | "regionId"> & {
    stockRegionId?: string | null;
  },
  productId: string,
  target: number,
  ref: MovementRef,
) {
  // Lock the row (if any) so the difference we compute is the difference we apply.
  await tx.$queryRaw`SELECT 1 FROM "Stock" WHERE "locationId"=${location.id}::uuid AND "productId"=${productId}::uuid FOR UPDATE`;
  const before = await currentQuantity(tx, location.id, productId);
  await adjustStock(tx, location, productId, target - before, ref);
}
