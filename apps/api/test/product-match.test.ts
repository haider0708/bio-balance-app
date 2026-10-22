import { describe, expect, it } from "vitest";
import catalogue from "./fixtures-catalogue.json";
import { matchLines, parseList } from "../src/modules/catalog/match";

// The real catalogue (copied from production), and the lists the owner actually pasted.
const ref = (r: string) => catalogue.find((p) => p.reference === r)!.name;
const run = (text: string) => matchLines(parseList(text), catalogue);
const names = (text: string) =>
  run(text).map((m) => (m.product ? m.product.name : `${m.status}:${m.raw}`));

describe("pasted lists", () => {
  it("reads barcode, name and quantity columns (a delivery note)", () => {
    const parsed = parseList(
      [
        "Référence\tDésignation\tQuantité",
        "8697711600852\tBIOBALANCE SERUM RETINOL E 30ML\t8",
        "8697711700156\tBIOBALANCE SHP LAVENDER 330ML\t1",
      ].join("\n"),
    );
    expect(parsed).toMatchObject([
      {
        code: "8697711600852",
        name: "BIOBALANCE SERUM RETINOL E 30ML",
        quantity: 8,
      },
      { code: "8697711700156", quantity: 1 },
    ]);
  });

  it("matches a delivery note by barcode, all six lines, with their quantities", () => {
    const m = run(
      [
        "8697711600852\tBIOBALANCE SERUM RETINOL E 30ML\t8",
        "8697711600838\tBIOBALANCE SERUM COLLAGEN-VITC\t8",
        "8697711602023\tBIOBALANCE SUPER GLOW GEL CR\t8",
        "8697711700170\tBIOBALANCE SHP CITRUS 330ML\t3",
        "8697711700156\tBIOBALANCE SHP LAVENDER 330ML\t1",
        "8697711700187\tBIOBALANCE SHP ALOE VERA 330ML\t2",
      ].join("\n"),
    );
    expect(m.map((x) => x.status)).toEqual(Array(6).fill("MATCHED"));
    expect(m.map((x) => x.quantity)).toEqual([8, 8, 8, 3, 1, 2]);
    expect(m[0]!.product!.name).toBe(ref("BB-WEB-64"));
    expect(m[4]!.product!.name).toBe(ref("BB-WEB-48"));
  });

  it("reads a name on one line and its quantity on the next", () => {
    const parsed = parseList(
      "First list\n\nProduct\n\nQuantité\n\nBIOBALANCE DERMA SOOTHE GEL NETTOY 250ML\n\n5\n\nBIOBALANCE SERUM RETINOL 30ML\n\n4\n\nTotal: 33 produits",
    );
    expect(parsed.map((p) => [p.name, p.quantity])).toEqual([
      ["BIOBALANCE DERMA SOOTHE GEL NETTOY 250ML", 5],
      ["BIOBALANCE SERUM RETINOL 30ML", 4],
    ]);
  });

  it("matches the names of the first order by words", () => {
    expect(
      names(
        [
          "BIOBALANCE DERMA SOOTHE GEL NETTOY 250ML\n5",
          "BIOBALANCE DERMA SEBUM GEL 250ML\n5",
          "BIOBALANCE SERUM COLLAGEN+VIT C 30ML\n4",
          "BIOBALANCE SERUM DISCOLORATION FREE\n5",
          "BIOBALANCE SERUM NIACINAMIDE-B3 30ML\n5",
          "BIOBALANCE SERUM RETINOL 30ML\n4",
          "BIOBALANCE SHAMP LAVENDER 330ML\n5",
        ].join("\n"),
      ),
    ).toEqual([
      ref("BB-WEB-23"),
      ref("BB-WEB-28"),
      ref("BB-EAN-8697711600838"),
      ref("BB-WEB-36"),
      ref("BB-WEB-39"),
      ref("BB-WEB-64"),
      ref("BB-WEB-48"),
    ]);
  });

  it("matches the quantity-first list of an opening count", () => {
    const m = run(
      [
        "26 serum discoloration",
        "28 serum niacinamide-G",
        "12 serum pure vitamin C",
        "10 serum collagen vitamin C",
        "10 serum retinol",
        "24 cream super eye",
        "30 cream super plump",
        "20 cream super glow",
        "27 cream super hydrator",
        "22 cream super pure",
        "28 cream super lift",
        "1 super toner glow skin c",
        "9 magic touch",
        "10 gel net dermasoothe",
        "10 gel net dermasebum",
        "47 shampoo organic citrus",
        "45 shampoo organic aloe vera",
        "12 conditionner organic argan oil",
        "48 shampoo lavender",
        "2 shampoo pomegranate",
      ].join("\n"),
    );
    expect(m.filter((x) => x.status !== "MATCHED").map((x) => x.raw)).toEqual(
      [],
    );
    expect(m.map((x) => x.quantity)).toEqual([
      26, 28, 12, 10, 10, 24, 30, 20, 27, 22, 28, 1, 9, 10, 10, 47, 45, 12, 48,
      2,
    ]);
    expect(m.map((x) => x.product!.reference)).toEqual([
      "BB-WEB-36",
      "BB-WEB-39",
      "BB-WEB-37",
      "BB-EAN-8697711600838",
      "BB-WEB-64",
      "BB-WEB-32",
      "BB-WEB-33",
      "BB-WEB-29",
      "BB-WEB-65",
      "BB-WEB-31",
      "BB-WEB-30",
      "BB-WEB-43",
      "BB-WEB-46",
      "BB-WEB-23",
      "BB-WEB-28",
      "BB-WEB-49",
      "BB-WEB-50",
      "BB-WEB-51",
      "BB-WEB-48",
      "BB-WEB-47",
    ]);
  });

  it("says when a line is unsure or missing instead of guessing", () => {
    const m = run("3 banana split\n4 serum\n5 xyzzy");
    expect(m[0]!.status).toBe("MISSING");
    expect(m[1]!.status).toBe("UNSURE"); // many serums
    expect(m[1]!.candidates.length).toBeGreaterThan(1);
    expect(m[2]!.status).toBe("MISSING");
  });
});
