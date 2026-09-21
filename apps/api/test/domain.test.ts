import { describe, it, expect } from "vitest";
import { Money, expiryDate } from "../src/shared/domain/money";
import { Sale } from "../src/modules/operations/domain/sale";
import { totp } from "../src/modules/identity/identity.service";
const line = {
  id: "line",
  productId: "product",
  quantity: 2,
  unitPriceMillimes: "49900",
  allocations: [{ lotId: "lot", quantity: 2 }],
};
const lots = new Map([
  [
    "lot",
    {
      id: "lot",
      productId: "product",
      batch: "A",
      expiry: new Date("2027-03-31"),
      sellable: 1,
      damaged: 0,
      version: 1,
    },
  ],
]);
describe("exact business values", () => {
  it("calculates TND exactly and rejects fractions, negative values and overflow", () => {
    expect(Money.from("49900").multiply(3).toJSON()).toEqual({
      currency: "TND",
      millimes: "149700",
    });
    for (const bad of ["1.2", "-1", "1e3", "01", "1000000000000000"])
      expect(() => Money.from(bad)).toThrow();
    expect(() => Money.from("1").multiply(1.2)).toThrow();
  });
  it("normalizes month expiry and validates leap days", () => {
    expect(expiryDate("2028-02")).toBe("2028-02-29");
    expect(expiryDate("2027-02")).toBe("2027-02-28");
    expect(() => expiryDate("2027-02-29")).toThrow();
  });
  it("accepts real sales with a recorded shortage and freezes accepted rates", () => {
    const sale = Sale.accept(
      "s",
      "seller",
      new Date("2026-09-01"),
      [line],
      new Map([["product", 10]]),
      lots,
      "Africa/Tunis",
    );
    expect(sale.record.earnedPoints).toBe(20n);
    expect(sale.stockDelta().get("lot")).toBe(-2);
    const corrected = Sale.accept(
      "s",
      "seller",
      sale.record.occurredAt,
      [{ ...line, quantity: 1, allocations: [{ lotId: "lot", quantity: 1 }] }],
      new Map([["product", 99]]),
      lots,
      "Africa/Tunis",
      sale.record,
    );
    expect(corrected.record.earnedPoints).toBe(10n);
    expect(corrected.stockDelta(sale.record).get("lot")).toBe(1);
  });
  it("prevents over-returns including repeated lot entries", () => {
    const sale = Sale.accept(
      "s",
      "seller",
      new Date("2026-09-01"),
      [line],
      new Map([["product", 10]]),
      lots,
      "Africa/Tunis",
    );
    expect(() =>
      sale.returnItems([
        { lineId: "line", lotId: "lot", quantity: 2, sellable: true },
        { lineId: "line", lotId: "lot", quantity: 1, sellable: true },
      ]),
    ).toThrow();
    expect(
      sale.returnItems([
        { lineId: "line", lotId: "lot", quantity: 1, sellable: false },
      ]).points,
    ).toBe(-10n);
  });
  it("checks expiry using the actual sale date", () => {
    expect(() =>
      Sale.accept(
        "s",
        "seller",
        new Date("2027-04-01"),
        [line],
        new Map(),
        lots,
        "Africa/Tunis",
        undefined,
        new Date("2027-04-02"),
      ),
    ).toThrow();
  });
  it("matches the RFC 6238 SHA-1 test vector truncated to six digits", () => {
    expect(totp(Buffer.from("12345678901234567890").toString("hex"), 1n)).toBe(
      "287082",
    );
  });
});
