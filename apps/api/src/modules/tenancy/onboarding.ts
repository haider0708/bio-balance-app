import { Prisma } from "@prisma/client";

export class OnboardingProgress {
  static calculate(
    store: {
      name: string;
      address: string;
      city: string;
      workingAlone: boolean;
      noOpeningStock: boolean;
    },
    activeMembers: number,
    invitations: number,
    hasReceipts: boolean,
    carried: string[],
    configurations: {
      productId: string;
      pointsConfigured: boolean;
      pointsPerUnit: number;
      zeroPointsConfirmed: boolean;
    }[],
  ) {
    const incompleteProducts = carried.filter((id) => {
      const config = configurations.find((c) => c.productId === id);
      return (
        !config?.pointsConfigured ||
        (config.pointsPerUnit === 0 && !config.zeroPointsConfirmed)
      );
    });
    const steps = {
      profile:
        store.name.trim().length >= 2 &&
        store.address.trim().length >= 3 &&
        store.city.trim().length >= 2,
      team: store.workingAlone || activeMembers > 1 || invitations > 0,
      stock: store.noOpeningStock || hasReceipts,
      products:
        incompleteProducts.length === 0 &&
        (carried.length > 0 || store.noOpeningStock),
    };
    return {
      ...steps,
      workingAlone: store.workingAlone,
      noOpeningStock: store.noOpeningStock,
      carriedCount: carried.length,
      incompleteProducts,
      completedCount: Object.values(steps).filter(Boolean).length,
      complete: Object.values(steps).every(Boolean),
    };
  }
}

export async function onboardingProgress(
  tx: Prisma.TransactionClient,
  storeId: string,
) {
  const store = await tx.store.findUniqueOrThrow({ where: { id: storeId } });
  const members = await tx.membership.count({
    where: { storeId, active: true },
  });
  const invitations = await tx.accessToken.count({
    where: {
      storeId,
      purpose: "invite",
      usedAt: null,
      expiresAt: { gt: new Date() },
    },
  });
  const receipt = await tx.stockMovement.findFirst({
    where: {
      storeId,
      reason: { in: ["opening", "receipt", "delivery.receive"] },
    },
  });
  const configurations = await tx.storeProduct.findMany({ where: { storeId } });
  const stocked = await tx.inventoryLot.findMany({
    where: { storeId },
    distinct: ["productId"],
    select: { productId: true },
  });
  const carried = [
    ...new Set([...configurations, ...stocked].map((c) => c.productId)),
  ];
  return OnboardingProgress.calculate(
    store,
    members,
    invitations,
    receipt != null,
    carried,
    configurations,
  );
}
