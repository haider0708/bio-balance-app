import { Module } from "@nestjs/common";
import { AnalyticsService } from "./analytics.service";
import { ApprovalsService } from "./approvals.service";
import { DashboardService } from "./dashboard.service";
import { ReportingController } from "./reporting.controller";
import { InsightsService } from "./insights.service";
import { ReportsService } from "./reports.service";

@Module({
  controllers: [ReportingController],
  providers: [
    AnalyticsService,
    ApprovalsService,
    DashboardService,
    InsightsService,
    ReportsService,
  ],
})
export class ReportingModule {}
