/* Android force-stop probe. Only synthetic *_journeys_test data are accepted. */
const { randomUUID, createHash } = require("node:crypto"),
  { spawn, execFile } = require("node:child_process");
const { mkdtemp, writeFile, readFile, rm } = require("node:fs/promises"),
  { promisify } = require("node:util"),
  path = require("node:path"),
  os = require("node:os"),
  assert = require("node:assert/strict");
const { NestFactory } = require("@nestjs/core"),
  express = require("express"),
  { PrismaClient } = require("@prisma/client"),
  { PrismaPg } = require("@prisma/adapter-pg");
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
process.env.DATABASE_URL = appUrl;
const { AppModule } = require("../dist/app.module"),
  {
    OperationsService,
  } = require("../dist/modules/operations/application/operations.service");
const owner = new PrismaClient({
  adapter: new PrismaPg({ connectionString: ownerUrl }),
});
(async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "biobalance-restart-"));
  process.env.MEDIA_ROOT = root;
  const app = await NestFactory.create(AppModule, {
    logger: false,
    bodyParser: false,
  });
  app.use(
    "/v1/media/uploads",
    express.raw({ type: "application/octet-stream", limit: "4mb" }),
  );
  app.use(express.json({ limit: "1mb" }));
  const user = await owner.user.create({
    data: {
      email: `${randomUUID()}@example.test`,
      name: "Crash probe",
      passwordHash: "not-a-login",
    },
  });
  const org = await owner.organization.create({
      data: { name: "Crash probe" },
    }),
    store = await owner.store.create({
      data: {
        organizationId: org.id,
        name: "Crash probe",
        address: "Test",
        city: "Tunis",
      },
    });
  await owner.membership.create({
    data: {
      organizationId: org.id,
      storeId: store.id,
      userId: user.id,
      permissions: ["manage", "sell", "receive"],
    },
  });
  const product = await owner.product.create({
    data: {
      reference: randomUUID(),
      name: `Crash serum ${randomUUID().slice(0, 5)}`,
    },
  });
  await owner.storeProduct.create({
    data: {
      organizationId: org.id,
      storeId: store.id,
      productId: product.id,
      priceMillimes: 49900n,
      pointsPerUnit: 10,
      pointsConfigured: true,
    },
  });
  const token = randomUUID(),
    session = await owner.session.create({
      data: {
        userId: user.id,
        tokenHash: createHash("sha256").update(token).digest("hex"),
        expiresAt: new Date(Date.now() + 3600000),
      },
    });
  await app.get(OperationsService).submit(user, {
    operationId: randomUUID(),
    organizationId: org.id,
    storeId: store.id,
    payloadVersion: 2,
    command: {
      type: "stock.receive",
      reason: "opening",
      lines: [
        {
          productId: product.id,
          batch: "OPENING",
          expiry: "2030-12-31",
          quantity: 10,
        },
      ],
    },
  });
  const {
      TrainingService,
    } = require("../dist/modules/training/training.service"),
    {
      MediaProcessor,
    } = require("../dist/modules/training/infrastructure/media-processor"),
    { Database } = require("../dist/shared/infrastructure/database");
  const mediaAdmin = await owner.user.create({
    data: {
      email: `${randomUUID()}@example.test`,
      name: "Media fixture",
      passwordHash: "not-a-login",
      platformAdmin: true,
    },
  });
  const source = path.join(root, "sample.mp4");
  await promisify(execFile)("ffmpeg", [
    "-nostdin",
    "-v",
    "error",
    "-f",
    "lavfi",
    "-i",
    "testsrc2=size=320x180:rate=15",
    "-t",
    "4",
    "-c:v",
    "libx264",
    "-threads",
    "1",
    "-pix_fmt",
    "yuv420p",
    source,
  ]);
  const bytes = await readFile(source),
    training = app.get(TrainingService);
  const asset = await training.startUpload(
    mediaAdmin,
    "sample.mp4",
    "video/mp4",
    bytes.length,
    {
      purpose: "training",
      sha256: createHash("sha256").update(bytes).digest("hex"),
    },
  );
  await training.chunk(mediaAdmin, asset.id, 0, bytes);
  await new MediaProcessor(app.get(Database), root).process(asset.id);
  const videoTitle = `Vidéo native ${randomUUID().slice(0, 6)}`;
  await training.save(mediaAdmin, {
    id: randomUUID(),
    submissionId: randomUUID(),
    expectedVersion: 0,
    title: videoTitle,
    body: "Vidéo de test synthétique",
    type: "video",
    mediaId: asset.id,
    productIds: [product.id],
    status: "published",
  });
  let child, checkpoint, termination;
  const key = randomUUID(),
    device = process.env.TEST_DEVICE ?? "emulator-5554",
    adb =
      process.env.ADB_BIN ??
      path.join(process.env.ANDROID_HOME ?? "", "platform-tools/adb");
  app.use("/__test/checkpoint", async (req, res) => {
    if (req.headers["x-test-key"] !== key) return res.sendStatus(404);
    checkpoint = req.body;
    if (checkpoint.accountId !== user.id) return res.sendStatus(409);
    assert.equal(
      await owner.processedOperation.count({
        where: { id: checkpoint.operationId },
      }),
      0,
      "operation must still be offline",
    );
    // Capture this driver: a delayed cleanup must never terminate the restore phase.
    const saveDriver = child;
    termination = new Promise((resolve, reject) => {
      setTimeout(async () => {
        try {
          const before = await promisify(execFile)(adb, [
            "-s",
            device,
            "shell",
            "pidof",
            "tn.biobalance.app",
          ]);
          assert(
            before.stdout.trim(),
            "an actual Android app process must be running",
          );
          await promisify(execFile)(adb, [
            "-s",
            device,
            "shell",
            "am",
            "force-stop",
            "tn.biobalance.app",
          ]);
          const after = await promisify(execFile)(adb, [
            "-s",
            device,
            "shell",
            "pidof",
            "tn.biobalance.app",
          ]).catch((error) => {
            if (error.code === 1) return { stdout: error.stdout };
            throw error;
          });
          assert.equal(
            after.stdout.trim(),
            "",
            "the Android app process must no longer exist",
          );
          resolve(true);
        } catch (error) {
          reject(error);
        } finally {
          setTimeout(() => {
            if (
              saveDriver?.exitCode === null &&
              saveDriver.signalCode === null
            ) {
              saveDriver.kill("SIGTERM");
            }
          }, 500);
        }
      }, 300);
    });
    // Attach an error handler immediately; the driver can exit before we await.
    termination.catch(() => {});
    res.json({ ok: true });
  });
  // Configure the installed restore APK, not the previous build. Android may
  // reset user permission flags during an update/reinstall by flutter drive.
  app.use("/__test/deny-camera", async (req, res) => {
    if (req.headers["x-test-key"] !== key) return res.sendStatus(404);
    try {
      await promisify(execFile)(adb, [
        "-s",
        device,
        "shell",
        "pm",
        "revoke",
        "tn.biobalance.app",
        "android.permission.CAMERA",
      ]);
      await promisify(execFile)(adb, [
        "-s",
        device,
        "shell",
        "pm",
        "set-permission-flags",
        "tn.biobalance.app",
        "android.permission.CAMERA",
        "user-set",
        "user-fixed",
      ]);
      const permissions = await promisify(execFile)(adb, [
        "-s",
        device,
        "shell",
        "dumpsys",
        "package",
        "tn.biobalance.app",
      ]);
      assert.match(
        permissions.stdout,
        /android\.permission\.CAMERA: granted=false, flags=\[[^\]]*USER_FIXED/,
      );
      res.json({ ok: true });
    } catch (error) {
      console.error("Camera denial fixture failed", error.message);
      res.sendStatus(500);
    }
  });
  app
    .getHttpAdapter()
    .getInstance()
    .set("json replacer", (_k, v) =>
      typeof v === "bigint" ? v.toString() : v,
    );
  try {
    await app.listen(0, "127.0.0.1");
    const port = app.getHttpServer().address().port;
    const base = {
      API_BASE_URL: `http://10.0.2.2:${port}`,
      TEST_KEY: key,
      TEST_ACCOUNT: JSON.stringify({
        token,
        expiresAt: session.expiresAt.toISOString(),
        user: {
          id: user.id,
          name: user.name,
          email: user.email,
          platformAdmin: false,
        },
      }),
      TEST_STORE: store.id,
      PRODUCT_NAME: product.name,
      TEST_VIDEO_TITLE: videoTitle,
    };
    for (const phase of ["save", "restore"]) {
      const config = path.join(root, phase + ".json");
      await writeFile(config, JSON.stringify({ ...base, TEST_PHASE: phase }), {
        mode: 0o600,
      });
      const code = await new Promise((resolve, reject) => {
        child = spawn(
          process.env.FLUTTER_BIN ?? "flutter",
          [
            "drive",
            "--keep-app-running",
            "--driver=test_driver/integration_test.dart",
            "--target=integration_test/offline_restart_test.dart",
            "-d",
            device,
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
      if (phase === "save") {
        assert(
          checkpoint,
          "SQLite commit checkpoint is required before intentional termination",
        );
        assert.equal(
          await termination,
          true,
          "verified Android process termination required",
        );
        console.log(
          "EXPECTED: Android process terminated after durable local sale commit.",
        );
      } else
        assert.equal(
          code,
          0,
          "restart must recover and synchronize the same operation",
        );
    }
    assert.equal(
      await owner.processedOperation.count({
        where: { id: checkpoint.operationId, actorId: user.id },
      }),
      1,
    );
    const lot = await owner.inventoryLot.findFirstOrThrow({
      where: { storeId: store.id },
    });
    assert.deepEqual([lot.sellable, lot.version], [7, 3]);
    const points = await owner.pointsAccount.findFirstOrThrow({
      where: { storeId: store.id, userId: user.id },
    });
    assert.equal(points.balance, 30n);
    assert.equal(await owner.sale.count({ where: { storeId: store.id } }), 1);
    console.log(
      "PASS: downloaded H.264 video plays from a verified local file on Android.",
    );
    console.log(
      "PASS: actual Android force-stop, preserved account/outbox ID and payload, one accepted sale, stock 7 v3, points 30.",
    );
  } finally {
    await promisify(execFile)(adb, [
      "-s",
      device,
      "shell",
      "pm",
      "clear-permission-flags",
      "tn.biobalance.app",
      "android.permission.CAMERA",
      "user-set",
      "user-fixed",
    ]).catch(() => {});
    await owner.session.update({
      where: { id: session.id },
      data: { revokedAt: new Date() },
    });
    await app.close();
    await owner.$disconnect();
    await rm(root, { recursive: true, force: true });
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
