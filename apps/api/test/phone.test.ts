import { describe, expect, it } from "vitest";
import {
  formatPhone,
  normalizeTunisianPhone,
  whatsappChatId,
} from "../src/core/phone";

describe("Tunisian phone numbers", () => {
  it.each([
    "21345678",
    "21 345 678",
    "21.345.678",
    "21-345-678",
    "+216 21 345 678",
    "+21621345678",
    "00216 21345678",
    "0021621345678",
    "216 21 345 678",
    "21621345678",
    "(+216) 21 345 678",
    "  +216-21-345-678  ",
  ])("reads %j as +21621345678", (input) => {
    expect(normalizeTunisianPhone(input)).toBe("+21621345678");
  });

  it.each([
    "",
    "2134567", // seven digits
    "213456789", // nine digits
    "+216 2134567",
    "+33 6 12 34 56 78", // another country
    "0021 21345678",
    "abc",
    "01234567", // starts with 0
    "11345678", // starts with 1
    "+216 0 1234567",
    "21 345 678 9",
  ])("refuses %j", (input) => {
    expect(normalizeTunisianPhone(input)).toBeNull();
  });

  it("shows a number back readably and gives its WhatsApp id", () => {
    expect(formatPhone("+21621345678")).toBe("+216 21 345 678");
    expect(whatsappChatId("+21621345678")).toBe("21621345678@c.us");
  });
});
