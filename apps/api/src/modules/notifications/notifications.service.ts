import { Injectable } from "@nestjs/common";
import { Database } from "../../shared/infrastructure/database";
import { WorkspaceService } from "../tenancy/workspace.service";
import { Actor } from "../operations/domain/contracts";
@Injectable()
export class NotificationsService {
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
  ) {}
  async list(actor: Actor, after?: string) {
    const stores = await this.workspace.stores(actor);
    return this.db.notification.findMany({
      where: {
        userId: actor.id,
        OR: [{storeId:null},{storeId:{in:stores.map(s=>s.id)}}],
        ...(after ? { createdAt: { lt: new Date(after) } } : {}),
      },
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: 100,
    });
  }
  read(actor: Actor, id: string) {
    return this.db.notification.updateMany({
      where: { id, userId: actor.id },
      data: { readAt: new Date() },
    });
  }
  removeDevice(actor:Actor,token:string){
    return this.db.deviceToken.deleteMany({where:{userId:actor.id,token}});
  }
  device(actor: Actor, token: string, platform: string) {
    return this.db.deviceToken.upsert({
      where: { token },
      create: { userId: actor.id, token, platform, sessionId:actor.sessionId },
      update: { userId: actor.id, platform, sessionId:actor.sessionId },
    });
  }
  announce(
    actor: Actor,
    organizationId: string,
    storeId: string,
    title: string,
    body: string,
    audience: "all" | "salespeople",
  ) {
    return this.workspace.mutate(
      actor,
      organizationId,
      storeId,
      "announcement.send",
      storeId,
      async (tx) => {
        const announcement = await tx.announcement.create({
          data: {
            organizationId,
            storeId,
            authorId: actor.id,
            title,
            body,
            audience,
          },
        });
        const members = await tx.membership.findMany({
          where: {
            storeId,
            active: true,
            ...(audience === "salespeople"
              ? { permissions: { has: "sell" } }
              : {}),
          },
        });
        for (const userId of new Set(members.map((m) => m.userId))) {
          const notification = await tx.notification.create({
            data: {
              organizationId,
              storeId,
              userId,
              title,
              body,
              eventKey: announcement.id,
            },
          });
          await tx.job.create({
            data: {
              kind: "push",
              key: `push:${notification.id}`,
              payload: { notificationId: notification.id, userId },
            },
          });
        }
        return { id: announcement.id, recipients: members.length };
      },
    );
  }
}
