import { Database } from "../../../shared/infrastructure/database";
import { NotificationPolicy } from "./notification-policy";

export type PushResult = { success: boolean; errorCode?: string };
export interface PushGateway {
  send(tokens: string[], data: Record<string, string>): Promise<PushResult[]>;
}
export class PushDeliveryService {
  private readonly policy: NotificationPolicy;
  constructor(
    private readonly db: Database,
    private readonly gateway: PushGateway,
  ) {
    this.policy = new NotificationPolicy(db);
  }
  async deliver(
    notificationId: string,
    stillOwned: () => Promise<boolean> = async () => true,
  ) {
    const n = await this.db.notification.findUnique({
      where: { id: notificationId },
    });
    if (!n || !(await this.policy.allows(n))) return;
    let after: string | undefined;
    let failed = false;
    do {
      const devices = await this.db.deviceToken.findMany({
        where: { userId: n.userId, ...(after ? { id: { gt: after } } : {}) },
        orderBy: { id: "asc" },
        take: 100,
      });
      if (!devices.length) break;
      after = devices[devices.length - 1]!.id;
      const eligible = [];
      for (const device of devices) {
        if (!device.sessionId) continue;
        const session = await this.db.session.findFirst({
          where: {
            id: device.sessionId,
            userId: n.userId,
            revokedAt: null,
            expiresAt: { gt: new Date() },
          },
        });
        const sent = await this.db.pushDelivery.findUnique({
          where: {
            notificationId_deviceId_sessionId: {
              notificationId: n.id,
              deviceId: device.id,
              sessionId: device.sessionId,
            },
          },
        });
        if (session && !sent) eligible.push(device);
      }
      if (!eligible.length) continue;
      if (!(await stillOwned()) || !(await this.policy.allows(n))) return;
      // No business text in OS notifications: an already queued platform message
      // may arrive after logout. The app obtains content via the authorized inbox.
      const results = await this.gateway.send(
        eligible.map((d) => d.token),
        { notificationId: n.id, userId: n.userId, storeId: n.storeId ?? "" },
      );
      for (let i = 0; i < eligible.length; i++) {
        const device = eligible[i]!,
          result = results[i];
        if (result?.success) {
          await this.db.pushDelivery.upsert({
            where: {
              notificationId_deviceId_sessionId: {
                notificationId: n.id,
                deviceId: device.id,
                sessionId: device.sessionId!,
              },
            },
            create: {
              notificationId: n.id,
              deviceId: device.id,
              sessionId: device.sessionId!,
            },
            update: {},
          });
        } else if (
          [
            "messaging/registration-token-not-registered",
            "messaging/invalid-registration-token",
          ].includes(result?.errorCode ?? "")
        ) {
          await this.db.deviceToken.deleteMany({
            where: {
              id: device.id,
              token: device.token,
              sessionId: device.sessionId,
            },
          });
        } else failed = true;
      }
    } while (after);
    if (failed) throw new Error("PUSH_DELIVERY_FAILED");
  }
}
