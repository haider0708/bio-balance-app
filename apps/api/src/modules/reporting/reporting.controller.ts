import { Controller, Get, Query, Param, Req, Res } from "@nestjs/common";
import { ApiTags, ApiBearerAuth } from "@nestjs/swagger";
import { Response } from "express";
import { z } from "zod";
import { AuthRequest } from "../../shared/infrastructure/http";
import { WorkspaceService } from "../tenancy/workspace.service";
import { Database } from "../../shared/infrastructure/database";
import { requireRule } from "../../shared/domain/errors";
@ApiTags("reporting")
@ApiBearerAuth()
@Controller("v1/reports")
export class ReportingController {
  constructor(
    private readonly db: Database,
    private readonly workspace: WorkspaceService,
  ) {}
  @Get("overview") async overview(@Req() r: AuthRequest) {
    requireRule(
      r.actor.platformAdmin,
      "FORBIDDEN",
      "Accès réservé à BioBalance.",
      403,
    );
    const stores = await this.workspace.stores(r.actor);
    return {
      stores,
      totalStores: stores.length,
      organizations: await this.db.organization.count(),
      staff: await this.db.user.count({ where: { disabled: false } }),
    };
  }
  @Get("stores/:store/sales.csv") async export(
    @Req() r: AuthRequest,
    @Param("store") store: string,
    @Query("organizationId") org: string,
    @Query("after") after: string | undefined,
    @Res() res: Response,
  ) {
    const rows = await this.workspace.list(
      r.actor,
      z.uuid().parse(org),
      z.uuid().parse(store),
      "sales",
      z.uuid().optional().parse(after),
    );
    const safe = (v: unknown) =>
      `"${String(v ?? "")
        .replace(/^[=+@-]/, "'$&")
        .replace(/"/g, '""')}"`;
    const lines = rows.map((row) => {
      const x = row as unknown as Record<string, unknown>;
      return [x.id, x.occurredAt, x.sellerId, x.totalMillimes, x.earnedPoints]
        .map(safe)
        .join(";");
    });
    res.setHeader("Content-Disposition", 'attachment; filename="ventes.csv"');
    res
      .type("text/csv; charset=utf-8")
      .send(
        "\uFEFFIdentifiant;Date;Vendeur;Total en millimes;Points\n" +
          lines.join("\n"),
      );
  }
}
