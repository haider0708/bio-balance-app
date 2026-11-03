/** How close to a place counts as being there, and what a position at a check-in says about it. */
export const CHECK_IN_RADIUS_M = 150;
/** Indoors a phone is often wrong by tens of metres: the radius grows by its own doubt, up to this much. */
export const ACCURACY_ALLOWANCE_M = 100;
/** A reading that doubtful says nothing about where the phone is. */
export const MAX_USABLE_ACCURACY_M = 200;
/** To set a place's position the reading must be good. */
export const MAX_POSITION_ACCURACY_M = 50;

/** Tunisia with some margin: a latitude and longitude typed the wrong way round fall outside it. */
const TUNISIA = { minLat: 29.5, maxLat: 38.5, minLng: 7, maxLng: 12.5 };

export interface Point {
  latitude: number;
  longitude: number;
}

export type Verdict =
  "VERIFIED" | "OUT_OF_RANGE" | "NO_FIX" | "NO_POSITION" | "SANDBOX";

export function inTunisia(p: Point) {
  return (
    p.latitude >= TUNISIA.minLat &&
    p.latitude <= TUNISIA.maxLat &&
    p.longitude >= TUNISIA.minLng &&
    p.longitude <= TUNISIA.maxLng
  );
}

/** Metres between two points on the earth (haversine). */
export function distanceMeters(a: Point, b: Point) {
  const rad = Math.PI / 180;
  const dLat = (b.latitude - a.latitude) * rad;
  const dLng = (b.longitude - a.longitude) * rad;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(a.latitude * rad) *
      Math.cos(b.latitude * rad) *
      Math.sin(dLng / 2) ** 2;
  return Math.round(2 * 6_371_000 * Math.asin(Math.min(1, Math.sqrt(h))));
}

export interface Judgement {
  verdict: Verdict;
  distanceM: number | null;
  flags: string[];
}

/**
 * What the position given at a check-in says. It is evidence, not proof: it tells where the phone
 * was, not who held it. The test region accepts any position (a store reviewer is not at a store).
 */
export function judgePresence(input: {
  place: Point | null;
  fix: Partial<Point> | null;
  accuracyM?: number | null;
  sandbox?: boolean;
}): Judgement {
  if (input.sandbox) return { verdict: "SANDBOX", distanceM: null, flags: [] };
  const { fix } = input;
  if (fix?.latitude == null || fix.longitude == null)
    return { verdict: "NO_FIX", distanceM: null, flags: [] };
  const accuracy = input.accuracyM ?? null;
  if (accuracy != null && accuracy > MAX_USABLE_ACCURACY_M)
    return { verdict: "NO_FIX", distanceM: null, flags: ["LOW_ACCURACY"] };
  if (!input.place)
    return { verdict: "NO_POSITION", distanceM: null, flags: [] };
  const distanceM = distanceMeters(
    { latitude: fix.latitude, longitude: fix.longitude },
    input.place,
  );
  const radius =
    CHECK_IN_RADIUS_M + Math.min(accuracy ?? 0, ACCURACY_ALLOWANCE_M);
  return {
    verdict: distanceM <= radius ? "VERIFIED" : "OUT_OF_RANGE",
    distanceM,
    flags: [],
  };
}
