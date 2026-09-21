import { Money, unitQuantity, localDate } from "../../../shared/domain/money";
import { requireRule } from "../../../shared/domain/errors";
import { AcceptedLine, LineInput, Lot, SaleRecord } from "./contracts";
export class Sale {
  constructor(readonly record: SaleRecord) {}
  static accept(
    id: string,
    sellerId: string,
    occurredAt: Date,
    inputs: LineInput[],
    rates: Map<string, number>,
    lots: Map<string, Lot>,
    timezone: string,
    previous?: SaleRecord,
    now = new Date(),
  ): Sale {
    requireRule(
      Number.isFinite(occurredAt.getTime()) &&
        occurredAt.getTime() <= now.getTime() + 300_000,
      "INVALID_SALE_DATE",
      "La date de vente est invalide.",
    );
    requireRule(
      !previous || previous.occurredAt.getTime() === occurredAt.getTime(),
      "SALE_DATE_IMMUTABLE",
      "La date de la vente d’origine doit être conservée.",
    );
    requireRule(
      new Set(inputs.map((l) => l.id)).size === inputs.length,
      "DUPLICATE_LINE",
      "Ligne de vente répétée.",
    );
    const lines: AcceptedLine[] = inputs.map((line) => {
      unitQuantity(line.quantity);
      requireRule(
        new Set(line.allocations.map((a) => a.lotId)).size ===
          line.allocations.length,
        "DUPLICATE_LOT",
        "Regroupez les quantités du même lot.",
      );
      requireRule(
        line.allocations.reduce(
          (sum, a) => sum + unitQuantity(a.quantity),
          0,
        ) === line.quantity,
        "ALLOCATION_MISMATCH",
        "Les quantités par lot doivent correspondre à la ligne.",
      );
      for (const allocation of line.allocations) {
        const lot = lots.get(allocation.lotId);
        requireRule(
          lot && lot.productId === line.productId,
          "LOT_MISMATCH",
          "Le lot ne correspond pas au produit.",
        );
        requireRule(
          lot.expiry.toISOString().slice(0, 10) >=
            localDate(occurredAt, timezone),
          "LOT_EXPIRED",
          "Le lot était périmé à la date de vente.",
        );
      }
      const accepted = previous?.lines.find((old) => old.id === line.id);
      requireRule(
        !accepted || accepted.productId === line.productId,
        "LINE_PRODUCT_CHANGED",
        "Ajoutez une nouvelle ligne pour changer de produit.",
      );
      return {
        ...line,
        pointsPerUnit:
          accepted?.pointsPerUnit ?? previous?.lines.find(old=>old.productId===line.productId)?.pointsPerUnit ?? rates.get(line.productId) ?? 0,
      };
    });
    const returned = previous?.returned ?? {};
    for (const [key, quantity] of Object.entries(returned)) {
      const [lineId, lotId] = key.split(":");
      const line = lines.find((l) => l.id === lineId);
      requireRule(
        line &&
          (line.allocations.find((a) => a.lotId === lotId)?.quantity ?? 0) >=
            quantity,
        "ALREADY_RETURNED",
        "La correction ne peut pas supprimer des unités déjà retournées.",
      );
    }
    const total = lines.reduce(
      (sum, line) =>
        sum.add(Money.from(line.unitPriceMillimes).multiply(line.quantity)),
      Money.from("0"),
    );
    const points = lines.reduce(
      (sum, line) => sum + BigInt(line.pointsPerUnit) * BigInt(line.quantity),
      0n,
    );
    return new Sale({
      id,
      sellerId,
      occurredAt,
      version: (previous?.version ?? 0) + 1,
      lines,
      returned,
      totalMillimes: total.millimes,
      earnedPoints: points,
    });
  }
  stockDelta(previous?: SaleRecord): Map<string, number> {
    const delta = new Map<string, number>();
    for (const l of previous?.lines ?? [])
      for (const a of l.allocations)
        delta.set(a.lotId, (delta.get(a.lotId) ?? 0) + a.quantity);
    for (const l of this.record.lines)
      for (const a of l.allocations)
        delta.set(a.lotId, (delta.get(a.lotId) ?? 0) - a.quantity);
    return delta;
  }
  returnItems(
    items: {
      lineId: string;
      lotId: string;
      quantity: number;
      sellable: boolean;
    }[],
  ): { returned: Record<string, number>; points: bigint } {
    const returned = { ...this.record.returned };
    let points = 0n;
    for (const item of items) {
      unitQuantity(item.quantity);
      const line = this.record.lines.find((l) => l.id === item.lineId);
      const allocation = line?.allocations.find((a) => a.lotId === item.lotId);
      const key = `${item.lineId}:${item.lotId}`;
      requireRule(
        line &&
          allocation &&
          item.quantity + (returned[key] ?? 0) <= allocation.quantity,
        "RETURN_EXCEEDS_SALE",
        "Quantité supérieure aux unités encore retournables.",
      );
      returned[key] = (returned[key] ?? 0) + item.quantity;
      points -= BigInt(item.quantity) * BigInt(line.pointsPerUnit);
    }
    return { returned, points };
  }
}
