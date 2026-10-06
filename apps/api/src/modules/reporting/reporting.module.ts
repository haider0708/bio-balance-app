import { Module } from "@nestjs/common";
import { ApprovalsService } from "./approvals.service";
import { DashboardService } from "./dashboard.service";
import { ReportingController } from "./reporting.controller";
import { ReportsService } from "./reports.service";

@Module({
  controllers: [ReportingController],
  providers: [ApprovalsService, DashboardService, ReportsService],
})
export class ReportingModule {}
