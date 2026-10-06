import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { startApi, type Api } from "./helpers";
import { renderEmail } from "../src/email/templates";

let api: Api;
beforeAll(async () => {
  api = await startApi();
});
afterAll(() => api.close());

describe("the page a code email links to", () => {
  it("is public, has a Copy button and allows only its own script", async () => {
    const res = await fetch(`${api.url}/c`);
    const html = await res.text();
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/html");
    expect(html).toContain('id="copy"');
    expect(html).toContain("intent://app/code");
    expect(res.headers.get("content-security-policy")).toMatch(
      /script-src 'sha256-[A-Za-z0-9+/=]+'/,
    );
  });

  it("is linked from the code email, in both languages", () => {
    const link = "https://api.example.test/c#i.ABCD2345";
    for (const locale of ["fr", "en"] as const) {
      const mail = renderEmail(locale, {
        kind: "invite",
        code: "ABCD2345",
        expiresAt: new Date(),
        name: "Amira",
        link,
      });
      expect(mail.text).toContain(link);
      expect(mail.html).toContain(`href="${link}"`);
      expect(mail.html).toContain("ABCD-2345");
    }
  });
});
