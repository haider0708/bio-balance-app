// Builds a small, realistic world on a LOCAL development API through its public routes,
// for the on-device end-to-end test (apps/mobile/integration_test). Never point it at production.
//   node scripts/dev/seed-dev-world.mjs <admin-setup.json> <world-out.json>
import { createHmac, randomBytes } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";

const API = process.env.API_URL ?? "http://localhost:3000";
if (!/localhost|127\.0\.0\.1/.test(API)) throw new Error("Development API only.");
const [setupPath, outPath] = process.argv.slice(2);
const setup = JSON.parse(readFileSync(setupPath, "utf8"));
const PASSWORD = "a-long-password";

function totp(uri) {
  const secret = new URL(uri).searchParams.get("secret");
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = "";
  for (const c of secret.replace(/=+$/, "")) bits += alphabet.indexOf(c).toString(2).padStart(5, "0");
  const key = Buffer.from(bits.match(/.{8}/g).map((b) => parseInt(b, 2)));
  const step = Buffer.alloc(8);
  step.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 30000)));
  const h = createHmac("sha1", key).update(step).digest();
  const o = h[h.length - 1] & 15;
  return String((h.readUInt32BE(o) & 0x7fffffff) % 1e6).padStart(6, "0");
}

async function call(method, route, token, body, raw) {
  const res = await fetch(API + route, {
    method,
    headers: {
      ...(token && { Authorization: `Bearer ${token}` }),
      ...(raw ? { "Content-Type": "application/octet-stream" } : body !== undefined && { "Content-Type": "application/json" }),
    },
    body: raw ?? (body === undefined ? undefined : JSON.stringify(body)),
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : undefined;
  if (!res.ok) throw new Error(`${method} ${route} → ${res.status} ${text}`);
  return data;
}

/** The last activation code mailed to this address, read from the development database. */
function codeFor(email) {
  const sql = `SELECT payload->>'code' FROM "Job" j JOIN "User" u ON u.id = (j.payload->>'userId')::uuid WHERE j.kind='email' AND u.email='${email}' ORDER BY j."createdAt" DESC LIMIT 1`;
  return execFileSync("docker", ["exec", "biobalance-dev-postgres-1", "psql", "-U", "biobalance", "-d", "biobalance", "-Atc", sql]).toString().trim();
}

async function activate(email) {
  await call("POST", "/v1/auth/activate", null, { email, code: codeFor(email), password: PASSWORD });
  return (await call("POST", "/v1/auth/login", null, { email, password: PASSWORD })).token;
}

const photo = async (token) =>
  (await call("POST", "/v1/media?purpose=PROOF&filename=photo.jpg", token, undefined, Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), randomBytes(2000)]))).id;

const admin = (await call("POST", "/v1/auth/login", null, { email: setup.email, password: setup.password, otp: totp(setup.totpUri) })).token;
const regions = await call("GET", "/v1/regions", admin);
const nord = regions.find((r) => r.code === "NORD").id;

await call("POST", "/v1/users", admin, { role: "RESPONSABLE", regionId: nord, name: "Nora Ben Salah", email: "nora@example.test" });
const resp = await activate("nora@example.test");
await call("POST", "/v1/users", admin, { role: "GROSSISTE", regionId: nord, name: "Hedi Trabelsi", email: "hedi@example.test", phone: "20 111 222", depot: { name: "Dépôt Hedi", address: "Zone industrielle", city: "Ben Arous", phone: "20 111 222" } });
const gros = await activate("hedi@example.test");
const depotId = (await call("GET", "/v1/depots", gros))[0].id;

const group = await call("POST", "/v1/groups", resp, { name: "Groupe Tunis" });
await call("POST", `/v1/groups/${group.id}/approve`, admin, {});
const pdv = await call("POST", "/v1/pdvs", resp, { name: "Para Lac", address: "12 rue du Lac", city: "Tunis", groupId: group.id });
await call("POST", `/v1/pdvs/${pdv.id}/approve`, admin, {});
await call("POST", "/v1/pdvs", resp, { name: "Pharma Marsa", address: "3 avenue de la Plage", city: "La Marsa" });

const amira = await call("POST", `/v1/pdvs/${pdv.id}/members`, resp, { name: "Amira Gharbi", email: "amira@example.test" });
await call("POST", `/v1/users/${amira.id}/approve`, admin, {});
const vendeur = await activate("amira@example.test");
await call("POST", `/v1/pdvs/${pdv.id}/members`, resp, { name: "Karim Mejri", email: "karim@example.test" });

const all = await call("GET", "/v1/products", admin);
const products = [...all.filter((p) => p.family === "Sérums").slice(0, 4), ...all.filter((p) => p.family !== "Sérums").slice(0, 8)];
const lines = (n) => products.map((p, i) => ({ productId: p.id, quantity: n + (i % 4) }));

const stock = await call("POST", "/v1/stock/declarations", resp, { locationId: pdv.id, photoIds: [await photo(resp)], lines: lines(20) });
await call("POST", `/v1/stock/declarations/${stock.id}/approve`, admin, {});
const dstock = await call("POST", "/v1/stock/declarations", gros, { locationId: depotId, photoIds: [await photo(gros)], lines: lines(60) });
if (dstock.status === "REVIEW") await call("POST", `/v1/stock/declarations/${dstock.id}/review`, resp, { action: "approve" });
await call("POST", `/v1/stock/declarations/${dstock.id}/approve`, admin, {});

const today = new Date().toISOString().slice(0, 10);
await call("POST", "/v1/reward-rules", admin, { scope: "FAMILY", family: "Sérums", amountMillimes: 500, startsOn: today });
await call("POST", "/v1/reward-rules", admin, { scope: "FAMILY", family: "Soins capillaires", amountMillimes: 300, startsOn: today });

const order = await call("POST", "/v1/restocks", resp, { destId: pdv.id, lines: products.slice(0, 2).map((p) => ({ productId: p.id, quantity: 6 })) });
await call("POST", `/v1/restocks/${order.id}/assign`, admin, { depotId });

writeFileSync(outPath, JSON.stringify({
  api: API,
  admin: { email: setup.email, password: setup.password, totpUri: setup.totpUri },
  responsable: { email: "nora@example.test", password: PASSWORD },
  grossiste: { email: "hedi@example.test", password: PASSWORD },
  vendeur: { email: "amira@example.test", password: PASSWORD },
}, null, 2));
console.log("world ready");
