import { Controller, Get, Module } from "@nestjs/common";
import { CoreModule } from "./core/core.module";
import { Database } from "./core/database";
import { Public } from "./core/http";
import { CatalogModule } from "./modules/catalog/catalog.module";
import { DirectoryModule } from "./modules/directory/directory.module";
import { MediaModule } from "./modules/media/media.module";
import { RestockModule } from "./modules/restock/restock.module";
import { RewardsModule } from "./modules/rewards/rewards.module";
import { SalesModule } from "./modules/sales/sales.module";
import { StockModule } from "./modules/stock/stock.module";

@Controller("health")
class HealthController {
  constructor(private readonly db: Database) {}
  @Public() @Get() async health() {
    await this.db.$queryRaw`SELECT 1`;
    return { status: "ok" };
  }
}

@Module({
  imports: [CoreModule, DirectoryModule, CatalogModule, MediaModule, StockModule, RestockModule, RewardsModule, SalesModule],
  controllers: [HealthController],
})
export class AppModule {}
