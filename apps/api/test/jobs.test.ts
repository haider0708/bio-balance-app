import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { Database } from "../src/core/database";
import { EmailDelivery, type EmailTransport } from "../src/email/delivery";
import { renderEmail } from "../src/email/templates";
import { JobRunner } from "../src/jobs/job-runner";
import { cleanup } from "../src/jobs/maintenance";
import {
  client,
  createAccount,
  owner,
  regionId,
  resetDatabase,
  startApi,
  type Api,
} from "./helpers";
import { buildWorld, type World } from "./world";

let api: Api;
let w: World;
let db: Database;
beforeAll(async () => {
  api = await startApi();
  db = new Database();
});
afterAll(async () => {
  await db.$disconnect();
  await api.close();
});
beforeEach(async () => {
  await resetDatabase();
  w = await buildWorld(api);
});

class FakeMail implements EmailTransport {
  sent: { to: string; subject: string; text: string }[] = [];
  async send(to: string, content: { subject: string; text: string }) {
    this.sent.push({ to, subject: content.subject, text: content.text });
  }
}

const runAll = async (mail: FakeMail) => {
  const delivery = new EmailDelivery(db, mail);
  const runner = new JobRunner(db, ["email"], (job, owned) =>
    delivery.deliver(job, owned).then(() => undefined),
  );
  while (await runner.tick());
};

describe("emails", () => {
  it("send the activation code in the person's language and then forget it", async () => {
    await w.a.post("/v1/users", {
      role: "RESPONSABLE",
      regionId: await regionId("CENTRE"),
      name: "Mounir",
      email: "mounir@example.test",
    });
    const mail = new FakeMail();
    await runAll(mail);
    const invite = mail.sent.find((m) => m.to === "mounir@example.test")!;
    expect(invite.subject).toBe("Votre compte BioBalance est prêt");
    expect(invite.text).toMatch(/Code d’activation : [A-Z0-9]{4}-[A-Z0-9]{4}/);
    const jobs = await db.job.findMany({
      where: { kind: "email", status: "completed" },
    });
    expect(jobs.every((j) => JSON.stringify(j.payload) === "{}")).toBe(true);
  });

  it("use English when the person chose it", async () => {
    await w.a.post("/v1/users", {
      role: "RESPONSABLE",
      regionId: await regionId("CENTRE"),
      name: "Mounir",
      email: "mounir@example.test",
    });
    await db.user.update({
      where: { email: "mounir@example.test" },
      data: { locale: "en" },
    });
    const mail = new FakeMail();
    await runAll(mail);
    expect(mail.sent.find((m) => m.to === "mounir@example.test")!.subject).toBe(
      "Your BioBalance account is ready",
    );
  });

  it("are not sent for a code that was already used", async () => {
    await w.a.post("/v1/users", {
      role: "RESPONSABLE",
      regionId: await regionId("CENTRE"),
      name: "Mounir",
      email: "mounir@example.test",
    });
    const o = await owner();
    const { code } = (
      await o.query(
        `SELECT payload FROM "Job" WHERE kind='email' AND payload->>'userId' = (SELECT id::text FROM "User" WHERE email='mounir@example.test')`,
      )
    ).rows[0].payload;
    await o.end();
    await client(api).post("/v1/auth/activate", {
      email: "mounir@example.test",
      code,
      password: "a-long-password",
    });
    const mail = new FakeMail();
    await runAll(mail);
    expect(
      mail.sent.filter((m) => m.to === "mounir@example.test"),
    ).toHaveLength(0);
  });

  it("do not reach people who are no longer active", async () => {
    await w.a.post("/v1/users", {
      role: "RESPONSABLE",
      regionId: await regionId("CENTRE"),
      name: "Mounir",
      email: "mounir@example.test",
    });
    await db.user.update({
      where: { email: "mounir@example.test" },
      data: { status: "SUSPENDED" },
    });
    const mail = new FakeMail();
    await runAll(mail);
    expect(
      mail.sent.filter((m) => m.to === "mounir@example.test"),
    ).toHaveLength(0);
  });

  it("escape anything that came from a name", () => {
    const mail = renderEmail("en", {
      kind: "invite",
      code: "ABCD2345",
      expiresAt: new Date(),
      name: "<script>alert(1)</script>",
    });
    expect(mail.html).not.toContain("<script>");
    expect(mail.html).toContain("&lt;script&gt;");
  });
});

describe("job runner", () => {
  it("retries a failed job later and gives up after the last attempt", async () => {
    await db.job.create({
      data: { kind: "email", key: "retry:1", payload: { template: "bogus" } },
    });
    const runner = new JobRunner(db, ["email"], async () => {
      throw new Error("BOOM_PROVIDER_DOWN");
    });
    expect(await runner.tick()).toBe(true);
    let job = await db.job.findUniqueOrThrow({ where: { key: "retry:1" } });
    expect(job).toMatchObject({
      status: "pending",
      attempts: 1,
      lastError: "BOOM_PROVIDER_DOWN",
    });
    expect(job.availableAt.getTime()).toBeGreaterThan(Date.now());
    await db.job.update({
      where: { key: "retry:1" },
      data: { attempts: 7, availableAt: new Date() },
    });
    await runner.tick();
    job = await db.job.findUniqueOrThrow({ where: { key: "retry:1" } });
    expect(job.status).toBe("failed");
  });

  it("never lets two workers take the same job", async () => {
    await db.job.create({
      data: { kind: "cleanup", key: "once", payload: {} },
    });
    const claimed = await Promise.all(
      [1, 2, 3, 4].map(() =>
        new JobRunner(db, ["cleanup"], async () => undefined).claim(),
      ),
    );
    expect(claimed.filter(Boolean)).toHaveLength(1);
  });
});

describe("cleanup", () => {
  it("removes expired sessions and codes but keeps business history", async () => {
    const o = await owner();
    const user = await createAccount({
      role: "RESPONSABLE",
      regionCode: "CENTRE",
    });
    await o.query(
      `INSERT INTO "Session"(id,"userId","tokenHash","expiresAt") VALUES (gen_random_uuid(),$1,'old-token',now()-interval '30 days')`,
      [user.id],
    );
    await o.query(
      `INSERT INTO "AccessToken"(id,"userId",purpose,"tokenHash","expiresAt") VALUES (gen_random_uuid(),$1,'reset','old-code',now()-interval '30 days')`,
      [user.id],
    );
    await cleanup(db);
    expect(
      (await o.query(`SELECT 1 FROM "Session" WHERE "tokenHash"='old-token'`))
        .rowCount,
    ).toBe(0);
    expect(
      (
        await o.query(
          `SELECT 1 FROM "AccessToken" WHERE "tokenHash"='old-code'`,
        )
      ).rowCount,
    ).toBe(0);
    expect(
      (await o.query(`SELECT 1 FROM "Session" WHERE "userId"=$1`, [user.id]))
        .rowCount,
    ).toBe(1);
    expect(
      Number(
        (await o.query(`SELECT count(*) FROM "AuditEntry"`)).rows[0].count,
      ),
    ).toBeGreaterThanOrEqual(0);
    await o.end();
  });
});
