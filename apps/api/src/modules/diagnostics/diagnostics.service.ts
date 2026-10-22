import { Injectable } from "@nestjs/common";
import { createHash } from "node:crypto";
import type { Actor } from "../../core/actor";
import { Database } from "../../core/database";
import { requireRule } from "../../core/errors";
import { AuthService } from "../auth/auth.service";
import { tokenHash } from "../auth/codes";

export interface ClientErrorInput {
  platform: string;
  appVersion: string;
  message: string;
  stack: string;
}

/**
 * What makes two reports the same error: object ids ("Gl#12cba", "minified:Gl") and the line and column
 * of a minified build change every time, so one bug would otherwise fill the list with a row per report.
 */
export function normalizeError(text: string) {
  return text
    .replace(/#[0-9a-f]{3,}/gi, "#id")
    .replace(/minified:[\w$<>]+/g, "minified:x")
    .replace(/:\d+:\d+/g, ":N:N");
}

/** Above this many kinds of error in a day, new kinds are ignored (a flood is not more useful). */
const DAILY_KINDS = 500;

@Injectable()
export class DiagnosticsService {
  constructor(
    private readonly db: Database,
    private readonly auth: AuthService,
  ) {}

  /**
   * Count an error a phone or the console met. The same error from the same version adds to one
   * row (its "fingerprint": platform, version, message and the first lines of where it happened).
   */
  async report(input: ClientErrorInput, ip: string) {
    await this.auth.throttle(`errors:${tokenHash(ip)}`, 30);
    const fingerprint = createHash("sha256")
      .update(
        [
          input.platform,
          input.appVersion,
          normalizeError(input.message),
          normalizeError(input.stack.split("\n").slice(0, 3).join("\n")),
        ].join("\0"),
      )
      .digest("hex");
    await this.db.run("SYSTEM", async (tx) => {
      const known = await tx.clientError.updateMany({
        where: { fingerprint },
        data: { count: { increment: 1 }, lastSeen: new Date() },
      });
      if (known.count) return;
      const today = await tx.clientError.count({
        where: { firstSeen: { gt: new Date(Date.now() - 86_400_000) } },
      });
      if (today >= DAILY_KINDS) return;
      await tx.clientError.createMany({
        data: [{ fingerprint, ...input }],
        skipDuplicates: true,
      });
    });
    return { ok: true };
  }

  /** The admin's list: the most recent kinds of error first. */
  list(actor: Actor) {
    requireRule(actor.role === "ADMIN", "FORBIDDEN", "Not allowed.", 403);
    return this.db.run("SYSTEM", (tx) =>
      tx.clientError.findMany({
        orderBy: { lastSeen: "desc" },
        take: 100,
        select: {
          id: true,
          platform: true,
          appVersion: true,
          message: true,
          stack: true,
          count: true,
          firstSeen: true,
          lastSeen: true,
        },
      }),
    );
  }
}
