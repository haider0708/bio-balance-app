import { assertTestDatabases } from "./test-database.cjs";
import { afterAll, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { Database } from "../src/shared/infrastructure/database";
import { IdentityService } from "../src/modules/identity/identity.service";
import { PasswordHasher } from "../src/modules/identity/password-hasher";
import { accountTokenMessage } from "../src/modules/identity/account-links";
import {
  EmailDeliveryService,
  EmailPayload,
  EmailTransport,
} from "../src/shared/email/email-delivery";
import { EmailContent, renderEmail } from "../src/shared/email/email-templates";
import { SmtpEmailTransport } from "../src/shared/email/smtp-transport";
import { JobRunner } from "../src/shared/jobs/job-runner";

process.env.DATABASE_URL =
  process.env.TEST_APP_DATABASE_URL ??
  "postgresql://biobalance_app:local-app-only@localhost:54329/biobalance_test";
if (!new URL(process.env.DATABASE_URL).pathname.endsWith("_test"))
  throw Error("ISOLATED_TEST_DATABASE_REQUIRED");
assertTestDatabases(process.env.DATABASE_URL);
const db = new Database();
class TestPasswords extends PasswordHasher {
  override async hash(password: string) {
    return `test:${password}`;
  }
  override async verify(hash: string, password: string) {
    return hash === `test:${password}`;
  }
}
const identity = new IdentityService(db, new TestPasswords());
afterAll(() => db.$disconnect());
async function account(admin = false) {
  return db.user.create({
    data: {
      email: `${randomUUID()}@example.test`,
      name: "Email test",
      platformAdmin: admin,
      passwordHash: "test:original",
    },
  });
}
async function invitation(staff = false) {
  const admin = await account(true);
  const org = await db.organization.create({
    data: { name: "Organisation <Nord> & Sud" },
  });
  const store = staff
    ? await db.store.create({
        data: {
          organizationId: org.id,
          name: 'Magasin "Tunis"',
          address: "Test",
          city: "Tunis",
        },
      })
    : null;
  const recipient = `${randomUUID()}@example.test`;
  const result = await identity.invite(admin, {
    email: recipient,
    organizationId: org.id,
    ...(store ? { storeId: store.id } : {}),
    permissions: staff ? ["sell"] : [],
  });
  const job = await db.job.findUniqueOrThrow({
    where: { key: `invite:${result.id}` },
  });
  return {
    admin,
    org,
    store,
    recipient,
    tokenId: result.id,
    job: { ...job, payload: job.payload as Record<string, string> },
  };
}
function recorder() {
  const sent: { to: string; content: EmailContent; id: string }[] = [];
  const transport: EmailTransport = {
    async send(to, content, id) {
      sent.push({ to, content, id });
    },
  };
  return { sent, service: new EmailDeliveryService(db, transport) };
}

it("renders complete French multipart content with escaped context, one copyable code and Tunis expiry", () => {
  const token = randomBytes(32).toString("base64url");
  for (const kind of ["invite", "reset"] as const) {
    const message = renderEmail({
      kind,
      token,
      storeName: '<img src=x onerror="bad()">',
      expiresAt: new Date("2026-09-22T12:30:00Z"),
    });
    expect(message.html).toContain('lang="fr"');
    expect(message.html).toContain("13:30");
    expect(message.html).toContain(token);
    expect(message.text).toContain(token);
    expect(message.text).toContain("heure de Tunis");
    expect(message.html).not.toMatch(/<img|<script|<iframe|<link|https?:\/\//);
    if (kind === "invite") expect(message.html).toContain("&lt;img");
  }
  const security = renderEmail({
    kind: "password-changed",
    changedAt: new Date("2026-09-22T12:30:00Z"),
  });
  expect(security.text).toContain("sessions précédentes ont été fermées");
  expect(security.html).not.toContain("Votre code personnel");
});

it("uses optional owned HTTPS links and keeps the manual code in both alternatives", () => {
  const before = process.env.ACTIVATION_URL;
  try {
    process.env.ACTIVATION_URL = "https://accounts.example.test/activate";
    const message = renderEmail({
      kind: "invite",
      token: "abc",
      expiresAt: new Date(),
    });
    expect(message.text).toContain(
      "https://accounts.example.test/activate?token=abc",
    );
    expect(message.html).toContain(
      'href="https://accounts.example.test/activate?token=abc"',
    );
    expect(message.text).toContain("Votre code : abc");
    process.env.ACTIVATION_URL = "https://untrusted.example/other";
    expect(() =>
      renderEmail({ kind: "invite", token: "abc", expiresAt: new Date() }),
    ).toThrow();
  } finally {
    if (before === undefined) delete process.env.ACTIVATION_URL;
    else process.env.ACTIVATION_URL = before;
  }
});

it("renders manager and staff invitations from authorized current organization/store context", async () => {
  for (const staff of [false, true]) {
    const f = await invitation(staff),
      r = recorder();
    expect(await r.service.deliver(f.job, async () => true)).toBe("accepted");
    expect(r.sent).toHaveLength(1);
    expect(r.sent[0]!.to).toBe(f.recipient);
    expect(r.sent[0]!.content.text).toContain(
      staff ? f.store!.name : f.org.name,
    );
    expect(
      await db.user.findUnique({ where: { email: f.recipient } }),
    ).toBeNull();
  }
});

it("suppresses expired/consumed invitations and disabled issuers without invoking SMTP", async () => {
  for (const cause of ["expired", "used", "disabled"] as const) {
    const f = await invitation(),
      r = recorder();
    if (cause === "disabled")
      await db.user.update({
        where: { id: f.admin.id },
        data: { disabled: true },
      });
    else
      await db.accessToken.update({
        where: { id: f.tokenId },
        data:
          cause === "used"
            ? { usedAt: new Date() }
            : { expiresAt: new Date(0) },
      });
    expect(await r.service.deliver(f.job, async () => true)).toBe("suppressed");
    expect(r.sent).toHaveLength(0);
  }
});

it("rechecks issuer store management permission at email delivery", async () => {
  const f = await invitation(true),
    manager = await account();
  await db.membership.create({
    data: {
      organizationId: f.org.id,
      storeId: f.store!.id,
      userId: manager.id,
      permissions: ["sell"],
    },
  });
  await db.accessToken.update({
    where: { id: f.tokenId },
    data: { createdBy: manager.id },
  });
  const r = recorder();
  expect(await r.service.deliver(f.job, async () => true)).toBe("suppressed");
  await db.membership.update({
    where: { storeId_userId: { storeId: f.store!.id, userId: manager.id } },
    data: { permissions: ["manage"] },
  });
  expect(await r.service.deliver(f.job, async () => true)).toBe("accepted");
  expect(r.sent).toHaveLength(1);
});

it("rejects a substituted code/recipient, injected headers, unknown template and a lost lease", async () => {
  const f = await invitation(),
    r = recorder();
  for (const extra of [
    { token: randomBytes(32).toString("base64url") },
    { to: "another@example.test" },
  ]) {
    await expect(
      r.service.deliver(
        { ...f.job, payload: { ...f.job.payload, ...extra } },
        async () => true,
      ),
    ).rejects.toThrow("EMAIL_CAPABILITY_MISMATCH");
  }
  for (const extra of [
    { to: "a@example.test\r\nBcc: b@example.test" },
    { template: "newsletter" },
  ]) {
    await expect(
      r.service.deliver(
        { ...f.job, payload: { ...f.job.payload, ...extra } },
        async () => true,
      ),
    ).rejects.toThrow("EMAIL_PAYLOAD_INVALID");
  }
  await expect(r.service.deliver(f.job, async () => false)).rejects.toThrow(
    "EMAIL_LEASE_LOST",
  );
  expect(r.sent).toHaveLength(0);
});

it("upgrades legacy queued text in memory without changing IDs, payload bytes or granting access", async () => {
  const f = await invitation(),
    r = recorder();
  const legacy = {
    ...f.job,
    payload: {
      to: f.recipient,
      subject: "Old subject",
      text: accountTokenMessage("invite", f.job.payload.token!),
    },
  };
  const before = JSON.stringify(legacy);
  expect(await r.service.deliver(legacy, async () => true)).toBe("accepted");
  expect(JSON.stringify(legacy)).toBe(before);
  expect(r.sent[0]!.id).toBe(f.job.id);
  expect(r.sent[0]!.content.html).toContain("Activer votre accès");
});

it("reset and confirmation are transactional, single use, close sessions, and keep secrets out of confirmation", async () => {
  const user = await account();
  const session = await db.session.create({
    data: {
      userId: user.id,
      tokenHash: randomUUID(),
      expiresAt: new Date(Date.now() + 3600000),
    },
  });
  await identity.forgot(user.email, randomUUID());
  const reset = await db.accessToken.findFirstOrThrow({
    where: { email: user.email, purpose: "reset" },
  });
  const job = await db.job.findUniqueOrThrow({
    where: { key: `reset:${reset.id}` },
  });
  const payload = EmailPayload.parse(job.payload);
  if (payload.template !== "reset") throw Error("RESET_EXPECTED");
  const r = recorder();
  expect(await r.service.deliver({ ...job, payload }, async () => true)).toBe(
    "accepted",
  );
  await identity.reset(payload.token, "replacement", randomUUID());
  expect(
    (await db.session.findUniqueOrThrow({ where: { id: session.id } }))
      .revokedAt,
  ).not.toBeNull();
  await expect(
    identity.reset(payload.token, "another", randomUUID()),
  ).rejects.toMatchObject({ code: "RESET_EXPIRED" });
  expect(
    await db.job.count({ where: { key: `password-changed:${reset.id}` } }),
  ).toBe(1);
  const confirmation = await db.job.findUniqueOrThrow({
    where: { key: `password-changed:${reset.id}` },
  });
  expect(
    await r.service.deliver(
      {
        ...confirmation,
        payload: confirmation.payload as Record<string, string>,
      },
      async () => true,
    ),
  ).toBe("accepted");
  const content = r.sent[1]!.content;
  expect(JSON.stringify(content)).not.toContain(payload.token);
  expect(JSON.stringify(content)).not.toContain("replacement");
  expect(await r.service.deliver({ ...job, payload }, async () => true)).toBe(
    "suppressed",
  );
});

it("disabled recipients and unknown addresses cannot receive reset emails; target throttling resists rotating IPs", async () => {
  const disabled = await account();
  await db.user.update({
    where: { id: disabled.id },
    data: { disabled: true },
  });
  const unknown = `${randomUUID()}@example.test`;
  const a = await identity.forgot(disabled.email, randomUUID());
  expect(await identity.forgot(unknown, randomUUID())).toEqual(a);
  expect(
    await db.job.count({
      where: { payload: { path: ["to"], equals: disabled.email } },
    }),
  ).toBe(0);
  const user = await account();
  for (let i = 0; i < 3; i++) await identity.forgot(user.email, randomUUID());
  await expect(identity.forgot(user.email, randomUUID())).rejects.toMatchObject(
    { code: "TOO_MANY_ATTEMPTS" },
  );
  const jobs = await db.job.findMany({
    where: { payload: { path: ["to"], equals: user.email } },
  });
  expect(jobs).toHaveLength(3);
  await db.user.update({ where: { id: user.id }, data: { disabled: true } });
  const r = recorder();
  expect(
    await r.service.deliver(
      { ...jobs[0]!, payload: jobs[0]!.payload as Record<string, string> },
      async () => true,
    ),
  ).toBe("suppressed");
  expect(r.sent).toHaveLength(0);
});

it("a response lost after SMTP acceptance retries the same message identity and clears completed secrets", async () => {
  const f = await invitation();
  const ids: string[] = [];
  const service = new EmailDeliveryService(db, {
    async send(_to, _content, id) {
      ids.push(id);
      if (ids.length === 1) throw Error("SMTP_RESPONSE_LOST");
    },
  });
  const runner = new JobRunner(db, ["email"], (job, owned) =>
    service.deliver(job, owned).then(() => {}),
  );
  // Target this fixture explicitly; never drain unrelated test jobs.
  for (let attempt = 1; attempt <= 2; attempt++) {
    const leaseToken = randomUUID();
    await db.job.update({
      where: { id: f.job.id },
      data: { status: "running", leaseToken, attempts: attempt },
    });
    const claimed = { ...f.job, attempts: attempt, leaseToken };
    try {
      await service.deliver(claimed, async () => runner.renew(claimed));
      await runner.complete(claimed);
    } catch (error) {
      await runner.fail(claimed, error);
    }
  }
  expect(ids).toEqual([f.job.id, f.job.id]);
  expect(
    await db.job.findUniqueOrThrow({ where: { id: f.job.id } }),
  ).toMatchObject({ status: "completed", payload: {} });
});

it("delivers real multipart invitations, recovery and security notices to isolated Mailpit with stable Message-ID", async () => {
  const smtp = new SmtpEmailTransport({
    SMTP_HOST: "127.0.0.1",
    SMTP_PORT: "1029",
    SMTP_FROM: "BioBalance <mail@example.test>",
  });
  const service = new EmailDeliveryService(db, smtp);
  const f = await invitation(true);
  try {
    await service.deliver(f.job, async () => true);
    await identity.activate(
      f.job.payload.token!,
      "Mail recipient",
      "original",
      randomUUID(),
    );
    await identity.forgot(f.recipient, randomUUID());
    const reset = await db.accessToken.findFirstOrThrow({
      where: { email: f.recipient, purpose: "reset" },
    });
    const resetJob = await db.job.findUniqueOrThrow({
      where: { key: `reset:${reset.id}` },
    });
    const resetPayload = resetJob.payload as Record<string, string>;
    await service.deliver(
      { ...resetJob, payload: resetPayload },
      async () => true,
    );
    await identity.reset(resetPayload.token!, "changed", randomUUID());
    const confirmation = await db.job.findUniqueOrThrow({
      where: { key: `password-changed:${reset.id}` },
    });
    await service.deliver(
      {
        ...confirmation,
        payload: confirmation.payload as Record<string, string>,
      },
      async () => true,
    );
    const response = await fetch(
      `http://127.0.0.1:8029/api/v1/search?query=${encodeURIComponent(`to:${f.recipient}`)}`,
    );
    expect(response.ok).toBe(true);
    const result = (await response.json()) as {
      messages: { ID: string; Subject: string; MessageID: string }[];
    };
    expect(result.messages).toHaveLength(3);
    for (const summary of result.messages) {
      const detail = (await (
        await fetch(`http://127.0.0.1:8029/api/v1/message/${summary.ID}`)
      ).json()) as { HTML: string; Text: string; MessageID: string };
      expect(detail.HTML).toContain('lang="fr"');
      expect(detail.Text).toContain("BioBalance");
      expect(detail.MessageID).toMatch(/@example\.test>?$/);
    }
  } finally {
    smtp.close();
  }
}, 20000);

it("delivers a new-group grant before the organization exists", async () => {
  const admin = await account(true),
    r = recorder();
  const invitation = await identity.invite(admin, {
    kind: "new_group",
    email: `${randomUUID()}@example.test`,
    permissions: [],
  });
  const job = await db.job.findUniqueOrThrow({
    where: { key: `invite:${invitation.id}` },
  });
  expect(
    await r.service.deliver(
      { ...job, payload: job.payload as Record<string, string> },
      async () => true,
    ),
  ).toBe("accepted");
  expect(r.sent[0]!.content.text).toContain("créer votre groupe");
  expect(
    (await db.accessToken.findUniqueOrThrow({ where: { id: invitation.id } }))
      .organizationId,
  ).toBeNull();
});

it("issues eight uppercase recovery characters, accepts grouped paste, and supersedes the previous code", async () => {
  const user = await account(),
    r = recorder();
  await identity.forgot(user.email, randomUUID());
  const old = await db.accessToken.findFirstOrThrow({
    where: { email: user.email, purpose: "reset", usedAt: null },
  });
  const oldJob = await db.job.findUniqueOrThrow({
    where: { key: `reset:${old.id}` },
  });
  await identity.forgot(user.email, randomUUID());
  const current = await db.accessToken.findFirstOrThrow({
    where: { email: user.email, purpose: "reset", usedAt: null },
  });
  const job = await db.job.findUniqueOrThrow({
    where: { key: `reset:${current.id}` },
  });
  const payload = EmailPayload.parse(job.payload);
  if (payload.template !== "reset") throw Error("RESET_EXPECTED");
  expect(payload.token).toMatch(/^[A-Z0-9]{8}$/);
  expect(current.expiresAt.getTime() - Date.now()).toBeLessThanOrEqual(1800000);
  expect(current.tokenHash).not.toContain(payload.token);
  expect(
    await r.service.deliver(
      { ...oldJob, payload: oldJob.payload as Record<string, string> },
      async () => true,
    ),
  ).toBe("suppressed");
  expect(await r.service.deliver({ ...job, payload }, async () => true)).toBe(
    "accepted",
  );
  const grouped = payload.token.slice(0, 4) + "-" + payload.token.slice(4);
  expect(r.sent[0]!.content.text).toContain(grouped);
  await identity.reset(grouped.toLowerCase(), "replacement", randomUUID());
  await expect(
    identity.reset(payload.token, "again", randomUUID()),
  ).rejects.toMatchObject({ code: "RESET_EXPIRED" });
});

it("keeps one active group invitation per email, including simultaneous sends, and retains the old records", async () => {
  const admin = await account(true);
  const group = await db.organization.create({
    data: { name: "Invitation regression" },
  });
  const email = `${randomUUID()}@example.test`;
  const input = {
    email,
    organizationId: group.id,
    kind: "responsible" as const,
    storeIds: [],
    permissions: [],
  };
  const result = await Promise.all([
    identity.invite(admin, input),
    identity.invite(admin, input),
  ]);
  const rows = await db.accessToken.findMany({
    where: { email, purpose: "invite", organizationId: group.id },
  });
  expect(rows).toHaveLength(2);
  const active = rows.filter((r) => !r.usedAt);
  expect(active).toHaveLength(1);
  const old = result.find((r) => r.id !== active[0]!.id)!;
  const oldJob = await db.job.findUniqueOrThrow({
    where: { key: `invite:${old.id}` },
  });
  const r = recorder();
  expect(
    await r.service.deliver(
      { ...oldJob, payload: oldJob.payload as Record<string, string> },
      async () => true,
    ),
  ).toBe("suppressed");
  const latest = await db.job.findUniqueOrThrow({
    where: { key: `invite:${active[0]!.id}` },
  });
  await identity.activate(
    (latest.payload as Record<string, string>).token!,
    "Invité",
    "password",
    randomUUID(),
  );
  await expect(identity.invite(admin, input)).rejects.toMatchObject({
    code: "MEMBER_ALREADY_EXISTS",
  });
});

it("serializes simultaneous recovery replacements without keeping two usable codes", async () => {
  const user = await account();
  await Promise.all([
    identity.forgot(user.email, randomUUID()),
    identity.forgot(user.email, randomUUID()),
  ]);
  const rows = await db.accessToken.findMany({
    where: { email: user.email, purpose: "reset" },
  });
  expect(rows).toHaveLength(2);
  expect(rows.filter((row) => !row.usedAt)).toHaveLength(1);
});

it("delivers a group manager's seller invitation and activates only its latest code with store-scoped access", async () => {
  const manager = await account();
  const group = await db.organization.create({
    data: { name: "Seller invitation regression" },
  });
  const store = await db.store.create({
    data: {
      organizationId: group.id,
      name: "Tunis",
      address: "Test",
      city: "Tunis",
    },
  });
  await db.organizationMembership.create({
    data: { organizationId: group.id, userId: manager.id },
  });
  const recipient = `${randomUUID()}+vendeur@example.test`;
  const input = {
    email: recipient,
    kind: "salesperson" as const,
    organizationId: group.id,
    storeIds: [store.id],
    permissions: ["sell", "receive"],
  };
  const first = await identity.invite(manager, input);
  const oldJob = await db.job.findUniqueOrThrow({
    where: { key: `invite:${first.id}` },
  });
  const latest = await identity.invite(manager, input);
  const job = await db.job.findUniqueOrThrow({
    where: { key: `invite:${latest.id}` },
  });
  const r = recorder();
  expect(
    await r.service.deliver(
      { ...oldJob, payload: oldJob.payload as Record<string, string> },
      async () => true,
    ),
  ).toBe("suppressed");
  expect(
    await r.service.deliver(
      { ...job, payload: job.payload as Record<string, string> },
      async () => true,
    ),
  ).toBe("accepted");
  expect(r.sent).toHaveLength(1);
  expect(r.sent[0]!.to).toBe(recipient);
  await expect(
    identity.activate(
      (oldJob.payload as Record<string, string>).token!,
      "Vendeur",
      "seller-password",
      randomUUID(),
    ),
  ).rejects.toMatchObject({ code: "INVITATION_EXPIRED" });
  const code = (job.payload as Record<string, string>).token!;
  await identity.activate(code, "Vendeur", "seller-password", randomUUID());
  const session = await identity.login(
    recipient,
    "seller-password",
    undefined,
    randomUUID(),
  );
  expect(session.user.platformAdmin).toBe(false);
  const memberships = await db.membership.findMany({
    where: { userId: session.user.id },
  });
  expect(memberships).toHaveLength(1);
  expect(memberships[0]).toMatchObject({
    storeId: store.id,
    active: true,
    permissions: ["sell", "receive"],
  });
  expect(
    await db.organizationMembership.count({
      where: { userId: session.user.id },
    }),
  ).toBe(0);
  await expect(
    identity.activate(code, "Vendeur", "seller-password", randomUUID()),
  ).rejects.toMatchObject({ code: "INVITATION_EXPIRED" });
});
