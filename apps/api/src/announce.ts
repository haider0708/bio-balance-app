import "reflect-metadata";
import { Database } from "./core/database";
import type { Actor } from "./core/actor";
import { UsersService } from "./modules/directory/users.service";

/**
 * Brings everyone to the current app, once, from the server:
 *   node dist/announce.js            only counts who would be reached (nothing is changed)
 *   node dist/announce.js --send     does it
 * People waiting for approval are approved and, like anyone invited who has not chosen a password yet,
 * get the welcome message with a fresh temporary password. People who already have their own password get
 * the "update your app" message (email and WhatsApp). Suspended people and admins are
 * left out. Running it again sends the update message to nobody twice (same job key).
 */
const VERSION = process.env.ANNOUNCE_VERSION;
if (!VERSION)
  throw new Error(
    "Set ANNOUNCE_VERSION to the version being announced (it keeps one message per person per version).",
  );

async function main() {
  const send = process.argv.includes("--send");
  const db = new Database();
  try {
    const people = await db.run("SYSTEM", (tx) =>
      tx.user.findMany({
        where: {
          role: { not: "ADMIN" },
          status: { in: ["PENDING", "ACTIVE"] },
        },
        select: {
          id: true,
          status: true,
          passwordHash: true,
          mustChangePassword: true,
          phone: true,
        },
        orderBy: { createdAt: "asc" },
      }),
    );
    const pending = people.filter((u) => u.status === "PENDING");
    const invited = people.filter(
      (u) => u.status === "ACTIVE" && (!u.passwordHash || u.mustChangePassword),
    );
    const updating = people.filter(
      (u) => u.status === "ACTIVE" && u.passwordHash && !u.mustChangePassword,
    );
    const withPhone = (list: typeof people) =>
      list.filter((u) => u.phone).length;
    console.log(
      JSON.stringify({
        send,
        approveAndWelcome: pending.length,
        welcomeAgain: invited.length,
        updateMessage: updating.length,
        whatsappReach: {
          welcome: withPhone(pending) + withPhone(invited),
          update: withPhone(updating),
        },
      }),
    );
    if (!send) return;

    const admin = await db.user.findFirstOrThrow({
      where: { role: "ADMIN", status: "ACTIVE" },
      orderBy: { createdAt: "asc" },
    });
    const actor: Actor = {
      id: admin.id,
      name: admin.name,
      email: admin.email,
      role: "ADMIN",
      regionId: null,
      pdvId: null,
      locale: admin.locale === "en" ? "en" : "fr",
    };
    const users = new UsersService(db);
    let failed = 0;
    for (const u of pending) {
      try {
        await users.decide(actor, u.id, "approve");
      } catch (error) {
        failed++;
        console.error("approve failed", u.id, (error as Error).message);
      }
    }
    for (const u of invited) {
      try {
        await users.resendInvite(actor, u.id);
      } catch (error) {
        failed++;
        console.error("welcome failed", u.id, (error as Error).message);
      }
    }
    const jobs = updating.flatMap((u) => {
      const payload = { template: "update", userId: u.id, version: VERSION };
      return [
        { kind: "email", key: `update:${VERSION}:${u.id}`, payload },
        { kind: "whatsapp", key: `wa:update:${VERSION}:${u.id}`, payload },
      ];
    });
    const queued = await db.run("SYSTEM", (tx) =>
      tx.job.createMany({ data: jobs, skipDuplicates: true }),
    );
    console.log(JSON.stringify({ queuedUpdateJobs: queued.count, failed }));
  } finally {
    await db.$disconnect();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
