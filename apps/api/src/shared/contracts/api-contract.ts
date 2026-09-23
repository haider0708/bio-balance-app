import { z } from "zod";
import { exportRequest } from "../../modules/reporting/export.controller";
import { OpenAPIObject } from "@nestjs/swagger";
import { GroupRequests } from "../../modules/tenancy/group.contracts";
import { redesignSchemas, extendLegacySchemas } from "./redesign-schemas";
import {
  IdentityRequests,
  WorkspaceRequests,
  CatalogRequests,
  NotificationRequests,
  TrainingRequests,
} from "./requests";
import {
  commandSchema,
  operationSchema,
  syncBatchSchema,
} from "../../modules/operations/domain/contracts";
import {
  Schema,
  wireSchemas,
  ref,
  obj,
  arr,
  str,
  uuid,
  integer,
} from "./wire-schemas";

const requests: Record<string, z.ZodType> = {
  ExportController_create: exportRequest,
  GroupController_create: GroupRequests.Create,
  GroupController_update: GroupRequests.Update,
  GroupController_member: GroupRequests.Member,
  IdentityController_login: IdentityRequests.Login,
  IdentityController_invite: IdentityRequests.Invite,
  IdentityController_activate: IdentityRequests.Activate,
  IdentityController_forgot: IdentityRequests.Forgot,
  IdentityController_reset: IdentityRequests.Reset,
  WorkspaceController_create: WorkspaceRequests.Create,
  WorkspaceController_updateStore: WorkspaceRequests.UpdateStore,
  WorkspaceController_config: WorkspaceRequests.Config,
  WorkspaceController_member: WorkspaceRequests.Member,
  WorkspaceController_onboarding: WorkspaceRequests.Onboarding,
  WorkspaceController_reward: WorkspaceRequests.Reward,
  CatalogController_save: CatalogRequests.Save,
  CatalogController_import: CatalogRequests.Import,
  NotificationsController_removeDevice: NotificationRequests.RemoveDevice,
  NotificationsController_device: NotificationRequests.Device,
  NotificationsController_announce: NotificationRequests.Announce,
  TrainingController_save: TrainingRequests.Save,
  TrainingController_start: TrainingRequests.Start,
  OperationsController_push: syncBatchSchema,
  OperationsController_status: syncBatchSchema,
};
const responses: Record<string, Schema> = {
  ExportController_create: ref("ReportExport"),
  ExportController_get: ref("ReportExport"),
  ExportController_file: { type: "string" },
  GroupController_list: ref("GroupPage"),
  GroupController_create: ref("Group"),
  GroupController_update: ref("Group"),
  GroupController_stores: arr(ref("StoreAccess")),
  GroupController_team: ref("GroupTeam"),
  GroupController_member: ref("Ok"),
  CatalogController_list: ref("ProductPage"),
  DashboardController_get: ref("Dashboard"),
  DashboardController_attention: ref("AttentionPage"),
  DashboardController_orders: ref("OrderPage"),
  DashboardController_order: ref("ScopedOrderDetails"),
  DashboardController_sales: ref("DashboardSalePage"),
  HealthController_health: ref("Health"),
  IdentityController_login: ref("LoginResponse"),
  IdentityController_me: ref("User"),
  IdentityController_logout: ref("Ok"),
  IdentityController_invite: ref("Invitation"),
  IdentityController_activate: ref("Activated"),
  IdentityController_forgot: ref("Message"),
  IdentityController_reset: ref("Ok"),
  WorkspaceController_organizations: arr(ref("Organization")),
  WorkspaceController_stores: arr(ref("StoreAccess")),
  WorkspaceController_create: ref("Store"),
  WorkspaceController_updateStore: ref("Store"),
  WorkspaceController_snapshot: ref("Snapshot"),
  WorkspaceController_snapshotPage: ref("SnapshotPage"),
  WorkspaceController_collection: arr(ref("CollectionItem")),
  WorkspaceController_history: ref("HistoryPage"),
  WorkspaceController_fulfillment: ref("OrderFulfillment"),
  WorkspaceController_sale: ref("SaleDetails"),
  WorkspaceController_changes: ref("ChangePage"),
  WorkspaceController_ranking: ref("Ranking"),
  WorkspaceController_config: ref("StoreProduct"),
  WorkspaceController_member: ref("Membership"),
  WorkspaceController_onboarding: ref("OnboardingResult"),
  WorkspaceController_reward: ref("Reward"),
  CatalogController_save: ref("Product"),
  CatalogController_import: ref("CatalogImportResult"),
  NotificationsController_get: ref("Notification"),
  NotificationsController_list: arr(ref("Notification")),
  NotificationsController_read: ref("Count"),
  NotificationsController_removeDevice: ref("Count"),
  NotificationsController_device: ref("Device"),
  NotificationsController_announce: ref("AnnouncementResult"),
  TrainingController_list: arr(ref("TrainingContent")),
  TrainingController_get: ref("TrainingContent"),
  TrainingController_save: ref("TrainingContent"),
  TrainingController_start: ref("UploadStarted"),
  TrainingController_status: ref("UploadStatus"),
  TrainingController_chunk: ref("UploadChunkResult"),
  TrainingController_metadata: ref("MediaMetadata"),
  TrainingController_media: { type: "string", format: "binary" },
  ReportingController_export: { type: "string" },
  ReportingController_overview: ref("ReportOverview"),
  AdminController_overview: ref("AdminOverview"),
  OperationsController_push: ref("SyncResponse"),
  OperationsController_status: ref("StatusResponse"),
};
const publicIds = new Set([
  "HealthController_health",
  "IdentityController_login",
  "IdentityController_activate",
  "IdentityController_forgot",
  "IdentityController_reset",
]);
const rename = (value: string) =>
  value.replace(/Controller_([a-z])/, (_match, letter: string) =>
    letter.toUpperCase(),
  );
