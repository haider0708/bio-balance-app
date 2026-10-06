import { Module } from "@nestjs/common";
import { DirectoryController } from "./directory.controller";
import { StructureService } from "./structure.service";
import { UsersService } from "./users.service";

@Module({
  controllers: [DirectoryController],
  providers: [StructureService, UsersService],
  exports: [StructureService, UsersService],
})
export class DirectoryModule {}
