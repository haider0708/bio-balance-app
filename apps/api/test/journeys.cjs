/* Test-only harness. Never imported by the production application. */
const { randomUUID, randomBytes } = require("node:crypto");
const { spawn } = require("node:child_process");
const { mkdtemp, writeFile, rm } = require("node:fs/promises");
const path = require("node:path"),
  os = require("node:os"),
  assert = require("node:assert/strict");
const { NestFactory } = require("@nestjs/core"),
  express = require("express");
const { PrismaClient } = require("@prisma/client"),
  { PrismaPg } = require("@prisma/adapter-pg"),
  argon2 = require("argon2");
require("reflect-metadata");
const appUrl =
  process.env.TEST_APP_DATABASE_URL ??
  "postgresql://biobalance_app:local-app-only@localhost:54329/biobalance_journeys_test";
const ownerUrl =
  process.env.TEST_OWNER_DATABASE_URL ??
  "postgresql://biobalance:local-development-only@localhost:54329/biobalance_journeys_test";
if (
  ![appUrl, ownerUrl].every((v) =>
    new URL(v).pathname.endsWith("_journeys_test"),
  )
)
  throw Error("ISOLATED_JOURNEY_DATABASE_REQUIRED");
require("./test-database.cjs").assertTestDatabases(appUrl, ownerUrl);
process.env.DATABASE_URL = appUrl;
process.env.MFA_ENCRYPTION_KEY = randomBytes(32).toString("base64");
const { AppModule } = require("../dist/app.module"),
  {
    encryptSecret,
    totp,
  } = require("../dist/modules/identity/identity.service");
