import { describe, expect, it } from "vitest";
import { assertEmailLooksRight, suggestEmail } from "../src/core/email-typo";

describe("mistyped well-known email addresses", () => {
  it.each([
    ["benamorarij088@gamail.com", "benamorarij088@gmail.com"],
    ["a@gmial.com", "a@gmail.com"],
    ["a@gmai.com", "a@gmail.com"],
    ["a@gmail.con", "a@gmail.com"],
    ["a@gmail.co", "a@gmail.com"],
    ["a@gmail.fr", "a@gmail.com"],
    ["a@hotmial.com", "a@hotmail.com"],
    ["a@hotmail.con", "a@hotmail.com"],
    ["a@yaho.fr", "a@yahoo.fr"],
    ["a@yahoo.con", "a@yahoo.com"],
    ["a@outlok.com", "a@outlook.com"],
    ["a@iclod.com", "a@icloud.com"],
    ["First.Last@GAMAIL.COM", "First.Last@gmail.com"],
  ])("%s is probably %s", (typed, meant) => {
    expect(suggestEmail(typed)).toBe(meant);
  });

  it.each([
    "a@gmail.com",
    "a@yahoo.fr",
    "a@yahoo.com",
    "a@hotmail.fr",
    "a@outlook.com",
    "a@live.fr",
    "a@icloud.com",
    "eya.mtaallah@etudiant-issbat.utm.tn",
    "boss@galylio.com",
    "a@gmx.com",
    "a@mail.gmail.com.example.tn",
    "a@livelihood.com",
    "a@yahoo.co.uk",
  ])("%s is left alone", (email) => {
    expect(suggestEmail(email)).toBeNull();
  });

  it("refuses with a code the phone translates, naming the address that was meant", () => {
    expect(() => assertEmailLooksRight("a@gamail.com")).toThrowError(
      expect.objectContaining({
        code: "EMAIL_TYPO",
        details: { suggestion: "a@gmail.com" },
      }),
    );
    expect(() => assertEmailLooksRight("a@gmail.com")).not.toThrow();
  });
});
