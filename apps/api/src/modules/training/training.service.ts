import { Prisma, MediaAsset } from "@prisma/client";
import { Injectable } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { mkdir, open } from "node:fs/promises";
import path from "node:path";
import sanitizeHtml from "sanitize-html";
import { Database, json } from "../../shared/infrastructure/database";
import { Actor } from "../operations/domain/contracts";
import { requireRule } from "../../shared/domain/errors";
@Injectable()
export class TrainingService {
  readonly root = path.resolve(
    process.env.MEDIA_ROOT ?? "../../.volumes/media",
  );
  constructor(private readonly db: Database) {}
  private admin(actor: Actor) {
    requireRule(
      actor.platformAdmin,
      "FORBIDDEN",
      "Accès réservé à BioBalance.",
      403,
    );
  }
  list(actor: Actor, after?: string) {
    return this.db.trainingContent.findMany({
      where: {
        ...(!actor.platformAdmin ? { status: "published" } : {}),
        ...(after ? { id: { gt: after } } : {}),
      },
      orderBy: { id: "asc" },
      take: 100,
    });
  }
  async save(
    actor: Actor,
    input: {
      id?: string;
      title: string;
      body: string;
      type: string;
      mediaId?: string;
      productIds: string[];
      status: string;
      expectedVersion?: number;
    },
  ) {
    this.admin(actor);
    return this.db.$transaction(async (tx) => {
      this.admin(await this.globalActor(tx, actor));
      if (input.type === "video")
        requireRule(input.mediaId, "MEDIA_REQUIRED", "Ajoutez une vidéo.");
      if (input.mediaId) {
        const media = await tx.mediaAsset.findUnique({
          where: { id: input.mediaId },
        });
        requireRule(
          media &&
            media.ownerId === actor.id &&
            media.purpose === "training" &&
            !media.storeId,
          "MEDIA_NOT_FOUND",
          "Média introuvable.",
        );
        if (input.status === "published")
          requireRule(
            media.status === "ready",
            "MEDIA_PROCESSING",
            "Le traitement du média doit être terminé avant publication.",
          );
      }
      const { id, expectedVersion, ...values } = input;
      const data = {
        ...values,
        body: sanitizeHtml(values.body, {
          allowedTags: [
            "p",
            "br",
            "h2",
            "h3",
            "strong",
            "em",
            "ul",
            "ol",
            "li",
            "blockquote",
            "a",
          ],
          allowedAttributes: { a: ["href", "title"] },
          allowedSchemes: ["https"],
        }),
      };
      const old = id
        ? await tx.trainingContent.findUnique({ where: { id } })
        : null;
      requireRule(
        !id || old?.version === expectedVersion,
        "VERSION_CONFLICT",
        "Ce contenu a été modifié.",
        409,
      );
      const result = id
        ? await tx.trainingContent.update({
            where: { id },
            data: { ...data, version: { increment: 1 } },
          })
        : await tx.trainingContent.create({
            data: { ...data, authorId: actor.id },
          });
      await tx.auditEntry.create({
        data: {
          actorId: actor.id,
          action: "training.save",
          targetId: result.id,
          details: json({ status: result.status, version: result.version }),
        },
      });
      return result;
    });
  }
  private async globalActor(tx: Prisma.TransactionClient, actor: Actor) {
    await this.db.verifySession(tx, actor);
    const user = await tx.user.findUnique({ where: { id: actor.id } });
    requireRule(
      user && !user.disabled,
      "ACCESS_DISABLED",
      "Votre accès a été désactivé.",
      403,
    );
    return user;
  }
  private async assetTransaction<T>(
    actor: Actor,
    id: string,
    write: boolean,
    work: (
      tx: Prisma.TransactionClient,
      media: MediaAsset,
      manager: boolean,
    ) => Promise<T>,
  ) {
    const asset = await this.db.mediaAsset.findUnique({ where: { id } });
    requireRule(asset, "NOT_FOUND", "Média introuvable.", 404);
    const execute = async (
      tx: Prisma.TransactionClient,
      manager: boolean,
      admin: boolean,
    ) => {
      const media = await tx.mediaAsset.findUniqueOrThrow({ where: { id } });
      requireRule(
        !write || (manager && (media.ownerId === actor.id || admin)),
        "FORBIDDEN",
        "Téléversement inaccessible.",
        403,
      );
      return work(tx, media, manager);
    };
    if (asset.storeId && asset.organizationId)
      return this.db.scoped(
        actor,
        asset.organizationId,
        asset.storeId,
        (tx, scope) =>
          execute(
            tx,
            scope.permissions.includes("manage"),
            scope.actor.platformAdmin,
          ),
      );
    return this.db.$transaction(
      async (tx) => {
        const user = await this.globalActor(tx, actor);
        return execute(tx, user.platformAdmin, user.platformAdmin);
      },
      { timeout: 15000 },
    );
  }
  async startUpload(
    actor: Actor,
    fileName: string,
    mime: string,
    size: number,
    context: {
      purpose?: "training" | "catalog" | "store" | "reward";
      organizationId?: string;
      storeId?: string;
      sha256?: string;
    } = {},
  ) {
    const purpose = context.purpose ?? "training";
    const scoped = purpose === "store" || purpose === "reward";
    requireRule(
      scoped === Boolean(context.organizationId && context.storeId) &&
        (scoped || (!context.organizationId && !context.storeId)),
      "MEDIA_SCOPE",
      "Emplacement du média invalide.",
    );
    requireRule(
      purpose === "training" || ["image/jpeg", "image/png"].includes(mime),
      "IMAGE_REQUIRED",
      "Choisissez une image JPEG ou PNG.",
    );
    requireRule(
      !mime.startsWith("image/") || size <= 10 * 1024 * 1024,
      "IMAGE_TOO_LARGE",
      "L’image ne doit pas dépasser 10 Mo.",
    );
    const id = randomUUID();
    const create = async (tx: Prisma.TransactionClient) =>
      tx.mediaAsset.create({
        data: {
          id,
          ownerId: actor.id,
          fileName,
          mime,
          size: BigInt(size),
          path: `${id}.upload`,
          purpose,
          organizationId: context.organizationId,
          storeId: context.storeId,
          expectedSha256: context.sha256,
        },
        select: {
          id: true,
          status: true,
          received: true,
          size: true,
          expectedSha256: true,
        },
      });
    await mkdir(this.root, { recursive: true, mode: 0o750 });
    if (scoped)
      return this.db.scoped(
        actor,
        context.organizationId!,
        context.storeId!,
        async (tx, scope) => {
          requireRule(
            scope.permissions.includes("manage"),
            "FORBIDDEN",
            "Accès réservé au responsable.",
            403,
          );
          return create(tx);
        },
      );
    return this.db.$transaction(async (tx) => {
      const user = await this.globalActor(tx, actor);
      this.admin(user);
      return create(tx);
    });
  }
  async uploadStatus(actor: Actor, id: string) {
    return this.assetTransaction(actor, id, true, async (_tx, item) => ({
      id: item.id,
      status: item.status,
      received: item.received,
      size: item.size,
      expectedSha256: item.expectedSha256,
      sha256: item.sha256,
      processedSize: item.processedSize,
    }));
  }
  async chunk(actor: Actor, id: string, offset: number, buffer: Buffer) {
    requireRule(
      buffer.length > 0 && buffer.length <= 4 * 1024 * 1024,
      "CHUNK_SIZE",
      "Fragment de fichier invalide.",
    );
    return this.assetTransaction(actor, id, true, async (tx) => {
      await tx.$queryRaw`SELECT id FROM "MediaAsset" WHERE id=${id}::uuid FOR UPDATE`;
      const media = await tx.mediaAsset.findUniqueOrThrow({ where: { id } });
      requireRule(
        BigInt(offset + buffer.length) <= media.size,
        "UPLOAD_OFFSET",
        "Fragment hors du fichier.",
        409,
      );
      const source = path.join(this.root, `${id}.upload`);
      const handle = await open(source, "a+");
      await handle.close();
      const file = await open(source, "r+");
      try {
        if (BigInt(offset) < media.received) {
          const existing = Buffer.alloc(buffer.length);
          const read = await file.read(existing, 0, buffer.length, offset);
          requireRule(
            read.bytesRead === buffer.length && existing.equals(buffer),
            "CHUNK_CONFLICT",
            "Fragment différent de celui déjà reçu.",
            409,
          );
          return { received: media.received, status: media.status };
        }
        requireRule(
          media.status === "uploading",
          "UPLOAD_COMPLETE",
          "Le téléversement est déjà terminé.",
          409,
        );
        requireRule(
          BigInt(offset) === media.received &&
            BigInt(offset + buffer.length) <= media.size,
          "UPLOAD_OFFSET",
          "Reprenez à la dernière position confirmée.",
          409,
        );
        let written = 0;
        while (written < buffer.length) {
          const result = await file.write(
            buffer,
            written,
            buffer.length - written,
            offset + written,
          );
          written += result.bytesWritten;
        }
        await file.sync();
      } finally {
        await file.close();
      }
      const received = BigInt(offset + buffer.length);
      const status = received === media.size ? "processing" : "uploading";
      await tx.mediaAsset.update({
        where: { id },
        data: { received, status },
      });
      if (status === "processing")
        await tx.job.create({
          data: {
            kind: "media",
            key: `media:${id}`,
            payload: { mediaId: id },
          },
        });
      return { received, status };
    });
  }
  async media(actor: Actor, id: string) {
    return this.assetTransaction(
      actor,
      id,
      false,
      async (tx, media, manager) => {
        requireRule(
          media.status === "ready",
          "MEDIA_NOT_READY",
          "Média indisponible.",
          404,
        );
        if (!manager) {
          if (media.storeId) {
            const store = await tx.store.findFirst({
              where: { id: media.storeId, imageId: id },
            });
            const reward = await tx.reward.findFirst({
              where: { storeId: media.storeId, imageId: id, active: true },
            });
            requireRule(
              store || reward,
              "FORBIDDEN",
              "Média inaccessible.",
              403,
            );
          } else {
            const content = await tx.trainingContent.findFirst({
              where: { mediaId: id, status: "published" },
            });
            const product = await tx.product.findFirst({
              where: { imageId: id, active: true },
            });
            requireRule(
              content || product,
              "FORBIDDEN",
              "Média inaccessible.",
              403,
            );
          }
        }
        return {
          path: path.join(this.root, media.path),
          mime: media.mime,
          sha256: media.sha256,
          size: media.processedSize,
        };
      },
    );
  }
}
