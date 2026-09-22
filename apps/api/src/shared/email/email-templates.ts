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
    dateStyle: "long",
    timeStyle: "short",
    hourCycle: "h23",
  }).format(value) + " (heure de Tunis)";

/** No remote images, tracking pixels, fonts, scripts or arbitrary HTML. */
export function renderEmail(input: EmailTemplate): EmailContent {
  let subject: string, heading: string, paragraphs: string[], note: string;
  let code: string | undefined,
    link: string | undefined,
    action: string | undefined;
  if (input.kind === "invite") {
    subject = "Votre invitation BioBalance";
    heading = input.storeName
      ? "Rejoignez votre équipe"
      : "Bienvenue sur BioBalance";
    paragraphs = [
      input.storeName
        ? `Vous êtes invité(e) à rejoindre l’équipe du magasin ${input.storeName}.`
        : `Vous êtes invité(e) à gérer les magasins de ${input.organizationName ?? "votre organisation"} sur BioBalance.`,
      "Ouvrez l’application BioBalance, choisissez « Activer mon invitation », puis collez le code ci-dessous.",
      "Vous avez déjà un compte ? Utilisez votre mot de passe actuel pour accepter cette invitation.",
    ];
    code = input.token;
    link = accountLink("invite", input.token);
    action = "Activer mon invitation";
    note = `Invitation valable jusqu’au ${dateLabel(input.expiresAt)}. Ce code est personnel et utilisable une seule fois. Si vous ne connaissez pas l’expéditeur de cette invitation, vous pouvez ignorer ce message.`;
  } else if (input.kind === "reset") {
    subject = "Réinitialiser votre mot de passe BioBalance";
    heading = "Choisissez un nouveau mot de passe";
    paragraphs = [
      "Une demande de réinitialisation a été faite pour votre compte BioBalance.",
      "Dans l’application, ouvrez « Mot de passe oublié ? », puis « J’ai déjà reçu un code ». Collez le code ci-dessous et choisissez votre nouveau mot de passe.",
    ];
    code = input.token;
    link = accountLink("reset", input.token);
    action = "Réinitialiser mon mot de passe";
    note = `Code valable jusqu’au ${dateLabel(input.expiresAt)} et utilisable une seule fois. Si vous n’avez pas fait cette demande, ignorez ce message : votre mot de passe reste inchangé.`;
  } else if (input.kind === "password-changed") {
    subject = "Votre mot de passe BioBalance a été modifié";
    heading = "Votre mot de passe a été modifié";
    paragraphs = [
      `Le mot de passe de votre compte BioBalance a été modifié le ${dateLabel(input.changedAt)}.`,
      "Vos sessions précédentes ont été fermées. Connectez-vous avec votre nouveau mot de passe.",
    ];
    note =
      "Si vous n’êtes pas à l’origine de ce changement, utilisez immédiatement « Mot de passe oublié ? » dans l’application et contactez votre responsable ou l’administrateur BioBalance.";
  } else {
    subject = "BioBalance — test de livraison des emails";
    heading = "Votre email de test BioBalance";
    paragraphs = [
      "Ce message vérifie l’envoi des emails depuis le backend BioBalance et présente leur nouvelle mise en page.",
      "Les invitations et les messages de sécurité utilisent ce même modèle : un texte clair, les informations utiles et aucune publicité.",
      `Test envoyé le ${dateLabel(input.sentAt)}. Référence : ${input.reference}.`,
    ];
    note =
      "Aucune action n’est requise. Ce test ne crée aucun compte et ne modifie aucun mot de passe. Les alertes de stock, commandes et récompenses restent dans l’application.";
  }
  const text = [
    "BIOBALANCE",
    heading,
    ...paragraphs,
    ...(code ? [`Votre code : ${code}`] : []),
    ...(link ? [`${action} : ${link}`] : []),
    note,
    "BioBalance · Accès et sécurité de votre compte",
    "Ne partagez jamais votre mot de passe ni vos codes de sécurité.",
  ].join("\n\n");
  const html = `<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="light"><title>${escape(subject)}</title></head>
<body style="margin:0;padding:0;background:#ffffff;color:#1c1e22;font-family:Arial,Helvetica,sans-serif;-webkit-text-size-adjust:100%">
<div style="display:none;max-height:0;overflow:hidden;mso-hide:all">${escape(heading)}</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"><tr><td align="center" style="padding:24px 16px">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:560px;text-align:left">
<tr><td style="border-top:3px solid #6ABE4E;padding:24px 0 28px;color:#286b34;font-size:16px;font-weight:bold;letter-spacing:2px">BIOBALANCE</td></tr>
<tr><td><h1 style="margin:0 0 24px;font-size:24px;line-height:1.3;font-weight:600">${escape(heading)}</h1>
${paragraphs.map((p) => `<p style="margin:0 0 18px;font-size:16px;line-height:1.6">${escape(p)}</p>`).join("\n")}
${code ? `<p style="margin:24px 0 8px;font-size:14px;color:#606164">Votre code personnel</p><p style="margin:0 0 24px;padding:16px;background:#f3f8f0;border-left:3px solid #6ABE4E;word-break:break-all;overflow-wrap:anywhere;font-family:Consolas,monospace;font-size:16px;line-height:1.7">${escape(code)}</p>` : ""}
${link ? `<p style="margin:24px 0"><a href="${escape(link)}" style="display:inline-block;background:#286b34;color:#ffffff;padding:14px 20px;border-radius:6px;text-decoration:none;font-size:16px;font-weight:bold">${escape(action!)}</a></p><p style="font-size:14px;line-height:1.6;word-break:break-all">Si le bouton ne fonctionne pas, utilisez le code dans l’application ou ce lien : <a href="${escape(link)}" style="color:#286b34">${escape(link)}</a></p>` : ""}
<p style="margin:24px 0;font-size:14px;line-height:1.6;color:#606164">${escape(note)}</p>
</td></tr><tr><td style="padding:20px 0 8px;border-top:1px solid #e5e9e1;font-size:14px;line-height:1.7;color:#606164">BioBalance · Accès et sécurité de votre compte<br>Ne partagez jamais votre mot de passe ni vos codes de sécurité.</td></tr>
</table></td></tr></table></body></html>`;
  return { subject, text, html };
}
