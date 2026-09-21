import { Body, Controller, Post, Req } from "@nestjs/common";
import { ApiTags, ApiBearerAuth } from "@nestjs/swagger";
import { AuthRequest } from "../../../shared/infrastructure/http";
import { syncBatchSchema } from "../domain/contracts";
import { OperationsService } from "../application/operations.service";
@ApiTags("synchronization")
@ApiBearerAuth()
@Controller("v1/sync")
export class OperationsController {
  constructor(private readonly service: OperationsService) {}
  @Post("status") async status(@Req() req: AuthRequest, @Body() body: unknown) {
    const batch = syncBatchSchema.parse(body);
    const results = [];
    for (const operation of batch.operations) results.push(await this.service.status(req.actor, operation));
    return { results };
  }
  @Post("push") async push(@Req() req: AuthRequest, @Body() body: unknown) {
    const batch = syncBatchSchema.parse(body);
    const results = [];
    for (const operation of batch.operations)
      results.push(await this.service.submit(req.actor, operation));
    return { results };
  }
}