const owner = new PrismaClient({
  adapter: new PrismaPg({ connectionString: ownerUrl }),
});
(async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "biobalance-journey-"));
  process.env.MEDIA_ROOT = root;
  const app = await NestFactory.create(AppModule, {
    logger: false,
    bodyParser: false,
  });
  const suffix = randomUUID().slice(0, 8),
    key = randomUUID(),
    secret = randomBytes(20).toString("hex"),
    password = "Journey-password-7391!";
  const adminEmail = `admin-${suffix}@example.test`,
    managerEmail = `manager-${suffix}@example.test`,
    sellerEmail = `seller-${suffix}@example.test`;
  const admin = await owner.user.create({
    data: {
      email: adminEmail,
      name: "Admin parcours",
      passwordHash: await argon2.hash(password),
      platformAdmin: true,
      mfaSecret: encryptSecret(secret),
    },
  });
  const settings = {
    TEST_KEY: key,
    ADMIN_EMAIL: adminEmail,
    MANAGER_EMAIL: managerEmail,
    SELLER_EMAIL: sellerEmail,
    TEST_PASSWORD: password,
    PRODUCT_NAME: `Sérum parcours ${suffix}`,
    PRODUCT_REF: `PDRN-${suffix}`,
    STORE_NAME: `Parapharmacie ${suffix}`,
  };
  app.use(
    "/v1/media/uploads",
    express.raw({ type: "application/octet-stream", limit: "4mb" }),
  );
  app.use(express.json({ limit: "1mb" }));
  const router = express.Router();
  router.use((req, res, next) =>
    req.headers["x-test-key"] === key ? next() : res.sendStatus(404),
  );
  async function state() {
    const manager = await owner.user.findUnique({
        where: { email: managerEmail },
      }),
      seller = await owner.user.findUnique({ where: { email: sellerEmail } });
    const org = manager
      ? await owner.organizationMembership.findFirst({
          where: { userId: manager.id },
        })
      : null;
    const store = org
      ? await owner.store.findFirst({
          where: {
            organizationId: org.organizationId,
            name: settings.STORE_NAME,
          },
        })
      : null;
    const invitation = async (email) => {
      const job = await owner.job.findFirst({
        where: { kind: "email", payload: { path: ["to"], equals: email } },
        orderBy: { createdAt: "desc" },
      });
      return (
        job?.payload.token ??
        job?.payload.text?.match(/ : ([\w-]{43})\./)?.[1] ??
        null
      );
    };
    const product = await owner.product.findUnique({
      where: { reference: settings.PRODUCT_REF },
    });
    const adminState = await owner.user.findUniqueOrThrow({
        where: { id: admin.id },
      }),
      currentStep = BigInt(Math.floor(Date.now() / 30000));
    const otpStep =
      adminState.lastTotpStep >= currentStep
        ? adminState.lastTotpStep + 1n
        : currentStep;
    return {
      managerCode: await invitation(managerEmail),
      sellerCode: await invitation(sellerEmail),
      otp: otpStep <= currentStep + 1n ? totp(secret, otpStep) : null,
      manager,
      seller,
      store,
      product,
      lots: store
        ? await owner.inventoryLot.findMany({ where: { storeId: store.id } })
        : [],
      sales: store
        ? await owner.sale.findMany({ where: { storeId: store.id } })
        : [],
      points: store
        ? await owner.pointsAccount.findMany({ where: { storeId: store.id } })
        : [],
      claims: store
        ? await owner.rewardClaim.findMany({ where: { storeId: store.id } })
        : [],
      deliveries: store
        ? await owner.delivery.findMany({ where: { storeId: store.id } })
        : [],
      orders: store
        ? await owner.replenishmentOrder.findMany({
            where: { storeId: store.id },
          })
        : [],
      revisions: store
        ? await owner.saleRevision.count({ where: { storeId: store.id } })
        : 0,
    };
  }
  router.get("/state", async (req, res) => {
    try {
      const value = await state();
      if (value.manager) delete value.manager.passwordHash;
      if (value.seller) delete value.seller.passwordHash;
      res.json(value);
    } catch {
      res.sendStatus(500);
    }
  });
  router.post("/revoke", async (req, res) => {
    const value = await state();
    if (!value.store || !value.seller) return res.sendStatus(409);
    await owner.membership.update({
      where: {
        storeId_userId: { storeId: value.store.id, userId: value.seller.id },
      },
      data: { active: false },
    });
    res.json({ ok: true });
  });
  app.use("/__test", router);
  app
    .getHttpAdapter()
    .getInstance()
    .set("json replacer", (_k, v) =>
      typeof v === "bigint" ? v.toString() : v,
    );
  let child;
  try {
    await app.listen(0, "127.0.0.1");
    const port = app.getHttpServer().address().port;
    const config = path.join(root, "defines.json");
    await writeFile(
      config,
      JSON.stringify({
        ...settings,
        API_BASE_URL: `http://${process.env.TEST_API_HOST ?? "10.0.2.2"}:${port}`,
      }),
      { mode: 0o600 },
    );
    const code = await new Promise((resolve, reject) => {
      child = spawn(
        process.env.FLUTTER_BIN ?? "flutter",
        [
          "drive",
          "--keep-app-running",
          "--driver=test_driver/integration_test.dart",
          "--target=integration_test/role_journeys_test.dart",
          "-d",
          process.env.TEST_DEVICE ?? "emulator-5554",
          `--dart-define-from-file=${config}`,
        ],
        {
          cwd: path.resolve(__dirname, "../../mobile"),
          stdio: "inherit",
          env: process.env,
        },
      );
      child.on("error", reject);
      child.on("exit", resolve);
    });
    assert.equal(code, 0, "Native Flutter role journeys failed");
    const final = await state();
    assert(final.store && final.product && final.seller);
    assert.equal(final.revisions, 3);
    assert.equal(final.claims[0].status, "fulfilled");
    assert.equal(final.deliveries[0].status, "received");
    assert.equal(final.sales[0].sellerId, final.seller.id);
    assert.equal(
      final.lots.reduce((sum, lot) => sum + lot.sellable, 0),
      21,
    );
    const points = final.points.find((p) => p.userId === final.seller.id);
    assert.equal(points.balance, 20n);
    assert.equal(points.reserved, 0n);
    console.log(
      "PASS: Android role journeys with isolated HTTP/PostgreSQL and business-effect assertions.",
    );
  } finally {
    if (child?.exitCode === null && child.signalCode === null)
      child.kill("SIGTERM");
    await app.close();
    await owner.$disconnect();
    await rm(root, { recursive: true, force: true });
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
