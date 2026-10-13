import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { Database } from "../src/core/database";
import { type CatalogEntry, refreshCatalog } from "../src/catalog/refresh";
import { fakeJpeg, resetDatabase, startApi, type Api } from "./helpers";
import { buildWorld, levels, stockPlace, type World } from "./world";

/** The catalogue file brings names, details and photos in line; stock and sales are never touched. */
let api: Api;
let w: World;
let db: Database;
let folder: string;

const entry = (
  barcode: string,
  name: string,
  extra: Partial<CatalogEntry> = {},
): CatalogEntry => ({
  barcode,
  reference: `REF-${barcode}`,
  name,
  family: "Serums",
  range: "Super Serum",
  packageSize: "30 ml",
  description: "Un sérum.",
  instructions: "Le soir.",
  ingredients: "Aqua",
  precautions: "",
  image: `images/${barcode}.jpg`,
  sources: [],
  ...extra,
});

beforeAll(async () => {
  await resetDatabase();
  api = await startApi();
  db = api.app.get(Database);
  w = await buildWorld(api);
  folder = await mkdtemp(path.join(tmpdir(), "catalog-"));
  process.env.MEDIA_ROOT = await mkdtemp(path.join(tmpdir(), "media-"));
  await mkdir(path.join(folder, "images"));
  for (const barcode of ["6000000000001", "6000000000002", "6000000000009"])
    await writeFile(path.join(folder, "images", `${barcode}.jpg`), fakeJpeg());
});

afterAll(() => api?.close());

describe("refreshing the catalogue", () => {
  it("shows the changes first, applies them once, and never touches stock", async () => {
    const pdv = w.depotId;
    await stockPlace(w, pdv, w.nord, [10, 20, 30]);
    const entries = [
      entry("6000000000001", "BIOBALANCE SUPER SERUM VITAMINE C 30ML"),
      entry("6000000000002", "Serum Niacinamide", { family: "Serums" }),
      entry("6000000000009", "BIOBALANCE NOUVEAU PRODUIT 50ML"),
    ];

    const preview = await refreshCatalog(db, entries, {
      apply: false,
      folder,
    });
    expect(preview.changes.map((c) => [c.barcode, c.action])).toEqual([
      ["6000000000001", "update"],
      ["6000000000002", "update"],
      ["6000000000009", "create"],
    ]);
    expect(preview.changes[0]!.fields).toContain("name");
    expect(preview.notInFile).toEqual(["6000000000003 Shampoo Argan"]);
    // A preview writes nothing.
    expect((await w.a.get(`/v1/products/${w.products[0]!.id}`)).body.name).toBe(
      "Serum Vitamin C",
    );

    await refreshCatalog(db, entries, { apply: true, folder });
    const first = (await w.a.get(`/v1/products/${w.products[0]!.id}`)).body;
    expect(first).toMatchObject({
      name: "BIOBALANCE SUPER SERUM VITAMINE C 30ML",
      range: "Super Serum",
      packageSize: "30 ml",
      active: true,
    });
    // The photo is stored and served like any product photo.
    const photo = await fetch(`${api.url}/v1/media/${first.imageId}`, {
      headers: { Authorization: `Bearer ${w.admin.token}` },
    });
    expect(photo.status).toBe(200);
    expect(Buffer.from(await photo.arrayBuffer())).toEqual(
      await readFile(path.join(folder, "images", "6000000000001.jpg")),
    );
    const created = (await w.a.get("/v1/products?q=NOUVEAU")).body as any[];
    expect(created).toHaveLength(1);
    expect(created[0]).toMatchObject({ barcode: "6000000000009" });
    expect(await levels(w, pdv)).toMatchObject({
      "BIOBALANCE SUPER SERUM VITAMINE C 30ML": 10,
      "Serum Niacinamide": 20,
      "Shampoo Argan": 30,
    });

    // Running it again changes nothing.
    const again = await refreshCatalog(db, entries, { apply: true, folder });
    expect(again.changes).toEqual([]);
    expect(again.unchanged).toBe(3);
  });

  it("refuses a file that lists a barcode twice", async () => {
    await expect(
      refreshCatalog(
        db,
        [entry("6000000000001", "A"), entry("6000000000001", "B")],
        { apply: false, folder },
      ),
    ).rejects.toThrow("twice");
  });
});
