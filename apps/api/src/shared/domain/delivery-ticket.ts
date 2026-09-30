import { createHmac, timingSafeEqual } from "node:crypto";
import { requireRule } from "./errors";

/** The QR proves the physical parcel: it carries a code only the server can
 * derive from the delivery and its current ticket version. The QR is shown to
 * the shipper alone, never to the receiver, and all content is read from the
 * server after sign-in. */
function key(): Buffer {
  const configured = Buffer.from(
    process.env.MFA_ENCRYPTION_KEY ?? "",
    "base64",
  );
  if (configured.length === 32) return configured;
  requireRule(
    process.env.NODE_ENV !== "production",
    "TICKET_CONFIGURATION",
    "Configuration des bons de livraison manquante.",
    503,
  );
  return Buffer.from("biobalance-development-ticket-key");
}

export function ticketCode(deliveryId: string, version: number): string {
  return createHmac("sha256", key())
    .update(`delivery-ticket:${deliveryId}:${version}`)
    .digest("base64url")
    .slice(0, 22);
}

/** The string printed in the QR. */
export function ticketPayload(deliveryId: string, version: number): string {
  return `BB1.${deliveryId}.${ticketCode(deliveryId, version)}`;
}

export function verifyTicketCode(
  deliveryId: string,
  version: number,
  code: string,
): boolean {
  const expected = Buffer.from(ticketCode(deliveryId, version));
  const given = Buffer.from(code);
  return given.length === expected.length && timingSafeEqual(given, expected);
}
