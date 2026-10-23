import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { client, owner, resetDatabase, startApi, type Api } from "./helpers";
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

const anon = () => client(api);
const open = async (code: string, kind: "i" | "r" = "i") =>
  (await anon().post("/v1/code-status", { code, kind })).body.open as boolean;

/** The code of the latest invitation, read from the queued email job (the way the email carries it). */
async function latestCode(email: string) {
  const o = await owner();
  try {
    const rows = (
      await o.query(
        `SELECT j.payload FROM "Job" j JOIN "User" u ON u.id::text = j.payload->>'userId'
         WHERE u.email = $1 AND j.kind = 'email' ORDER BY j."createdAt" DESC LIMIT 1`,
        [email],
      )
    ).rows;
    return rows[0].payload.code as string;
  } finally {
    await o.end();
  }
}

async function invite(email: string) {
  const pdv = await approvedPdv(w);
  const created = await w.a.post("/v1/users", {
    role: "VENDEUR",
    pdvId: pdv.id,
    name: "Hanen",
    email,
    phone: "21 345 678",
  });
  expect(created.status).toBe(201);
  return created.body.id as string;
}

describe("the link of an invitation", () => {
  it("works until the invitation is accepted, then says it is over", async () => {
    await invite("hanen@example.test");
    const code = await latestCode("hanen@example.test");
    expect(await open(code)).toBe(true);
    expect(await open(code.toLowerCase())).toBe(true); // however it is typed
    const activated = await anon().post("/v1/auth/activate", {
      email: "hanen@example.test",
      code,
      password: "a-long-test-password",
    });
    expect(activated.status).toBe(201);
    expect(await open(code)).toBe(false);
  });

  it("stops when the invitation is replaced, cancelled or has expired", async () => {
    const id = await invite("karim@example.test");
    const first = await latestCode("karim@example.test");
    await w.a.post(`/v1/users/${id}/resend-invite`, {});
    const second = await latestCode("karim@example.test");
    expect(first).not.toBe(second);
    // The new invitation replaced the old one.
    expect(await open(first)).toBe(false);
    expect(await open(second)).toBe(true);
    // Expired.
    const o = await owner();
    try {
      await o.query(
        `UPDATE "AccessToken" SET "expiresAt" = now() - interval '1 minute' WHERE "userId" = $1`,
        [id],
      );
    } finally {
      await o.end();
    }
    expect(await open(second)).toBe(false);

    // Cancelled by the admin.
    const other = await invite("sami@example.test");
    const code = await latestCode("sami@example.test");
    expect(await open(code)).toBe(true);
    await w.a.post(`/v1/users/${other}/cancel-invite`, {});
    expect(await open(code)).toBe(false);
  });

  it("stops when the person is deactivated, and knows nothing about a code that never existed", async () => {
    const id = await invite("nadia@example.test");
    const code = await latestCode("nadia@example.test");
    await w.a.post(`/v1/users/${id}/suspend`, {});
    expect(await open(code)).toBe(false);
    expect(await open("ABCD2345")).toBe(false);
    // A reset link is not an invitation link, and the other way round.
    expect(await open(code, "r")).toBe(false);
  });

  it("the page asks the server and is allowed to", async () => {
    const res = await fetch(`${api.url}/c`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-security-policy")).toContain(
      "connect-src 'self'",
    );
    expect(await res.text()).toContain("/v1/code-status");
  });

  it("is limited per address, so it cannot be used to guess codes", async () => {
    let last = 0;
    for (let i = 0; i < 45; i++)
      last = (
        await anon().post("/v1/code-status", { code: "ABCD2345", kind: "i" })
      ).status;
    expect(last).toBe(429);
  });
});
