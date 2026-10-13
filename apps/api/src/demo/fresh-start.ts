import type { Client } from "pg";
import { DEMO_NOTE } from "./seed";

/** The accounts the store reviewers sign in with (they live in the test region). */
export const REVIEW_EMAILS = {
  responsable: "demo-responsable@galylio.com",
  vendeur: "demo-vendeur@galylio.com",
} as const;

export interface WipeResult {
  /** The stored names of the photos and documents removed, to delete from the media folder. */
  files: string[];
  counts: Record<string, number>;
}

/** The history tables refuse changes (append-only): these are lifted for the wipe only. */
const APPEND_ONLY = [
  ["StockMovement", "StockMovement_append_only"],
  ["SaleRevision", "SaleRevision_append_only"],
  ["WalletEntry", "WalletEntry_append_only"],
  ["AuditEntry", "AuditEntry_append_only"],
] as const;

/** The password hashes of the review accounts, so a rebuilt test region keeps the same passwords. */
export async function reviewPasswordHashes(owner: Client) {
  const { rows } = await owner.query<{ email: string; passwordHash: string }>(
    `SELECT email, "passwordHash" FROM "User" WHERE email = ANY($1) AND "passwordHash" IS NOT NULL`,
    [Object.values(REVIEW_EMAILS)],
  );
  const of = (email: string) =>
    rows.find((r) => r.email === email)?.passwordHash;
  const responsable = of(REVIEW_EMAILS.responsable);
  const vendeur = of(REVIEW_EMAILS.vendeur);
  return responsable && vendeur ? { responsable, vendeur } : null;
}

/**
 * Empties the network for its real start: every region, group, store, grossiste, account (but the
 * admins), sale, stock, restock, reward earned, payout, announcement, course, notification, photo
 * and history line goes. What stays: the admins (with their sign-in), the product catalogue with
 * its pictures, and the reward rates. One transaction: all or nothing. The integrity checks stay
 * on (a forgotten link aborts it); only the append-only guards of the history are lifted, and only
 * inside it. Needs the database owner.
 */
export async function wipeNetwork(owner: Client): Promise<WipeResult> {
  const counts: Record<string, number> = {};
  const run = async (name: string, sql: string, values: unknown[] = []) => {
    counts[name] = (await owner.query(sql, values)).rowCount ?? 0;
  };
  await owner.query("BEGIN");
  try {
    for (const [table, trigger] of APPEND_ONLY)
      await owner.query(`ALTER TABLE "${table}" DISABLE TRIGGER "${trigger}"`);
    const { rows: admins } = await owner.query<{ id: string }>(
      `SELECT id FROM "User" WHERE role = 'ADMIN' ORDER BY "createdAt"`,
    );
    if (!admins.length) throw new Error("There is no admin to keep.");
    const keep = admins.map((a) => a.id);

    await run("Notification", `DELETE FROM "Notification"`);
    await run("Message", `DELETE FROM "Message"`);
    await run("LessonProgress", `DELETE FROM "LessonProgress"`);
    await run("Lesson", `DELETE FROM "Lesson"`);
    await run("Course", `DELETE FROM "Course"`);
    await run("SaleRevision", `DELETE FROM "SaleRevision"`);
    await run("SaleLine", `DELETE FROM "SaleLine"`);
    await run("WalletEntry", `DELETE FROM "WalletEntry"`);
    await run("Sale", `DELETE FROM "Sale"`);
    await run("PayoutRequest", `DELETE FROM "PayoutRequest"`);
    await run("StockMovement", `DELETE FROM "StockMovement"`);
    await run("Stock", `DELETE FROM "Stock"`);
    await run("StockDeclarationLine", `DELETE FROM "StockDeclarationLine"`);
    await run("StockDeclaration", `DELETE FROM "StockDeclaration"`);
    await run("StockRecount", `DELETE FROM "StockRecount"`);
    await run("RestockLine", `DELETE FROM "RestockLine"`);
    await run("RestockOrder", `DELETE FROM "RestockOrder"`);
    await run("AuditEntry", `DELETE FROM "AuditEntry"`);
    await run("Job", `DELETE FROM "Job"`);
    await run("LoginAttempt", `DELETE FROM "LoginAttempt"`);
    // Reward periods the old demonstration added to give its history rewards.
    await run("RewardRule", `DELETE FROM "RewardRule" WHERE note = $1`, [
      DEMO_NOTE,
    ]);
    // Photos: only the catalogue's pictures stay, now held by the first admin.
    const { rows: media } = await owner.query<{ path: string }>(
      `DELETE FROM "MediaAsset" WHERE id NOT IN (SELECT "imageId" FROM "Product" WHERE "imageId" IS NOT NULL)
       RETURNING path`,
    );
    counts.MediaAsset = media.length;
    await owner.query(
      `UPDATE "MediaAsset" SET "ownerId" = $1, "regionId" = NULL`,
      [keep[0]],
    );
    // Accounts but the admins (their sessions, devices and codes go with them).
    await run("User", `DELETE FROM "User" WHERE id <> ALL($1::uuid[])`, [keep]);
    await run("Pdv", `DELETE FROM "Pdv"`);
    await run("Group", `DELETE FROM "Group"`);
    await run("Depot", `DELETE FROM "Depot"`);
    await run("Region", `DELETE FROM "Region"`);
    for (const [table, trigger] of APPEND_ONLY)
      await owner.query(`ALTER TABLE "${table}" ENABLE TRIGGER "${trigger}"`);
    await owner.query("COMMIT");
    return { files: media.map((m) => m.path), counts };
  } catch (error) {
    await owner.query("ROLLBACK");
    throw error;
  }
}
