import "reflect-metadata";
import { readFile } from "node:fs/promises";
import path from "node:path";
import {
  type CatalogEntry,
  catalogFolder,
  refreshCatalog,
} from "./catalog/refresh";
import { Database } from "./core/database";

/**
 * The product catalogue, kept in apps/api/catalog (products.json and one photo per barcode).
 *   node dist/catalog.js refresh           shows what would change
 *   node dist/catalog.js refresh --apply   applies it (names, details and photos; never stock or sales)
 */
async function main() {
  if (process.argv[2] !== "refresh") throw new Error("Use: refresh [--apply]");
  const apply = process.argv.includes("--apply");
  const entries = JSON.parse(
    await readFile(path.join(catalogFolder(), "products.json"), "utf8"),
  ) as CatalogEntry[];
  const db = new Database();
  try {
    const result = await refreshCatalog(db, entries, { apply });
    for (const c of result.changes)
      console.log(
        `${apply ? "" : "would "}${c.action} ${c.barcode} ${c.name}` +
          (c.fields.length ? ` [${c.fields.join(", ")}]` : "") +
          (c.image ? " [photo]" : ""),
      );
    for (const p of result.notInFile)
      console.log(`not in the catalogue file, left as it is: ${p}`);
    console.log(
      `${result.changes.length} ${apply ? "changed" : "to change"}, ${result.unchanged} unchanged.`,
    );
  } finally {
    await db.$disconnect();
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
