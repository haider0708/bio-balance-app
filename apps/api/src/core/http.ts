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
import { isOpenAt, nextOpening } from "./hours";
import { SettingsService } from "./settings";

/** Still answered when BioBalance is closed: signing out, who I am, the phone's push token, its password. */
const OPEN_ALWAYS = new Set([
  "POST /v1/auth/logout",
  "GET /v1/me",
  "POST /v1/me/push-device",
  "POST /v1/me/password",
]);

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
    private readonly settings: SettingsService,
  ) {}

  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<AuthRequest>();
    request.correlationId ??= randomUUID();
    const targets = [context.getHandler(), context.getClass()];
    if (this.reflector.getAllAndOverride("public", targets)) return true;
    request.bearer =
      request.headers.authorization?.replace(/^Bearer /, "") ?? "";
    request.actor = await this.auth.authenticate(request.bearer);
    if (
      request.actor.role === "ADMIN" &&
      request.headers["x-biobalance-sandbox"] === "show"
    )
      request.actor.showSandbox = true;
    await this.requireOpen(request);
    const roles = this.reflector.getAllAndOverride<Role[] | undefined>(
      "roles",
      targets,
    );
    if (roles?.length && !roles.includes(request.actor.role))
      throw forbidden("Your role cannot do this.");
    return true;
  }

  /**
   * Outside the working hours (set by the admin, in Tunis time, never the phone's clock) only the admin and
   * the test region work; everyone else may sign in and sign out, nothing more. A sale made while open and
   * sent later (a phone that was offline) still goes through.
   */
  private async requireOpen(request: AuthRequest) {
    const actor = request.actor;
    if (actor.role === "ADMIN" || actor.sandbox) return;
    const { hours } = await this.settings.get();
    if (!hours.enabled) return;
    const path = request.path.replace(/\/+$/, "");
    if (OPEN_ALWAYS.has(`${request.method} ${path}`)) return;
    if (request.method === "POST" && path === "/v1/sales") {
      const at = new Date(
        (request.body as { occurredAt?: string } | undefined)?.occurredAt ?? "",
      );
      if (!Number.isNaN(at.getTime()) && isOpenAt(hours, at)) return;
    }
    if (isOpenAt(hours, new Date())) return;
    const next = nextOpening(hours, new Date());
    throw new DomainError(
      "SERVER_CLOSED",
      "BioBalance is closed for now.",
      423,
      { opensAt: next?.at.toISOString() ?? null, time: next?.time ?? null },
    );
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
    // What the caller needs to fix it (which products, how low): only what a business rule chose to say.
    details: error instanceof DomainError ? error.details : undefined,
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
