import { csvCell } from "../../shared/domain/csv";
import { Injectable } from "@nestjs/common";
import { Actor } from "../operations/domain/contracts";
import { WorkspaceService } from "../tenancy/workspace.service";
import { Database } from "../../shared/infrastructure/database";
@Injectable()
export class ReportingService {
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
  ) {}
  async overview(actor: Actor) {
    return this.db.authenticated(
      actor,
      async (tx, current) => {
        const stores = await this.workspace.storesInTransaction(tx, current);
        return {
          stores,
          totalStores: stores.length,
          organizations: await tx.organization.count(),
          staff: await tx.user.count({ where: { disabled: false } }),
        };
      },
      true,
    );
  }
  async salesCsv(
    actor: Actor,
    organizationId: string,
    storeId: string,
    after?: string,
  ) {
    const rows = await this.workspace.list(
      actor,
      organizationId,
      storeId,
      "sales",
      after,
    );
    const lines = rows.map((row) => {
      const sale = row as {
        id: string;
        occurredAt: Date;
        sellerId: string;
        totalMillimes: bigint;
        earnedPoints: bigint;
      };
      return [
        sale.id,
        sale.occurredAt.toISOString(),
        sale.sellerId,
        sale.totalMillimes,
        sale.earnedPoints,
      ]
        .map(csvCell)
        .join(";");
    });
    return (
      "\uFEFFIdentifiant;Date;Vendeur;Total en millimes;Points\n" +
      lines.join("\n")
    );
  }
}
