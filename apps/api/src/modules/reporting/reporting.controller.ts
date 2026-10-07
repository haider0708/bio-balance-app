import { Controller, Get, Query, Req, Res } from "@nestjs/common";
import type { Response } from "express";
import { z } from "zod";
import { type AuthRequest, Roles, parse } from "../../core/http";
import { PageQuery } from "../../core/pagination";
import { ApprovalsService } from "./approvals.service";
import { DashboardService } from "./dashboard.service";
import { ReportsService } from "./reports.service";

const id = z.uuid();
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const Period = z
  .object({ from: day, to: day })
  .refine((p) => p.from <= p.to, "from must not be after to");

@Controller("v1")
export class ReportingController {
  constructor(
    private readonly dashboard: DashboardService,
    private readonly approvals: ApprovalsService,
    private readonly reports: ReportsService,
  ) {}

  @Get("dashboard")
  dash(@Req() r: AuthRequest, @Query("regionId") region?: string) {
    return this.dashboard.forActor(r.actor, {
      regionId: parse(id.optional(), region),
    });
  }

  @Roles("ADMIN")
  @Get("approvals")
  inbox(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.approvals.inbox(
      r.actor,
      parse(
        z.object({
          regionId: id.optional(),
          type: z
            .enum([
              "GROUP",
              "PDV",
              "MEMBER",
              "STOCK",
              "RECEIPT",
              "PAYOUT",
              "RESTOCK_REQUEST",
              "RECOUNT",
            ])
            .optional(),
        }),
        q,
      ),
    );
  }

  @Roles("ADMIN", "RESPONSABLE")
  @Get("reports/sales")
  sales(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    const v = parse(
      z
        .object({
          groupBy: z
            .enum(["day", "region", "pdv", "seller", "product", "family"])
            .default("day"),
          regionId: id.optional(),
          pdvId: id.optional(),
          sellerId: id.optional(),
          productId: id.optional(),
          family: z.string().max(80).optional(),
        })
        .and(Period),
      q,
    );
    return this.reports.sales(r.actor, v);
  }

  @Roles("ADMIN", "RESPONSABLE")
  @Get("reports/sales.csv")
  async salesCsv(
    @Req() r: AuthRequest,
    @Query() q: Record<string, string>,
    @Res() res: Response,
  ) {
    const v = parse(
      z.object({ regionId: id.optional(), pdvId: id.optional() }).and(Period),
      q,
    );
    const csv = await this.reports.salesCsv(r.actor, v);
    res.setHeader(
      "Content-Disposition",
      `attachment; filename="sales-${v.from}-${v.to}.csv"`,
    );
    res.type("text/csv; charset=utf-8").send(csv);
  }

  @Roles("ADMIN", "RESPONSABLE")
  @Get("reports/stock")
  stock(@Req() r: AuthRequest, @Query("regionId") region?: string) {
    return this.reports.stock(r.actor, {
      regionId: parse(id.optional(), region),
    });
  }

  @Roles("ADMIN", "RESPONSABLE")
  @Get("reports/stock/attention")
  attention(@Req() r: AuthRequest, @Query("regionId") region?: string) {
    return this.reports.stockAttention(r.actor, {
      regionId: parse(id.optional(), region),
    });
  }

  @Roles("ADMIN")
  @Get("audit")
  audit(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.reports.audit(
      r.actor,
      parse(
        PageQuery.extend({
          entity: z.string().max(40).optional(),
          entityId: id.optional(),
          actorId: id.optional(),
          regionId: id.optional(),
        }),
        q,
      ),
    );
  }
}
