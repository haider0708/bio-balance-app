import { DomainError } from "./errors";

/**
 * The mistyped well-known address: "name@gamail.com" is never meant, and the password sent there would
 * reach a stranger (or nobody). Only the big public providers are checked; any other domain is trusted.
 * A first part that is a known slip of a provider, or a provider with an ending it does not have
 * ("gmail.con"), is refused with the address that was probably meant.
 */
const PROVIDERS: Record<string, readonly string[]> = {
  gmail: ["com"],
  yahoo: ["com", "fr"],
  hotmail: ["com", "fr"],
  outlook: ["com", "fr"],
  live: ["com", "fr"],
  icloud: ["com"],
};

const SLIPS: Record<string, string> = {
  gamail: "gmail",
  gmial: "gmail",
  gmai: "gmail",
  gmil: "gmail",
  gmaill: "gmail",
  gnail: "gmail",
  gmali: "gmail",
  gmal: "gmail",
  gmaol: "gmail",
  gmeil: "gmail",
  hotmial: "hotmail",
  hotmai: "hotmail",
  hotnail: "hotmail",
  homail: "hotmail",
  hotmal: "hotmail",
  hotmaill: "hotmail",
  hotamil: "hotmail",
  yaho: "yahoo",
  yahooo: "yahoo",
  yhoo: "yahoo",
  yahou: "yahoo",
  yaoo: "yahoo",
  outlok: "outlook",
  outllook: "outlook",
  outloock: "outlook",
  iclod: "icloud",
  icoud: "icloud",
  icloude: "icloud",
};

/** The address that was probably meant, or null when the one given looks right. */
export function suggestEmail(email: string): string | null {
  const at = email.lastIndexOf("@");
  if (at < 1) return null;
  const local = email.slice(0, at);
  const domain = email.slice(at + 1).toLowerCase();
  const dot = domain.indexOf(".");
  if (dot < 1) return null;
  const label = domain.slice(0, dot);
  const ending = domain.slice(dot + 1);
  // "yahoo.co.uk", "gmail.com.tn": an ending with several parts is not a slip we know.
  if (ending.includes(".")) return null;
  const provider = SLIPS[label] ?? (label in PROVIDERS ? label : null);
  if (!provider) return null;
  const endings = PROVIDERS[provider]!;
  if (provider === label && endings.includes(ending)) return null;
  const fixedEnding = endings.includes(ending) ? ending : endings[0]!;
  return `${local}@${provider}.${fixedEnding}`;
}

/** Refuses an address that is almost certainly a typo of a well-known provider. */
export function assertEmailLooksRight(email: string) {
  const suggestion = suggestEmail(email);
  if (suggestion)
    throw new DomainError(
      "EMAIL_TYPO",
      `This email address looks mistyped. Did you mean ${suggestion}?`,
      422,
      { suggestion },
    );
}
