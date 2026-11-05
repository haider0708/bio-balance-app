import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { startApi, type Api } from "./helpers";
import { renderInstallPage } from "../src/modules/auth/install-page.controller";
import { renderEmail } from "../src/email/templates";
import { renderWhatsApp } from "../src/whatsapp/templates";

let api: Api;
beforeAll(async () => {
  api = await startApi();
});
afterAll(() => api.close());

const stores = {
  android: "https://play.google.com/store/apps/details?id=tn.biobalance.app",
  ios: "https://testflight.apple.com/join/AbCd1234",
};

describe("the install page", () => {
  it("is public and allows only its own script", async () => {
    const res = await fetch(`${api.url}/install`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/html");
    expect(res.headers.get("content-security-policy")).toMatch(
      /script-src 'sha256-[A-Za-z0-9+/=]+'/,
    );
    expect(await res.text()).toContain("BioBalance");
  });

  it("gives each phone its steps and link, in both languages", () => {
    const html = renderInstallPage(stores);
    expect(html).toContain(`href="${stores.android}"`);
    expect(html).toContain(`href="${stores.ios}"`);
    expect(html).toContain("id899247664"); // TestFlight itself
    for (const text of ["Télécharger BioBalance", "Download BioBalance"])
      expect(html).toContain(text);
  });

  it("leaves out a phone whose link is not set", () => {
    const html = renderInstallPage({ android: stores.android, ios: null });
    expect(html).toContain('id="android"');
    expect(html).not.toContain('id="iphone"');
  });
});

describe("the welcome message", () => {
  const input = {
    kind: "credentials" as const,
    name: "Amira",
    email: "amira@example.test",
    password: "Kd7mPq2xWz",
    expiresAt: new Date("2026-11-12T10:00:00Z"),
    stores,
    installPage: "https://api.example.test/install",
  };

  it("says hello, installs, signs in: in French and in English, the same on both channels", () => {
    for (const locale of ["fr", "en"] as const) {
      const wa = renderWhatsApp(locale, input);
      const mail = renderEmail(locale, input).text;
      for (const text of [wa, mail]) {
        expect(text).toContain("Amira");
        expect(text).toContain(stores.android);
        expect(text).toContain(stores.ios);
        expect(text).toContain(input.installPage);
        expect(text).toContain("Kd7mPq2xWz");
        // The steps come before the sign-in details.
        expect(text.indexOf(stores.android)).toBeLessThan(
          text.indexOf("Kd7mPq2xWz"),
        );
        // An iPhone is first sent to TestFlight in the App Store, then to the app's own link.
        const store = text.indexOf("apps.apple.com/app/testflight");
        expect(store).toBeGreaterThan(-1);
        expect(store).toBeLessThan(text.indexOf(stores.ios));
        expect(text.indexOf(stores.ios)).toBeLessThan(
          text.indexOf("Kd7mPq2xWz"),
        );
      }
    }
  });

  it("skips a phone without a link instead of printing an empty step", () => {
    const text = renderWhatsApp("en", {
      ...input,
      stores: { android: stores.android, ios: null },
    });
    expect(text).not.toContain("TestFlight");
    expect(text).toContain("On Android");
    expect(text).not.toContain("On iPhone");
  });
});
