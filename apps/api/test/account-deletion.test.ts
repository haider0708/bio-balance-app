import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import argon2 from "argon2";
import { randomUUID } from "node:crypto";
import {
  client,
  createAccount,
  owner,
  resetDatabase,
  startApi,
  type Api,
} from "./helpers";
import { approvedPdv, buildWorld, stockPlace, type World } from "./world";

let api: Api;
let w: World;
beforeAll(async () => {
  api = await startApi();
});
afterAll(() => api.close());
beforeEach(async () => {
  await resetDatabase();
  w = await buildWorld(api);
});

async function setPassword(id: string, password: string) {
  const db = await owner();
  try {
    await db.query(`UPDATE "User" SET "passwordHash"=$2 WHERE id=$1`, [
      id,
      await argon2.hash(password, { type: argon2.argon2id }),
    ]);
  } finally {
    await db.end();
  }
}

describe("deleting one's own account", () => {
  it("erases who the person is, keeps the sales, and can never sign in again", async () => {
    const pdv = await approvedPdv(w);
    await stockPlace(w, pdv.id, w.nord, [10, 10, 10]);
    const seller = await createAccount({
      role: "VENDEUR",
      pdvId: pdv.id,
      name: "Karim Ben Ali",
      email: "karim@example.test",
    });
    await setPassword(seller.id, "karim-password-1");
    const k = client(api, seller.token);
    const sale = randomUUID();
    await k.post("/v1/sales", {
      id: sale,
      lines: [{ productId: w.products[0]!.id, quantity: 2 }],
    });

    const wrong = await k.post("/v1/me/delete", { password: "nope-nope" });
    expect(wrong.body.code).toBe("INVALID_CREDENTIALS");
    expect(
      (await k.post("/v1/me/delete", { password: "karim-password-1" })).status,
    ).toBe(201);

    // The session is gone and the address no longer signs in.
    expect((await k.get("/v1/me")).status).toBe(401);
    const login = await client(api).post("/v1/auth/login", {
      email: "karim@example.test",
      password: "karim-password-1",
    });
    expect(login.body.code).toBe("INVALID_CREDENTIALS");

    // The admin sees the record without the person, and the sale is still counted.
    const user = (await w.a.get(`/v1/users/${seller.id}`)).body;
    expect(user.name).toMatch(/^Compte supprimé #/);
    expect(user.email).not.toContain("karim");
    expect(user.phone ?? null).toBeNull();
    const kept = (await w.a.get(`/v1/sales/${sale}`)).body;
    expect(kept.units).toBe(2);
    expect(kept.seller.name).toMatch(/^Compte supprimé/);

    // Nothing brings it back.
    expect(
      (await w.a.post(`/v1/users/${seller.id}/reactivate`, {})).body.code,
    ).toBe("ACCOUNT_DELETED");
    expect(
      (await w.a.post(`/v1/users/${seller.id}/resend-invite`, {})).body.code,
    ).toBe("ACCOUNT_DELETED");

    // The admin is told.
    const inbox = (await w.a.get("/v1/notifications")).body.items;
    expect(inbox.some((n: any) => n.key === "account.deleted")).toBe(true);
  });

  it("keeps the network with an admin", async () => {
    await setPassword(w.admin.id, "admin-password-1");
    const res = await w.a.post("/v1/me/delete", {
      password: "admin-password-1",
    });
    expect(res.body.code).toBe("LAST_ADMIN");
    const second = await createAccount({ role: "ADMIN" });
    expect(second.id).toBeTruthy();
    expect(
      (await w.a.post("/v1/me/delete", { password: "admin-password-1" }))
        .status,
    ).toBe(201);
  });
});

describe("public pages for the app stores", () => {
  it("serves the privacy policy, the terms and the deletion page in both languages", async () => {
    for (const path of [
      "/privacy",
      "/terms",
      "/support",
      "/account-deletion",
    ]) {
      const fr = await fetch(`${api.url}${path}`, {
        headers: { "Accept-Language": "fr-FR" },
      });
      expect(fr.status).toBe(200);
      expect(fr.headers.get("content-type")).toContain("text/html");
      expect(await fr.text()).toContain('lang="fr"');
      const en = await fetch(`${api.url}${path}?lang=en`);
      const text = await en.text();
      expect(text).toContain('lang="en"');
      expect(text).toContain("mailto:");
      expect(en.headers.get("content-security-policy")).toContain(
        "default-src 'none'",
      );
    }
  });
});
