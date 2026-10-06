import { Global, Module } from "@nestjs/common";
import { APP_FILTER, APP_GUARD } from "@nestjs/core";
import { AuthController } from "../modules/auth/auth.controller";
import { AuthService } from "../modules/auth/auth.service";
import { PasswordHasher } from "../modules/auth/password-hasher";
import { Database } from "./database";
import { AuthGuard, ErrorFilter } from "./http";

/** Database, sign-in and the global guard: available everywhere without importing. */
@Global()
@Module({
  controllers: [AuthController],
  providers: [
    Database,
    { provide: PasswordHasher, useFactory: () => new PasswordHasher() },
    AuthService,
    { provide: APP_GUARD, useClass: AuthGuard },
    { provide: APP_FILTER, useClass: ErrorFilter },
  ],
  exports: [Database, AuthService],
})
export class CoreModule {}
