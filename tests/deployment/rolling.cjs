const assert = require("node:assert/strict");
const { spawn, execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const root = process.cwd();
const lab = path.join(root, ".artifacts/deployment-lab");
const fixture = JSON.parse(fs.readFileSync(path.join(lab, "fixture.json")));
const state = JSON.parse(fs.readFileSync(path.join(lab, "state.json")));
const apiImage = process.env.TARGET_API_IMAGE;
const mediaImage = process.env.TARGET_MEDIA_IMAGE;
assert(
  apiImage && mediaImage,
  "explicit tested rollback/update images required",
);
const args = [
  "compose",
  "-f",
  path.join(root, "infrastructure/production/compose.yml"),
  "--env-file",
  path.join(lab, ".env"),
  "-f",
  path.join(lab, "override.yml"),
  "-p",
  "biobalance-release-lab",
];
const env = { ...process.env, API_IMAGE: apiImage, MEDIA_IMAGE: mediaImage };
const scope = `organizationId=${fixture.organizationId}`;
const get = async (resource) => {
  const response = await fetch(
    `https://localhost:18443/v1/stores/${state.store}/${resource}`,
    {
      headers: { Authorization: `Bearer ${fixture.managerToken}` },
      signal: AbortSignal.timeout(10_000),
    },
  );
  assert.equal(response.status, 200, "authorized read must remain available");
  return response.json();
};
const assertStock = (lots) => {
  const lot = lots.find((lot) => lot.id === state.lot);
  assert(lot, "expected lot must remain visible in its authorized store");
  assert.equal(lot.sellable, 4);
  assert.equal(lot.version, 3);
};
const verifySnapshot = async () => {
  const body = await get(`snapshot?${scope}&protocol=3`);
  assertStock(body.lots);
  assert.equal(body.points.balance, "60");
};

(async () => {
  await verifySnapshot();
  let reads = 0;
  for (const services of [["api1"], ["api2"], ["worker", "media-worker"]]) {
    let done = false;
    const child = spawn(
      "docker",
      [
        ...args,
        "up",
        "-d",
        "--no-deps",
        "--force-recreate",
        "--wait",
        "--wait-timeout",
        "120",
        ...services,
      ],
      { env, stdio: ["ignore", "inherit", "inherit"], timeout: 180_000 },
    );
    // Always reap Compose, including when an HTTP assertion fails. Resolve its
    // outcome here to avoid an unhandled rejection while a request is in flight.
    const complete = new Promise((resolve) => {
      child.once("error", (error) => {
        done = true;
        resolve(error);
      });
      child.once("close", (code, signal) => {
        done = true;
        resolve(code === 0 ? null : Error(`restart failed: ${code ?? signal}`));
      });
    });
    let restartError;
    try {
      while (!done) {
        // Routine reads exercise authentication, RLS and stock during rollout.
        // Full snapshots are intentionally limited export operations.
        assertStock(await get(`collections/lots?${scope}`));
        reads++;
        await new Promise((resolve) => setTimeout(resolve, 1000));
      }
    } finally {
      restartError = await complete;
    }
    if (restartError) throw restartError;
    for (const service of services) {
      const id = execFileSync("docker", [...args, "ps", "-q", service], {
        env,
        encoding: "utf8",
        timeout: 30_000,
      }).trim();
      const actual = JSON.parse(
        execFileSync("docker", ["inspect", id], {
          encoding: "utf8",
          timeout: 30_000,
        }),
      )[0].Image;
      const expected = JSON.parse(
        execFileSync(
          "docker",
          [
            "image",
            "inspect",
            service === "media-worker" ? mediaImage : apiImage,
          ],
          { encoding: "utf8", timeout: 30_000 },
        ),
      )[0].Id;
      assert.equal(actual, expected);
    }
  }
  await verifySnapshot();
  console.log(
    `PASS: rolling change to ${apiImage}; ${reads} authorized lot reads preserved stock/version during API/worker replacement; snapshots verified stock and points before/after.`,
  );
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
