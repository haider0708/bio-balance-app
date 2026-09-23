import { imageOutputLimit, videoOutputLimit } from "./media-storage";
import { spawn } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { createReadStream } from "node:fs";
import { open, rename, stat, unlink } from "node:fs/promises";
import path from "node:path";
import { Database } from "../../../shared/infrastructure/database";

async function digest(file: string) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  return hash.digest("hex");
}
function run(
  program: string,
  args: string[],
  timeout = 600_000,
): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(program, args, { stdio: ["ignore", "pipe", "ignore"] });
    let output = "",
      settled = false;
    const done = (error?: Error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      error ? reject(error) : resolve(output);
    };
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      done(new Error("MEDIA_TIMEOUT"));
    }, timeout);
    child.stdout.on("data", (chunk) => {
      output += chunk.toString();
      if (output.length > 64 * 1024) {
        child.kill("SIGKILL");
        done(new Error("MEDIA_OUTPUT_LIMIT"));
      }
    });
    child.on("error", () => done(new Error("MEDIA_TOOL_UNAVAILABLE")));
    child.on("exit", (code) =>
      done(code === 0 ? undefined : new Error("MEDIA_PROCESSING_FAILED")),
    );
  });
}
export class MediaProcessor {
  constructor(
    private readonly db: Database,
    private readonly root = path.resolve(
      process.env.MEDIA_ROOT ?? "../../.volumes/media",
    ),
  ) {}
  async process(id: string) {
    const media = await this.db.mediaAsset.findUniqueOrThrow({ where: { id } });
    if (media.status === "ready") {
      if (!media.sha256 || media.processedSize === null) {
        const existing = path.join(this.root, media.path);
        await this.db.mediaAsset.update({
          where: { id },
          data: {
            sha256: await digest(existing),
            processedSize: BigInt((await stat(existing)).size),
          },
        });
      }
      await this.thumbnail(id);
      await this.removeAcceptedSource(id);
      return;
    }
    if (media.status !== "processing") throw new Error("MEDIA_NOT_UPLOADED");
    const source = path.join(this.root, `${media.id}.upload`);
    if (BigInt((await stat(source)).size) !== media.size)
      throw new Error("MEDIA_SIZE_MISMATCH");
    if (media.expectedSha256 && (await digest(source)) !== media.expectedSha256)
      throw new Error("MEDIA_CHECKSUM_MISMATCH");
    const video = media.mime.startsWith("video/");
    if (video) {
      const file = await open(source, "r"),
        header = Buffer.from(new Uint8Array(12));
      try {
        await file.read(header, 0, 12, 0);
      } finally {
        await file.close();
      }
      if (header.subarray(4, 8).toString("ascii") !== "ftyp")
        throw new Error("INVALID_VIDEO");
    }
    if (!video) {
      if (media.size > 10n * 1024n * 1024n) throw new Error("IMAGE_TOO_LARGE");
      const handle = await open(source, "r");
      const signature = Buffer.alloc(8);
      try {
        await handle.read(signature, 0, 8, 0);
      } finally {
        await handle.close();
      }
      if (
        media.mime === "image/png"
          ? !signature.equals(Buffer.from("89504e470d0a1a0a", "hex"))
          : media.mime !== "image/jpeg" ||
            signature[0] !== 255 ||
            signature[1] !== 216
      )
        throw new Error("INVALID_IMAGE");
      const probe = JSON.parse(
        await run(
          "ffprobe",
          [
            "-v",
            "error",
            "-protocol_whitelist",
            "file,pipe",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height",
            "-of",
            "json",
            source,
          ],
          15_000,
        ),
      );
      const dimensions = probe.streams?.[0];
      if (
        !dimensions ||
        dimensions.width <= 0 ||
        dimensions.height <= 0 ||
        dimensions.width * dimensions.height > 25_000_000
      )
        throw new Error("IMAGE_DIMENSIONS");
    }
    const target = `${media.id}.${video ? "mp4" : media.mime === "image/png" ? "png" : "jpg"}`;
    const output = path.join(this.root, `processed-${target}`);
    const common = [
      "-nostdin",
      "-y",
      "-max_alloc",
      "67108864",
      "-threads",
      "2",
      "-filter_threads",
      "2",
      "-protocol_whitelist",
      "file,pipe",
      ...(video
        ? ["-f", "mov", "-enable_drefs", "0", "-use_absolute_path", "0"]
        : []),
      "-i",
      source,
      "-map_metadata",
      "-1",
    ];
    const encoding = video
      ? [
          "-map",
          "0:v:0",
          "-map",
          "0:a:0?",
          "-c:v",
          "libx264",
          "-preset",
          "fast",
          "-threads",
          "2",
          "-vf",
          "scale=1280:720:force_original_aspect_ratio=decrease:force_divisible_by=2,format=yuv420p",
          "-c:a",
          "aac",
          "-movflags",
          "+faststart",
        ]
      : [
          "-frames:v",
          "1",
          "-threads",
          "2",
          "-vf",
          "scale='min(1600,iw)':'min(1600,ih)':force_original_aspect_ratio=decrease",
        ];
    await run(
      "ffmpeg",
      [
        ...common,
        ...encoding,
        "-fs",
        String(video ? videoOutputLimit : imageOutputLimit),
        output,
      ],
      video ? 600_000 : 60_000,
    );
    const outputSize = BigInt((await stat(output)).size);
    if (outputSize >= (video ? videoOutputLimit : imageOutputLimit))
      throw new Error("MEDIA_OUTPUT_LIMIT");
    await rename(output, path.join(this.root, target));
    const published = await this.db.mediaAsset.updateMany({
      where: { id: media.id, status: "processing" },
      data: {
        status: "ready",
        path: target,
        mime: video ? "video/mp4" : media.mime,
        sha256: await digest(path.join(this.root, target)),
        processedSize: outputSize,
        storageBytes: media.size + outputSize,
      },
    });
    if (!published.count) {
      const current = await this.db.mediaAsset.findUniqueOrThrow({
        where: { id },
      });
      if (current.status !== "ready") {
        await unlink(path.join(this.root, target)).catch((error) => {
          if (error.code !== "ENOENT") throw error;
        });
        throw new Error("MEDIA_UPLOAD_EXPIRED");
      }
    }
    await this.thumbnail(id);
    await this.removeAcceptedSource(id);
  }
  async thumbnail(id: string) {
    const media = await this.db.mediaAsset.findUniqueOrThrow({ where: { id } });
    if (
      media.status !== "ready" ||
      !media.mime.startsWith("image/") ||
      media.thumbnailPath
    )
      return;
    const target = `${id}-thumbnail.png`;
    const output = path.join(this.root, `processed-${randomUUID()}-${target}`);
    await run(
      "ffmpeg",
      [
        "-nostdin",
        "-y",
        "-max_alloc",
        "67108864",
        "-threads",
        "1",
        "-filter_threads",
        "1",
        "-protocol_whitelist",
        "file,pipe",
        "-i",
        path.join(this.root, media.path),
        "-map_metadata",
        "-1",
        "-frames:v",
        "1",
        "-vf",
        "scale=384:384:force_original_aspect_ratio=decrease",
        "-fs",
        "1048576",
        output,
      ],
      30000,
    );
    const size = BigInt((await stat(output)).size);
    if (size >= 1048576n) throw new Error("THUMBNAIL_SIZE");
    const sha256 = await digest(output);
    await rename(output, path.join(this.root, target));
    await this.db.mediaAsset.updateMany({
      where: { id, thumbnailPath: null },
      data: {
        thumbnailPath: target,
        thumbnailSize: size,
        thumbnailSha256: sha256,
        storageBytes: { increment: size },
      },
    });
  }
  private async removeAcceptedSource(id: string) {
    const media = await this.db.mediaAsset.findUniqueOrThrow({ where: { id } });
    if (
      media.status !== "ready" ||
      media.processedSize === null ||
      media.cleanedAt
    )
      return;
    // Accepted chunk hashes preserve idempotent retries after the source is removed.
    const chunks = await this.db.uploadChunk.aggregate({
      where: { mediaId: id },
      _sum: { length: true },
    });
    if (BigInt(chunks._sum.length ?? 0) === media.size) {
      await unlink(path.join(this.root, `${id}.upload`)).catch((error) => {
        if (error.code !== "ENOENT") throw error;
      });
      await this.db.mediaAsset.update({
        where: { id },
        data: {
          storageBytes: media.processedSize + (media.thumbnailSize ?? 0n),
          cleanedAt: new Date(),
        },
      });
    }
  }
}
