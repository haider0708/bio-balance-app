import {
  ArgumentsHost,
  CanActivate,
  Catch,
  ExceptionFilter,
  ExecutionContext,
  HttpException,
  Injectable,
  SetMetadata,
} from "@nestjs/common";
import { Reflector } from "@nestjs/core";
import type { Role } from "@prisma/client";
import type { Request, Response } from "express";
import { randomUUID } from "node:crypto";
import { ZodError, type ZodType } from "zod";
import type { Actor } from "./actor";
import { DomainError, forbidden } from "./errors";
import { AuthService } from "../modules/auth/auth.service";

export type AuthRequest = Request & {
  actor: Actor;
  bearer: string;
  correlationId: string;
};

export const Public = () => SetMetadata("public", true);
/** Restricts a route (or controller) to some roles. Without it, any signed-in user may call. */
export const Roles = (...roles: Role[]) => SetMetadata("roles", roles);

/** Parse a request body or query with zod; invalid input becomes a 400. */
export function parse<T>(schema: ZodType<T>, value: unknown): T {
  return schema.parse(value);
}

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly auth: AuthService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<AuthRequest>();
    request.correlationId ??= randomUUID();
    const targets = [context.getHandler(), context.getClass()];
    if (this.reflector.getAllAndOverride("public", targets)) return true;
    request.bearer =
      request.headers.authorization?.replace(/^Bearer /, "") ?? "";
    request.actor = await this.auth.authenticate(request.bearer);
    const roles = this.reflector.getAllAndOverride<Role[] | undefined>(
      "roles",
      targets,
    );
    if (roles?.length && !roles.includes(request.actor.role))
      throw forbidden("Your role cannot do this.");
    return true;
  }
}

@Catch()
export class ErrorFilter implements ExceptionFilter {
  catch(error: unknown, host: ArgumentsHost) {
    sendError(
      error,
      host.switchToHttp().getRequest<AuthRequest>(),
      host.switchToHttp().getResponse<Response>(),
    );
  }
}

/** One redacted error shape for every failure, with a correlation id for support. */
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
        message: error instanceof Error ? error.message.slice(0, 300) : "",
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
          ? "Check the information you entered."
          : status < 500
            ? "The request is invalid or the resource is unavailable."
            : "The service is temporarily unavailable.",
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
