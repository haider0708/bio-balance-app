import { raw, Request, Response, NextFunction } from "express";
import { z } from "zod";
import { randomUUID } from "node:crypto";
import { IdentityService } from "../../identity/identity.service";
import { TrainingService } from "../training.service";
import { DomainError } from "../../../shared/domain/errors";
import { sendError } from "../../../shared/infrastructure/http";

/** Bound aggregate buffers, and authorize the asset before reading raw bytes. */
export function uploadIngress(
  identity: IdentityService,
  training: TrainingService,
  capacity = 8,
) {
  const parse = raw({ type: "application/octet-stream", limit: "4mb" });
  let active = 0;
  return async (request: Request, response: Response, next: NextFunction) => {
    if (request.method !== "PUT") {
      next();
      return;
    }
    const context = request as Request & { correlationId: string };
    context.correlationId ??= randomUUID();
    if (active >= capacity) {
      sendError(
        new DomainError(
          "UPLOAD_BUSY",
          "Téléversements occupés. Réessayez.",
          429,
          { retryAfterSeconds: 1 },
        ),
        context,
        response,
      );
      return;
    }
    active++;
    let released = false;
    const release = () => {
      if (!released) {
        released = true;
        active--;
      }
    };
    response.once("finish", release);
    response.once("close", release);
    try {
      const id = z.uuid().parse(request.path.replace(/^\//, ""));
      const bearer =
        request.headers.authorization?.replace(/^Bearer /, "") ?? "";
      const actor = await identity.authenticate(bearer);
      await training.uploadStatus(actor, id);
      if (!request.is("application/octet-stream"))
        throw new DomainError(
          "INVALID_CONTENT_TYPE",
          "Format de fragment invalide.",
          415,
        );
      if (!request.aborted && !response.destroyed)
        parse(request, response, (error) => {
          if (error) sendError(error, context, response);
          else next();
        });
    } catch (error) {
      sendError(error, context, response);
    }
  };
}
