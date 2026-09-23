import { Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import {
  mkdir,
  open,
  rename,
  unlink,
  readdir,
  stat,
  statfs,
} from "node:fs/promises";
import path from "node:path";
import { Actor } from "../operations/domain/contracts";
import { Database, json } from "../../shared/infrastructure/database";
import { requireRule } from "../../shared/domain/errors";
import { csvCell } from "../../shared/domain/csv";
import { DashboardService } from "./dashboard.service";
import { ExportQuery, exportQuery, exportScope } from "./export.contracts";

const queryKey = (value: unknown) =>
  JSON.stringify(
    Object.entries(exportQuery.parse(value)).sort(([a], [b]) =>
      a.localeCompare(b),
    ),
  );
@Injectable()
export class ExportService {
  constructor(
    private readonly db: Database,
    private readonly dashboards: DashboardService,
  ) {}
  private root() {
    return process.env.REPORT_EXPORT_ROOT
      ? path.resolve(process.env.REPORT_EXPORT_ROOT)
      : path.resolve(
          process.env.MEDIA_ROOT ?? "../../.volumes/media",
          "exports",
        );
  }
  private file(id: string, generation: string) {
    requireRule(
      /^[a-f0-9-]{36}$/.test(id) && /^[a-f0-9-]{36}$/.test(generation),
      "INVALID_EXPORT",
      "Export invalide.",
    );
    return path.join(this.root(), `${id}-${generation}.csv`);
  }
  create(actor: Actor, id: string, query: ExportQuery) {
    return this.dashboards.scope(
      actor,
      exportScope(query),
      async (tx, current) => {
        const old = await tx.reportExport.findUnique({ where: { id } });
        if (old) {
          requireRule(
            old.actorId === current.id &&
              queryKey(old.query) === queryKey(query),
            "OPERATION_REUSED",
            "Identifiant d’export déjà utilisé.",
            409,
          );
          return this.view(old);
        }
        // Export work has a bounded resource queue, independent of ordinary API reads.
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(42023,922)`;
        const outstanding = await tx.job.count({
          where: {
            kind: "report-export",
            status: { in: ["pending", "running"] },
          },
        });
        requireRule(
          outstanding < 5,
          "EXPORT_BUSY",
          "Des exports sont en préparation. Réessayez dans un instant.",
          409,
        );
        requireRule(
          (await tx.reportExport.count({
            where: {
              actorId: current.id,
              status: { in: ["pending", "processing"] },
              expiresAt: { gt: new Date() },
            },
          })) === 0,
          "EXPORT_BUSY",
          "Votre précédent export est encore en préparation.",
          409,
        );
        const item = await tx.reportExport.create({
          data: {
            id,
            actorId: current.id,
            sessionId: actor.sessionId,
            query: json(query),
            expiresAt: new Date(Date.now() + 86400000),
          },
        });
        await tx.job.create({
          data: {
            key: `export:${id}`,
            kind: "report-export",
            payload: { exportId: id },
          },
        });
        return this.view(item);
      },
    );
  }
  private view(item: {
    id: string;
    status: string;
    rows: number;
    error: string | null;
    createdAt: Date;
    expiresAt: Date;
  }) {
    return {
      id: item.id,
      status: item.status,
      rows: item.rows,
      error: item.error,
      createdAt: item.createdAt,
      expiresAt: item.expiresAt,
    };
  }
  async get(actor: Actor, id: string) {
    const item = await this.db.reportExport.findUnique({ where: { id } });
    requireRule(
      item && item.actorId === actor.id,
      "NOT_FOUND",
      "Export introuvable.",
      404,
    );
    requireRule(
      item.expiresAt > new Date(),
      "EXPORT_EXPIRED",
      "Cet export a expiré. Créez-en un nouveau.",
      410,
    );
    return this.dashboards.scope(
      actor,
      exportScope(exportQuery.parse(item.query)),
      async () => this.view(item),
    );
  }
  async download(actor: Actor, id: string) {
    await this.get(actor, id);
    const item = await this.db.reportExport.findUniqueOrThrow({
      where: { id },
    });
    requireRule(
      item.status === "ready" && item.generation,
      "EXPORT_PENDING",
      "L’export est en préparation.",
      409,
    );
    const file = this.file(id, item.generation);
    requireRule(
      await stat(file).then(
        () => true,
        () => false,
      ),
      "EXPORT_EXPIRED",
      "Le fichier n’est plus disponible. Créez un nouvel export.",
      410,
    );
    return file;
  }
  async process(
    id: string,
    generation: string,
    stillOwned: () => Promise<boolean>,
  ) {
    const item = await this.db.reportExport.findUniqueOrThrow({
      where: { id },
    });
    if (item.status === "ready" || item.expiresAt <= new Date()) return;
    const user = await this.db.user.findUniqueOrThrow({
      where: { id: item.actorId },
    });
    const actor: Actor = {
      id: user.id,
      name: user.name,
      email: user.email,
      platformAdmin: user.platformAdmin,
      sessionId: item.sessionId ?? undefined,
    };
    const query = exportQuery.parse(item.query);
    let temporary: string | undefined;
    try {
      await this.dashboards.scope(
        actor,
        exportScope(query),
        async (tx, current) => {
          await tx.reportExport.update({
            where: { id },
            data: { status: "processing", generation, error: null },
          });
          await tx.reportExportRow.deleteMany({ where: { exportId: id } });
          // Materialize the complete filtered rows in one database snapshot. Later
          // corrections cannot change half of an export while its file is streamed.
          let count: number;
          if ("kind" in query) {
            const source =
              query.resource === "movements"
                ? Prisma.sql`SELECT m.id,m."createdAt",u.name,st.name AS store,m.quantity::text AS value,m.reason AS reason
                FROM "StockMovement" m JOIN "User" u ON u.id=m."actorId" JOIN "Store" st ON st.id=m."storeId"
                JOIN "InventoryLot" l ON l.id=m."lotId"
                WHERE m."storeId"=${query.storeId}::uuid ${query.productId ? Prisma.sql`AND l."productId"=${query.productId}::uuid` : Prisma.empty}`
                : query.resource === "points"
                  ? Prisma.sql`SELECT p.id,p."createdAt",u.name,st.name AS store,p.amount::text AS value,p.kind AS reason
                FROM "PointsEntry" p JOIN "User" u ON u.id=p."userId" JOIN "Store" st ON st.id=p."storeId"
                WHERE p."storeId"=${query.storeId}::uuid AND p."userId"=${current.id}::uuid`
                  : Prisma.sql`SELECT a.id,a."createdAt",u.name,st.name AS store,a."targetId"::text AS value,a.action AS reason
                FROM "AuditEntry" a JOIN "User" u ON u.id=a."actorId" JOIN "Store" st ON st.id=a."storeId"
                WHERE a."storeId"=${query.storeId}::uuid`;
            count =
              await tx.$executeRaw(Prisma.sql`INSERT INTO "ReportExportRow" ("exportId","saleId",cells)
            SELECT ${id}::uuid,h.id,jsonb_build_array(h.id,
              to_char(h."createdAt" AT TIME ZONE 'UTC' AT TIME ZONE 'Africa/Tunis','DD/MM/YYYY HH24:MI:SS'),
              h.store,h.name,h.value,h.reason) FROM (${source}) h`);
          } else {
            const where = this.dashboards.where(query, current);
            count =
              await tx.$executeRaw(Prisma.sql`INSERT INTO "ReportExportRow" ("exportId","saleId",cells)
            SELECT ${id}::uuid,c."saleId",jsonb_build_array(c."saleId",c.day,g.name,s.name,u.name,c."netUnits"::text,c."netMillimes"::text)
            FROM (SELECT * FROM "SalesContribution" WHERE ${where}) c
            JOIN "Store" s ON s.id=c."storeId" JOIN "Organization" g ON g.id=c."organizationId" JOIN "User" u ON u.id=c."sellerId"`);
          }
          requireRule(
            count <= 2000000,
            "EXPORT_TOO_LARGE",
            "Choisissez une période plus courte ou un groupe plus précis.",
          );
          await tx.reportExport.update({
            where: { id },
            data: { rows: count },
          });
        },
      );
      await mkdir(this.root(), { recursive: true, mode: 0o700 });
      const disk = await statfs(this.root(), { bigint: true });
      let retained = 0;
      for (const name of await readdir(this.root())) {
        if (/^[a-f0-9-]{36}-[a-f0-9-]{36}\.csv(?:\.part)?$/.test(name))
          retained += (await stat(path.join(this.root(), name))).size;
      }
      requireRule(
        disk.bavail * disk.bsize > 1280n * 1024n * 1024n &&
          retained < 1024 * 1024 * 1024,
        "EXPORT_STORAGE",
        "Capacité temporaire des exports atteinte. Réessayez après expiration des anciens fichiers.",
        503,
      );
      const target = this.file(id, generation);
      temporary = `${target}.part`;
      const handle = await open(temporary, "w", 0o600);
      let after: string | undefined;
      let bytes = 0;
      try {
        await handle.write(
          "kind" in query
            ? `\uFEFFIdentifiant;Date (Tunisie);Magasin;Utilisateur;${query.resource === "points" ? "Points" : query.resource === "movements" ? "Quantité" : "Cible"};Motif\n`
            : "\uFEFFVente;Date de vente;Groupe;Magasin;Vendeur;Unités nettes;Ventes nettes (TND)\n",
        );
        for (;;) {
          requireRule(
            await stillOwned(),
            "EXPORT_LEASE_LOST",
            "La préparation doit reprendre.",
          );
          const rows = await this.dashboards.scope(
            actor,
            exportScope(query),
            (tx) =>
              tx.reportExportRow.findMany({
                where: {
                  exportId: id,
                  ...(after ? { saleId: { gt: after } } : {}),
                },
                orderBy: { saleId: "asc" },
                take: 1000,
              }),
          );
          if (!rows.length) break;
          const block =
            rows
              .map((row) => {
                const cells = [...(row.cells as (string | number)[])];
                if (!("kind" in query)) {
                  const millimes = BigInt(cells[6]!);
                  cells[6] = `${millimes / 1000n},${(millimes % 1000n).toString().padStart(3, "0")}`;
                }
                return cells.map(csvCell).join(";");
              })
              .join("\n") + "\n";
          bytes += Buffer.byteLength(block);
          requireRule(
            bytes <= 256 * 1024 * 1024,
            "EXPORT_TOO_LARGE",
            "Choisissez une période plus courte.",
          );
          await handle.write(block);
          after = rows.at(-1)!.saleId;
        }
        await handle.sync();
      } finally {
        await handle.close();
      }
      requireRule(
        await stillOwned(),
        "EXPORT_LEASE_LOST",
        "La préparation doit reprendre.",
      );
      await rename(temporary, target);
      temporary = undefined;
      await this.dashboards.scope(actor, exportScope(query), async (tx) => {
        requireRule(
          (
            await tx.reportExport.updateMany({
              where: { id, generation },
              data: { status: "ready" },
            })
          ).count === 1,
          "EXPORT_LEASE_LOST",
          "La préparation doit reprendre.",
        );
        await tx.reportExportRow.deleteMany({ where: { exportId: id } });
      });
    } catch (e) {
      await this.db.reportExport.updateMany({
        where: { id, generation },
        data: {
          status: "failed",
          error:
            "La préparation a échoué. Vérifiez votre accès puis réessayez.",
        },
      });
      if (temporary) await unlink(temporary).catch(() => {});
      throw e;
    }
  }
  async cleanup() {
    // Foreign-key cascading deletes temporary snapshot rows; files are disposable.
    await this.db.reportExport.deleteMany({
      where: { expiresAt: { lt: new Date() } },
    });
    await mkdir(this.root(), { recursive: true });
    for (const name of await readdir(this.root())) {
      if (!/^[a-f0-9-]{36}-[a-f0-9-]{36}\.csv(?:\.part)?$/.test(name)) continue;
      const file = path.join(this.root(), name),
        info = await stat(file);
      if (info.mtimeMs < Date.now() - 86400000)
        await unlink(file).catch(() => {});
    }
  }
}
