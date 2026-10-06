import { Injectable } from "@nestjs/common";
import type { MediaPurpose } from "@prisma/client";
import { createHash, randomUUID } from "node:crypto";
import { createWriteStream } from "node:fs";
import { mkdir, rename, statfs, unlink } from "node:fs/promises";
import path from "node:path";
import type { Readable } from "node:stream";
import type { Actor } from "../../core/actor";
import { Database } from "../../core/database";
import { DomainError, notFound, requireRule } from "../../core/errors";
import { AuthService } from "../auth/auth.service";
import { mediaRules, sniff } from "./sniff";

const root = () =>
  path.resolve(process.env.MEDIA_ROOT ?? "../../.volumes/media");

@Injectable()
export class MediaService {
  constructor(
    private readonly db: Database,
    private readonly auth: AuthService,
  ) {}

  /** Who may upload for which purpose. */
  private allowed(actor: Actor, purpose: MediaPurpose) {
    return purpose === "PROOF" ? true : actor.role === "ADMIN";
  }

  /** Stream an upload to disk, checking size and real content as it arrives. */
  async upload(
    actor: Actor,
    purpose: MediaPurpose,
    fileName: string,
    body: Readable,
  ) {
    requireRule(
      this.allowed(actor, purpose),
      "FORBIDDEN",
      "You cannot upload this kind of file.",
      403,
    );
    await this.auth.throttle(`upload:${actor.id}`, actor.role === "ADMIN" ? 400 : 80);
    const rule = mediaRules[purpose];
    const dir = root();
    await mkdir(dir, { recursive: true });
    const free = await statfs(dir, { bigint: true });
    requireRule(
      free.bavail * free.bsize > 1_073_741_824n,
      "STORAGE_LOW",
      "The server is low on storage. Try again later.",
      503,
    );

    const id = randomUUID();
    const temp = path.join(dir, `${id}.part`);
    const hash = createHash("sha256");
    let size = 0;
    let head = Buffer.alloc(0);
    const out = createWriteStream(temp, { flags: "wx", mode: 0o640 });
    try {
      await new Promise<void>((resolve, reject) => {
        body.on("data", (chunk: Buffer) => {
          size += chunk.length;
          if (size > rule.maxBytes) {
            reject(
              new DomainError("FILE_TOO_LARGE", "This file is too large.", 413),
            );
            body.destroy();
            return;
          }
          if (head.length < 16)
            head = Buffer.concat([head, chunk]).subarray(0, 16);
          hash.update(chunk);
          if (!out.write(chunk)) {
            body.pause();
            out.once("drain", () => body.resume());
          }
        });
        body.on("end", () => out.end(() => resolve()));
        body.on("error", reject);
        body.on("aborted", () =>
          reject(
            new DomainError(
              "UPLOAD_ABORTED",
              "The upload was interrupted.",
              400,
            ),
          ),
        );
        out.on("error", reject);
      });
      requireRule(size > 0, "EMPTY_FILE", "The file is empty.", 400);
      const type = sniff(head);
      requireRule(
        type && (rule.mimes as readonly string[]).includes(type.mime),
        "UNSUPPORTED_FILE",
        "This file type is not supported.",
        415,
      );
      const finalName = `${id}.${type.ext}`;
      await rename(temp, path.join(dir, finalName));
      const asset = await this.db.run(actor, (tx) =>
        tx.mediaAsset.create({
          data: {
            id,
            ownerId: actor.id,
            purpose,
            regionId: purpose === "PROOF" ? actor.regionId : null,
            fileName: path.basename(fileName).slice(0, 120) || "file",
            mime: type.mime,
            size: BigInt(size),
            sha256: hash.digest("hex"),
            path: finalName,
          },
          select: {
            id: true,
            mime: true,
            size: true,
            sha256: true,
            purpose: true,
          },
        }),
      );
      return { ...asset, size: Number(asset.size) };
    } catch (error) {
      out.destroy();
      await unlink(temp).catch(() => undefined);
      throw error;
    }
  }

  /** The file to send back; row-level security decides whether this person may see it. */
  async open(actor: Actor, id: string) {
    const asset = await this.db.run(actor, (tx) =>
      tx.mediaAsset.findUnique({ where: { id } }),
    );
    if (!asset) throw notFound("File");
    return {
      file: path.join(root(), path.basename(asset.path)),
      mime: asset.mime,
      sha256: asset.sha256,
    };
  }
}
