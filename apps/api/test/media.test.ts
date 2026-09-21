import { beforeAll, afterAll, it, expect } from "vitest";
import { randomUUID, createHash } from "node:crypto";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import path from "node:path";
import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { Database } from "../src/shared/infrastructure/database";
import { TrainingService } from "../src/modules/training/training.service";
import { WorkspaceService } from "../src/modules/tenancy/workspace.service";
import { MediaProcessor } from "../src/modules/training/infrastructure/media-processor";

process.env.DATABASE_URL =
  process.env.TEST_APP_DATABASE_URL ??
  "postgresql://biobalance_app:local-app-only@localhost:54329/biobalance_test";
if (!new URL(process.env.DATABASE_URL).pathname.endsWith("_test"))
  throw new Error("ISOLATED_TEST_DATABASE_REQUIRED");
const owner = new PrismaClient({
  adapter: new PrismaPg({
    connectionString:
      process.env.TEST_OWNER_DATABASE_URL ??
      "postgresql://biobalance:local-development-only@localhost:54329/biobalance_test",
  }),
});
const db = new Database(),
  workspace = new WorkspaceService(db);
const manager = {
  id: randomUUID(),
  name: "Media manager",
  email: `${randomUUID()}@example.test`,
  platformAdmin: false,
};
const seller = {
  ...manager,
  id: randomUUID(),
  email: `${randomUUID()}@example.test`,
};
const outsider = {
  ...manager,
  id: randomUUID(),
  email: `${randomUUID()}@example.test`,
};
const org = randomUUID(),
  store = randomUUID(),
  otherStore = randomUUID();
