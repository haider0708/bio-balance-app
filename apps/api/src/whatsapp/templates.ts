import type { Locale } from "../email/templates";
import {
  installBlocks,
  installWords,
  updateBlocks,
  updateWords,
  type Stores,
} from "../core/install";

export type WhatsAppTemplate =
  | { kind: "invite"; code: string; name: string; link?: string }
  | {
      kind: "reset";
      code: string;
      name: string;
      minutes: number;
      link?: string;
    }
  | { kind: "password-changed"; name: string; changedAt: Date }
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

const at = (locale: Locale, date: Date) =>
  new Intl.DateTimeFormat(locale === "fr" ? "fr-TN" : "en-GB", {
    timeZone: "Africa/Tunis",
    dateStyle: "medium",
    timeStyle: "short",
    hourCycle: "h23",
  }).format(date);

/** "ABCD2345" as "ABCD-2345", easier to read and to copy (the app accepts it with or without the dash). */
export const shown = (code: string) => `${code.slice(0, 4)}-${code.slice(4)}`;

/** The page that shows the code with a copy button and opens the app: one tap from the message. */
const tap = (locale: Locale, link?: string) =>
  link
    ? locale === "fr"
      ? `\n\nCopier le code en un toucher :\n${link}`
      : `\n\nCopy the code in one tap:\n${link}`
    : "";

/** Step 1 of the welcome message: one block per phone, then the help page. */
const installLines = (
  locale: Locale,
  stores: Stores,
  installPage: string | null,
) =>
  [
    `*${installWords[locale].install}*`,
    ...installBlocks(locale, stores).map(
      (b) => `_${b.title}_\n${b.lines.join("\n")}`,
    ),
    installPage && `${installWords[locale].help}\n${installPage}`,
  ]
    .filter(Boolean)
    .join("\n\n");

/** The "update your app" message: what is new, one block per phone, the help page. */
const updateText = (
  locale: Locale,
  t: Extract<WhatsAppTemplate, { kind: "update" }>,
) => {
  const w = updateWords[locale];
  return [
    `${w.intro(t.name)}\n${w.news}`,
    ...updateBlocks(locale, t.stores).map(
      (b) => `*${b.title}*\n${b.lines.join("\n")}`,
    ),
    w.same,
    t.installPage && `${installWords[locale].help}\n${t.installPage}`,
  ]
    .filter(Boolean)
    .join("\n\n");
};

/** The WhatsApp text of each message that is also sent by email: short, with the code on its own line. */
export function renderWhatsApp(locale: Locale, t: WhatsAppTemplate): string {
  if (t.kind === "update") return updateText(locale, t);
  if (locale === "fr") {
    switch (t.kind) {
      case "invite":
        return `Bonjour ${t.name}, votre compte BioBalance est prêt.\n\nCode d’activation :\n*${shown(t.code)}*${tap(locale, t.link)}\n\nDans l’application BioBalance, touchez « Activer mon compte », saisissez votre email et ce code, puis choisissez votre mot de passe. Le code est valable 72 heures.\n\nNe le partagez avec personne.`;
      case "reset":
        return `Bonjour ${t.name}, voici votre code pour réinitialiser votre mot de passe BioBalance :\n\n*${shown(t.code)}*${tap(locale, t.link)}\n\nDans l’application BioBalance, touchez « Mot de passe oublié ? », puis « J’ai déjà un code », saisissez votre email et ce code, puis choisissez un nouveau mot de passe.\n\nLe code est valable ${t.minutes} minutes. Si vous ne l’avez pas demandé, ignorez ce message.\n\nNe le partagez avec personne.`;
      case "credentials":
        return `Bonjour ${t.name}, bienvenue sur BioBalance : votre compte est prêt. Suivez ces 3 étapes.\n\n${installLines(locale, t.stores, t.installPage)}\n\n*${installWords.fr.signIn}*\n${installWords.fr.signInDo}\nEmail :\n${t.email}\nMot de passe provisoire :\n*${t.password}*\nValable jusqu’au ${at(locale, t.expiresAt)}.\n\n*${installWords.fr.choose}*\nÀ la première connexion, l’application vous demande de choisir votre propre mot de passe.\n\nNe partagez ce message avec personne.`;
      case "password-changed":
        return `Bonjour ${t.name}, votre mot de passe BioBalance a été modifié le ${at(locale, t.changedAt)}.\n\nSi ce n’est pas vous, prévenez votre responsable tout de suite.`;
    }
  }
  switch (t.kind) {
    case "invite":
      return `Hello ${t.name}, your BioBalance account is ready.\n\nActivation code:\n*${shown(t.code)}*${tap(locale, t.link)}\n\nIn the BioBalance app, tap “Activate my account”, enter your email and this code, then choose your password. The code is valid for 72 hours.\n\nDo not share it with anyone.`;
    case "reset":
      return `Hello ${t.name}, here is your code to reset your BioBalance password:\n\n*${shown(t.code)}*${tap(locale, t.link)}\n\nIn the BioBalance app, tap “Forgot password?”, then “I already have a code”, enter your email and this code, then choose a new password.\n\nThe code is valid for ${t.minutes} minutes. If you did not ask for it, ignore this message.\n\nDo not share it with anyone.`;
    case "credentials":
      return `Hello ${t.name}, welcome to BioBalance: your account is ready. Follow these 3 steps.\n\n${installLines(locale, t.stores, t.installPage)}\n\n*${installWords.en.signIn}*\n${installWords.en.signInDo}\nEmail:\n${t.email}\nTemporary password:\n*${t.password}*\nValid until ${at(locale, t.expiresAt)}.\n\n*${installWords.en.choose}*\nWhen you first sign in, the app asks you to choose your own password.\n\nDo not share this message with anyone.`;
    case "password-changed":
      return `Hello ${t.name}, your BioBalance password was changed on ${at(locale, t.changedAt)}.\n\nIf this was not you, tell your manager right away.`;
  }
}
