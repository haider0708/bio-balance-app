import "reflect-metadata";
import { unlink } from "node:fs/promises";
import path from "node:path";
import { NestFactory } from "@nestjs/core";
import { Client } from "pg";
import { AppModule } from "./app.module";
import { reviewPasswordHashes, wipeNetwork } from "./demo/fresh-start";
import { purgeDemo } from "./demo/purge";
import { type DemoOptions, demoServices, seedDemo } from "./demo/seed";

/**
 * The test region of the store reviewers (docs/runbook.md, "The test region").
 *   node dist/demo.js seed                             builds it (DEMO_RESPONSABLE_PASSWORD, DEMO_VENDEUR_PASSWORD, DEMO_DAYS)
 *   node dist/demo.js purge                            removes all of it, and nothing else
 *   node dist/demo.js fresh-start --delete-everything  empties the whole network but the admins, the
 *                                                      catalogue and the reward rates, then builds the
 *                                                      test region again with the reviewers' current passwords
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
      await removeFiles(result.files);
      console.log(JSON.stringify(result, null, 2));
      return;
    }
    if (command === "fresh-start") {
      if (process.argv[3] !== "--delete-everything")
        throw new Error(
          "This deletes the whole network but the admins: add --delete-everything.",
        );
      const passwordHashes = await reviewPasswordHashes(owner);
      const passwords = passwordHashes ? undefined : passwordsFromEnv();
      const wiped = await wipeNetwork(owner);
      await removeFiles(wiped.files);
      console.error(JSON.stringify({ wiped: wiped.counts }));
      await seed(owner, {
        passwordHashes: passwordHashes ?? undefined,
        passwords,
      });
      return;
    }
    if (command !== "seed")
      throw new Error("Use: seed | purge | fresh-start --delete-everything");
    await seed(owner, { passwords: passwordsFromEnv() });
  } finally {
    await owner.end();
  }
}

function passwordsFromEnv() {
  const responsable = process.env.DEMO_RESPONSABLE_PASSWORD ?? "";
  const vendeur = process.env.DEMO_VENDEUR_PASSWORD ?? "";
  if (responsable.length < 10 || vendeur.length < 10)
    throw new Error("Both demo passwords need at least 10 characters.");
  return { responsable, vendeur };
}

async function seed(
  owner: Client,
  credentials: Pick<DemoOptions, "passwords" | "passwordHashes">,
) {
  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: false,
  });
  try {
    const result = await seedDemo(demoServices(app), owner, {
      days: Number(process.env.DEMO_DAYS) || 60,
      ...credentials,
      log: (m) => console.error(m),
    });
    console.log(JSON.stringify(result, null, 2));
  } finally {
    await app.close();
  }
}

async function removeFiles(files: string[]) {
  const root = process.env.MEDIA_ROOT ?? "/var/lib/biobalance/media";
  for (const file of files)
    await unlink(path.join(root, file)).catch(() => undefined);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
