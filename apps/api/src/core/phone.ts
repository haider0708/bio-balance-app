import { DomainError } from "./errors";

/**
 * Tunisian mobile numbers, as people write them: "21 345 678", "+216 21 345 678", "00216 21345678",
 * "216-21-345-678", "(+216) 21.345.678". Every form becomes the one canonical "+21621345678", which is
 * what WhatsApp needs and what is stored. Only Tunisia for now: eight digits after the country code.
 */
export const TUNISIA_CODE = "216";

/** Digits only, with the country code and the "+" / "00" international prefix taken off. */
function nationalDigits(input: string): string | null {
  let digits = input.trim().replace(/[\s.\-()]/g, "");
  if (digits.startsWith("+")) digits = digits.slice(1);
  else if (digits.startsWith("00")) digits = digits.slice(2);
  else if (digits.length === 11 && digits.startsWith(TUNISIA_CODE)) {
    // "21621345678": the code written without a prefix.
  } else if (/^\d{8}$/.test(digits)) return digits;
  if (!/^\d+$/.test(digits)) return null;
  if (!digits.startsWith(TUNISIA_CODE)) return null;
  const rest = digits.slice(TUNISIA_CODE.length);
  return /^\d{8}$/.test(rest) ? rest : null;
}

/** "+21621345678", or null when it is not a Tunisian number of eight digits. */
export function normalizeTunisianPhone(input: string): string | null {
  const national = nationalDigits(input);
  // A number never starts with 0 or 1 in Tunisia.
  if (!national || !/^[2-9]/.test(national)) return null;
  return `+${TUNISIA_CODE}${national}`;
}

/** "+216 21 345 678", for showing a number back to the person who typed it. */
export function formatPhone(e164: string): string {
  const m = /^\+216(\d{2})(\d{3})(\d{3})$/.exec(e164);
  return m ? `+216 ${m[1]} ${m[2]} ${m[3]}` : e164;
}

/** The WhatsApp chat id of a canonical number. */
export const whatsappChatId = (e164: string) => `${e164.slice(1)}@c.us`;

/**
 * The canonical number of a field a person filled in, or the reason it cannot be used: the field is
 * required for new accounts (the codes are sent to it by WhatsApp), and it must be a Tunisian number.
 */
export function canonicalPhone(input: string | null | undefined): string {
  if (!input?.trim())
    throw new DomainError(
      "PHONE_REQUIRED",
      "Enter the phone number: the codes are sent by WhatsApp too.",
    );
  const phone = normalizeTunisianPhone(input);
  if (!phone)
    throw new DomainError(
      "PHONE_INVALID",
      "Enter a Tunisian mobile number: 8 digits, with or without +216 or 00216.",
    );
  return phone;
}
