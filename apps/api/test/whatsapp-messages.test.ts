import { describe, expect, it } from "vitest";
import { renderWhatsApp, shown } from "../src/whatsapp/templates";
import type { WhatsAppTemplate } from "../src/whatsapp/templates";

const stores = {
  android: "https://play.google.com/store/apps/details?id=tn.biobalance.app",
  ios: "https://apps.apple.com/tn/app/biobalance/id6822445997",
};
const links = {
  stores,
  installPage: "https://api.example.test/install?lang=fr",
};
const code = "K7MQ4XZR";
const password = "Kd7mPq2xWz";
const email = "nora@example.test";

const notices: Record<string, WhatsAppTemplate> = {
  invite: {
    kind: "invite",
    code,
    name: "Nora",
    email,
    link: `https://api.example.test/c#i.${code}`,
    ...links,
  },
  credentials: {
    kind: "credentials",
    name: "Amira",
    email,
    password,
    expiresAt: new Date("2026-11-12T10:00:00Z"),
    ...links,
  },
  reset: {
    kind: "reset",
    code,
    name: "Nora",
    minutes: 60,
    link: `https://api.example.test/c#r.${code}`,
    ...links,
  },
  changed: {
    kind: "password-changed",
    name: "Nora",
    changedAt: new Date("2026-11-09T10:00:00Z"),
    ...links,
  },
  update: { kind: "update", name: "Nora", ...links },
};

describe("the WhatsApp messages", () => {
  it.each(["fr", "en"] as const)(
    "are short, named, and never mention TestFlight, in %s",
    (locale) => {
      for (const [name, notice] of Object.entries(notices)) {
        const texts = renderWhatsApp(locale, notice);
        expect(texts.length, name).toBeLessThanOrEqual(4);
        // The first message always opens with the app's name, then greets.
        expect(texts[0], name).toMatch(
          locale === "fr"
            ? /^\*BioBalance\*\nBonjour /
            : /^\*BioBalance\*\nHello /,
        );
        for (const text of texts) {
          expect(text.length, name).toBeLessThan(700);
          expect(text).not.toMatch(/testflight/i);
        }
      }
    },
  );

  it.each(["fr", "en"] as const)(
    "carry both store links, each alone on its line, in every notice, in %s",
    (locale) => {
      for (const [name, notice] of Object.entries(notices)) {
        const first = renderWhatsApp(locale, notice)[0]!;
        const lines = first.split("\n");
        expect(lines, name).toContain(stores.android);
        expect(lines, name).toContain(stores.ios);
      }
    },
  );

  it.each(["fr", "en"] as const)(
    "give every new account the same steps: stores first, then the guide, in %s",
    (locale) => {
      // A code (responsable, order manager) or a password (seller, buyer): the same first message.
      for (const kind of ["invite", "credentials"]) {
        const first = renderWhatsApp(locale, notices[kind]!)[0]!;
        expect(first).toContain("*1.");
        expect(first).toContain("*2.");
        expect(first).toContain(links.installPage);
        expect(first.indexOf(stores.android)).toBeLessThan(
          first.indexOf(links.installPage),
        );
        // The secrets are not in it: they follow, each alone.
        expect(first).not.toContain(password);
        expect(first).not.toContain(shown(code));
        expect(first).not.toContain(email);
      }
    },
  );

  it("sends the email, then the code or the password, each alone in its message", () => {
    const invite = renderWhatsApp("fr", notices.invite!);
    expect(invite.slice(1)).toEqual([email, shown(code)]);
    const credentials = renderWhatsApp("fr", notices.credentials!);
    expect(credentials.slice(1, 3)).toEqual([email, password]);
    const reset = renderWhatsApp("fr", notices.reset!);
    expect(reset.at(-1)).toBe(shown(code));
  });

  it("tells a person who already has the app to update, without the guide or a code", () => {
    const [text] = renderWhatsApp("fr", notices.update!);
    expect(text).toContain("mettre à jour");
    expect(text).not.toContain("/install");
    expect(text).not.toContain(code);
  });
});
