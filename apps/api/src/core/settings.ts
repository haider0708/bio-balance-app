import { Injectable } from "@nestjs/common";
import { z } from "zod";
import type { Actor } from "./actor";
import { audit } from "./audit";
import { Database } from "./database";
import { DEFAULT_HOURS, type Hours } from "./hours";
import { requireRule } from "./errors";
import { json } from "./database";

export interface Settings {
  /** The oldest app build still allowed, per phone platform (0: all). */
  minimumBuild: { ios: number; android: number };
  /** Where each store's page is (null: not known yet). */
  stores: { ios: string | null; android: string | null };
  hours: Hours;
  /** Responsables with the permission may suggest the grossiste of a restock. */
  supplierChoice: boolean;
  /** Codes (account invitations, password resets) are also sent by WhatsApp when this is on. */
  whatsapp: { enabled: boolean };
}

const ANDROID_STORE =
  "https://play.google.com/store/apps/details?id=tn.biobalance.app";
const time = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);
const day = z
  .object({ open: time, close: time })
  .refine((d) => d.close > d.open, "Closing must be after opening.")
  .nullable();

/** What the admin may change; every part is optional. */
export const SettingsPatch = z.object({
  minimumBuild: z
    .object({
      ios: z.number().int().min(0).max(1_000_000),
      android: z.number().int().min(0).max(1_000_000),
    })
    .partial()
    .optional(),
  stores: z
    .object({
      ios: z.url().max(300).nullable(),
      android: z.url().max(300).nullable(),
    })
    .partial()
    .optional(),
  hours: z
    .object({ enabled: z.boolean(), days: z.array(day).length(7) })
    .optional(),
  supplierChoice: z.boolean().optional(),
  whatsapp: z.object({ enabled: z.boolean() }).optional(),
});
export type SettingsPatch = z.infer<typeof SettingsPatch>;

const TTL_MS = 10_000;

/**
 * The settings, kept in the database so the admin changes them from the app. Read often (every
 * request checks the opening hours), so each API instance keeps them for ten seconds.
 */
@Injectable()
export class SettingsService {
  private cache: { at: number; value: Settings } | null = null;

  constructor(private readonly db: Database) {}

  async get(): Promise<Settings> {
    if (this.cache && Date.now() - this.cache.at < TTL_MS)
      return this.cache.value;
    const rows = await this.db.run("SYSTEM", (tx) => tx.appSetting.findMany());
    const stored = new Map(rows.map((r) => [r.key, r.value as unknown]));
    const fromEnv = Math.max(0, Number(process.env.MIN_APP_BUILD) || 0);
    const value: Settings = {
      minimumBuild: {
        ios: fromEnv,
        android: fromEnv,
        ...((stored.get("minimumBuild") as object | undefined) ?? {}),
      },
      stores: {
        ios: process.env.IOS_STORE_URL || null,
        android: process.env.PLAY_STORE_URL || ANDROID_STORE,
        ...((stored.get("stores") as object | undefined) ?? {}),
      },
      hours: (stored.get("hours") as Hours | undefined) ?? DEFAULT_HOURS,
      supplierChoice: (stored.get("supplierChoice") as boolean) ?? false,
      whatsapp: (stored.get("whatsapp") as
        { enabled: boolean } | undefined) ?? {
        enabled: false,
      },
    };
    this.cache = { at: Date.now(), value };
    return value;
  }

  /** Admin only. Each changed part is saved whole, and the change is in the audit log. */
  async update(actor: Actor, patch: SettingsPatch): Promise<Settings> {
    requireRule(
      actor.role === "ADMIN",
      "FORBIDDEN",
      "Only the admin changes the settings.",
      403,
    );
    const current = await this.get();
    await this.db.run(actor, async (tx) => {
      for (const [key, part] of Object.entries(patch)) {
        if (part === undefined) continue;
        // Parts the admin sends in pieces (one platform, one store) are merged into what is saved.
        const merged: Record<string, unknown> = {
          minimumBuild: current.minimumBuild,
          stores: current.stores,
        };
        const value =
          key === "minimumBuild" || key === "stores"
            ? { ...(merged[key] as object), ...(part as object) }
            : part;
        await tx.appSetting.upsert({
          where: { key },
          create: { key, value: json(value), updatedById: actor.id },
          update: { value: json(value), updatedById: actor.id },
        });
        await audit(tx, actor, "settings.changed", "AppSetting", ZERO, {
          key,
          value,
        });
      }
    });
    this.cache = null;
    return this.get();
  }

  /** Forget what was read (after a change on this instance). */
  forget() {
    this.cache = null;
  }
}

/** AppSetting has no row id of its own: its audit entries point at this one. */
const ZERO = "00000000-0000-0000-0000-000000000000";
