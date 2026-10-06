import { Module } from "@nestjs/common";
import { RewardsController } from "./rewards.controller";
import { RewardsService } from "./rewards.service";
import { WalletService } from "./wallet.service";

@Module({ controllers: [RewardsController], providers: [RewardsService, WalletService], exports: [WalletService] })
export class RewardsModule {}
