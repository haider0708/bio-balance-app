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
  ios: "https://apps.apple.com/tn/app/biobalance/id6822445997",
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

  it("gives each phone its store, with the app's own screens, in each language", () => {
    for (const [lang, title] of [
      ["fr", "Installer BioBalance"],
      ["en", "Install BioBalance"],
    ] as const) {
      const html = renderInstallPage(stores, lang);
      expect(html).toContain(`href="${stores.android}"`);
      expect(html).toContain(`href="${stores.ios}"`);
      expect(html).toContain(title);
      expect(html).not.toContain("TestFlight");
      for (const shot of [
        "1-sign-in",
        "2-activate",
        "3-choose-password",
        "4-home",
      ])
        expect(html).toContain(`/install/img/${lang}/${shot}.jpg`);
    }
  });

  it("picks the language of the link, then of the phone, then French", async () => {
    const get = async (path: string, accept?: string) =>
      (
        await fetch(`${api.url}${path}`, {
          headers: accept ? { "accept-language": accept } : {},
        })
      ).text();
    expect(await get("/install?lang=en")).toContain("Install BioBalance");
    expect(await get("/install", "en-GB,en;q=0.9")).toContain(
      "Install BioBalance",
    );
    expect(await get("/install", "fr-TN")).toContain("Installer BioBalance");
    expect(await get("/install?lang=en", "fr")).toContain("Install BioBalance");
    expect(await get("/install")).toContain("Installer BioBalance");
  });

  it("serves its four pictures in both languages, and nothing else", async () => {
    for (const lang of ["fr", "en"])
      for (const shot of [
        "1-sign-in",
        "2-activate",
        "3-choose-password",
        "4-home",
      ]) {
        const res = await fetch(`${api.url}/install/img/${lang}/${shot}.jpg`);
        expect(res.status).toBe(200);
        expect(res.headers.get("content-type")).toContain("image/jpeg");
        expect((await res.arrayBuffer()).byteLength).toBeGreaterThan(10_000);
      }
    for (const path of [
      "/install/img/de/1-sign-in.jpg",
      "/install/img/fr/secret.jpg",
      "/install/img/fr/1-sign-in.png",
      "/install/img/fr/..%2F..%2Fpackage.json",
    ])
      expect((await fetch(`${api.url}${path}`)).status).toBe(404);
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
      const wa = renderWhatsApp(locale, input).join("\n\n");
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
        // An iPhone goes straight to the app's page in the App Store, before the sign-in details.
        expect(text).not.toContain("TestFlight");
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
    }).join("\n\n");
    expect(text).not.toContain("TestFlight");
    expect(text).toContain("Android:");
    expect(text).not.toContain("iPhone");
  });
});
