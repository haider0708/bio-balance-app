import { Body, Controller, Post, Req } from "@nestjs/common";
import { ApiTags, ApiBearerAuth } from "@nestjs/swagger";
import { AuthRequest } from "../../../shared/infrastructure/http";
import { z } from "zod";
import { operationSchema } from "../domain/contracts";
import { OperationsService } from "../application/operations.service";
const batchEnvelope = z
  .object({ operations: z.array(z.unknown()).min(1).max(50) })
  .strict();
/** An operation this server no longer understands (a command removed since the
 * phone queued it) is rejected on its own; it never blocks the valid ones. */
function rejected(raw: unknown) {
  const id = z.object({ operationId: z.uuid() }).safeParse(raw);
  return id.success
    ? {
        operationId: id.data.operationId,
        status: "rejected" as const,
        code: "UNSUPPORTED_OPERATION",
        message:
          "Cette opération n’est plus acceptée par cette version. Reprenez-la depuis l’application à jour.",
      }
    : null;
}
@ApiTags("synchronization")
@ApiBearerAuth()
@Controller("v1/sync")
export class OperationsController {
  constructor(private readonly service: OperationsService) {}
  @Post("status") async status(@Req() req: AuthRequest, @Body() body: unknown) {
    const batch = batchEnvelope.parse(body);
    const results = [];
    for (const raw of batch.operations) {
      const operation = operationSchema.safeParse(raw);
      if (operation.success)
        results.push(await this.service.status(req.actor, operation.data));
      else
        results.push(
          rejected(raw) ??
            (() => {
              throw operation.error;
            })(),
        );
    }
    return { results };
  }
  @Post("push") async push(@Req() req: AuthRequest, @Body() body: unknown) {
    const batch = batchEnvelope.parse(body);
    const results = [];
    for (const raw of batch.operations) {
      const operation = operationSchema.safeParse(raw);
      if (operation.success)
        results.push(await this.service.submit(req.actor, operation.data));
      else
        results.push(
          rejected(raw) ??
            (() => {
              throw operation.error;
            })(),
        );
    }
    return { results };
  }
}
