// Resume only synthetic deployment-lab sessions; preserve all business records.
const { PrismaClient } = require('/app/node_modules/@prisma/client');
const { PrismaPg } = require('/app/node_modules/@prisma/adapter-pg');
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const url = process.env.DATABASE_URL;
if (!url || new URL(url).pathname !== '/biobalance_deployment_test') {
  throw Error('Isolated deployment database required');
}
const fixture = JSON.parse(fs.readFileSync('/run/deployment-fixture.json', 'utf8'));
const db = new PrismaClient({ adapter: new PrismaPg({ connectionString: url }) });
(async () => {
  await db.$transaction(async tx => {
    for (const role of ['manager', 'outsider']) {
      const userId = fixture[role + 'Id'];
      const user = await tx.user.findUniqueOrThrow({ where: { id: userId } });
      if (!user.email.endsWith('@example.test') ||
          user.passwordHash !== '!synthetic-session-only' || user.platformAdmin) {
        throw Error('Expected a synthetic deployment fixture account');
      }
      const tokenHash = createHash('sha256').update(fixture[role + 'Token']).digest('hex');
      const session = await tx.session.findUnique({ where: { tokenHash } });
      if (session && session.userId !== userId) throw Error('Fixture identity mismatch');
      await tx.session.upsert({
        where: { tokenHash },
        create: { tokenHash, userId, expiresAt: new Date(Date.now() + 86400000) },
        update: { expiresAt: new Date(Date.now() + 86400000), revokedAt: null },
      });
    }
  });
  console.log('PASS: isolated fixture sessions renewed; business records preserved.');
})().catch(error => { console.error(error.name); process.exitCode = 1; })
  .finally(() => db.$disconnect());
