import { createHash, randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { audit } from "../core/audit";
import type { Database } from "../core/database";

/** One product of the catalogue file (apps/api/catalog/products.json), matched by its barcode. */
export interface CatalogEntry {
  barcode: string;
  reference: string;
  name: string;
  family: string;
  range: string;
  packageSize: string;
  description: string;
  instructions: string;
  ingredients: string;
  precautions: string;
  /** Relative to the catalogue folder. */
  image: string;
  /** Where the facts and the photo were checked (not stored in the database). */
  sources: string[];
}

const FIELDS = [
  "name",
  "family",
  "range",
  "packageSize",
  "description",
  "instructions",
  "ingredients",
  "precautions",
] as const;

export interface RefreshChange {
  barcode: string;
  name: string;
  action: "create" | "update";
  fields: string[];
  image: boolean;
}

export interface RefreshResult {
  changes: RefreshChange[];
  unchanged: number;
  /** Products in the database that the file does not mention (left as they are). */
  notInFile: string[];
}

export const catalogFolder = () =>
  process.env.CATALOG_ROOT ?? path.resolve(__dirname, "..", "..", "catalog");

const mediaRoot = () =>
  path.resolve(process.env.MEDIA_ROOT ?? "../../.volumes/media");

/**
 * Brings the products in line with the catalogue file: names, families, details and photos,
 * matched by barcode (a new barcode becomes a new product). Stock, sales, rewards and whether a
 * product is active are never touched. Nothing is written unless `apply` is set; running it again
 * changes nothing.
 */
export async function refreshCatalog(
  db: Database,
  entries: CatalogEntry[],
  options: { apply: boolean; folder?: string },
): Promise<RefreshResult> {
  const folder = options.folder ?? catalogFolder();
  const barcodes = entries.map((e) => e.barcode);
  if (new Set(barcodes).size !== barcodes.length)
    throw new Error("The catalogue file lists a barcode twice.");
  const photos = new Map<string, { bytes: Buffer; sha256: string }>();
  for (const e of entries) {
    const bytes = await readFile(path.join(folder, e.image));
    photos.set(e.barcode, {
      bytes,
      sha256: createHash("sha256").update(bytes).digest("hex"),
    });
  }

  return db.run("SYSTEM", async (tx) => {
    const [products, admin] = await Promise.all([
      tx.product.findMany(),
      tx.user.findFirst({
        where: { role: "ADMIN", status: "ACTIVE" },
        orderBy: { createdAt: "asc" },
        select: { id: true },
      }),
    ]);
    if (!admin) throw new Error("There is no active administrator.");
    const images = await tx.mediaAsset.findMany({
      where: {
        id: {
          in: products.map((p) => p.imageId).filter((x): x is string => !!x),
        },
      },
      select: { id: true, sha256: true },
    });
    const imageSha = new Map(images.map((i) => [i.id, i.sha256]));
    const byBarcode = new Map(products.map((p) => [p.barcode, p]));
    const result: RefreshResult = {
      changes: [],
      unchanged: 0,
      notInFile: products
        .filter((p) => !p.barcode || !barcodes.includes(p.barcode))
        .map((p) => `${p.barcode ?? p.reference} ${p.name}`),
    };

    for (const entry of entries) {
      const current = byBarcode.get(entry.barcode);
      const photo = photos.get(entry.barcode)!;
      const fields = FIELDS.filter((f) => !current || current[f] !== entry[f]);
      const image =
        !current?.imageId || imageSha.get(current.imageId) !== photo.sha256;
      if (current && !fields.length && !image) {
        result.unchanged++;
        continue;
      }
      result.changes.push({
        barcode: entry.barcode,
        name: entry.name,
        action: current ? "update" : "create",
        fields: [...fields],
        image,
      });
      if (!options.apply) continue;

      const imageId = image
        ? await storePhoto(tx, admin.id, entry, photo)
        : current!.imageId;
      const data = {
        ...Object.fromEntries(FIELDS.map((f) => [f, entry[f]])),
        imageId,
      } as Record<(typeof FIELDS)[number], string> & { imageId: string | null };
      const product = current
        ? await tx.product.update({ where: { id: current.id }, data })
        : await tx.product.create({
            data: {
              ...data,
              reference: entry.reference,
              barcode: entry.barcode,
            },
          });
      await audit(
        tx,
        null,
        current ? "product.refreshed" : "product.created",
        "Product",
        product.id,
        { fields, image, source: "catalog" },
      );
    }
    return result;
  });
}

/** A photo already stored with the same content is reused; otherwise it is written once. */
async function storePhoto(
  tx: Parameters<Parameters<Database["run"]>[1]>[0],
  ownerId: string,
  entry: CatalogEntry,
  photo: { bytes: Buffer; sha256: string },
) {
  const known = await tx.mediaAsset.findFirst({
    where: { sha256: photo.sha256, purpose: "PRODUCT" },
    select: { id: true },
  });
  if (known) return known.id;
  const id = randomUUID();
  const file = `${id}.jpg`;
  await mkdir(mediaRoot(), { recursive: true });
  await writeFile(path.join(mediaRoot(), file), photo.bytes, {
    flag: "wx",
    mode: 0o640,
  });
  await tx.mediaAsset.create({
    data: {
      id,
      ownerId,
      purpose: "PRODUCT",
      fileName: `${entry.barcode}.jpg`,
      mime: "image/jpeg",
      size: BigInt(photo.bytes.length),
      sha256: photo.sha256,
      path: file,
    },
  });
  return id;
}
