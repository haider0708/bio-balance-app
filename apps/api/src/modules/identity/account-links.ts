import { requireRule } from "../../shared/domain/errors";

/** Capabilities are sent as manual codes unless an owned HTTPS link is configured. */
export function accountLink(purpose: "invite" | "reset", token: string) {
  const configured =
    process.env[purpose === "invite" ? "ACTIVATION_URL" : "RECOVERY_URL"];
  if (configured) {
    let url: URL | undefined;
    try {
      url = new URL(configured);
    } catch {
      /* handled by domain validation */
    }
    requireRule(
      url &&
        url.protocol === "https:" &&
        !url.username &&
        !url.password &&
        !url.search &&
        !url.hash &&
        (!url.port || url.port === "443") &&
        url.pathname === (purpose === "invite" ? "/activate" : "/recover"),
      "ACCOUNT_LINK_CONFIGURATION",
      "Le lien de compte doit utiliser le domaine HTTPS vérifié.",
      503,
    );
    url!.searchParams.set("token", token);
    return url!.toString();
  }
  return undefined;
}

export function accountTokenMessage(
  purpose: "invite" | "reset",
  token: string,
) {
  const url = accountLink(purpose, token);
  const link = url ? `Ouvrez ${url} ou ` : "";
  return purpose === "invite"
    ? `Vous êtes invité sur BioBalance. ${link}Saisissez ce code dans l’application : ${token}. Cette invitation expire dans 48 heures.`
    : `${link}Saisissez votre code de réinitialisation dans l’application : ${token}. Valable 30 minutes. Si vous n’avez pas demandé ce changement, ignorez ce message.`;
}
