#!/usr/bin/env node
// Operator-only: explicit, bounded demo identities. Never resets existing passwords.
const fs = require("node:fs");
const { z } = require("zod");
const { Database } = require(
  process.env.BIOBALANCE_DIST + "/shared/infrastructure/database.js",
);
const { PasswordHasher } = require(
  process.env.BIOBALANCE_DIST + "/modules/identity/password-hasher.js",
);
const uuid = z.uuid();
const name = z.string().min(5).max(120).startsWith("DÉMO — ");
const schema = z
  .object({
    dataset: z.literal("biobalance-demo-2026-09"),
    adminId: uuid,
    organizations: z
      .array(z.object({ id: uuid, name }).strict())
      .min(1)
      .max(5),
    users: z
      .array(
        z
          .object({
            id: uuid,
            name,
            email: z.email().endsWith("@demo.biobalance.invalid"),
            password: z.string().min(24).max(128),
            organizationId: uuid,
            owner: z.boolean(),
          })
          .strict(),
      )
      .min(1)
      .max(20),
    memberships: z
      .array(
        z
          .object({
            userId: uuid,
            organizationId: uuid,
            storeId: uuid,
            permissions: z.array(z.enum(["sell", "receive", "manage"])).min(1),
          })
          .strict(),
      )
      .max(50),
  })
  .strict();
async function main() {
  if (process.argv[2] !== "--apply-demo" || !process.argv[3])
    throw Error("Explicit --apply-demo manifest required");
  const input = schema.parse(
    JSON.parse(fs.readFileSync(process.argv[3], "utf8")),
  );
  const orgs = new Set(input.organizations.map((x) => x.id));
  const users = new Map(input.users.map((x) => [x.id, x]));
  if (
    orgs.size !== input.organizations.length ||
    users.size !== input.users.length
  )
    throw Error("Duplicate identities");
  for (const user of input.users)
    if (!orgs.has(user.organizationId))
      throw Error("Unknown demo organization");
  for (const member of input.memberships)
    if (users.get(member.userId)?.organizationId !== member.organizationId)
      throw Error("Invalid demo membership");
  const db = new Database();
  try {
    const actor = await db.user.findUniqueOrThrow({
      where: { id: input.adminId },
    });
    if (!actor.platformAdmin || actor.disabled)
      throw Error("Active administrator required");
    const hashes = new Map();
    const hasher = new PasswordHasher();
    for (const user of input.users)
      hashes.set(user.id, await hasher.hash(user.password));
    await db.authenticated(
      actor,
      async (tx) => {
        for (const org of input.organizations) {
          const old = await tx.organization.findUnique({
            where: { id: org.id },
          });
          if (old && old.name !== org.name)
            throw Error("Existing organization differs");
          if (!old) {
            await tx.organization.create({ data: org });
            await audit(tx, "demo.organization.create", org.id);
          }
        }
        for (const user of input.users) {
          const old = await tx.user.findUnique({ where: { id: user.id } });
          if (
            old &&
            (old.email !== user.email ||
              old.name !== user.name ||
              old.platformAdmin ||
              old.disabled)
          )
            throw Error("Existing user differs");
          if (!old) {
            await tx.user.create({
              data: {
                id: user.id,
                name: user.name,
                email: user.email,
                passwordHash: hashes.get(user.id),
              },
            });
            await audit(tx, "demo.user.create", user.id);
          }
          if (user.owner) {
            const where = {
              organizationId_userId: {
                organizationId: user.organizationId,
                userId: user.id,
              },
            };
            const owner = await tx.organizationMembership.findUnique({ where });
            if (owner && !owner.active)
              throw Error("Cannot reactivate retired demo owner");
            if (!owner) {
              await tx.organizationMembership.create({
                data: where.organizationId_userId,
              });
              await audit(tx, "demo.owner.grant", user.id);
            }
          }
        }
      },
      true,
    );
    for (const member of input.memberships) {
      await db.scoped(
        actor,
        member.organizationId,
        member.storeId,
        async (tx) => {
          const store = await tx.store.findUniqueOrThrow({
            where: { id: member.storeId },
          });
          if (!store.name.startsWith("DÉMO — "))
            throw Error("Demo store required");
          const old = await tx.membership.findUnique({
            where: {
              storeId_userId: {
                storeId: member.storeId,
                userId: member.userId,
              },
            },
          });
          if (
            old &&
            (!old.active ||
              [...old.permissions].sort().join() !==
                [...member.permissions].sort().join())
          )
            throw Error("Existing member differs");
          if (!old) {
            await tx.membership.create({ data: member });
            await audit(tx, "demo.membership.grant", member.userId, member);
          }
        },
      );
    }
    async function audit(tx, action, targetId, scope = {}) {
      await tx.auditEntry.create({
        data: {
          actorId: actor.id,
          action,
          targetId,
          organizationId: scope.organizationId,
          storeId: scope.storeId,
          details: { dataset: input.dataset },
        },
      });
    }
    console.log(
      JSON.stringify({
        dataset: input.dataset,
        organizations: input.organizations.length,
        users: input.users.length,
        memberships: input.memberships.length,
      }),
    );
  } finally {
    await db.$disconnect();
  }
}
main().catch((e) => {
  console.error(
    "Demo provisioning failed:",
    e.name,
    e.message.startsWith("Existing")
      ? e.message
      : "See validated input and database state; no credentials logged",
  );
  process.exitCode = 1;
});
