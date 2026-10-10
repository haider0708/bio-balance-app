// Pushes a LOCAL development API to its limits: races, replays, abuse, malformed input,
// oversized uploads and load. Run after scripts/dev/reset-dev-world.sh.
//   node scripts/dev/stress.mjs /tmp/biobalance-world.json
import { createHmac, randomUUID, randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";

const world = JSON.parse(readFileSync(process.argv[2], "utf8"));
const API = world.api;
if (!/localhost|127\.0\.0\.1/.test(API)) throw new Error("Development API only.");

const results = [];
const check = (name, ok, detail = "") => {
  results.push({ name, ok });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? "  — " + detail : ""}`);
};

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

async function call(method, route, token, body, headers = {}) {
  const res = await fetch(API + route, {
    method,
    headers: { ...(token && { Authorization: `Bearer ${token}` }), ...(body !== undefined && !(body instanceof Uint8Array) && { "Content-Type": "application/json" }), ...headers },
    body: body === undefined ? undefined : body instanceof Uint8Array ? body : typeof body === "string" ? body : JSON.stringify(body),
  });
  const text = await res.text();
  let data;
  try { data = text ? JSON.parse(text) : undefined; } catch { data = text; }
  return { status: res.status, body: data, headers: res.headers };
}
const login = async (a, otp) => (await call("POST", "/v1/auth/login", null, { email: a.email, password: a.password, ...(otp && { otp }) })).body.token;

const admin = await login(world.admin, totp(world.admin.totpUri));
const vendeur = await login(world.vendeur);
const resp = await login(world.responsable);

const me = (await call("GET", "/v1/me", vendeur)).body;
const pdvId = me.pdv.id;
const productsRes = await call("GET", "/v1/products", admin);
if (productsRes.status !== 200) throw new Error("products: " + productsRes.status + " " + JSON.stringify(productsRes.body) + " admin=" + String(admin).slice(0, 8));
const products = productsRes.body;
const serum = products.find((p) => p.family === "Sérums");
const levelOf = async (productId) => (await call("GET", `/v1/stock/locations/${pdvId}`, admin)).body.items.find((i) => i.productId === productId)?.quantity ?? 0;

// ───────── 1. Two hundred phones sell the last five units at the same instant
{
  await call("POST", "/v1/stock/adjust", admin, { locationId: pdvId, reason: "stress", lines: [{ productId: serum.id, quantity: 5 }] });
  const sales = await Promise.all(Array.from({ length: 200 }, () => call("POST", "/v1/sales", vendeur, { id: randomUUID(), lines: [{ productId: serum.id, quantity: 1 }] })));
  const ok = sales.filter((s) => s.status === 201).length;
  const refused = sales.filter((s) => s.status === 409 && s.body.code === "OUT_OF_STOCK").length;
  const other = sales.filter((s) => ![201, 409].includes(s.status));
  check("last 5 units sold to exactly 5 of 200 simultaneous buyers", ok === 5 && refused === 195, `ok=${ok} refused=${refused} other=${other.map((o) => o.status).join(",")}`);
  check("stock ends at exactly zero, never negative", (await levelOf(serum.id)) === 0);
}

// ───────── 2. The same sale sent 50 times at once counts once
{
  await call("POST", "/v1/stock/adjust", admin, { locationId: pdvId, reason: "stress", lines: [{ productId: serum.id, quantity: 50 }] });
  const before = (await call("GET", "/v1/wallet", vendeur)).body.balanceMillimes;
  const id = randomUUID();
  const sends = await Promise.all(Array.from({ length: 50 }, () => call("POST", "/v1/sales", vendeur, { id, lines: [{ productId: serum.id, quantity: 3 }] })));
  const after = (await call("GET", "/v1/wallet", vendeur)).body.balanceMillimes;
  check("50 simultaneous replays of one sale: all answered, no server error", sends.every((s) => [200, 201].includes(s.status)), sends.map((s) => s.status).filter((x, i, a) => a.indexOf(x) === i).join(","));
  check("…the reward is credited once (500 × 3)", after - before === 1500, `delta=${after - before}`);
  check("…and stock fell by 3 only", (await levelOf(serum.id)) === 47);
}

// ───────── 3. Payout races can never exceed the balance
{
  const wallet = (await call("GET", "/v1/wallet", vendeur)).body;
  const half = Math.floor(wallet.availableMillimes / 2) + 1; // two of these cannot both fit
  const reqs = await Promise.all(Array.from({ length: 10 }, () => call("POST", "/v1/payouts", vendeur, { amountMillimes: half })));
  const ok = reqs.filter((r) => r.status === 201).length;
  check("10 simultaneous payout requests that cannot all fit: at most one accepted", ok === 1, `accepted=${ok}`);
  check("…the others are refused cleanly (409), no 5xx", reqs.every((r) => r.status === 201 || r.status === 409));
}

// ───────── 4. Abuse of sign-in
{
  const bad = await Promise.all(Array.from({ length: 40 }, () => call("POST", "/v1/auth/login", null, { email: "nobody@example.test", password: "wrong-password-1" })));
  check("40 wrong sign-ins: throttled with 429 after the limit", bad.some((b) => b.status === 429) && bad.every((b) => [401, 429].includes(b.status)), bad.map((b) => b.status).filter((x, i, a) => a.indexOf(x) === i).join(","));
  const codes = await Promise.all(Array.from({ length: 30 }, (_, i) => call("POST", "/v1/auth/activate", null, { email: "nora@example.test", code: "AAAA" + String(1000 + i), password: "a-long-password" })));
  check("guessing activation codes is throttled", codes.some((c) => c.status === 429), codes.map((c) => c.status).filter((x, i, a) => a.indexOf(x) === i).join(","));
  const resets = await Promise.all(Array.from({ length: 12 }, () => call("POST", "/v1/auth/forgot-password", null, { email: "someone@example.test" })));
  check("password-reset spam is throttled", resets.some((r) => r.status === 429));
}

// ───────── 5. Nobody reaches what is not theirs
{
  const adminOnly = ["/v1/approvals", "/v1/approvals/history", "/v1/reward-rules", "/v1/messages", "/v1/users", "/v1/reports/insights?from=2026-01-01&to=2026-12-31"];
  const asVendeur = await Promise.all(adminOnly.map((r) => call("GET", r, vendeur)));
  check("a team member is refused every admin and management route", asVendeur.every((r) => r.status === 403), asVendeur.map((r) => r.status).join(","));
  const noToken = await Promise.all(["/v1/me", "/v1/dashboard", "/v1/sales", "/v1/stock/locations/" + pdvId, "/v1/media/" + randomUUID()].map((r) => call("GET", r)));
  check("no token: always 401", noToken.every((r) => r.status === 401), noToken.map((r) => r.status).join(","));
  const forged = await call("GET", "/v1/me", "x".repeat(64));
  check("a forged token is refused", forged.status === 401);
  const writes = await Promise.all([
    call("POST", "/v1/users", vendeur, { role: "ADMIN", name: "Evil", email: "evil@example.test" }),
    call("POST", "/v1/reward-rules", resp, { scope: "FAMILY", family: "Sérums", amountMillimes: 999999, startsOn: "2026-10-07" }),
    call("POST", "/v1/stock/adjust", resp, { locationId: pdvId, reason: "cheat", lines: [{ productId: serum.id, quantity: 9999 }] }),
    call("POST", "/v1/payouts/" + randomUUID() + "/approve", vendeur, {}),
  ]);
  check("privilege escalation attempts all fail (400/403/404)", writes.every((r) => [400, 403, 404].includes(r.status)), writes.map((r) => r.status).join(","));
}

// ───────── 6. Malformed and hostile input never causes a 5xx
{
  const attacks = [
    ["POST", "/v1/sales", vendeur, { id: "not-a-uuid", lines: [] }],
    ["POST", "/v1/sales", vendeur, { id: randomUUID(), lines: [{ productId: serum.id, quantity: -5 }] }],
    ["POST", "/v1/sales", vendeur, { id: randomUUID(), lines: [{ productId: serum.id, quantity: 1.5 }] }],
    ["POST", "/v1/sales", vendeur, { id: randomUUID(), lines: [{ productId: serum.id, quantity: 99999999999 }] }],
    ["POST", "/v1/sales", vendeur, { id: randomUUID(), lines: Array.from({ length: 2000 }, () => ({ productId: serum.id, quantity: 1 })) }],
    ["POST", "/v1/sales", vendeur, { id: randomUUID(), occurredAt: "2999-01-01", lines: [{ productId: serum.id, quantity: 1 }] }],
    ["POST", "/v1/sales", vendeur, "{not json"],
    ["POST", "/v1/sales", vendeur, "null"],
    ["POST", "/v1/sales", vendeur, "[]"],
    ["GET", "/v1/sales?limit=999999&cursor=%00%00", vendeur],
    ["GET", "/v1/sales?from=2026-13-45&to=abc", vendeur],
    ["GET", "/v1/sales?productId=' OR 1=1 --", vendeur],
    ["GET", "/v1/products?q=%27%3B%20DROP%20TABLE%20%22User%22%3B--", admin],
    ["GET", "/v1/users?q=" + encodeURIComponent("%'; SELECT pg_sleep(5);--"), admin],
    ["GET", "/v1/reports/sales?groupBy=pdv;DROP&from=2026-01-01&to=2026-12-31", admin],
    ["GET", "/v1/reports/insights?from=1900-01-01&to=2999-12-31", admin],
    ["GET", "/v1/stock/locations/not-a-uuid", admin],
    ["GET", "/v1/media/../../etc/passwd", admin],
    ["GET", "/v1/media/" + randomUUID(), admin],
    ["PATCH", "/v1/me", vendeur, { locale: "xx", name: "A".repeat(10000) }],
    ["POST", "/v1/auth/login", null, { email: "a".repeat(5000) + "@x.test", password: "x" }],
    ["POST", "/v1/auth/login", null, { email: ["a@b.c"], password: { $ne: 1 } }],
    ["POST", "/v1/payouts", vendeur, { amountMillimes: "1e9" }],
    ["POST", "/v1/payouts", vendeur, { amountMillimes: Number.MAX_SAFE_INTEGER }],
    ["POST", "/v1/stock/declarations", resp, { locationId: pdvId, photoIds: [randomUUID()], lines: [{ productId: serum.id, quantity: 1 }] }],
    ["POST", "/v1/messages", admin, { title: "<script>alert(1)</script>", body: "x".repeat(200000), audience: { all: true } }],
    ["GET", "/c#<script>", null],
    ["GET", "/nope/nothing", admin],
    ["DELETE", "/v1/sales", admin],
  ];
  const out = await Promise.all(attacks.map(([m, r, t, b]) => call(m, r, t, b)));
  const bad = out.map((o, i) => ({ o, a: attacks[i] })).filter(({ o }) => o.status >= 500);
  check("27 hostile or malformed requests: none reaches a 5xx", bad.length === 0, bad.map(({ o, a }) => `${o.status} ${a[0]} ${a[1].slice(0, 50)}`).join(" | "));
  const html = await call("GET", "/c", null);
  check("the public code page forbids foreign scripts (CSP)", /script-src 'sha256-/.test(html.headers.get("content-security-policy") ?? ""));
  const health = await call("GET", "/health", null);
  const h = health.headers;
  check("security headers present", !!h.get("x-content-type-options") && !!h.get("strict-transport-security") && !h.get("x-powered-by"), `nosniff=${h.get("x-content-type-options")} hsts=${!!h.get("strict-transport-security")} powered=${h.get("x-powered-by")}`);
}

// ───────── 7. Uploads
{
  const jpeg = (n) => Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), randomBytes(n)]);
  const up = (bytes, token = resp, purpose = "PROOF") => call("POST", `/v1/media?purpose=${purpose}&filename=a.jpg`, token, new Uint8Array(bytes), { "Content-Type": "application/octet-stream" });
  check("a normal photo is accepted", (await up(jpeg(300_000))).status === 201);
  check("an empty upload is refused", (await up(Buffer.alloc(0))).status === 400);
  check("a file that is not an image is refused (415)", (await up(Buffer.from("hello world, not an image"))).status === 415);
  const huge = await up(jpeg(40 * 1024 * 1024)).catch(() => ({ status: "connection closed" }));
  check("a 40 MB photo is refused (413 or the connection is closed), not stored", huge.status === 413 || huge.status === "connection closed", `status=${huge.status}`);
  check("…and the server is still healthy afterwards", (await call("GET", "/health", null)).status === 200);
  const own = await call("GET", "/v1/payouts", vendeur);
  check("a team member sees only their own payouts", own.status === 200 && own.body.every((p) => p.userName === undefined || p.userName === me.name));
  check("a team member cannot upload product images", (await up(jpeg(1000), vendeur, "PRODUCT")).status === 403);
  const ten = await Promise.all(Array.from({ length: 10 }, () => up(jpeg(2_000_000))));
  check("10 simultaneous 2 MB uploads all succeed", ten.every((r) => r.status === 201), ten.map((r) => r.status).join(","));
  const many = await Promise.all(Array.from({ length: 100 }, () => up(jpeg(1000))));
  check("upload flood is throttled, never a 5xx", many.every((r) => [201, 429].includes(r.status)) && many.some((r) => r.status === 429), many.map((r) => r.status).filter((x, i, a) => a.indexOf(x) === i).join(","));
}

// ───────── 8. Load
{
  const run = async (name, route, token, n) => {
    const times = [];
    let errors = 0;
    const started = performance.now();
    await Promise.all(Array.from({ length: n }, async () => {
      const t = performance.now();
      const r = await call("GET", route, token);
      times.push(performance.now() - t);
      if (r.status >= 500 || r.status === 0) errors++;
    }));
    const wall = (performance.now() - started) / 1000;
    times.sort((a, b) => a - b);
    const p = (q) => Math.round(times[Math.floor(times.length * q)]);
    check(`${name}: ${n} requests, no errors, p95 under 1.5 s`, errors === 0 && p(0.95) < 1500, `p50=${p(0.5)}ms p95=${p(0.95)}ms p99=${p(0.99)}ms ${Math.round(n / wall)} req/s`);
  };
  await run("admin dashboard", "/v1/dashboard", admin, 300);
  await run("insights report", "/v1/reports/insights?from=2026-09-01&to=2026-10-31", admin, 150);
  await run("seller home", "/v1/dashboard", vendeur, 400);
  await run("product catalogue", "/v1/products", vendeur, 400);
  await run("sales days", "/v1/sales/days?from=2026-01-01&to=2026-12-31", vendeur, 300);
}

const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
process.exit(failed.length ? 1 : 0);
