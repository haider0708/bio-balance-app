import type { Locale } from "../email/templates";
import {
  installWords,
  TESTFLIGHT_STORE,
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
      ? `\n\nCopier le code et ouvrir l’application :\n${link}`
      : `\n\nCopy the code and open the app:\n${link}`
    : "";

/** Step 1 of the welcome message, short: a block per phone, every link alone on its line so it can be tapped. */
const installLines = (locale: Locale, stores: Stores) => {
  const fr = locale === "fr";
  return [
    stores.android && `Android${fr ? " :" : ":"}\n${stores.android}`,
    stores.ios &&
      (fr
        ? `iPhone, en 2 temps :\na) TestFlight, à installer d’abord :\n${TESTFLIGHT_STORE}\nb) BioBalance, touchez Installer :\n${stores.ios}`
        : `iPhone, in 2 steps:\na) TestFlight, install it first:\n${TESTFLIGHT_STORE}\nb) BioBalance, tap Install:\n${stores.ios}`),
  ]
    .filter(Boolean)
    .join("\n\n");
};

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

/**
 * The WhatsApp messages of each notice, in the order they are sent. Short, and anything the person has
 * to copy (a code, an email, a password) is a message of its own with nothing else in it, not even bold
 * marks: a long press on that message then copies exactly the value.
 */
export function renderWhatsApp(locale: Locale, t: WhatsAppTemplate): string[] {
  const fr = locale === "fr";
  switch (t.kind) {
    case "update":
      return [updateText(locale, t)];
    case "invite":
      return [
        fr
          ? `Bonjour ${t.name}, votre compte BioBalance est prêt.\n\nDans l’application, touchez « Activer mon compte », puis saisissez votre email et le code ci-dessous. Valable 72 heures. Ne le partagez avec personne.${tap(locale, t.link)}\n\nVotre code (touchez longuement, puis Copier) :`
          : `Hello ${t.name}, your BioBalance account is ready.\n\nIn the app, tap “Activate my account”, then enter your email and the code below. Valid for 72 hours. Do not share it with anyone.${tap(locale, t.link)}\n\nYour code (long-press, then Copy):`,
        shown(t.code),
      ];
    case "reset":
      return [
        fr
          ? `Bonjour ${t.name}, voici le code pour réinitialiser votre mot de passe BioBalance.\n\nDans l’application, touchez « Mot de passe oublié ? » puis « J’ai déjà un code », et saisissez votre email et le code ci-dessous. Valable ${t.minutes} minutes. Si vous ne l’avez pas demandé, ignorez ce message. Ne le partagez avec personne.${tap(locale, t.link)}\n\nVotre code (touchez longuement, puis Copier) :`
          : `Hello ${t.name}, here is the code to reset your BioBalance password.\n\nIn the app, tap “Forgot password?” then “I already have a code”, and enter your email and the code below. Valid for ${t.minutes} minutes. If you did not ask for it, ignore this message. Do not share it with anyone.${tap(locale, t.link)}\n\nYour code (long-press, then Copy):`,
        shown(t.code),
      ];
    case "credentials":
      return [
        fr
          ? `Bonjour ${t.name}, votre compte BioBalance est prêt.\n\n*1. Installez l’application*\n${installLines(locale, t.stores)}\n\n*2. Connectez-vous*\nVotre email, puis votre mot de passe provisoire, arrivent chacun dans un message à part. Touchez longuement un message, puis Copier.`
          : `Hello ${t.name}, your BioBalance account is ready.\n\n*1. Install the app*\n${installLines(locale, t.stores)}\n\n*2. Sign in*\nYour email, then your temporary password, each arrive in a message of their own. Long-press a message, then Copy.`,
        t.email,
        t.password,
        fr
          ? `*3. Choisissez votre mot de passe*\nÀ la première connexion, l’application vous demande d’en choisir un nouveau. Le mot de passe provisoire est valable jusqu’au ${at(locale, t.expiresAt)}. Ne partagez ces messages avec personne.${t.installPage ? `\n\nBesoin d’aide ? ${t.installPage}` : ""}`
          : `*3. Choose your password*\nWhen you first sign in, the app asks you to choose a new one. The temporary password is valid until ${at(locale, t.expiresAt)}. Do not share these messages with anyone.${t.installPage ? `\n\nNeed help? ${t.installPage}` : ""}`,
      ];
    case "password-changed":
      return [
        fr
          ? `Bonjour ${t.name}, votre mot de passe BioBalance a été modifié le ${at(locale, t.changedAt)}. Si ce n’est pas vous, prévenez votre responsable tout de suite.`
          : `Hello ${t.name}, your BioBalance password was changed on ${at(locale, t.changedAt)}. If this was not you, tell your manager right away.`,
      ];
  }
}
