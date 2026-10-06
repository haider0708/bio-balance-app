import { Controller, Get, Module } from "@nestjs/common";
import { CoreModule } from "./core/core.module";
import { Database } from "./core/database";
import { Public } from "./core/http";
import { CatalogModule } from "./modules/catalog/catalog.module";
import { DirectoryModule } from "./modules/directory/directory.module";
import { MediaModule } from "./modules/media/media.module";
import { MessagingModule } from "./modules/messaging/messaging.module";
import { ReportingModule } from "./modules/reporting/reporting.module";
import { RestockModule } from "./modules/restock/restock.module";
import { RewardsModule } from "./modules/rewards/rewards.module";
import { SalesModule } from "./modules/sales/sales.module";
import { TrainingModule } from "./modules/training/training.module";
import { StockModule } from "./modules/stock/stock.module";
import { CodePageController } from "./modules/auth/code-page.controller";

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
    TrainingModule,
    ReportingModule,
  ],
  controllers: [HealthController, CodePageController],
})
export class AppModule {}
