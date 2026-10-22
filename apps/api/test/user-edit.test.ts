import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { owner, resetDatabase, startApi, type Api } from "./helpers";
import { approvedPdv, buildWorld, type World } from "./world";

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

async function member(email = "hanen@example.test") {
  const pdv = await approvedPdv(w);
  const res = await w.a.post("/v1/users", {
    role: "VENDEUR",
    pdvId: pdv.id,
    name: "Hanen Smiri",
    email,
    phone: "21 345 678",
  });
  return { pdv, user: res.body };
}

async function jobs(kind: string) {
  const o = await owner();
  try {
    return (
      await o.query(
        `SELECT key FROM "Job" WHERE kind = $1 ORDER BY "createdAt"`,
        [kind],
      )
    ).rows as { key: string }[];
  } finally {
    await o.end();
  }
}

describe("editing a person in full", () => {
  it("the admin changes the name, email, phone and store, and the invitation goes again to the new contacts", async () => {
    const { pdv, user } = await member();
    const other = await approvedPdv(w, "n", "Para Marsa");
    const before = (await jobs("email")).length;
    const done = await w.a.patch(`/v1/users/${user.id}`, {
      name: "Hanen S.",
      email: "New.Address@Example.test",
      phone: "+216 22 333 444",
      pdvId: other.id,
    });
    expect(done.status).toBe(200);
    expect(done.body).toMatchObject({
      name: "Hanen S.",
      email: "new.address@example.test",
      phone: "+21622333444",
    });
    // The invitation was not used yet: it is sent again, by email and WhatsApp, and the old code dies.
    expect((await jobs("email")).length).toBe(before + 1);
    expect((await jobs("whatsapp")).length).toBe(before + 1);
    // The new email is the login now; the old one is free again.
    expect((await member("hanen@example.test")).user.email).toBe(
      "hanen@example.test",
    );
    // An email already used elsewhere is refused.
    const taken = await w.a.patch(`/v1/users/${user.id}`, {
      email: "hanen@example.test",
    });
    expect(taken.body.code).toBe("EMAIL_TAKEN");
    expect(pdv.id).not.toBe(other.id);
  });

  it("a responsable edits only the name and store of her team, never an email or a phone", async () => {
    const pdv = await approvedPdv(w);
    const added = await w.n.post(`/v1/pdvs/${pdv.id}/members`, {
      name: "Karim",
      email: "karim@example.test",
      phone: "21 345 679",
    });
    const ok = await w.n.patch(`/v1/users/${added.body.id}`, {
      name: "Karim B.",
    });
    expect(ok.body.name).toBe("Karim B.");
    expect(
      (
        await w.n.patch(`/v1/users/${added.body.id}`, {
          email: "other@example.test",
        })
      ).status,
    ).toBe(403);
    expect(
      (await w.n.patch(`/v1/users/${added.body.id}`, { phone: "22 000 000" }))
        .status,
    ).toBe(403);
    // Nor a person of another region.
    expect(
      (await w.s.patch(`/v1/users/${added.body.id}`, { name: "X" })).status,
    ).toBe(404);
  });

  it("an administrator is not edited from here, and the audit keeps what changed", async () => {
    const { user } = await member();
    const me = (await w.a.get("/v1/me")).body;
    expect((await w.a.patch(`/v1/users/${me.id}`, { name: "X" })).status).toBe(
      403,
    );
    await w.a.patch(`/v1/users/${user.id}`, { email: "changed@example.test" });
    const audit = (await w.a.get("/v1/audit?limit=20")).body.items as any[];
    const entry = audit.find((e) => e.action === "user.updated");
    expect(entry.details.email).toEqual({
      from: "hanen@example.test",
      to: "changed@example.test",
    });
  });

  it("a person's own phone is checked and stored the same way, and cannot be emptied (except by an admin)", async () => {
    expect(
      (await w.n.patch("/v1/me", { phone: "00216 22 333 444" })).body.phone,
    ).toBe("+21622333444");
    expect((await w.n.patch("/v1/me", { phone: "nope" })).body.code).toBe(
      "PHONE_INVALID",
    );
    expect((await w.n.patch("/v1/me", { phone: "" })).body.code).toBe(
      "PHONE_REQUIRED",
    );
    // An administrator may have no number.
    expect((await w.a.patch("/v1/me", { phone: "" })).status).toBe(200);
  });
});
