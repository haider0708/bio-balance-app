import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { SwaggerModule, DocumentBuilder } from "@nestjs/swagger";
import { writeFileSync } from "node:fs";
import { z } from "zod";
import { AppModule } from "./app.module";
import {
  operationSchema,
  syncBatchSchema,
} from "./modules/operations/domain/contracts";
async function main() {
  const app = await NestFactory.create(AppModule, { logger: false });
  const document = SwaggerModule.createDocument(
    app,
    new DocumentBuilder()
      .setTitle("BioBalance API")
      .setDescription(
        "API v1. Tenant context is always verified on the server. Millimes and balances are decimal integer strings. Operations are idempotent and processed atomically.",
      )
      .setVersion("1.0.0")
      .addBearerAuth()
      .build(),
  );
  const ref = (name: string) => ({ $ref: `#/components/schemas/${name}` });
  const object = (
    properties: Record<string, unknown>,
    required: string[] = Object.keys(properties),
  ) => ({ type: "object", properties, required, additionalProperties: false });
  const str = { type: "string" },
    uuid = { type: "string", format: "uuid" },
    integer = { type: "integer", format: "int32" },
    strings = { type: "array", items: str };
  const components: Record<string, unknown> = {
    FulfillmentLine: object({productId:uuid,ordered:integer,received:integer,inTransit:integer,remainingToDispatch:integer,remainingToReceive:integer}),
    OrderFulfillment: object({orderId:uuid,version:integer,status:str,lines:{type:'array',items:ref('FulfillmentLine')}}),
    Money: object({
      currency: { type: "string", enum: ["TND"] },
      millimes: { type: "string", pattern: "^(0|[1-9][0-9]*)$" },
    }),
    User: object({
      id: uuid,
      email: str,
      name: str,
      platformAdmin: { type: "boolean" },
    }),
    LoginRequest: object(
      {
        email: { type: "string", format: "email" },
        password: { type: "string", maxLength: 128 },
        otp: { type: "string" },
      },
      ["email", "password"],
    ),
    LoginResponse: object({
      token: str,
      expiresAt: { type: "string", format: "date-time" },
      user: ref("User"),
    }),
    Store: object({
      id: uuid,
      organizationId: uuid,
      name: str,
      address: str,
      city: str,
      timezone: str,
      permissions: strings,
    }),
    SyncOperation: z.toJSONSchema(operationSchema),
    SyncBatch: z.toJSONSchema(syncBatchSchema),
    SyncResult: object(
      {
        operationId: uuid,
        status: { type: "string", enum: ["accepted", "conflict", "rejected", "blocked", "retryable"] },
        committedCursor: {type:"string",pattern:"^[0-9]+$"},
        affectedVersions: {type:"array",items:object({resource:str,id:uuid,version:integer})},
        retryAfterMs: integer,
        code: str,
        message: str,
        data: { type: "object", additionalProperties: true },
      },
      ["operationId", "status"],
    ),
    SyncResponse: object({
      results: { type: "array", items: ref("SyncResult") },
    }),
    SaleSubmission: object({
      operationId: uuid,
      storeId: uuid,
      saleId: uuid,
      status: {
        type: "string",
        enum: ["local", "pending", "accepted", "conflict", "rejected"],
      },
    }),
    SaleRevision: object(
      {
        id: uuid,
        saleId: uuid,
        version: integer,
        editorId: uuid,
        reason: str,
        before: { type: "object", additionalProperties: true },
        after: { type: "object", additionalProperties: true },
        operationId: uuid,
        createdAt: { type: "string", format: "date-time" },
      },
      [
        "id",
        "saleId",
        "version",
        "editorId",
        "reason",
        "after",
        "operationId",
        "createdAt",
      ],
    ),
    DeliveryReceipt: object({
      id: uuid,
      deliveryId: uuid,
      actorId: uuid,
      operationId: uuid,
      lines: {
        type: "array",
        items: { type: "object", additionalProperties: true },
      },
      differences: { type: "object", additionalProperties: true },
    }),
    RewardClaim: object(
      {
        id: uuid,
        storeId: uuid,
        userId: uuid,
        rewardId: uuid,
        title: str,
        cost: integer,
        status: {
          type: "string",
          enum: ["requested", "fulfilled", "rejected", "cancelled"],
        },
        version: integer,
        productId: uuid,
        quantity: integer,
      },
      [
        "id",
        "storeId",
        "userId",
        "rewardId",
        "title",
        "cost",
        "status",
        "version",
        "quantity",
      ],
    ),
    ApiError: object({ code: str, message: str, correlationId: str }, [
      "code",
      "message",
    ]),
  };
  document.openapi = "3.1.0";
  document.components ??= {};
  document.components.schemas = components as never;
  const schemaBody = (name: string) => ({
    required: true,
    content: { "application/json": { schema: ref(name) } },
  });
  const response = (name: string) => ({
    description: "Success",
    content: { "application/json": { schema: ref(name) } },
  });
  document.paths["/v1/identity/login"]!.post!.requestBody =
    schemaBody("LoginRequest");
  document.paths["/v1/identity/login"]!.post!.responses = {
    "201": response("LoginResponse"),
  };
  document.paths["/v1/sync/status"]!.post!.requestBody = schemaBody("SyncBatch");
  document.paths["/v1/sync/push"]!.post!.requestBody = schemaBody("SyncBatch");
  document.paths["/v1/sync/push"]!.post!.responses = {
    "201": response("SyncResponse"),
  };
  document.paths['/v1/stores/{store}/orders/{order}/fulfillment']!.get!.responses = {'200':response('OrderFulfillment')};
  for (const [path, item] of Object.entries(document.paths))
    for (const [method, value] of Object.entries(item)) {
      if (!["get", "post", "patch", "put", "delete"].includes(method)) continue;
      const route = value as Record<string, unknown>;
      if (["post", "patch", "put"].includes(method) && !route.requestBody)
        route.requestBody = {
          required: false,
          content: {
            "application/json": {
              schema: { type: "object", additionalProperties: true },
            },
          },
        };
      (route.responses as Record<string, unknown>)["400"] = {
        description: "Validation error",
        content: { "application/json": { schema: ref("ApiError") } },
      };
      if (path != "/health")
        (route.responses as Record<string, unknown>)["403"] = {
          description: "Permission or store context denied",
          content: { "application/json": { schema: ref("ApiError") } },
        };
    }
  writeFileSync(
    "../../contracts/openapi/biobalance.json",
    JSON.stringify(document, null, 2) + "\n",
  );
  await app.close();
}
void main();
