const path = require("node:path"),
  fs = require("node:fs/promises");
const { monitorEventLoopDelay, performance } = require("node:perf_hooks");
const lag = monitorEventLoopDelay({ resolution: 20 });
lag.enable();
let previous = performance.eventLoopUtilization(),
  cpu = process.cpuUsage();
const sample = setInterval(() => {
  const utilization = performance.eventLoopUtilization(previous);
  previous = performance.eventLoopUtilization();
  const used = process.cpuUsage(cpu);
  cpu = process.cpuUsage();
  console.log(
    JSON.stringify({
      event: "process-sample",
      pid: process.pid,
      eventLoopP95Ms: lag.percentile(95) / 1e6,
      eventLoopUtilization: utilization.utilization,
      cpuPercent: (used.user + used.system) / 50000,
      rssBytes: process.memoryUsage().rss,
    }),
  );
  lag.reset();
}, 5000);
sample.unref();
if (process.env.LOAD_PROFILE === "yes") {
  const { Session } = require("node:inspector/promises");
  const inspector = new Session();
  inspector.connect();
  void (async () => {
    await inspector.post("Profiler.enable");
    await inspector.post("Profiler.start");
    setTimeout(async () => {
      const { profile } = await inspector.post("Profiler.stop");
      await fs.writeFile(
        path.resolve(
          ".artifacts/evidence/step10/api-" + process.pid + ".cpuprofile",
        ),
        JSON.stringify(profile),
      );
      inspector.disconnect();
    }, 40000).unref();
  })();
}
const url = process.env.DATABASE_URL;
if (!url || !new URL(url).pathname.endsWith("_load_test"))
  throw Error("Isolated load database required");
process.env.MEDIA_ROOT = path.resolve(".artifacts/load-media");
require("../../apps/api/dist/main")
  .bootstrap()
  .then(async (app) => {
    if (process.env.LOAD_READY_FILE)
      await fs.writeFile(
        process.env.LOAD_READY_FILE,
        String(app.getHttpServer().address().port),
        { mode: 0o600 },
      );
  })
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
