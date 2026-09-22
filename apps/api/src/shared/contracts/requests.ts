import { z } from "zod";

export namespace IdentityRequests {
  const email = z.email().trim().toLowerCase();
  const password = z.string().min(12).max(128);
  export const Login = z.object({
    email,
    password: z.string().min(1).max(128),
    otp: z.string().optional(),
  });
  export const Invite = z.object({
    email,
    organizationId: z.uuid().optional(),
    organizationName: z.string().min(2).max(120).optional(),
    storeId: z.uuid().optional(),
    permissions: z
      .array(z.enum(["sell", "receive", "manage"]))
      .min(1)
      .default(["sell", "receive"]),
  });
  export const Activate = z.object({
    token: z.string().min(32).max(256),
    name: z.string().trim().min(2).max(120),
    password,
  });
  export const Forgot = z.object({ email });
  export const Reset = z.object({
    token: z.string().min(32).max(256),
    password,
  });
}

export namespace WorkspaceRequests {
  const uuid = z.uuid();
  const name = z.string().trim().min(2).max(120);
  export const Create = z
    .object({
      organizationId: uuid,
      name,
      address: z.string().trim().min(3).max(300),
      city: name,
      phone: z.string().max(30).optional(),
    })
    .strict();
  export const UpdateStore = z
    .object({
      name,
      address: z.string().trim().min(3).max(300),
      city: name,
      phone: z.string().trim().max(30).nullable().optional(),
      imageId: uuid.nullable().optional(),
      expectedVersion: z.number().int().positive(),
    })
    .strict();
  export const Config = z
    .object({
      priceMillimes: z.string().regex(/^(0|[1-9]\d{0,14})$/),
      threshold: z.number().int().min(0).max(1_000_000),
      pointsPerUnit: z.number().int().min(0).max(100_000),
      zeroPointsConfirmed: z.boolean().optional(),
      expectedVersion: z.number().int().positive().optional(),
    })
    .strict();
  export const Member = z
    .object({
      active: z.boolean(),
      permissions: z.array(z.enum(["sell", "receive", "manage"])).min(1),
    })
    .strict();
  export const Onboarding = z
    .object({
      step: z.number().int().min(1).max(5).optional(),
      workingAlone: z.boolean().optional(),
      noOpeningStock: z.boolean().optional(),
      expectedVersion: z.number().int().positive().optional(),
    })
    .strict();
  export const Reward = z
    .object({
      id: uuid.optional(),
      title: name,
      description: z.string().max(2000).default(""),
      cost: z.number().int().positive().max(100_000_000),
      productId: uuid.nullable().optional(),
      imageId: uuid.nullable().optional(),
      quantity: z.number().int().positive().max(1_000_000).default(1),
      active: z.boolean().default(true),
      expectedVersion: z.number().int().positive().optional(),
    })
    .strict();
}

export namespace CatalogRequests {
  const product = z
    .object({
      id: z.uuid().optional(),
      reference: z.string().trim().min(1).max(80),
      name: z.string().trim().min(2).max(160),
      imageId: z.uuid().nullable().optional(),
      barcode: z.string().trim().min(3).max(80).optional(),
      description: z.string().max(5000).default(""),
      active: z.boolean().default(true),
      expectedVersion: z.number().int().positive().optional(),
    })
    .strict();
  export const Save = product;
  export const Import = z
    .object({
      rows: z
        .array(product.omit({ id: true, expectedVersion: true, imageId: true }))
        .min(1)
        .max(1000),
      commit: z.boolean().default(false),
    })
    .strict();
}

export namespace NotificationRequests {
  export const RemoveDevice = z.object({ token: z.string().min(20).max(4096) });
  export const Device = z.object({
    token: z.string().min(20).max(4096),
    platform: z.enum(["android", "ios"]),
  });
  export const Announce = z
    .object({
      id: z.uuid(),
      title: z.string().trim().min(2).max(120),
      body: z.string().trim().min(2).max(2000),
      audience: z.enum(["all", "salespeople"]),
    })
    .strict();
}

export namespace TrainingRequests {
  export const Save = z
    .object({
      id: z.uuid().optional(),
      submissionId: z.uuid().optional(),
      title: z.string().trim().min(3).max(200),
      body: z.string().max(100_000),
      type: z.enum(["article", "video"]),
      mediaId: z.uuid().nullable().optional(),
      productIds: z.array(z.uuid()).max(100).default([]),
      status: z.enum(["draft", "published", "archived"]),
      expectedVersion: z.number().int().min(0).optional(),
    })
    .strict();
  export const Start = z
    .object({
      purpose: z.enum(["training", "catalog", "store", "reward"]).optional(),
      organizationId: z.uuid().optional(),
      storeId: z.uuid().optional(),
      sha256: z
        .string()
        .regex(/^[a-f0-9]{64}$/)
        .optional(),
      fileName: z.string().min(1).max(200),
      mime: z.enum(["image/jpeg", "image/png", "video/mp4", "video/quicktime"]),
      size: z
        .number()
        .int()
        .positive()
        .max(500 * 1024 * 1024),
    })
    .strict();
}
