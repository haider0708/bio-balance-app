import "reflect-metadata";
import { readFileSync } from "node:fs";
import { Database } from "./core/database";
import { AdminInput, addAdministrator } from "./modules/auth/admins";

/**
 * Adds an administrator, or gives an existing one a fresh authenticator, and prints a one-time
 * link that shows the QR code once (valid one hour). The details arrive on standard input as
 * JSON, so a password never appears in a command line:
 *   echo '{"email":"…","name":"…","password":"…"}' | node dist/add-admin.js
 *   echo '{"email":"…","again":true}' | node dist/add-admin.js      (new authenticator and link)
 * Needs the usual database settings and API_PUBLIC_URL for the link.
 */
async function main() {
  const input = AdminInput.parse(JSON.parse(readFileSync(0, "utf8")));
  const db = new Database();
  try {
    console.log(
      await addAdministrator(
        db,
        input,
        process.env.API_PUBLIC_URL ?? "https://api.galylio.com",
      ),
    );
  } finally {
    await db.$disconnect();
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
