import { describe, it } from "vitest";
import { serveFixture } from "./serve-fixture";

// Only runs when asked to; see serve-fixture.ts.
describe.skipIf(!process.env.FIXTURE_OUT)(
  "fixture server for the mobile contract test",
  () => {
    it(
      "serves until stopped",
      () => serveFixture(process.env.FIXTURE_OUT!),
      30 * 60_000,
    );
  },
);
