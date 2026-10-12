import "reflect-metadata";
import { unlink } from "node:fs/promises";
import path from "node:path";
import { NestFactory } from "@nestjs/core";
import { Client } from "pg";
import { AppModule } from "./app.module";
import { purgeDemo } from "./demo/purge";
import { demoServices, seedDemo } from "./demo/seed";

/**
 * The demonstration region for the store reviewers and for showing the app (docs/runbook.md).
 *   node dist/demo.js seed    builds it (DEMO_RESPONSABLE_PASSWORD, DEMO_VENDEUR_PASSWORD, DEMO_DAYS)
 *   node dist/demo.js purge   removes all of it
 * Needs MIGRATION_DATABASE_URL (the database owner) next to the usual settings.
 */
async function main() {
  const command = process.argv[2];
  const ownerUrl = process.env.MIGRATION_DATABASE_URL;
  if (!ownerUrl) throw new Error("MIGRATION_DATABASE_URL is required.");
  const owner = new Client({ connectionString: ownerUrl });
  await owner.connect();
  try {
    if (command === "purge") {
      const result = await purgeDemo(owner);
      for (const file of result.files)
        await unlink(
          path.join(
            process.env.MEDIA_ROOT ?? "/var/lib/biobalance/media",
            file,
          ),
        ).catch(() => undefined);
      console.log(JSON.stringify(result, null, 2));
      return;
    }
    if (command !== "seed") throw new Error("Use: seed | purge");
    const responsable = process.env.DEMO_RESPONSABLE_PASSWORD ?? "";
    const vendeur = process.env.DEMO_VENDEUR_PASSWORD ?? "";
    if (responsable.length < 10 || vendeur.length < 10)
      throw new Error("Both demo passwords need at least 10 characters.");
    const app = await NestFactory.createApplicationContext(AppModule, {
      logger: false,
    });
    try {
      const result = await seedDemo(demoServices(app), owner, {
        days: Number(process.env.DEMO_DAYS) || 60,
        passwords: { responsable, vendeur },
        log: (m) => console.error(m),
      });
      console.log(JSON.stringify(result, null, 2));
    } finally {
      await app.close();
    }
  } finally {
    await owner.end();
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
