import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { randomUUID } from "node:crypto";
import { json, raw, Request, Response, NextFunction } from "express";
import helmet from "helmet";
import { AppModule } from "./app.module";
import { DocumentBuilder, SwaggerModule } from "@nestjs/swagger";
export async function bootstrap() {
  if (
    process.env.NODE_ENV === "production" &&
    (!process.env.DATABASE_URL ||
      Buffer.from(process.env.MFA_ENCRYPTION_KEY ?? "", "base64").length !== 32)
  )
    throw new Error(
      "DATABASE_URL and a 32-byte MFA_ENCRYPTION_KEY are required.",
    );
  const app = await NestFactory.create(AppModule, { bodyParser: false });
  app.enableShutdownHooks();
  app.use(helmet());
  app.use((req:Request,res:Response,next:NextFunction)=>{
    const start=performance.now();
    (req as Request & {correlationId:string}).correlationId=randomUUID();
    res.setHeader('X-Correlation-Id',(req as Request & {correlationId:string}).correlationId);
    res.on('finish',()=>console.log(JSON.stringify({level:'info',event:'http',
      correlationId:(req as Request & {correlationId:string}).correlationId,
      method:req.method,route:req.route?.path??'unmatched',status:res.statusCode,
      durationMs:Math.round(performance.now()-start)})));
    next();
  });
  app.use(
    "/v1/media/uploads",
    raw({ type: "application/octet-stream", limit: "4mb" }),
  );
  app.use(json({ limit: "1mb" }));
  app
    .getHttpAdapter()
    .getInstance()
    .set("json replacer", (_k: string, v: unknown) =>
      typeof v === "bigint" ? v.toString() : v,
    );
  app.getHttpAdapter().getInstance().disable("x-powered-by");
  if (process.env.NODE_ENV === "production")
    app.getHttpAdapter().getInstance().set("trust proxy", 1);
  if (process.env.NODE_ENV !== "production") {
    const doc = SwaggerModule.createDocument(
      app,
      new DocumentBuilder()
        .setTitle("BioBalance API")
        .setVersion("1.0")
        .addBearerAuth()
        .build(),
    );
    SwaggerModule.setup("docs", app, doc);
  }
  await app.listen(Number(process.env.PORT ?? 3000), "0.0.0.0");
  return app;
}
if (require.main === module) void bootstrap();