let root: string, service: TrainingService, image: Buffer;
beforeAll(async () => {
  root = await mkdtemp(path.join(tmpdir(), "biobalance-media-test-"));
  process.env.MEDIA_ROOT = root;
  service = new TrainingService(db);
  for (const user of [manager, seller, outsider])
    await owner.user.create({ data: { ...user, passwordHash: "test-only" } });
  await owner.organization.create({
    data: { id: org, name: "Isolated media tests" },
  });
  for (const id of [store, otherStore])
    await owner.store.create({
      data: {
        id,
        organizationId: org,
        name: "Images",
        address: "Test address",
        city: "Tunis",
      },
    });
  await owner.membership.create({
    data: {
      organizationId: org,
      storeId: store,
      userId: manager.id,
      permissions: ["manage"],
    },
  });
  await owner.membership.create({
    data: {
      organizationId: org,
      storeId: store,
      userId: seller.id,
      permissions: ["sell"],
    },
  });
  await owner.membership.create({
    data: {
      organizationId: org,
      storeId: otherStore,
      userId: outsider.id,
      permissions: ["manage"],
    },
  });
  execFileSync("ffmpeg", [
    "-nostdin",
    "-y",
    "-v",
    "error",
    "-f",
    "lavfi",
    "-i",
    "color=c=0x6ABE4E:s=2400x1200",
    "-frames:v",
    "1",
    "-threads",
    "1",
    path.join(root, "fixture.png"),
  ]);
  image = await readFile(path.join(root, "fixture.png"));
});
afterAll(async () => {
  await db.$disconnect();
  await owner.$disconnect();
  if (root) await rm(root, { recursive: true, force: true });
});
it("processes a scoped image, verifies it, and refuses cross-store attachment and access", async () => {
  const scope = {
    purpose: "store" as const,
    organizationId: org,
    storeId: store,
    sha256: createHash("sha256").update(image).digest("hex"),
  };
  await expect(
    service.startUpload(seller, "image.png", "image/png", image.length, scope),
  ).rejects.toThrow();
  await expect(
    service.startUpload(
      manager,
      "image.png",
      "image/png",
      10 * 1024 * 1024 + 1,
      scope,
    ),
  ).rejects.toThrow();
  await expect(
    service.startUpload(manager, "image.png", "image/png", image.length, {
      purpose: "catalog",
    }),
  ).rejects.toThrow();
  const asset = await service.startUpload(
    manager,
    "image.png",
    "image/png",
    image.length,
    scope,
  );
  await service.chunk(manager, asset.id, 0, image.subarray(0, 1000));
  await service.chunk(manager, asset.id, 1000, image.subarray(1000));
  const settings = {
    name: "Updated",
    address: "Test address",
    city: "Tunis",
    expectedVersion: 1,
    imageId: asset.id,
  };
  await expect(
    workspace.updateStore(manager, org, store, settings),
  ).rejects.toThrow("traitement");
  await new MediaProcessor(db, root).process(asset.id);
  const ready = await service.uploadStatus(manager, asset.id);
  expect(ready.status).toBe("ready");
  expect(ready.sha256).toMatch(/^[a-f0-9]{64}$/);
  expect(ready.processedSize! > 0n).toBe(true);
  const content = await service.media(manager, asset.id);
  const dimensions = JSON.parse(
    execFileSync("ffprobe", [
      "-v",
      "error",
      "-show_entries",
      "stream=width,height",
      "-of",
      "json",
      content.path,
    ]).toString(),
  ).streams[0];
  expect(dimensions).toEqual({ width: 1600, height: 800 });
  expect(
    createHash("sha256")
      .update(await readFile(content.path))
      .digest("hex"),
  ).toBe(ready.sha256);
  await workspace.updateStore(manager, org, store, settings);
  expect((await service.media(seller, asset.id)).path).toBe(content.path);
  await expect(service.uploadStatus(seller, asset.id)).rejects.toThrow();
  await expect(service.media(outsider, asset.id)).rejects.toThrow();
  await expect(
    workspace.updateStore(outsider, org, otherStore, settings),
  ).rejects.toThrow("emplacement");
  expect(
    (await owner.store.findUniqueOrThrow({ where: { id: otherStore } }))
      .imageId,
  ).toBeNull();
  expect(
    (await service.chunk(manager, asset.id, 1000, image.subarray(1000))).status,
  ).toBe("ready");
  expect(await owner.job.count({ where: { key: `media:${asset.id}` } })).toBe(
    1,
  );
  const rewardImage = await service.startUpload(
    manager,
    "reward.png",
    "image/png",
    image.length,
    { ...scope, purpose: "reward" },
  );
  await service.chunk(manager, rewardImage.id, 0, image);
  await new MediaProcessor(db, root).process(rewardImage.id);
  const reward = await workspace.reward(manager, org, store, {
    title: "Gift",
    description: "Test",
    cost: 20,
    quantity: 1,
    active: true,
    imageId: rewardImage.id,
  });
  expect(reward.imageId).toBe(rewardImage.id);
  await expect(
    workspace.reward(outsider, org, otherStore, {
      title: "Stolen",
      description: "Test",
      cost: 20,
      quantity: 1,
      active: true,
      imageId: rewardImage.id,
    }),
  ).rejects.toThrow();
  await owner.membership.update({
    where: { storeId_userId: { storeId: store, userId: manager.id } },
    data: { active: false },
  });
  await expect(service.media(manager, asset.id)).rejects.toThrow();
});
it("refuses mismatched uploaded bytes before creating processed media", async () => {
  const asset = await service.startUpload(
    outsider,
    "bad.png",
    "image/png",
    image.length,
    {
      purpose: "store",
      organizationId: org,
      storeId: otherStore,
      sha256: "0".repeat(64),
    },
  );
  await service.chunk(outsider, asset.id, 0, image);
  await expect(new MediaProcessor(db, root).process(asset.id)).rejects.toThrow(
    "MEDIA_CHECKSUM_MISMATCH",
  );
  expect((await service.uploadStatus(outsider, asset.id)).status).toBe(
    "processing",
  );
  await expect(service.media(outsider, asset.id)).rejects.toThrow();
});
