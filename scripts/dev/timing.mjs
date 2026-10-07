// Times the main screens' requests one by one (cold, then warm) on a LOCAL server with volume data.
import { createHmac } from "node:crypto";
import { readFileSync } from "node:fs";
const world = JSON.parse(readFileSync(process.argv[2], "utf8"));
const API = world.api;
function totp(uri) {
  const secret = new URL(uri).searchParams.get("secret");
  const a = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = "";
  for (const c of secret.replace(/=+$/, "")) bits += a.indexOf(c).toString(2).padStart(5, "0");
  const key = Buffer.from(bits.match(/.{8}/g).map((b) => parseInt(b, 2)));
  const step = Buffer.alloc(8);
  step.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 30000)));
  const h = createHmac("sha1", key).update(step).digest();
  const o = h[h.length - 1] & 15;
  return String((h.readUInt32BE(o) & 0x7fffffff) % 1e6).padStart(6, "0");
}
const get = async (route, token) => {
  const t = performance.now();
  const r = await fetch(API + route, { headers: { Authorization: `Bearer ${token}` } });
  const body = await r.text();
  return { ms: Math.round(performance.now() - t), status: r.status, kb: Math.round(body.length / 1024) };
};
const post = (route, body) => fetch(API + route, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) }).then((r) => r.json());
const admin = (await post("/v1/auth/login", { email: world.admin.email, password: world.admin.password, otp: totp(world.admin.totpUri) })).token;
const resp = (await post("/v1/auth/login", { email: world.responsable.email, password: world.responsable.password })).token;
const vendeur = (await post("/v1/auth/login", { email: world.vendeur.email, password: world.vendeur.password })).token;
const year = "from=2026-01-01&to=2026-12-31";
const month = "from=2026-09-07&to=2026-10-07";
const rows = [
  ["admin dashboard", "/v1/dashboard", admin],
  ["responsable dashboard", "/v1/dashboard", resp],
  ["insights, 1 month", `/v1/reports/insights?${month}`, admin],
  ["insights, 1 year", `/v1/reports/insights?${year}`, admin],
  ["report by store, 1 year", `/v1/reports/sales?groupBy=pdv&${year}`, admin],
  ["report by seller, 1 year", `/v1/reports/sales?groupBy=seller&${year}`, admin],
  ["report by product, 1 year", `/v1/reports/sales?groupBy=product&${year}`, admin],
  ["report by day, 1 year", `/v1/reports/sales?groupBy=day&${year}`, admin],
  ["stock overview", "/v1/reports/stock", admin],
  ["stock attention", "/v1/reports/stock/attention", admin],
  ["approvals", "/v1/approvals", admin],
  ["approvals history", "/v1/approvals/history", admin],
  ["all sales, first page", "/v1/sales?limit=30", admin],
  ["sales days, 1 year (admin)", `/v1/sales/days?${year}`, admin],
  ["stores list", "/v1/pdvs", admin],
  ["people list", "/v1/users", admin],
  ["seller home", "/v1/dashboard", vendeur],
  ["seller wallet", "/v1/wallet", vendeur],
  ["seller sales days", `/v1/sales/days?${year}`, vendeur],
  ["notifications", "/v1/notifications?limit=30", admin],
];
console.log("screen".padEnd(30), "cold".padStart(7), "warm".padStart(7), "size");
for (const [name, route, token] of rows) {
  const cold = await get(route, token);
  const warm = await get(route, token);
  const flag = cold.status !== 200 ? ` ← ${cold.status}` : cold.ms > 1500 ? "  ← SLOW" : "";
  console.log(name.padEnd(30), `${cold.ms}ms`.padStart(7), `${warm.ms}ms`.padStart(7), `${cold.kb} KB${flag}`);
}
