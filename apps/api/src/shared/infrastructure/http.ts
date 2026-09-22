import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  CanActivate,
  ExecutionContext,
  Injectable,
  SetMetadata,
  HttpException,
} from "@nestjs/common";
import { Reflector } from "@nestjs/core";
import { Request, Response } from "express";
import { randomUUID } from "node:crypto";
import { ZodError } from "zod";
import { Actor } from "../../modules/operations/domain/contracts";
import { IdentityService } from "../../modules/identity/identity.service";
import { DomainError } from "../domain/errors";
export type AuthRequest = Request & {
  actor: Actor;
  bearer: string;
  correlationId: string;
};
export const Public = () => SetMetadata("public", true);
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly identity: IdentityService,
    private readonly reflector: Reflector,
  ) {}
  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<AuthRequest>();
    request.correlationId ??= randomUUID();
    if (
      this.reflector.getAllAndOverride("public", [
        context.getHandler(),
        context.getClass(),
      ])
    )
      return true;
    request.bearer =
      request.headers.authorization?.replace(/^Bearer /, "") ?? "";
    request.actor = await this.identity.authenticate(request.bearer);
    return true;
  }
}
@Catch()
export class ErrorFilter implements ExceptionFilter {
  catch(error: unknown, host: ArgumentsHost) {
    const request = host.switchToHttp().getRequest<AuthRequest>();
    const response = host.switchToHttp().getResponse<Response>();
    sendError(error, request, response);
  }
}

/** The same redacted contract is used before and after Nest dispatch. */
export function sendError(
  error: unknown,
  request: Pick<AuthRequest, "correlationId">,
  response: Response,
) {
  if (response.headersSent) {
    response.end();
    return;
  }
  const parser = error as { type?: string } | null;
  const parserStatus =
    parser?.type === "entity.too.large"
      ? 413
      : parser?.type === "entity.parse.failed"
        ? 400
        : undefined;
  const status =
    error instanceof DomainError
      ? error.status
      : error instanceof ZodError
        ? 400
        : error instanceof HttpException
          ? error.getStatus()
          : (parserStatus ?? 500);
  const code =
    error instanceof DomainError
      ? error.code
      : error instanceof ZodError
        ? "VALIDATION"
        : status < 500
          ? `HTTP_${status}`
          : "SERVER_ERROR";
  if (status >= 500)
    console.error(
      JSON.stringify({
        level: "error",
        correlationId: request.correlationId,
        code,
        error: error instanceof Error ? error.name : "Unknown",
      }),
    );
  const retry =
    error instanceof DomainError
      ? (error.details as { retryAfterSeconds?: number } | undefined)
          ?.retryAfterSeconds
      : undefined;
  if (status === 429 || status === 503)
    response.setHeader(
      "Retry-After",
      String(retry ?? (status === 429 ? 900 : 1)),
    );
  response.status(status).json({
    code,
    message:
      error instanceof DomainError
        ? error.message
        : error instanceof ZodError
          ? "Vérifiez les informations saisies."
          : status === 413
            ? "Le fichier ou la requête dépasse la taille autorisée."
            : status < 500
              ? "La requête est invalide ou la ressource est indisponible."
              : "Le service est momentanément indisponible.",
    fields:
      error instanceof ZodError
        ? error.issues.map((i) => ({
            path: i.path.join("."),
            message: i.message,
          }))
        : undefined,
    correlationId: request.correlationId,
  });
}
