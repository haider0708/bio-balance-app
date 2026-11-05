import {
  installBlocks,
  installWords,
  updateBlocks,
  updateWords,
  type Stores,
} from "../core/install";

export interface EmailContent {
  subject: string;
  text: string;
  html: string;
}
export type Locale = "fr" | "en";

export type EmailTemplate =
  | {
      kind: "invite";
      code: string;
      expiresAt: Date;
      name: string;
      link?: string;
    }
  | {
      kind: "reset";
      code: string;
      expiresAt: Date;
      name: string;
      link?: string;
    }
  | { kind: "password-changed"; changedAt: Date; name: string }
  | {
      kind: "update";
      name: string;
      stores: Stores;
      installPage: string | null;
    }
  | {
      kind: "credentials";
      name: string;
      email: string;
      password: string;
      expiresAt: Date;
      stores: Stores;
      installPage: string | null;
    };

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
      copyLink: "Copier le code en un toucher",
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
      copyLink: "Copier le code en un toucher",
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
      copyLink: "Copy the code with one tap",
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
      copyLink: "Copy the code with one tap",
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

/** What the account message says, in each language. The password is the only secret in it. */
const credentials = {
  fr: {
    subject: "Votre compte BioBalance est prêt",
    heading: "Votre compte BioBalance est prêt",
    intro: (name: string) =>
      `Bonjour ${name}, bienvenue sur BioBalance : votre compte est prêt. Suivez ces 3 étapes.`,
    emailLabel: "Adresse email",
    passwordLabel: "Mot de passe provisoire",
    first:
      "À la première connexion, l’application vous demande de choisir votre propre mot de passe.",
    valid: (date: string) =>
      `Ce mot de passe provisoire fonctionne jusqu’au ${date} (heure de Tunis).`,
    note: "Ne le partagez avec personne. Si vous ne vous attendiez pas à ce message, ignorez-le et prévenez votre responsable.",
  },
  en: {
    subject: "Your BioBalance account is ready",
    heading: "Your BioBalance account is ready",
    intro: (name: string) =>
      `Hello ${name}, welcome to BioBalance: your account is ready. Follow these 3 steps.`,
    emailLabel: "Email address",
    passwordLabel: "Temporary password",
    first:
      "When you first sign in, the app asks you to choose your own password.",
    valid: (date: string) =>
      `This temporary password works until ${date} (Tunis time).`,
    note: "Do not share it with anyone. If you were not expecting this message, ignore it and tell your manager.",
  },
} as const;

const shown = (code: string) => `${code.slice(0, 4)}-${code.slice(4)}`;

