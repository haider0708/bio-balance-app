import { accountLink } from "../../modules/identity/account-links";

export interface EmailContent {
  subject: string;
  text: string;
  html: string;
}
interface CredentialEmail {
  token: string;
  expiresAt: Date;
  organizationName?: string;
  storeName?: string;
  invitationKind?: "new_group" | "responsible" | "salesperson" | null;
}
export type EmailTemplate =
  | ({ kind: "invite" } & CredentialEmail)
  | ({ kind: "reset" } & CredentialEmail)
  | { kind: "password-changed"; changedAt: Date }
  | { kind: "delivery-test"; reference: string; sentAt: Date };

const escape = (value: string) =>
  value.replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ]!,
  );
const dateLabel = (value: Date) =>
  new Intl.DateTimeFormat("fr-TN", {
    timeZone: "Africa/Tunis",
    dateStyle: "short",
    timeStyle: "short",
    hourCycle: "h23",
  }).format(value) + " (heure de Tunis)";

/** No remote images, tracking pixels, fonts, scripts or arbitrary HTML. */
export function renderEmail(input: EmailTemplate): EmailContent {
  let subject: string, heading: string, paragraphs: string[];
  let code: string | undefined,
    codeLabel: string | undefined,
    expiry: string | undefined,
    instruction: string | undefined,
    link: string | undefined,
    action: string | undefined,
    note: string | undefined;
  let details: string[] = [];
  if (input.kind === "invite") {
    subject = "Votre invitation BioBalance";
    heading = input.storeName
      ? "Rejoindre votre équipe"
      : "Activer votre accès";
    paragraphs = [
      input.invitationKind === "new_group"
        ? "Vous êtes invité(e) à créer votre groupe et vos magasins dans BioBalance."
        : input.storeName
          ? `Vous êtes invité(e) à rejoindre l’équipe de ${input.storeName}.`
          : input.invitationKind === "salesperson"
            ? `Vous êtes invité(e) à rejoindre les magasins qui vous sont attribués dans ${input.organizationName ?? "votre groupe"}.`
            : `Vous êtes invité(e) à gérer tous les magasins de ${input.organizationName ?? "votre groupe"}.`,
    ];
    instruction =
      "Dans l’application BioBalance, choisissez « Activer mon invitation » et saisissez ce code.";
    code = input.token;
    codeLabel = "Code d’activation";
    expiry = `Valable jusqu’au ${dateLabel(input.expiresAt)}. Usage unique.`;
    link = accountLink("invite", input.token);
    action = "Activer mon invitation";
    details = [
      "Si vous avez déjà un compte, utilisez votre mot de passe actuel.",
    ];
    note =
      "Ce code est personnel. Si vous ne reconnaissez pas cette invitation, ignorez cet email.";
  } else if (input.kind === "reset") {
    subject = "Réinitialiser votre mot de passe BioBalance";
    heading = "Réinitialiser votre mot de passe";
    paragraphs = [
      "Une réinitialisation du mot de passe a été demandée pour votre compte.",
    ];
    instruction =
      "Dans BioBalance, ouvrez « Mot de passe oublié ? », puis « J’ai déjà reçu un code » et saisissez ce code.";
    code = input.token;
    codeLabel = "Code de récupération";
    expiry = `Valable jusqu’au ${dateLabel(input.expiresAt)}. Usage unique.`;
    link = accountLink("reset", input.token);
    action = "Réinitialiser mon mot de passe";
    note =
      "Si vous n’avez pas fait cette demande, ignorez cet email. Votre mot de passe reste inchangé.";
  } else if (input.kind === "password-changed") {
    subject = "Votre mot de passe BioBalance a été modifié";
    heading = "Mot de passe modifié";
    paragraphs = [
      "Votre mot de passe a été modifié. Vos sessions précédentes ont été fermées.",
      "Connectez-vous avec votre nouveau mot de passe.",
    ];
    details = [dateLabel(input.changedAt)];
    note =
      "Si vous n’êtes pas à l’origine de ce changement, réinitialisez immédiatement votre mot de passe dans l’application et contactez votre responsable ou l’administrateur BioBalance.";
  } else {
    subject = "BioBalance — test de livraison des emails";
    heading = "Email de test";
    paragraphs = [
      "Ceci est un test d’envoi BioBalance. Aucune action n’est nécessaire.",
    ];
    details = [dateLabel(input.sentAt), `Référence : ${input.reference}`];
  }
  const text = [
    "BioBalance",
    heading,
    ...paragraphs,
    ...(link ? [`${action} : ${link}`] : []),
    ...(instruction ? [instruction] : []),
    ...(code ? [`Votre code : ${code}`] : []),
    ...(expiry ? [expiry] : []),
    ...details,
    ...(note ? [note] : []),
  ].join("\n\n");
  const html = `<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="light"><title>${escape(subject)}</title></head>
<body style="margin:0;padding:0;background:#ffffff;color:#202522;font-family:Arial,Helvetica,sans-serif;-webkit-text-size-adjust:100%">
<div style="display:none;max-height:0;overflow:hidden;mso-hide:all">${escape(paragraphs[0]!)}</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"><tr><td align="center" style="padding:32px 20px">
<!--[if mso]><table role="presentation" width="480" cellspacing="0" cellpadding="0" border="0"><tr><td><![endif]-->
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:480px;text-align:left">
<tr><td style="padding:0 0 28px;color:#286b34;font-size:15px;line-height:1.5;font-weight:600">BioBalance</td></tr>
<tr><td><h1 style="margin:0 0 16px;font-size:22px;line-height:1.35;font-weight:600">${escape(heading)}</h1>
${paragraphs.map((p) => `<p style="margin:0 0 16px;font-size:16px;line-height:1.6">${escape(p)}</p>`).join("\n")}
${link ? `<p style="margin:24px 0"><a href="${escape(link)}" style="display:inline-block;background:#286b34;color:#ffffff;padding:12px 18px;border-radius:4px;text-decoration:none;font-size:16px;line-height:1.5;font-weight:600">${escape(action!)}</a></p>` : ""}
${instruction ? `<p style="margin:0 0 20px;font-size:16px;line-height:1.6">${escape(instruction)}</p>` : ""}
${code ? `<p style="margin:0 0 8px;font-size:14px;line-height:1.5;color:#5d665f">${escape(codeLabel!)}</p><p style="margin:0 0 8px;padding:12px;border:1px solid #e1e6e2;border-radius:4px;word-break:break-all;overflow-wrap:anywhere;font-family:Consolas,monospace;font-size:16px;line-height:1.6">${escape(code)}</p>` : ""}
${expiry ? `<p style="margin:0 0 20px;font-size:14px;line-height:1.5;color:#5d665f">${escape(expiry)}</p>` : ""}
${details.map((p) => `<p style="margin:0 0 12px;font-size:14px;line-height:1.6;color:#5d665f;overflow-wrap:anywhere">${escape(p)}</p>`).join("\n")}
${note ? `<p style="margin:24px 0 0;font-size:14px;line-height:1.6;color:#5d665f">${escape(note)}</p>` : ""}
</td></tr></table>
<!--[if mso]></td></tr></table><![endif]-->
</td></tr></table></body></html>`;
  return { subject, text, html };
}
