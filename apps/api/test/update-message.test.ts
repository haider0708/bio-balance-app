import { describe, expect, it } from "vitest";
import { renderEmail } from "../src/email/templates";
import { Payload } from "../src/email/delivery";
import { renderWhatsApp } from "../src/whatsapp/templates";

const stores = {
  android: "https://play.google.com/store/apps/details?id=tn.biobalance.app",
  ios: "https://testflight.apple.com/join/AbCd1234",
};
const input = {
  kind: "update" as const,
  name: "Amira",
  stores,
  installPage: "https://api.example.test/install",
};

describe("the 'update your app' message", () => {
  it("tells an existing user to update, with the right link per phone, and no password", () => {
    for (const locale of ["fr", "en"] as const) {
      const whatsapp = renderWhatsApp(locale, input).join("\n\n");
      const email = renderEmail(locale, input);
      for (const part of [whatsapp, email.text, email.html]) {
        expect(part).toContain("Amira");
        expect(part).toContain(stores.android);
        expect(part).toContain(stores.ios);
        expect(part).toContain("https://api.example.test/install");
        expect(part).not.toMatch(/mot de passe provisoire|temporary password/i);
      }
    }
    expect(renderWhatsApp("fr", input).join("\n")).toContain("Mettre à jour");
    expect(renderWhatsApp("en", input).join("\n")).toContain("tap Update");
    expect(renderEmail("fr", input).subject).toBe("Mettez à jour BioBalance");
  });

  it("is a valid queued payload, and only a user id and a version travel in it", () => {
    const payload = {
      template: "update",
      userId: "6f1c1c1e-1d57-4d6a-8c0e-0a7a5b1d4a11",
      version: "3.5.0",
    };
    expect(Payload.safeParse(payload).success).toBe(true);
    expect(Payload.safeParse({ ...payload, userId: "x" }).success).toBe(false);
  });
});
