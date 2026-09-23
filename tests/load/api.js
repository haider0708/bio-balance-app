import http from "k6/http";
import execution from "k6/execution";
import { SharedArray } from "k6/data";
import { check, sleep } from "k6";
import { Counter, Trend } from "k6/metrics";
import { submitSale } from "./operation-retry.mjs";
const fixtures = new SharedArray("synthetic-accounts", () =>
  JSON.parse(open(__ENV.FIXTURES)),
);
const bases = (
  __ENV.BASE_URLS ||
  __ENV.BASE_URL ||
  "http://127.0.0.1:3000"
).split(",");
if (__ENV.ALLOW_SYNTHETIC_LOAD !== "yes")
  throw Error(
    "Set ALLOW_SYNTHETIC_LOAD=yes only for the isolated synthetic database",
  );
if (
  __ENV.SYNTHETIC_PROXY === "yes" &&
  bases.some((base) => !/^https:\/\/load\.biobalance\.invalid:\d+$/.test(base))
)
  throw Error(
    "Synthetic proxy headers are limited to the isolated loopback TLS lab",
  );
const rejected = new Counter("rejected_operations");
const acceptedOperations = new Counter("accepted_operations");
const retryResponses = new Counter("retryable_responses");
const saleDuration = new Trend("sale_operation_duration", true);
const cursors = new Map(); // VU-local, scoped to the original account/store.
const duration = __ENV.STEADY_DURATION || "5m";
function durationMilliseconds(value) {
  const match = /^(\d+(?:\.\d+)?)(ms|s|m|h)$/.exec(value);
  if (!match) throw Error("Use a duration such as 10s, 5m or 1h");
  return Number(match[1]) * { ms: 1, s: 1000, m: 60000, h: 3600000 }[match[2]];
}
const steadyMilliseconds = durationMilliseconds(duration);
const steadyRate = Number(__ENV.STEADY_RATE || 100);
const burstRate = Number(__ENV.BURST_RATE || 200);
export const options = {
  scenarios: {
    workload: {
      executor: "ramping-arrival-rate",
      startRate: steadyRate,
      timeUnit: "1s",
      // One client pool preserves connections and per-account cursors across
      // the rate change. Cold reconnection is a separate stress scenario.
      preAllocatedVUs: 200,
      maxVUs: 300,
      stages: [
        { duration, target: steadyRate },
        { duration: "0s", target: burstRate },
        { duration: __ENV.BURST_DURATION || "30s", target: burstRate },
      ],
    },
  },
  thresholds: {
    "http_req_duration{kind:read}": ["p(95)<300"],
    "http_req_duration{kind:write}": ["p(95)<700"],
    "http_req_duration{kind:read,phase:steady}": ["p(95)<300"],
    "http_req_duration{kind:write,phase:steady}": ["p(95)<700"],
    "http_req_duration{kind:read,phase:burst}": ["p(95)<300"],
    "http_req_duration{kind:write,phase:burst}": ["p(95)<700"],
    sale_operation_duration: ["p(95)<700"],
    "sale_operation_duration{phase:steady}": ["p(95)<700"],
    "sale_operation_duration{phase:burst}": ["p(95)<700"],
    http_req_failed: ["rate<0.001"],
    checks: ["rate==1"],
    rejected_operations: ["count==0"],
    dropped_iterations: ["count==0"],
  },
};
function uuid() {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === "x" ? r : (r & 3) | 8).toString(16);
  });
}
export default function () {
  const phase =
    Date.now() - execution.scenario.startTime < steadyMilliseconds
      ? "steady"
      : "burst";
  const base = bases[execution.scenario.iterationInTest % bases.length];
  const f = fixtures[execution.scenario.iterationInTest % fixtures.length];
  const key = f.userId + ":" + f.storeId;
  if (!cursors.has(key))
    cursors.set(key, {
      cursor: f.cursor,
      revision: f.catalogRevision,
      pages: [],
    });
  const state = cursors.get(key),
    headers = {
      Authorization: `Bearer ${f.token}`,
      "Accept-Encoding": "gzip",
      "Content-Type": "application/json",
    };
  if (__ENV.SYNTHETIC_PROXY === "yes") {
    const storeNumber = Math.floor((Number(f.n) - 1) / 10);
    headers["X-Load-Phase"] = phase;
    headers["X-Load-Client-IP"] =
      `198.18.${Math.floor(storeNumber / 250)}.${(storeNumber % 250) + 1}`;
  }
  const prefix = `/v1/stores/${f.storeId}`,
    scope = `organizationId=${f.organizationId}`;
  const mode = (__ITER + __VU * 7) % 100;
  if (mode >= 90) {
    const operation = {
      operationId: uuid(),
      organizationId: f.organizationId,
      storeId: f.storeId,
      payloadVersion: 2,
      dependencies: [],
      command: {
        type: "sale.create",
        saleId: uuid(),
        occurredAt: new Date().toISOString(),
        lines: [
          {
            id: uuid(),
            productId: f.productId,
            quantity: 1,
            unitPriceMillimes: "49900",
            allocations: [{ lotId: f.lotId, quantity: 1 }],
          },
        ],
      },
    };
    const payload = JSON.stringify({ operations: [operation] });
    const started = Date.now();
    const outcome = submitSale(
      () =>
        http.post(base + "/v1/sync/push", payload, {
          headers,
          tags: { kind: "write", endpoint: "sale", phase },
        }),
      sleep,
      operation.operationId,
      (code) => {
        retryResponses.add(1, { code, phase });
        console.info(`Retryable sale response: ${code}`);
      },
    );
    saleDuration.add(Date.now() - started, { phase });
    check(outcome.response, { "sale accepted": () => outcome.accepted });
    rejected.add(outcome.accepted ? 0 : 1, { code: outcome.code });
    if (!outcome.accepted)
      console.warn(
        `Sale failed after ${outcome.attempts} attempts: ${outcome.code}`,
      );
    acceptedOperations.add(outcome.accepted ? 1 : 0);
    // A committed write cursor cannot advance a client's read cursor: another
    // account may have changed the same store in between.
    return;
  }
  let url, endpoint;
  if (state.pages.length) {
    url = `${prefix}/snapshot-pages/${state.pages[0]}?${scope}`;
    endpoint = "snapshot-page";
  } else if (mode < 20) {
    const now = new Date();
    const date = new Date(now.getTime() + 3600000).toISOString().slice(0, 10);
    const first = date.slice(0, 8) + "01";
    const manager = (Number(f.n) - 1) % 10 === 0;
    const dashboardScope = manager ? (mode < 10 ? "group" : "store") : "personal";
    url = `/v1/dashboards?scope=${dashboardScope}&${scope}&from=${first}&to=${date}` +
      (dashboardScope === "group" ? "" : `&storeId=${f.storeId}`);
    endpoint = `dashboard-${dashboardScope}`;
  } else if (mode < 50) {
    url =
      `${prefix}/snapshot?${scope}&protocol=3` +
      (state.cursor === undefined
        ? ""
        : `&after=${state.cursor}&catalogRevision=${state.revision}`);
    endpoint = "snapshot";
  } else if (mode < 65) {
    url =
      `${prefix}/history/sales?${scope}` +
      (state.before ? `&before=${encodeURIComponent(state.before)}` : "");
    endpoint = "history";
  } else if (mode < 75) {
    url = `${prefix}/ranking?${scope}`;
    endpoint = "ranking";
  } else if (mode < 85) {
    url = "/v1/notifications";
    endpoint = "inbox";
  } else {
    url = `${prefix}/collections/lots?${scope}`;
    endpoint = "inventory";
  }
  const response = http.get(base + url, {
    headers,
    tags: { kind: "read", endpoint, phase },
  });
  const expired = endpoint === "snapshot-page" && response.status === 410;
  check(response, {
    "read accepted or snapshot safely expired": (r) =>
      r.status === 200 || expired,
  });
  if (expired) {
    state.pages = [];
    state.cursor = undefined;
    return;
  }
  if (response.status !== 200) return;
  const data = response.json();
  if (endpoint === "snapshot") {
    state.revision = data.catalogRevision;
    state.nextCursor = data.cursor;
    state.pages = Object.values(data.snapshotPages || {}).filter(Boolean);
    if (!state.pages.length) state.cursor = data.cursor;
  } else if (endpoint === "snapshot-page") {
    state.pages.shift();
    if (data.nextPage) state.pages.unshift(data.nextPage);
    if (!state.pages.length) state.cursor = state.nextCursor;
  } else if (endpoint === "history") {
    state.before = data.nextCursor;
  }
}