function parameter(
  name: string,
  location: "query" | "path" | "header",
  schema: Schema,
  required = false,
) {
  return {
    name,
    in: location,
    required: required || location === "path",
    schema,
  };
}
export function applyContract(document: OpenAPIObject): OpenAPIObject {
  const schemas: Record<string, Schema> = structuredClone(wireSchemas);
  extendLegacySchemas(schemas);
  Object.assign(schemas, redesignSchemas);
  schemas.Command = z.toJSONSchema(commandSchema, { io: "input" });
  schemas.SyncOperation = z.toJSONSchema(operationSchema, { io: "input" });
  schemas.SyncBatch = z.toJSONSchema(syncBatchSchema, { io: "input" });
  // Shared references keep command types identical in standalone and envelope APIs.
  schemas.SyncOperation.properties.command = ref("Command");
  schemas.SyncOperation.properties.payloadVersion = {
    type: "integer",
    enum: [1, 2],
  };
  schemas.SyncBatch.properties.operations.items = ref("SyncOperation");
  schemas.CatalogImportResult = {
    anyOf: [
      obj({
        valid: { const: true, type: "boolean" },
        count: integer,
        rows: arr(
          z.toJSONSchema(
            CatalogRequests.Save.omit({
              id: true,
              expectedVersion: true,
              imageId: true,
            }),
            { io: "input" },
          ),
        ),
      }),
      ref("Count"),
    ],
  };
  for (const [path, item] of Object.entries(document.paths))
    for (const method of ["get", "post", "patch", "put", "delete"] as const) {
      const route = item?.[method];
      if (!route) continue;
      const original = route.operationId!;
      if (!responses[original])
        throw new Error(`MISSING_RESPONSE_CONTRACT:${original}`);
      route.operationId = rename(original);
      const schemaName = route.operationId + "Response";
      schemas[schemaName] = responses[original];
      route.security = publicIds.has(original) ? [] : [{ bearer: [] }];
      const params: any[] = [];
      if (
        [
          "GroupController_list",
          "CatalogController_list",
          "DashboardController_orders",
          "DashboardController_sales",
          "DashboardController_attention",
        ].includes(original)
      )
        params.push(parameter("after", "query", uuid));
      if (original === "GroupController_list")
        params.push(parameter("search", "query", str));
      if (original === "DashboardController_orders")
        params.push(
          parameter("phase", "query", {
            type: "string",
            enum: ["preparation", "transit", "complete"],
          }),
        );
      if (
        [
          "DashboardController_get",
          "DashboardController_orders",
          "DashboardController_sales",
          "DashboardController_attention",
        ].includes(original)
      )
        params.push(
          parameter(
            "scope",
            "query",
            { type: "string", enum: ["network", "group", "store", "personal"] },
            true,
          ),
          parameter("from", "query", { type: "string", format: "date" }, true),
          parameter("to", "query", { type: "string", format: "date" }, true),
          parameter("organizationId", "query", uuid),
          parameter("storeId", "query", uuid),
        );
      for (const name of path.matchAll(/\{([^}]+)\}/g)) {
        const resource = path.includes("/history/")
          ? ["sales", "points", "movements", "audit"]
          : ["lots", "config", "products", "sales", "points", "audit"];
        params.push(
          parameter(
            name[1]!,
            "path",
            name[1] === "resource" ? { type: "string", enum: resource } : uuid,
          ),
        );
      }
      if (path.includes("{store}"))
        params.push(parameter("organizationId", "query", uuid, true));
      if (original === "WorkspaceController_snapshot")
        params.push(
          parameter("after", "query", {
            type: "string",
            pattern: "^[0-9]{1,19}$",
          }),
          parameter("catalogRevision", "query", {
            type: "string",
            pattern: "^[0-9]+:[0-9]+$",
          }),
          parameter("protocol", "query", {
            type: "integer",
            enum: [2, 3],
            default: 2,
          }),
          parameter("acknowledgments", "query", {
            type: "string",
            maxLength: 1849,
          }),
        );
      if (
        [
          "WorkspaceController_collection",
          "ReportingController_export",
          "TrainingController_list",
        ].includes(original)
      )
        params.push(parameter("after", "query", uuid));
      if (original === "WorkspaceController_history")
        params.push(
          parameter("productId", "query", uuid),
          parameter("before", "query", {
            type: "string",
            maxLength: 300,
            pattern: "^[A-Za-z0-9_-]+$",
          }),
        );
      if (original === "WorkspaceController_changes")
        params.push(
          parameter("after", "query", {
            type: "string",
            pattern: "^[0-9]{1,19}$",
            default: "0",
          }),
        );
      if (original === "NotificationsController_list")
        params.push(
          parameter("before", "query", { type: "string", format: "date-time" }),
        );
      if (
        ["TrainingController_metadata", "TrainingController_media"].includes(
          original,
        )
      )
        params.push(
          parameter("variant", "query", {
            type: "string",
            enum: ["original", "thumbnail"],
            default: "original",
          }),
        );
      if (original === "DashboardController_attention")
        params.push(
          parameter(
            "kind",
            "query",
            {
              type: "string",
              enum: ["low_stock", "expired", "deliveries", "rewards"],
            },
            true,
          ),
        );
      route.parameters = params;
      delete route.requestBody;
      if (requests[original]) {
        const requestName = route.operationId + "Request";
        schemas[requestName] = z.toJSONSchema(requests[original], {
          io: "input",
        });
        if (original.startsWith("OperationsController_"))
          schemas[requestName] = ref("SyncBatch");
        route.requestBody = {
          required: true,
          content: { "application/json": { schema: ref(requestName) } },
        } as never;
      }
      if (original === "TrainingController_chunk") {
        params.push(
          parameter(
            "Upload-Offset",
            "header",
            { type: "integer", minimum: 0, maximum: 524288000 },
            true,
          ),
        );
        route.requestBody = {
          required: true,
          content: {
            "application/octet-stream": {
              schema: { type: "string", format: "binary", maxLength: 4194304 },
            },
          },
        } as never;
      }
      const contentType =
        original === "TrainingController_media"
          ? "application/octet-stream"
          : ["ReportingController_export", "ExportController_file"].includes(
                original,
              )
            ? "text/csv"
            : "application/json";
      const success = method === "post" ? "201" : "200";
      route.responses = {
        [success]: {
          description:
            "Réponse autorisée. Les entiers monétaires sont des chaînes décimales exactes.",
          content: { [contentType]: { schema: ref(schemaName) } },
        },
      } as never;
      if (original === "TrainingController_media") {
        params.push(
          parameter("Range", "header", str),
          parameter("If-Range", "header", str),
        );
        route.responses["206"] = {
          description: "Plage de contenu autorisé",
          content: { "application/octet-stream": { schema: ref(schemaName) } },
          headers: {
            "Content-Range": { schema: str },
            ETag: { schema: str },
            "X-Content-SHA256": { schema: str },
          },
        } as never;
      }
      for (const status of [
        "400",
        "401",
        "403",
        "404",
        "409",
        "410",
        "413",
        "415",
        "416",
        "422",
        "429",
        "500",
        "503",
      ])
        route.responses[status] = {
          description: "Erreur stable à traduire pour l’utilisateur",
          content: { "application/json": { schema: ref("ApiError") } },
          ...(["429", "503"].includes(status)
            ? { headers: { "Retry-After": { schema: str } } }
            : {}),
        } as never;
    }
  for (const schema of Object.values(schemas)) delete schema.$schema;
  document.openapi = "3.1.0";
  document.components ??= {};
  document.components.schemas = schemas as never;
  return document;
}
