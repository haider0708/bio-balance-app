import { Prisma } from "@prisma/client";
import { randomUUID } from "node:crypto";
import { Scope } from "../../operations/domain/contracts";
import { json } from "../../../shared/infrastructure/database";

/** Pages belong to one transaction snapshot, actor, and exact permission set. */
export class SnapshotPages {
  constructor(
    private readonly tx: Prisma.TransactionClient,
    private readonly scope: Scope,
    private readonly cursor: string,
    private readonly expiresAt: Date,
  ) {}

  async materialize(
    resource: string,
    after: string | undefined,
    load: (after: string) => Promise<{ id: string }[]>,
  ): Promise<string | null> {
    let first: string | null = null,
      previous: string | null = null;
    while (after) {
      const items = await load(after),
        id = randomUUID();
      await this.tx.syncSnapshotPage.create({
        data: {
          id,
          organizationId: this.scope.organizationId,
          storeId: this.scope.storeId,
          actorId: this.scope.actor.id,
          permissions: JSON.stringify([...this.scope.permissions].sort()),
          expiresAt: this.expiresAt,
          payload: json({
            resource,
            items,
            nextPage: null,
            cursor: this.cursor,
          }),
        },
      });
      if (previous) {
        const prior = await this.tx.syncSnapshotPage.findUniqueOrThrow({
          where: { id: previous },
        });
        await this.tx.syncSnapshotPage.update({
          where: { id: previous },
          data: {
            payload: json({ ...(prior.payload as object), nextPage: id }),
          },
        });
      } else first = id;
      previous = id;
      after = items.length === 200 ? items.at(-1)?.id : undefined;
    }
    return first;
  }
}
