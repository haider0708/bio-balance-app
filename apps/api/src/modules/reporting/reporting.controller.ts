import { Controller, Get, Query, Req, Res } from "@nestjs/common";
import type { Response } from "express";
import { z } from "zod";
import { type AuthRequest, Roles, parse } from "../../core/http";
import { PageQuery } from "../../core/pagination";
import { AnalyticsService } from "./analytics.service";
import { ApprovalsService } from "./approvals.service";
import { DashboardService } from "./dashboard.service";
import { InsightsService } from "./insights.service";
import { ReportsService } from "./reports.service";

const id = z.uuid();
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const Period = z
  .object({ from: day, to: day })
  .refine((p) => p.from <= p.to, "from must not be after to")
  .refine(
    (p) => Date.parse(p.to) - Date.parse(p.from) <= 400 * 86400_000,
    "A report covers at most 400 days",
  );
/** Any narrowing of the sales: the same filters for the analytics, the ledger and the spreadsheet. */
const LensFilters = z.object({
  regionId: id.optional(),
  groupId: id.optional(),
  pdvId: id.optional(),
  sellerId: id.optional(),
  productId: id.optional(),
  family: z.string().trim().min(1).max(80).optional(),
});

@Controller("v1")
export class ReportingController {
  constructor(
    private readonly dashboard: DashboardService,
    private readonly approvals: ApprovalsService,
    private readonly reports: ReportsService,
    private readonly insights: InsightsService,
    private readonly analytics: AnalyticsService,
  ) {}

  @Roles("ADMIN", "RESPONSABLE")
  @Get("analytics/overview")
  analyticsOverview(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.analytics.overview(
      r.actor,
      parse(
        LensFilters.extend({
          sort: z.enum(["units", "sales", "reward"]).default("units"),
        }).and(Period),
        q,
      ),
    );
  }

  @Roles("ADMIN", "RESPONSABLE")
  @Get("analytics/stores")
  analyticsStores(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.analytics.stores(
      r.actor,
      parse(
        z
          .object({ regionId: id.optional(), groupId: id.optional() })
          .and(Period),
        q,
      ),
    );
  }

  @Get("dashboard")
  dash(@Req() r: AuthRequest, @Query("regionId") region?: string) {
    return this.dashboard.forActor(r.actor, {
      regionId: parse(id.optional(), region),
    });
  }

  @Roles("ADMIN")
  @Get("approvals/history")
  history(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    const v = parse(
      z.object({
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
        before: z.coerce.date().optional(),
      }),
      q,
    );
    return this.approvals.history(r.actor, v);
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
  @Get("reports/insights")
  insightsReport(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.insights.report(
      r.actor,
      parse(z.object({ regionId: id.optional() }).and(Period), q),
    );
  }

  @Roles("ADMIN", "RESPONSABLE")
  @Get("reports/sales.csv")
  async salesCsv(
    @Req() r: AuthRequest,
    @Query() q: Record<string, string>,
    @Res() res: Response,
  ) {
    const v = parse(LensFilters.and(Period), q);
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
