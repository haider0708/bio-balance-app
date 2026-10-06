import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { randomUUID } from "node:crypto";
import { json, type NextFunction, type Request, type Response } from "express";
import helmet from "helmet";
import { AppModule } from "./app.module";

export async function bootstrap() {
  if (
    process.env.NODE_ENV === "production" &&
    (!process.env.DATABASE_URL ||
      Buffer.from(process.env.MFA_ENCRYPTION_KEY ?? "", "base64").length !== 32)
  )
    throw new Error(
      "DATABASE_URL and a 32-byte MFA_ENCRYPTION_KEY are required.",
    );

  // The body parser is applied below, except for file uploads, which stream to disk.
  const app = await NestFactory.create(AppModule, {
    bodyParser: false,
    logger:
      process.env.NODE_ENV === "test"
        ? false
        : process.env.NODE_ENV === "production"
          ? ["warn", "error"]
          : ["log", "warn", "error"],
  });
  app.enableShutdownHooks();
  app.use(helmet());
  app.use((req: Request, res: Response, next: NextFunction) => {
    const started = performance.now();
    const context = req as Request & { correlationId: string };
    context.correlationId = randomUUID();
    res.setHeader("X-Correlation-Id", context.correlationId);
    res.setHeader("Cache-Control", "no-store");
    if (process.env.NODE_ENV !== "test")
      res.on("finish", () =>
        console.log(
          JSON.stringify({
            level: "info",
            event: "http",
            correlationId: context.correlationId,
            method: req.method,
            route: req.route?.path ?? "unmatched",
            status: res.statusCode,
            durationMs: Math.round(performance.now() - started),
          }),
        ),
      );
    next();
  });
  const parseJson = json({ limit: "1mb", inflate: false });
  app.use((req: Request, res: Response, next: NextFunction) =>
    req.method === "POST" && req.path === "/v1/media"
      ? next()
      : parseJson(req, res, next),
  );
  const http = app.getHttpAdapter().getInstance();
  http.set("json replacer", (_k: string, v: unknown) =>
    typeof v === "bigint" ? Number(v) : v,
  );
  http.disable("x-powered-by");
  if (process.env.NODE_ENV === "production") http.set("trust proxy", 1);

  await app.listen(Number(process.env.PORT ?? 3000), "0.0.0.0");
  const server = app.getHttpServer();
  server.headersTimeout = 10_000;
  server.requestTimeout = 120_000; // large training videos
  server.keepAliveTimeout = 5_000;
  return app;
}

if (require.main === module) void bootstrap();
