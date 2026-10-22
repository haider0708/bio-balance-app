import { describe, expect, it } from "vitest";
import { normalizeError } from "../src/modules/diagnostics/diagnostics.service";

describe("grouping app errors", () => {
  it("makes the same bug one kind, whatever the object id or build", () => {
    const a = normalizeError(
      "Bad state: RenderBox was not laid out: minified:Gl#12cba",
    );
    const b = normalizeError(
      "Bad state: RenderBox was not laid out: minified:Gl#a93d5",
    );
    expect(a).toBe(b);
    expect(
      normalizeError("at Object.ad (https://x/main.dart.js:4209:30)"),
    ).toBe(normalizeError("at Object.ad (https://x/main.dart.js:77:5)"));
    // Different errors stay different.
    expect(normalizeError("Null check operator used on a null value")).not.toBe(
      a,
    );
  });
});
