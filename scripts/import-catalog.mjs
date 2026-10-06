#!/usr/bin/env node
// Load the BioBalance catalog (data/initial-catalog) into a running API.
//   API_URL=https://api.galylio.com ADMIN_EMAIL=… ADMIN_PASSWORD=… ADMIN_OTP=123456 node scripts/import-catalog.mjs
// It signs in as the admin, uploads each product photo, then creates or refreshes the products
// (matched by reference), so it is safe to run again.
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const dir = path.join(here, "..", "data", "initial-catalog");
const { API_URL = "http://localhost:3000", ADMIN_EMAIL, ADMIN_PASSWORD, ADMIN_OTP } = process.env;
if (!ADMIN_EMAIL || !ADMIN_PASSWORD) {
  console.error("Set ADMIN_EMAIL and ADMIN_PASSWORD (and ADMIN_OTP for the authenticator code).");
  process.exit(1);
}

async function call(method, route, token, body, headers = {}) {
  const res = await fetch(`${API_URL}${route}`, {
    method,
    headers: { ...(token && { Authorization: `Bearer ${token}` }), ...headers },
    body,
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : undefined;
  if (!res.ok) throw new Error(`${method} ${route} → ${res.status} ${data?.code ?? ""} ${data?.message ?? ""}`);
  return data;
}
const json = (method, route, token, value) => call(method, route, token, JSON.stringify(value), { "Content-Type": "application/json" });

const login = await json("POST", "/v1/auth/login", null, { email: ADMIN_EMAIL, password: ADMIN_PASSWORD, otp: ADMIN_OTP });
const token = login.token;

const products = JSON.parse(await readFile(path.join(dir, "produits.json"), "utf8"));
const items = [];
for (const p of products) {
  let imageId = null;
  if (p.image) {
    try {
      const bytes = await readFile(path.join(dir, p.image));
      imageId = (await call("POST", `/v1/media?purpose=PRODUCT&filename=${encodeURIComponent(path.basename(p.image))}`, token, bytes, { "Content-Type": "application/octet-stream" })).id;
    } catch (error) {
      console.warn(`no image for ${p.reference}: ${error.message}`);
    }
  }
  items.push({
    reference: p.reference,
    name: p.designation || p.name,
    barcode: p.ean || null,
    family: p.category || "Divers",
    range: p.range || "",
    packageSize: p.size || "",
    description: p.description || "",
    instructions: p.instructions || "",
    ingredients: p.ingredients || "",
    precautions: p.precautions || "",
    imageId,
    active: true,
  });
}
for (let i = 0; i < items.length; i += 25) {
  const result = await json("POST", "/v1/products/import", token, { items: items.slice(i, i + 25) });
  console.log(`products ${i + 1}–${Math.min(i + 25, items.length)}: ${result.created} created, ${result.updated} updated`);
}
await call("POST", "/v1/auth/logout", token);
