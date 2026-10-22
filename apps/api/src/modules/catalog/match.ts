/**
 * Turns a pasted list ("8697711600852  BIOBALANCE SERUM RETINOL E 30ML  8", "26 serum discoloration",
 * or a name line followed by a quantity line) into product lines: parsing, then matching each line
 * to the catalogue by barcode or reference, then by name. Pure functions, no database.
 */
export interface ParsedLine {
  raw: string;
  /** A barcode (8 to 14 digits) or a product reference found in the line. */
  code: string | null;
  name: string;
  quantity: number | null;
}

const HEADER =
  /^(total|first list|second list|premi|deuxi|liste?\b|product|produit|r[ée]f[ée]rence|d[ée]signation|quantit[ée]|qt[ée]\b)/i;
const BARCODE = /^\d{8,14}$/;
const REFERENCE = /^BB-[A-Z]+-[\w-]+$/i;
const COUNT = /^\d{1,5}$/;

export function parseList(text: string): ParsedLine[] {
  const out: ParsedLine[] = [];
  let waiting: ParsedLine | null = null;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line) continue;
    if (waiting && COUNT.test(line)) {
      // A name on one line, its quantity on the next.
      waiting.quantity = Number(line);
      waiting = null;
      continue;
    }
    if (HEADER.test(line)) continue;
    const columns = line
      .split(/\t|;/)
      .map((c) => c.trim())
      .filter(Boolean);
    const parts = columns.length > 1 ? columns : line.split(/\s+/);
    let quantity: number | null = null;
    let code: string | null = null;
    const names: string[] = [];
    parts.forEach((part, index) => {
      if (code === null && (BARCODE.test(part) || REFERENCE.test(part))) {
        code = part;
      } else if (
        quantity === null &&
        COUNT.test(part) &&
        (index === 0 || index === parts.length - 1) &&
        (columns.length > 1 || parts.length > 1)
      ) {
        quantity = Number(part);
      } else names.push(part);
    });
    const name = names.join(" ").trim();
    if (!name && !code) continue;
    const parsed: ParsedLine = { raw: line, code, name, quantity };
    out.push(parsed);
    waiting = quantity === null ? parsed : null;
  }
  return out;
}

// ───────────────────────── Matching ─────────────────────────

export interface CatalogEntry {
  id: string;
  reference: string;
  barcode: string | null;
  name: string;
  family: string;
  imageId?: string | null;
}

export type MatchStatus = "MATCHED" | "UNSURE" | "MISSING";

export interface Match {
  raw: string;
  quantity: number | null;
  status: MatchStatus;
  product: CatalogEntry | null;
  candidates: CatalogEntry[];
}

/** Words that are written differently on a delivery note and in the catalogue. */
const SYNONYMS: Record<string, string> = {
  lavender: "lavande",
  pomegranate: "grenade",
  collagen: "collagene",
  shp: "shampoing",
  shamp: "shampoing",
  shampooing: "shampoing",
  shampoo: "shampoing",
  cream: "creme",
  net: "nettoyant",
  nety: "nettoyant",
  netv: "nettoyant",
  conditionner: "apres",
  conditioner: "apres",
  oil: "huile",
  vitamin: "vit",
  vitamine: "vit",
  hyaluronic: "hyaluronique",
  glycolic: "glycolique",
  eyes: "yeux",
};
/** Left out: brand and filler words that carry no meaning for matching. */
const IGNORED = new Set([
  "biobalance",
  "de",
  "du",
  "des",
  "la",
  "le",
  "d",
  "et",
  "and",
  "ml",
  "e",
  "g",
]);

export function tokens(text: string): string[] {
  const clean = text
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/niacinamide[\s-]*g\b/g, "niacinamide glycolique")
    .replace(/\bvit[\s-]*c\b|\bvitc\b/g, "vit c")
    .replace(/\bderma[\s-]+(soothe|sebum)/g, "derma$1")
    .replace(/(\d)\s*ml\b/g, "$1 ")
    .replace(/[^a-z0-9]+/g, " ");
  return (
    clean
      .split(" ")
      .filter(Boolean)
      .map((t) => SYNONYMS[t] ?? t)
      .flatMap((t) => t.split(" "))
      // A letter and a digit (B3, B5) is a vitamin label, not a word that tells products apart.
      .filter((t) => !IGNORED.has(t) && !/^[a-z]\d$/.test(t))
  );
}

const same = (a: string, b: string) =>
  a === b ||
  (a.length >= 4 && b.length >= 4 && (a.startsWith(b) || b.startsWith(a)));

/** How much of what was written is found in the product (a size counts for less than a word). */
export function score(query: string[], product: string[]): number {
  if (!query.length) return 0;
  let wanted = 0;
  let found = 0;
  for (const t of query) {
    const weight = /^\d+$/.test(t) ? 0.5 : 1;
    wanted += weight;
    if (product.some((p) => same(t, p))) found += weight;
  }
  return found / wanted;
}

export function matchLines(
  lines: ParsedLine[],
  catalogue: CatalogEntry[],
): Match[] {
  const prepared = catalogue.map((p) => ({
    p,
    tokens: [...tokens(p.name), ...tokens(p.family)],
  }));
  return lines.map((line) => {
    const byCode = line.code
      ? catalogue.find(
          (p) =>
            p.barcode === line.code ||
            p.reference.toLowerCase() === line.code!.toLowerCase() ||
            p.reference.endsWith(line.code!),
        )
      : undefined;
    if (byCode)
      return {
        raw: line.raw,
        quantity: line.quantity,
        status: "MATCHED" as const,
        product: byCode,
        candidates: [],
      };
    const query = tokens(line.name);
    const ranked = prepared
      .map((x) => ({
        p: x.p,
        score: score(query, x.tokens),
        // Fewer extra words in the product breaks ties.
        extra: x.tokens.length,
      }))
      .filter((x) => x.score >= 0.4)
      .sort((a, b) => b.score - a.score || a.extra - b.extra);
    const best = ranked[0];
    const second = ranked[1];
    const sure =
      best &&
      best.score >= 0.8 &&
      (!second || best.score - second.score >= 0.15);
    return {
      raw: line.raw,
      quantity: line.quantity,
      status: sure
        ? ("MATCHED" as const)
        : best
          ? ("UNSURE" as const)
          : ("MISSING" as const),
      product: sure ? best.p : null,
      candidates: sure ? [] : ranked.slice(0, 3).map((x) => x.p),
    };
  });
}
