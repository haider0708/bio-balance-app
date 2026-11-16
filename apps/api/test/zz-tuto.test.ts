// Scratch (never committed): the fixture world, with French names and accounts that can sign in,
// for recording the tutorials in a simulator.
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { randomBytes } from "node:crypto";
import * as argon2 from "argon2";
import { it } from "vitest";
import { client, owner } from "./helpers";
import { serveFixture } from "./serve-fixture";
import { encryptSecret } from "../src/modules/auth/mfa";

const out = process.env.TUTO_OUT!;
const base32 = (buf: Buffer) => {
  const a = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = "";
  for (const b of buf) bits += b.toString(2).padStart(8, "0");
  let s = "";
  for (let i = 0; i + 5 <= bits.length; i += 5) s += a[parseInt(bits.slice(i, i + 5), 2)];
  return s;
};
it.skipIf(!out)(
  "serves the tutorial world",
  async () => {
    const serving = serveFixture(out);
    while (!existsSync(out)) await new Promise((r) => setTimeout(r, 300));
    const world = JSON.parse(readFileSync(out, "utf8"));
    const password = "Tuto-" + randomBytes(5).toString("hex") + "A1";
    const secret = randomBytes(20);
    const db = await owner();
    await db.query(`UPDATE "User" SET "passwordHash"=$1`, [
      await argon2.hash(password, { type: argon2.argon2id }),
    ]);
    await db.query(`UPDATE "User" SET "mfaSecret"=$1 WHERE role='ADMIN'`, [
      encryptSecret(secret.toString("hex")),
    ]);
    for (const [from, to] of [
      ["Admin BioBalance", "Karim Tajer"],
      ["Nora Nord", "Nora Ben Salah"],
      ["Amira Vendeuse", "Amira Trabelsi"],
      ["Karim Vendeur", "Sami Jaziri"],
      ["Omar Commandes", "Omar Gharbi"],
    ])
      await db.query(`UPDATE "User" SET name=$2 WHERE name=$1`, [from, to]);
    await db.query(`UPDATE "Depot" SET name='Grossiste Hedi' WHERE name='Depot Hedi'`);
    // The sister para holds stock too, so both can send.
    const people = (
      await db.query(`SELECT email, role, name, "pdvId" FROM "User" ORDER BY role, name`)
    ).rows;
    await db.end();
    const a = client({ url: world.baseUrl } as never, world.tokens.admin);
    void a;
    writeFileSync(
      `${out}.world`,
      JSON.stringify({ password, adminSecret: base32(secret), people, ids: world.ids, tokens: world.tokens, baseUrl: world.baseUrl }),
    );
    await serving;
  },
  8 * 3600_000,
);
