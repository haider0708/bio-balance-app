import { Notification, Prisma } from "@prisma/client";

/** Re-evaluated at delivery time; the original recipient list is not authority. */
export class NotificationPolicy {
  constructor(private readonly db: Prisma.TransactionClient) {}
  async allows(n: Notification) {
    const user = await this.db.user.findUnique({ where: { id: n.userId } });
    if (!user || user.disabled) return false;
    if (user.platformAdmin) return true;
    if (!n.storeId || !n.organizationId) return false;
    const store = await this.db.store.findFirst({
      where: { id: n.storeId, organizationId: n.organizationId },
    });
    if (!store || store.status !== "active") return false;
    const group = await this.db.organization.findUnique({
      where: { id: n.organizationId },
    });
    if (group?.status !== "active") return false;
    const member = await this.db.membership.findUnique({
      where: { storeId_userId: { storeId: n.storeId, userId: n.userId } },
    });
    const owner = await this.db.organizationMembership.findUnique({
      where: {
        organizationId_userId: {
          organizationId: n.organizationId,
          userId: n.userId,
        },
      },
    });
    if (owner?.active) return true;
    if (!member?.active) return false;
    return n.kind === "operational"
      ? member.permissions.includes("manage")
      : n.audience !== "salespeople" || member.permissions.includes("sell");
  }
}
