import { Prisma } from "@prisma/client";
import { statfs, unlink } from "node:fs/promises";
import path from "node:path";
import { Database } from "../../../shared/infrastructure/database";
import { requireRule } from "../../../shared/domain/errors";

const MiB = 1024n * 1024n;
export const imageOutputLimit = 16n * MiB;
export const videoOutputLimit = 2048n * MiB;
export function mediaReservation(size: number, mime: string) {
  return (
    BigInt(size) +
    (mime.startsWith("video/") ? videoOutputLimit : imageOutputLimit)
  );
}
function setting(name: string, fallback: bigint) {
  const value = process.env[name];
  if (value === undefined) return fallback;
  requireRule(
    /^\d+$/.test(value) && BigInt(value) > 0n,
    "MEDIA_CONFIGURATION",
    "Configuration des médias invalide.",
    503,
  );
  return BigInt(value);
}

/** Reserve the worst-case retained bytes before accepting an upload. */
export async function reserveMedia(
  tx: Prisma.TransactionClient,
  root: string,
  ownerId: string,
  storeId: string | undefined,
  bytes: bigint,
) {
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(672144521)`;
  const [usage] = await tx.$queryRaw<
    {
      total: bigint;
      scoped: bigint;
      assets: bigint;
      pending: bigint;
      unwritten: bigint;
    }[]
  >`
    SELECT COALESCE(SUM("storageBytes"),0)::bigint AS total,
      COALESCE(SUM("storageBytes") FILTER (WHERE "storeId" IS NOT DISTINCT FROM ${storeId ?? null}::uuid),0)::bigint AS scoped,
      COUNT(*) FILTER (WHERE "storeId" IS NOT DISTINCT FROM ${storeId ?? null}::uuid AND status<>'expired') AS assets,
      COUNT(*) FILTER (WHERE "ownerId"=${ownerId}::uuid AND status IN ('uploading','processing')) AS pending,
      COALESCE(SUM(GREATEST(0,"storageBytes"-received-COALESCE("processedSize",0))),0)::bigint AS unwritten
    FROM "MediaAsset"`;
  requireRule(
    usage &&
      usage.total + bytes <= setting("MEDIA_TOTAL_BYTES", 50n * 1024n * MiB),
    "MEDIA_QUOTA",
    "La capacité des médias est atteinte. Contactez BioBalance.",
    409,
  );
  requireRule(
    !storeId ||
      usage.scoped + bytes <= setting("MEDIA_STORE_BYTES", 1024n * MiB),
    "MEDIA_QUOTA",
    "La capacité des images du magasin est atteinte.",
    409,
  );
  requireRule(
    usage.assets < setting("MEDIA_ASSET_LIMIT", 1000n) &&
      usage.pending < setting("MEDIA_PENDING_LIMIT", 20n),
    "MEDIA_QUOTA",
    "Trop de médias ou de transferts en cours. Terminez les transferts avant de réessayer.",
    409,
  );
  const disk = await statfs(root, { bigint: true });
  requireRule(
    disk.bavail * disk.bsize >=
      usage.unwritten + bytes + setting("MEDIA_FREE_BYTES", 1024n * MiB),
    "MEDIA_STORAGE_LOW",
    "Espace serveur insuffisant. Réessayez plus tard.",
    503,
  );
}

async function remove(file: string) {
  try {
    await unlink(file);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
}

/** Ready final files are immutable and are never removed by temporary cleanup. */
export async function cleanupMedia(
  db: Database,
  root: string,
  now = new Date(),
) {
  const cutoff = new Date(now.getTime() - 7 * 86400000);
  let after: string | undefined;
  do {
    const assets = await db.mediaAsset.findMany({
      where: {
        createdAt: { lt: cutoff },
        cleanedAt: null,
        ...(after ? { id: { gt: after } } : {}),
      },
      orderBy: { id: "asc" },
      take: 100,
    });
    if (!assets.length) break;
    for (const asset of assets) {
      after = asset.id;
      const claimed = await db.transaction(async (tx) => {
        await tx.$queryRaw`SELECT id FROM "MediaAsset" WHERE id=${asset.id}::uuid FOR UPDATE`;
        const current = await tx.mediaAsset.findUniqueOrThrow({
          where: { id: asset.id },
        });
        const running = await tx.job.findFirst({
          where: {
            key: `media:${asset.id}`,
            status: "running",
            lockedAt: { gt: new Date(now.getTime() - 900000) },
          },
        });
        if (running || current.cleanedAt) return false;
        if (current.status !== "ready") {
          await tx.job.updateMany({
            where: {
              key: `media:${asset.id}`,
              status: { in: ["pending", "running"] },
            },
            data: {
              status: "failed",
              lastError: "UPLOAD_EXPIRED",
              leaseToken: null,
              lockedAt: null,
            },
          });
          await tx.mediaAsset.update({
            where: { id: asset.id },
            data: { status: "expired" },
          });
        }
        return current;
      });
      if (!claimed) continue;
      // Only server-owned UUID basenames are eligible; never follow stored paths.
      for (const suffix of [".upload", ".png", ".jpg", ".mp4"]) {
        await remove(path.join(root, `processed-${asset.id}${suffix}`));
        if (suffix === ".upload" || claimed.status !== "ready")
          await remove(path.join(root, `${asset.id}${suffix}`));
      }
      await db.mediaAsset.update({
        where: { id: asset.id },
        data: {
          cleanedAt: now,
          storageBytes:
            claimed.status === "ready"
              ? (claimed.processedSize ?? claimed.storageBytes)
              : 0n,
        },
      });
    }
  } while (after);
}
