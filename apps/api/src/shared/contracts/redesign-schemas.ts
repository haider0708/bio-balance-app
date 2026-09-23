import {
  arr,
  bool,
  decimal,
  integer,
  nullable,
  obj,
  ref,
  str,
  timestamp,
  uuid,
  Schema,
} from "./wire-schemas";
const totals = { netMillimes: decimal, netUnits: decimal, saleCount: decimal };
const group = {
  id: uuid,
  name: str,
  createdAt: timestamp,
  imageId: nullable(uuid),
  phone: nullable(str),
  version: integer,
};
export const redesignSchemas: Record<string, Schema> = {
  AttentionPage: obj({
    items: arr(
      obj({
        id: uuid,
        organizationId: uuid,
        storeId: uuid,
        productId: nullable(uuid),
        kind: {
          type: "string",
          enum: ["low_stock", "expired", "deliveries", "rewards"],
        },
        title: str,
        detail: str,
        storeName: str,
      }),
    ),
    nextCursor: nullable(uuid),
  }),
  ReportExport: obj({
    id: uuid,
    status: {
      type: "string",
      enum: ["pending", "processing", "ready", "failed"],
    },
    rows: integer,
    error: nullable(str),
    createdAt: timestamp,
    expiresAt: timestamp,
  }),
  DashboardSale: obj({
    id: uuid,
    organizationId: uuid,
    storeId: uuid,
    sellerId: uuid,
    day: str,
    occurredAt: timestamp,
    version: integer,
    netMillimes: decimal,
    netUnits: decimal,
    storeName: str,
    sellerName: str,
  }),
  DashboardSalePage: obj({
    items: arr(ref("DashboardSale")),
    nextCursor: nullable(uuid),
  }),
  Group: obj(group),
  GroupAccess: obj({ ...group, canManage: bool, storeCount: integer }),
  GroupPage: obj({
    items: arr(ref("GroupAccess")),
    nextCursor: nullable(uuid),
    creationGrants: arr(obj({ id: uuid })),
  }),
  GroupTeam: obj({
    members: arr(
      obj({
        id: uuid,
        name: str,
        email: str,
        role: { type: "string", enum: ["responsible", "salesperson"] },
        active: bool,
        storeIds: arr(uuid),
      }),
    ),
    invitations: arr(
      obj({
        id: uuid,
        email: str,
        kind: str,
        storeIds: arr(uuid),
        storeId: nullable(uuid),
        expiresAt: timestamp,
      }),
    ),
  }),
  ProductPage: obj({ items: arr(ref("Product")), nextCursor: nullable(uuid) }),
  Dashboard: obj({
    scope: { type: "string", enum: ["network", "group", "store", "personal"] },
    organizationId: nullable(uuid),
    storeId: nullable(uuid),
    from: str,
    to: str,
    generatedAt: timestamp,
    ...totals,
    groupCount: integer,
    storeCount: integer,
    series: arr(obj({ day: str, ...totals })),
    comparisons: arr(obj({ id: uuid, name: str, ...totals })),
    products: arr(
      obj({
        id: uuid,
        name: str,
        imageId: nullable(uuid),
        netUnits: decimal,
        netMillimes: decimal,
      }),
    ),
    recentSales: arr(
      obj({
        id: uuid,
        occurredAt: timestamp,
        netMillimes: decimal,
        netUnits: decimal,
      }),
    ),
    ranking: nullable(
      obj({ month: str, rank: nullable(decimal), score: decimal }),
    ),
    current: obj({
      pendingOrders: integer,
      pendingDeliveries: integer,
      pendingClaims: integer,
      expiredLots: integer,
      expiringLots: integer,
      lowStock: integer,
      availablePoints: nullable(decimal),
      reservedPoints: nullable(decimal),
    }),
    alerts: arr(
      obj({
        id: uuid,
        organizationId: uuid,
        storeId: uuid,
        productId: nullable(uuid),
        kind: str,
        message: str,
        storeName: str,
      }),
    ),
  }),
  ScopedOrder: obj({
    id: uuid,
    organizationId: uuid,
    storeId: uuid,
    createdBy: uuid,
    lines: arr(obj({ productId: uuid, quantity: integer })),
    status: str,
    version: integer,
    createdAt: timestamp,
    storeName: str,
    groupName: str,
  }),
  OrderPage: obj({
    items: arr(ref("ScopedOrder")),
    nextCursor: nullable(uuid),
  }),
  ScopedOrderDetails: obj(
    {
      order: ref("ScopedOrder"),
      deliveries: arr(ref("Delivery")),
      receipts: arr(ref("DeliveryReceipt")),
      fulfillment: arr(ref("FulfillmentLine")),
    },
    ["order", "deliveries"],
  ),
};
export function extendLegacySchemas(schemas: Record<string, Schema>) {
  Object.assign(schemas.Organization!.properties, {
    imageId: nullable(uuid),
    phone: nullable(str),
    version: integer,
  });
  Object.assign(schemas.Product!.properties, {
    category: str,
    range: str,
    packageSize: str,
    instructions: str,
    ingredients: str,
    precautions: str,
    referencePriceMillimes: nullable(decimal),
    priceStatus: str,
    sourceUrls: arr(str),
  });
  Object.assign(schemas.StoreProduct!.properties, { priceConfigured: bool });
}
