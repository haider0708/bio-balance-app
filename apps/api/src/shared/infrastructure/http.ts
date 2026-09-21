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
    const status =
      error instanceof DomainError
        ? error.status
        : error instanceof ZodError
          ? 400
          : error instanceof HttpException
            ? error.getStatus()
            : 500;
    const code =
      error instanceof DomainError
        ? error.code
        : error instanceof ZodError
          ? "VALIDATION"
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
    response
      .status(status)
      .json({
        code,
        message:
          error instanceof DomainError
            ? error.message
            : error instanceof ZodError
              ? "Vérifiez les informations saisies."
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
}
