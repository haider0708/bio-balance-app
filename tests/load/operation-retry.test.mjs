import test from "node:test";
import assert from "node:assert/strict";
import { submitSale } from "./operation-retry.mjs";
const response = (status, result) => ({
  status,
  json: () => ({ results: [result] }),
});
const accepted = response(201, { operationId: "fixed-id", status: "accepted" });
test("retryable response completes using the same serialized command", () => {
  const payload = JSON.stringify({
    operationId: "fixed-id",
    command: { type: "sale.create", saleId: "fixed-sale" },
  });
  const sent = [],
    delays = [],
    codes = [];
  const results = [
    response(201, {
      operationId: "fixed-id",
      status: "retryable",
      code: "RETRY_LATER",
      retryAfterMs: 250,
    }),
    accepted,
  ];
  const out = submitSale(
    () => {
      sent.push(payload);
      return results.shift();
    },
    (s) => delays.push(s),
    "fixed-id",
    (c) => codes.push(c),
  );
  assert.equal(out.accepted, true);
  assert.equal(out.attempts, 2);
  assert.deepEqual(sent, [payload, payload]);
  assert.deepEqual(delays, [0.25]);
  assert.deepEqual(codes, ["RETRY_LATER"]);
});
test("terminal rejection and mismatched identity cannot be retried or accepted", () => {
  for (const value of [
    response(201, {
      operationId: "fixed-id",
      status: "rejected",
      code: "FORBIDDEN",
    }),
    response(201, { operationId: "another-id", status: "accepted" }),
    response(401, { code: "SESSION_EXPIRED" }),
  ]) {
    let calls = 0;
    const out = submitSale(
      () => {
        calls++;
        return value;
      },
      () => assert.fail("unexpected retry"),
      "fixed-id",
    );
    assert.equal(out.accepted, false);
    assert.equal(calls, 1);
  }
});
test("an exhausted retry remains a failed sale after three bounded attempts", () => {
  let calls = 0;
  const delays = [];
  const out = submitSale(
    () => {
      calls++;
      return response(201, {
        operationId: "fixed-id",
        status: "retryable",
        code: "RETRY_LATER",
      });
    },
    (s) => delays.push(s),
    "fixed-id",
  );
  assert.equal(out.accepted, false);
  assert.equal(calls, 3);
  assert.deepEqual(delays, [0.1, 0.2]);
});
test("non-JSON responses fail immediately", () => {
  const out = submitSale(
    () => ({
      status: 502,
      json() {
        throw Error("not JSON");
      },
    }),
    () => assert.fail("unexpected retry"),
    "fixed-id",
  );
  assert.equal(out.accepted, false);
  assert.equal(out.code, "http_502");
});
