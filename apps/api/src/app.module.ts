import { Controller, Get, Module } from "@nestjs/common";
import { CoreModule } from "./core/core.module";
import { Database } from "./core/database";
import { Public } from "./core/http";
import { CatalogModule } from "./modules/catalog/catalog.module";
import { DirectoryModule } from "./modules/directory/directory.module";
import { MediaModule } from "./modules/media/media.module";
import { OrdersModule } from "./modules/orders/orders.module";
import { PlanningModule } from "./modules/planning/planning.module";
import { ReturnsModule } from "./modules/returns/returns.module";
import { TransfersModule } from "./modules/transfers/transfers.module";
import { DiagnosticsModule } from "./modules/diagnostics/diagnostics.module";
import { MessagingModule } from "./modules/messaging/messaging.module";
import { ReportingModule } from "./modules/reporting/reporting.module";
import { RestockModule } from "./modules/restock/restock.module";
import { RewardsModule } from "./modules/rewards/rewards.module";
import { SalesModule } from "./modules/sales/sales.module";
import { TrainingModule } from "./modules/training/training.module";
import { StockModule } from "./modules/stock/stock.module";
import { CodePageController } from "./modules/auth/code-page.controller";
import { InstallPageController } from "./modules/auth/install-page.controller";
import { CalendarController } from "./modules/planning/calendar.controller";
import { SetupLinkController } from "./modules/auth/setup-link.controller";
import { AppConfigController } from "./modules/legal/app-config.controller";
import { LegalController } from "./modules/legal/legal.controller";

@Controller("health")
class HealthController {
  constructor(private readonly db: Database) {}
  @Public() @Get() async health() {
    await this.db.$queryRaw`SELECT 1`;
    return { status: "ok" };
  }
}

@Module({
  imports: [
    CoreModule,
    DirectoryModule,
    CatalogModule,
    MediaModule,
    StockModule,
    RestockModule,
    RewardsModule,
    SalesModule,
    MessagingModule,
    DiagnosticsModule,
    TrainingModule,
    ReportingModule,
    PlanningModule,
    TransfersModule,
    ReturnsModule,
    OrdersModule,
  ],
  controllers: [
    HealthController,
    CodePageController,
    InstallPageController,
    SetupLinkController,
    CalendarController,
    LegalController,
    AppConfigController,
  ],
})
export class AppModule {}
