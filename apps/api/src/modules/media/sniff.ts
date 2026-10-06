/** What a file really is, judged by its first bytes, never by its name or declared type. */
export type Sniffed = { mime: string; ext: string };

export function sniff(head: Buffer): Sniffed | null {
  if (
    head.length >= 3 &&
    head[0] === 0xff &&
    head[1] === 0xd8 &&
    head[2] === 0xff
  )
    return { mime: "image/jpeg", ext: "jpg" };
  if (
    head.length >= 8 &&
    head
      .subarray(0, 8)
      .equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
  )
    return { mime: "image/png", ext: "png" };
  if (
    head.length >= 12 &&
    head.subarray(0, 4).toString() === "RIFF" &&
    head.subarray(8, 12).toString() === "WEBP"
  )
    return { mime: "image/webp", ext: "webp" };
  if (head.length >= 5 && head.subarray(0, 5).toString() === "%PDF-")
    return { mime: "application/pdf", ext: "pdf" };
  if (head.length >= 12 && head.subarray(4, 8).toString() === "ftyp")
    return { mime: "video/mp4", ext: "mp4" };
  return null;
}

const MiB = 1024 * 1024;

/** Allowed formats and the largest size for each use of a file. */
export const mediaRules = {
  PROOF: {
    mimes: ["image/jpeg", "image/png", "image/webp"],
    maxBytes: 12 * MiB,
  },
  PRODUCT: {
    mimes: ["image/jpeg", "image/png", "image/webp"],
    maxBytes: 8 * MiB,
  },
  TRAINING: {
    mimes: [
      "image/jpeg",
      "image/png",
      "image/webp",
      "application/pdf",
      "video/mp4",
    ],
    maxBytes: 300 * MiB,
  },
} as const;
