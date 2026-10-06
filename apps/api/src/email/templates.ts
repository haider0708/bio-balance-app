export interface EmailContent {
  subject: string;
  text: string;
  html: string;
}
export type Locale = "fr" | "en";

export type EmailTemplate =
  | { kind: "invite"; code: string; expiresAt: Date; name: string }
  | { kind: "reset"; code: string; expiresAt: Date; name: string }
  | { kind: "password-changed"; changedAt: Date; name: string };

const escape = (value: string) =>
  value.replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ]!,
  );

const when = (locale: Locale, date: Date) =>
  new Intl.DateTimeFormat(locale === "fr" ? "fr-TN" : "en-GB", {
    timeZone: "Africa/Tunis",
    dateStyle: "medium",
    timeStyle: "short",
    hourCycle: "h23",
  }).format(date);

const words = {
  fr: {
    invite: {
      subject: "Votre compte BioBalance est prêt",
      heading: "Activez votre compte",
      intro: (name: string) =>
        `Bonjour ${name}, votre compte BioBalance a été approuvé.`,
      steps:
        "Dans l’application BioBalance, choisissez « Activer mon compte », saisissez votre adresse email et ce code, puis choisissez votre mot de passe.",
      codeLabel: "Code d’activation",
      copyHint:
        "Maintenez le doigt sur le code pour le copier, puis touchez « Coller » dans l’application.",
      note: "Ce code est personnel et à usage unique. Si vous ne reconnaissez pas cette invitation, ignorez cet email.",
    },
    reset: {
      subject: "Réinitialiser votre mot de passe BioBalance",
      heading: "Réinitialiser votre mot de passe",
      intro: (name: string) =>
        `Bonjour ${name}, une réinitialisation du mot de passe a été demandée pour votre compte.`,
      steps:
        "Dans l’application, ouvrez « Mot de passe oublié ? », puis « J’ai déjà un code » et saisissez ce code.",
      codeLabel: "Code de récupération",
      copyHint:
        "Maintenez le doigt sur le code pour le copier, puis touchez « Coller » dans l’application.",
      note: "Si vous n’avez pas fait cette demande, ignorez cet email : votre mot de passe reste inchangé.",
    },
    changed: {
      subject: "Votre mot de passe BioBalance a été modifié",
      heading: "Mot de passe modifié",
      intro: (name: string) =>
        `Bonjour ${name}, votre mot de passe vient d’être modifié. Vos autres sessions ont été fermées.`,
      note: "Si vous n’êtes pas à l’origine de ce changement, réinitialisez votre mot de passe immédiatement et prévenez BioBalance.",
    },
    valid: (date: string) =>
      `Valable jusqu’au ${date} (heure de Tunis). Usage unique.`,
    at: (date: string) => `Le ${date} (heure de Tunis).`,
  },
  en: {
    invite: {
      subject: "Your BioBalance account is ready",
      heading: "Activate your account",
      intro: (name: string) =>
        `Hello ${name}, your BioBalance account has been approved.`,
      steps:
        "In the BioBalance app choose “Activate my account”, enter your email address and this code, then choose your password.",
      codeLabel: "Activation code",
      copyHint:
        "Touch and hold the code to copy it, then tap “Paste” in the app.",
      note: "This code is personal and single-use. If you do not recognise this invitation, ignore this email.",
    },
    reset: {
      subject: "Reset your BioBalance password",
      heading: "Reset your password",
      intro: (name: string) =>
        `Hello ${name}, a password reset was requested for your account.`,
      steps:
        "In the app open “Forgot password?”, then “I already have a code” and enter this code.",
      codeLabel: "Recovery code",
      copyHint:
        "Touch and hold the code to copy it, then tap “Paste” in the app.",
      note: "If you did not ask for this, ignore this email: your password stays unchanged.",
    },
    changed: {
      subject: "Your BioBalance password was changed",
      heading: "Password changed",
      intro: (name: string) =>
        `Hello ${name}, your password was just changed. Your other sessions were closed.`,
      note: "If this was not you, reset your password right away and tell BioBalance.",
    },
    valid: (date: string) => `Valid until ${date} (Tunis time). Single use.`,
    at: (date: string) => `On ${date} (Tunis time).`,
  },
} as const;

const shown = (code: string) => `${code.slice(0, 4)}-${code.slice(4)}`;

/** Plain, self-contained email: no remote images, tracking, fonts or scripts. */
export function renderEmail(
  locale: Locale,
  input: EmailTemplate,
): EmailContent {
  const t = words[locale];
  let subject: string, heading: string, intro: string, note: string;
  let steps: string | undefined,
    codeLabel: string | undefined,
    code: string | undefined,
    detail: string | undefined,
    copyHint: string | undefined;
  if (input.kind === "password-changed") {
    ({ subject, heading, note } = t.changed);
    intro = t.changed.intro(input.name);
    detail = t.at(when(locale, input.changedAt));
  } else {
    const copy = t[input.kind];
    ({ subject, heading, note, steps, codeLabel, copyHint } = copy);
    intro = copy.intro(input.name);
    code = shown(input.code);
    detail = t.valid(when(locale, input.expiresAt));
  }
  const text = [
    "BioBalance",
    heading,
    intro,
    ...(steps ? [steps] : []),
    ...(code
      ? [`${codeLabel} : ${code}`, ...(copyHint ? [copyHint] : [])]
      : []),
    ...(detail ? [detail] : []),
    note,
  ].join("\n\n");
  const html = `<!doctype html>
<html lang="${locale}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escape(subject)}</title></head>
<body style="margin:0;padding:0;background:#ffffff;color:#1f2a24;font-family:Arial,Helvetica,sans-serif">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"><tr><td align="center" style="padding:32px 20px">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:480px;text-align:left">
<tr><td style="padding:0 0 24px;color:#146c43;font-size:15px;font-weight:600">BioBalance</td></tr>
<tr><td><h1 style="margin:0 0 16px;font-size:22px;line-height:1.35">${escape(heading)}</h1>
<p style="margin:0 0 16px;font-size:16px;line-height:1.6">${escape(intro)}</p>
${steps ? `<p style="margin:0 0 20px;font-size:16px;line-height:1.6">${escape(steps)}</p>` : ""}
${code ? `<p style="margin:0 0 6px;font-size:14px;color:#5d665f">${escape(codeLabel!)}</p><p style="margin:0 0 8px;padding:14px;border:1px solid #dfe6e1;border-radius:6px;font-family:Consolas,monospace;font-size:30px;letter-spacing:5px;font-weight:700;-webkit-user-select:all;user-select:all">${escape(code)}</p>${copyHint ? `<p style="margin:0 0 8px;font-size:13px;color:#5d665f">${escape(copyHint)}</p>` : ""}` : ""}
${detail ? `<p style="margin:0 0 20px;font-size:14px;line-height:1.5;color:#5d665f">${escape(detail)}</p>` : ""}
<p style="margin:24px 0 0;font-size:14px;line-height:1.6;color:#5d665f">${escape(note)}</p>
</td></tr></table></td></tr></table></body></html>`;
  return { subject, text, html };
}
