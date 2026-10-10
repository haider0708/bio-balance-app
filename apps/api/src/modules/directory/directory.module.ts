import { Module } from "@nestjs/common";
import { DirectoryController } from "./directory.controller";
import { DepotsService } from "./depots.service";
import { RegionsService } from "./regions.service";
import { StructureService } from "./structure.service";
import { UsersService } from "./users.service";

@Module({
  controllers: [DirectoryController],
  providers: [StructureService, UsersService, DepotsService, RegionsService],
  exports: [StructureService, UsersService, DepotsService, RegionsService],
})
export class DirectoryModule {}
