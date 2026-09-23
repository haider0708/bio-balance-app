import { PasswordHasher } from "./modules/identity/password-hasher";
import { ReportingService } from "./modules/reporting/reporting.service";
import { AdminService } from "./modules/reporting/admin.service";
import { AdminController } from "./modules/reporting/admin.controller";
import { Module, Controller, Get } from "@nestjs/common";
import { ExportController } from "./modules/reporting/export.controller";
import { ExportService } from "./modules/reporting/export.service";
import { GroupService } from "./modules/tenancy/group.service";
import { GroupController } from "./modules/tenancy/group.controller";
import { DashboardController } from "./modules/reporting/dashboard.controller";
import { DashboardService } from "./modules/reporting/dashboard.service";
import { APP_GUARD, APP_FILTER } from "@nestjs/core";
import { Database } from "./shared/infrastructure/database";
import { AuthGuard, ErrorFilter, Public } from "./shared/infrastructure/http";
import { IdentityService } from "./modules/identity/identity.service";
import { IdentityController } from "./modules/identity/identity.controller";
import { WorkspaceService } from "./modules/tenancy/workspace.service";
import { WorkspaceController } from "./modules/tenancy/workspace.controller";
import { CatalogService } from "./modules/catalog/catalog.service";
import { CatalogController } from "./modules/catalog/catalog.controller";
import { OperationsService } from "./modules/operations/application/operations.service";
import { PrismaUnitOfWork } from "./modules/operations/infrastructure/prisma-ledger";
import { OperationsController } from "./modules/operations/http/operations.controller";
import { NotificationsService } from "./modules/notifications/notifications.service";
import { NotificationsController } from "./modules/notifications/notifications.controller";
import { TrainingService } from "./modules/training/training.service";
import { TrainingController } from "./modules/training/training.controller";
import { ReportingController } from "./modules/reporting/reporting.controller";
@Controller("health")
class HealthController {
  constructor(private readonly db: Database) {}
  @Public() @Get() async health() {
    await this.db.$queryRaw`SELECT 1`;
    return { status: "ok" };
  }
}
@Module({
  controllers: [
    ExportController,
    DashboardController,
    GroupController,
    AdminController,
    HealthController,
    IdentityController,
    WorkspaceController,
    CatalogController,
    OperationsController,
    NotificationsController,
    TrainingController,
    ReportingController,
  ],
  providers: [
    ExportService,
    DashboardService,
    GroupService,
    ReportingService,
    AdminService,
    Database,
    { provide: PasswordHasher, useFactory: () => new PasswordHasher() },
    IdentityService,
    WorkspaceService,
    CatalogService,
    NotificationsService,
    TrainingService,
    {
      provide: OperationsService,
      useFactory: (db: Database) =>
        new OperationsService(new PrismaUnitOfWork(db)),
      inject: [Database],
    },
    { provide: APP_GUARD, useClass: AuthGuard },
    { provide: APP_FILTER, useClass: ErrorFilter },
  ],
})
export class AppModule {}
