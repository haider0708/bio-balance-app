import type { Locale } from "../email/templates";
import { updateBlocks, updateWords, type Stores } from "../core/install";

/**
 * What a new account is sent. The same layout for everyone: a responsable, an order manager, a seller,
 * a buyer. `invite` carries an activation code (responsable, order manager, admin); `credentials` carries a
 * generated password (seller, buyer).
 */
export type WhatsAppTemplate =
  | {
      kind: "invite";
      code: string;
      name: string;
      email: string;
      link?: string;
      stores: Stores;
      installPage: string | null;
    }
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

/** Step 1 of the welcome: the store of each phone, every link alone on its line so it can be tapped. */
const stores = (locale: Locale, s: Stores) =>
  [
    s.android && `Android${locale === "fr" ? " :" : ":"}\n${s.android}`,
    s.ios && `iPhone${locale === "fr" ? " :" : ":"}\n${s.ios}`,
  ]
    .filter(Boolean)
    .join("\n\n");

/** The page with the steps and screenshots of the app. */
const guide = (locale: Locale, page: string | null) =>
  page
    ? `${locale === "fr" ? "Guide avec captures d’écran :" : "Guide with screenshots:"}\n${page}`
    : "";

/** The one-tap link that shows the code with a copy button and opens the app. */
const tap = (locale: Locale, link?: string) =>
  link
    ? `${locale === "fr" ? "Plus simple, touchez ce lien : il copie le code et ouvre l’application :" : "Easier, tap this link: it copies the code and opens the app:"}\n${link}`
    : "";

const blocks = (...parts: (string | false | null | undefined)[]) =>
  parts.filter(Boolean).join("\n\n");

/** The "update your app" message: one short message, a link per phone. */
const updateText = (
  locale: Locale,
  t: Extract<WhatsAppTemplate, { kind: "update" }>,
) => {
  const w = updateWords[locale];
  return blocks(
    `${w.intro(t.name)} ${w.news}`,
    ...updateBlocks(locale, t.stores).map(
      (b) => `*${b.title}*\n${b.lines.join("\n")}`,
    ),
    w.same,
  );
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
        blocks(
          fr
            ? `Bonjour ${t.name}, votre compte BioBalance est prêt.`
            : `Hello ${t.name}, your BioBalance account is ready.`,
          fr
            ? `*1. Installez l’application*\n${stores(locale, t.stores)}`
            : `*1. Install the app*\n${stores(locale, t.stores)}`,
          fr
            ? "*2. Activez votre compte*\nOuvrez l’application, touchez « Activer mon compte », puis saisissez votre email et le code ci-dessous (valable 72 heures). Pour copier : touchez longuement le message, puis Copier."
            : "*2. Activate your account*\nOpen the app, tap “Activate my account”, then enter your email and the code below (valid for 72 hours). To copy: long-press the message, then Copy.",
          tap(locale, t.link),
          guide(locale, t.installPage),
          fr
            ? "Ne partagez ces messages avec personne."
            : "Do not share these messages with anyone.",
        ),
        t.email,
        shown(t.code),
      ];
    case "reset":
      return [
        blocks(
          fr
            ? `Bonjour ${t.name}, voici le code pour réinitialiser votre mot de passe BioBalance.`
            : `Hello ${t.name}, here is the code to reset your BioBalance password.`,
          fr
            ? `Dans l’application, touchez « Mot de passe oublié ? » puis « J’ai déjà un code », et saisissez votre email et le code ci-dessous. Valable ${t.minutes} minutes.`
            : `In the app, tap “Forgot password?” then “I already have a code”, and enter your email and the code below. Valid for ${t.minutes} minutes.`,
          tap(locale, t.link),
          fr
            ? "Ce n’était pas vous ? Ignorez ce message. Ne le partagez avec personne."
            : "Not you? Ignore this message. Do not share it with anyone.",
        ),
        shown(t.code),
      ];
    case "credentials":
      return [
        blocks(
          fr
            ? `Bonjour ${t.name}, votre compte BioBalance est prêt.`
            : `Hello ${t.name}, your BioBalance account is ready.`,
          fr
            ? `*1. Installez l’application*\n${stores(locale, t.stores)}`
            : `*1. Install the app*\n${stores(locale, t.stores)}`,
          fr
            ? "*2. Connectez-vous*\nOuvrez l’application, puis saisissez votre email et votre mot de passe provisoire ci-dessous. Pour copier : touchez longuement le message, puis Copier."
            : "*2. Sign in*\nOpen the app, then enter your email and temporary password below. To copy: long-press the message, then Copy.",
          guide(locale, t.installPage),
        ),
        t.email,
        t.password,
        fr
          ? `*3. Choisissez votre mot de passe*\nÀ la première connexion, l’application vous demande d’en choisir un nouveau. Le mot de passe provisoire est valable jusqu’au ${at(locale, t.expiresAt)}. Ne partagez ces messages avec personne.`
          : `*3. Choose your password*\nWhen you first sign in, the app asks you to choose a new one. The temporary password is valid until ${at(locale, t.expiresAt)}. Do not share these messages with anyone.`,
      ];
    case "password-changed":
      return [
        fr
          ? `Bonjour ${t.name}, votre mot de passe BioBalance a été modifié le ${at(locale, t.changedAt)}. Ce n’était pas vous ? Prévenez votre responsable tout de suite.`
          : `Hello ${t.name}, your BioBalance password was changed on ${at(locale, t.changedAt)}. Not you? Tell your manager right away.`,
      ];
  }
}
