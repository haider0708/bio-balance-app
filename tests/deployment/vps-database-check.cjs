// Run via `biobalance-compose exec -T api1 node - < this-file`.
// Verify the running identity and every RLS table declared by its own migrations.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { Database } = require(
  path.resolve("dist/shared/infrastructure/database"),
);
const db = new Database();

(async () => {
  const migrations = path.resolve("prisma/migrations");
  const expected = new Set();
  for (const entry of fs.readdirSync(migrations, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const sql = fs.readFileSync(
      path.join(migrations, entry.name, "migration.sql"),
      "utf8",
    );
    for (const match of sql.matchAll(
      /ALTER TABLE "([A-Za-z0-9_]+)" FORCE ROW LEVEL SECURITY/g,
    )) {
      expected.add(match[1]);
    }
  }
  assert(expected.size > 0);
  const [identity] = await db.$queryRawUnsafe(
    "SELECT current_user::text AS identity,rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user",
  );
  assert.equal(identity.identity, "biobalance_app");
  assert.equal(identity.rolsuper, false);
  assert.equal(identity.rolbypassrls, false);
  const tables = await db.$queryRawUnsafe(
    "SELECT relname::text AS name,relrowsecurity,relforcerowsecurity FROM pg_class WHERE relnamespace='public'::regnamespace",
  );
  for (const name of expected) {
    const actual = tables.find((row) => row.name === name);
    assert(actual && actual.relrowsecurity && actual.relforcerowsecurity, name);
  }
  console.log(
    JSON.stringify(
      {
        status: "passed",
        identity: identity.identity,
        superuser: false,
        bypassRls: false,
        forcedRlsTables: [...expected].sort(),
        note: "Store and membership directory authorization is enforced by authenticated server transactions; these metadata tables are not declared as RLS tables by the migrations.",
      },
      null,
      2,
    ),
  );
})()
  .catch((error) => {
    console.error("Database deployment verification failed:", error.name);
    process.exitCode = 1;
  })
  .finally(() => db.$disconnect());
