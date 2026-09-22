import http from "k6/http";
import execution from "k6/execution";
import { SharedArray } from "k6/data";
import { check } from "k6";
import { Counter } from "k6/metrics";
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
const cursors = new Map(); // VU-local, scoped to the original account/store.
const duration = __ENV.STEADY_DURATION || "5m";
export const options = {
  scenarios: {
    steady: {
      executor: "constant-arrival-rate",
      rate: Number(__ENV.STEADY_RATE || 100),
      timeUnit: "1s",
      duration,
      // Provision clients before measurement; allocating VMs during the burst
      // competes with the API when the generator shares the reference VPS.
      preAllocatedVUs: 100,
      maxVUs: 200,
    },
    burst: {
      executor: "constant-arrival-rate",
      rate: Number(__ENV.BURST_RATE || 200),
      timeUnit: "1s",
      duration: __ENV.BURST_DURATION || "30s",
      startTime: duration,
      preAllocatedVUs: 100,
      maxVUs: 300,
    },
  },
  thresholds: {
    "http_req_duration{kind:read}": ["p(95)<300"],
    "http_req_duration{kind:write}": ["p(95)<700"],
    "http_req_duration{kind:read,scenario:steady}": ["p(95)<300"],
    "http_req_duration{kind:write,scenario:steady}": ["p(95)<700"],
    "http_req_duration{kind:read,scenario:burst}": ["p(95)<300"],
    "http_req_duration{kind:write,scenario:burst}": ["p(95)<700"],
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
      "Content-Type": "application/json",
    };
  if (__ENV.SYNTHETIC_PROXY === "yes") {
    const storeNumber = Math.floor((Number(f.n) - 1) / 10);
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
    const response = http.post(
      base + "/v1/sync/push",
      JSON.stringify({ operations: [operation] }),
      { headers, tags: { kind: "write", endpoint: "sale" } },
    );
    const accepted =
      response.status === 201 &&
      response.json("results.0.status") === "accepted";
    check(response, { "sale accepted": () => accepted });
    const rejectionCode = accepted
      ? "none"
      : String(
          response.json("results.0.code") ||
            response.json("code") ||
            `http_${response.status}`,
        );
    rejected.add(accepted ? 0 : 1, { code: rejectionCode });
    if (!accepted && __ITER < 5)
      console.warn(`Sale rejected: ${rejectionCode}`);
    acceptedOperations.add(accepted ? 1 : 0);
    // A committed write cursor cannot advance a client's read cursor: another
    // account may have changed the same store in between.
    return;
  }
  let url, endpoint;
  if (state.pages.length) {
    url = `${prefix}/snapshot-pages/${state.pages[0]}?${scope}`;
    endpoint = "snapshot-page";
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
    tags: { kind: "read", endpoint },
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
