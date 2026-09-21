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
      if (input.type === "video")
        requireRule(input.mediaId, "MEDIA_REQUIRED", "Ajoutez une vidéo.");
      if (input.mediaId) {
        const media = await tx.mediaAsset.findUnique({
          where: { id: input.mediaId },
        });
        requireRule(
          media && media.ownerId === actor.id,
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
  async startUpload(
    actor: Actor,
    fileName: string,
    mime: string,
    size: number,
  ) {
    this.admin(actor);
    const id = randomUUID();
    await mkdir(this.root, { recursive: true, mode: 0o750 });
    return this.db.mediaAsset.create({
      data: {
        id,
        ownerId: actor.id,
        fileName,
        mime,
        size: BigInt(size),
        path: `${id}.upload`,
      },
      select: { id: true, status: true, received: true, size: true },
    });
  }
  async uploadStatus(actor: Actor, id: string) {
    this.admin(actor);
    const item = await this.db.mediaAsset.findFirst({
      where: { id, ownerId: actor.id },
      select: { id: true, status: true, received: true, size: true },
    });
    requireRule(item, "NOT_FOUND", "Téléversement introuvable.", 404);
    return item;
  }
  async chunk(actor: Actor, id: string, offset: number, buffer: Buffer) {
    this.admin(actor);
    requireRule(
      buffer.length > 0 && buffer.length <= 4 * 1024 * 1024,
      "CHUNK_SIZE",
      "Fragment de fichier invalide.",
    );
    return this.db.$transaction(
      async (tx) => {
        await tx.$queryRaw`SELECT id FROM "MediaAsset" WHERE id=${id}::uuid FOR UPDATE`;
        const media = await tx.mediaAsset.findFirst({
          where: { id, ownerId: actor.id },
        });
        requireRule(media, "NOT_FOUND", "Média introuvable.", 404);
        requireRule(
          media.status === "uploading",
          "UPLOAD_COMPLETE",
          "Le téléversement est déjà terminé.",
          409,
        );
        const handle = await open(path.join(this.root, media.path), "a+");
        await handle.close();
        const file = await open(path.join(this.root, media.path), "r+");
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
      },
      { timeout: 15000 },
    );
  }
  async media(actor: Actor, id: string) {
    const media = await this.db.mediaAsset.findUnique({ where: { id } });
    requireRule(
      media && media.status === "ready",
      "MEDIA_NOT_READY",
      "Média indisponible.",
      404,
    );
    if (!actor.platformAdmin) {
      const [content, product] = await Promise.all([
        this.db.trainingContent.findFirst({
          where: { mediaId: id, status: "published" },
        }),
        this.db.product.findFirst({ where: { imageId: id, active: true } }),
      ]);
      requireRule(content || product, "FORBIDDEN", "Média inaccessible.", 403);
    }
    return { path: path.join(this.root, media.path), mime: media.mime };
  }
}