/** Plain, self-contained email: no remote images, tracking, fonts or scripts. */
export function renderEmail(
  locale: Locale,
  input: EmailTemplate,
): EmailContent {
  if (input.kind === "credentials") return renderCredentials(locale, input);
  if (input.kind === "update") return renderUpdate(locale, input);
  const t = words[locale];
  let subject: string, heading: string, intro: string, note: string;
  let steps: string | undefined,
    codeLabel: string | undefined,
    code: string | undefined,
    detail: string | undefined,
    copyHint: string | undefined,
    copyLink: string | undefined,
    link: string | undefined;
  if (input.kind === "password-changed") {
    ({ subject, heading, note } = t.changed);
    intro = t.changed.intro(input.name);
    detail = t.at(when(locale, input.changedAt));
  } else {
    const copy = t[input.kind];
    ({ subject, heading, note, steps, codeLabel, copyHint, copyLink } = copy);
    link = input.link;
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
      ? [
          `${codeLabel} : ${code}`,
          ...(link ? [`${copyLink} : ${link}`] : []),
          ...(copyHint ? [copyHint] : []),
        ]
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
${code ? `<p style="margin:0 0 6px;font-size:14px;color:#5d665f">${escape(codeLabel!)}</p><p style="margin:0 0 8px;padding:14px;border:1px solid #dfe6e1;border-radius:6px;font-family:Consolas,monospace;font-size:30px;letter-spacing:5px;font-weight:700;-webkit-user-select:all;user-select:all">${escape(code)}</p>${link ? `<p style="margin:0 0 12px"><a href="${escape(link)}" style="display:inline-block;padding:12px 18px;background:#146c43;color:#ffffff;text-decoration:none;border-radius:6px;font-size:15px;font-weight:700">${escape(copyLink!)}</a></p>` : ""}${copyHint ? `<p style="margin:0 0 8px;font-size:13px;color:#5d665f">${escape(copyHint)}</p>` : ""}` : ""}
${detail ? `<p style="margin:0 0 20px;font-size:14px;line-height:1.5;color:#5d665f">${escape(detail)}</p>` : ""}
<p style="margin:24px 0 0;font-size:14px;line-height:1.6;color:#5d665f">${escape(note)}</p>
</td></tr></table></td></tr></table></body></html>`;
  return { subject, text, html };
}

function renderCredentials(
  locale: Locale,
  input: Extract<EmailTemplate, { kind: "credentials" }>,
): EmailContent {
  const c = credentials[locale];
  const w = installWords[locale];
  const blocks = installBlocks(locale, input.stores);
  const valid = c.valid(when(locale, input.expiresAt));
  const text = [
    "BioBalance",
    c.heading,
    c.intro(input.name),
    w.install,
    ...blocks.map((b) => `${b.title}\n${b.lines.join("\n")}`),
    ...(input.installPage ? [`${w.help}\n${input.installPage}`] : []),
    `${w.signIn}\n${w.signInDo}`,
    `${c.emailLabel} : ${input.email}`,
    `${c.passwordLabel} : ${input.password}`,
    valid,
    `${w.choose}\n${c.first}`,
    c.note,
  ].join("\n\n");
  const box = (label: string, value: string, mono: boolean) =>
    `<p style="margin:0 0 6px;font-size:14px;color:#5d665f">${escape(label)}</p><p style="margin:0 0 16px;padding:14px;border:1px solid #dfe6e1;border-radius:6px;${mono ? "font-family:Consolas,monospace;font-size:24px;letter-spacing:2px;font-weight:700;" : "font-size:16px;"}-webkit-user-select:all;user-select:all;word-break:break-all">${escape(value)}</p>`;
  const html = `<!doctype html>
<html lang="${locale}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escape(c.subject)}</title></head>
<body style="margin:0;padding:0;background:#ffffff;color:#1f2a24;font-family:Arial,Helvetica,sans-serif">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"><tr><td align="center" style="padding:32px 20px">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:480px;text-align:left">
<tr><td style="padding:0 0 24px;color:#146c43;font-size:15px;font-weight:600">BioBalance</td></tr>
<tr><td><h1 style="margin:0 0 16px;font-size:22px;line-height:1.35">${escape(c.heading)}</h1>
<p style="margin:0 0 16px;font-size:16px;line-height:1.6">${escape(c.intro(input.name))}</p>
<h2 style="margin:24px 0 4px;font-size:19px">${escape(w.install)}</h2>
${blocks.map((b) => `<h3 style="margin:18px 0 8px;font-size:16px">${escape(b.title)}</h3>${b.lines.map((line) => (/^https:/.test(line) ? `<p style="margin:0 0 16px"><a href="${escape(line)}" style="display:inline-block;padding:12px 18px;background:#146c43;color:#ffffff;text-decoration:none;border-radius:6px;font-size:15px;font-weight:700;word-break:break-all">${escape(line)}</a></p>` : `<p style="margin:0 0 8px;font-size:15px;line-height:1.6">${escape(line)}</p>`)).join("")}`).join("")}
${input.installPage ? `<p style="margin:0 0 8px;font-size:14px;line-height:1.5"><a href="${escape(input.installPage)}" style="color:#146c43">${escape(w.help)}</a></p>` : ""}
<h2 style="margin:28px 0 4px;font-size:19px">${escape(w.signIn)}</h2>
<p style="margin:0 0 12px;font-size:15px;line-height:1.6">${escape(w.signInDo)}</p>
${box(c.emailLabel, input.email, false)}${box(c.passwordLabel, input.password, true)}
<p style="margin:0 0 20px;font-size:14px;line-height:1.5;color:#5d665f">${escape(valid)}</p>
<h2 style="margin:28px 0 4px;font-size:19px">${escape(w.choose)}</h2>
<p style="margin:0 0 20px;font-size:15px;line-height:1.6">${escape(c.first)}</p>
<p style="margin:24px 0 0;font-size:14px;line-height:1.6;color:#5d665f">${escape(c.note)}</p>
</td></tr></table></td></tr></table></body></html>`;
  return { subject: c.subject, text, html };
}

function renderUpdate(
  locale: Locale,
  input: Extract<EmailTemplate, { kind: "update" }>,
): EmailContent {
  const w = updateWords[locale];
  const blocks = updateBlocks(locale, input.stores);
  const help = installWords[locale].help;
  const text = [
    "BioBalance",
    w.heading,
    w.intro(input.name),
    w.news,
    ...blocks.map((b) => `${b.title}\n${b.lines.join("\n")}`),
    w.same,
    ...(input.installPage ? [`${help}\n${input.installPage}`] : []),
  ].join("\n\n");
  const html = `<!doctype html>
<html lang="${locale}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escape(w.subject)}</title></head>
<body style="margin:0;padding:0;background:#ffffff;color:#1f2a24;font-family:Arial,Helvetica,sans-serif">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"><tr><td align="center" style="padding:32px 20px">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:480px;text-align:left">
<tr><td style="padding:0 0 24px;color:#146c43;font-size:15px;font-weight:600">BioBalance</td></tr>
<tr><td><h1 style="margin:0 0 16px;font-size:22px;line-height:1.35">${escape(w.heading)}</h1>
<p style="margin:0 0 16px;font-size:16px;line-height:1.6">${escape(w.intro(input.name))}</p>
<p style="margin:0 0 8px;font-size:15px;line-height:1.6">${escape(w.news)}</p>
${blocks.map((b) => `<h3 style="margin:18px 0 8px;font-size:16px">${escape(b.title)}</h3>${b.lines.map((line) => (/^https:/.test(line) ? `<p style="margin:0 0 16px"><a href="${escape(line)}" style="display:inline-block;padding:12px 18px;background:#146c43;color:#ffffff;text-decoration:none;border-radius:6px;font-size:15px;font-weight:700;word-break:break-all">${escape(line)}</a></p>` : `<p style="margin:0 0 8px;font-size:15px;line-height:1.6">${escape(line)}</p>`)).join("")}`).join("")}
<p style="margin:20px 0 8px;font-size:15px;line-height:1.6">${escape(w.same)}</p>
${input.installPage ? `<p style="margin:0 0 8px;font-size:14px;line-height:1.5"><a href="${escape(input.installPage)}" style="color:#146c43">${escape(help)}</a></p>` : ""}
</td></tr></table></td></tr></table></body></html>`;
  return { subject: w.subject, text, html };
}
