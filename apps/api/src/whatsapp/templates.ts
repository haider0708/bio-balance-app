import type { Locale } from "../email/templates";
import type { Stores } from "../core/install";

/** The two store links and the guide: in every message, so the app is always one tap away. */
interface Links {
  stores: Stores;
  installPage: string | null;
}

/**
 * What each notice carries. `invite` has an activation code (responsable, order manager, admin);
 * `credentials` a generated password (seller, buyer): both start with the same install steps.
 */
export type WhatsAppTemplate =
  | ({
      kind: "invite";
      code: string;
      name: string;
      email: string;
      link?: string;
    } & Links)
  | ({
      kind: "reset";
      code: string;
      name: string;
      minutes: number;
      link?: string;
    } & Links)
  | ({ kind: "password-changed"; name: string; changedAt: Date } & Links)
  | ({ kind: "update"; name: string } & Links)
  | ({
      kind: "credentials";
      name: string;
      email: string;
      password: string;
      expiresAt: Date;
    } & Links);

const at = (locale: Locale, date: Date) =>
  new Intl.DateTimeFormat(locale === "fr" ? "fr-TN" : "en-GB", {
    timeZone: "Africa/Tunis",
    dateStyle: "medium",
    timeStyle: "short",
    hourCycle: "h23",
  }).format(date);

/** "ABCD2345" as "ABCD-2345", easier to read and to copy (the app accepts it with or without the dash). */
export const shown = (code: string) => `${code.slice(0, 4)}-${code.slice(4)}`;

/** One block of text: the parts that exist, a blank line between them. */
const blocks = (...parts: (string | false | null | undefined)[]) =>
  parts.filter(Boolean).join("\n\n");

/** The store of each phone, every link alone on its line so it can be tapped. */
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
    ? `${locale === "fr" ? "Guide illustré :" : "Illustrated guide:"}\n${page}`
    : "";

/** The one-tap link that shows the code with a copy button and opens the app. */
const shortcut = (locale: Locale, link?: string) =>
  link
    ? `${locale === "fr" ? "Raccourci (copie le code et ouvre l’application) :" : "Shortcut (copies the code and opens the app):"}\n${link}`
    : "";

/** Every message opens with the name of the app, then greets the person. */
const hello = (locale: Locale, name: string, line: string) =>
  `*BioBalance*\n${locale === "fr" ? "Bonjour" : "Hello"} ${name}, ${line}`;

/**
 * The WhatsApp messages of each notice, in the order they are sent. Short and in the same layout:
 * the app's name, one sentence, the steps, the store links. Anything the person has to copy (an
 * email, a password, a code) is a message of its own with nothing else in it, not even bold
 * marks: a long press on that message then copies exactly the value.
 */
export function renderWhatsApp(locale: Locale, t: WhatsAppTemplate): string[] {
  const fr = locale === "fr";
  const apps = stores(locale, t.stores);
  switch (t.kind) {
    case "invite":
      return [
        blocks(
          hello(
            locale,
            t.name,
            fr ? "votre compte est prêt." : "your account is ready.",
          ),
          `*${fr ? "1. Installez l’application" : "1. Install the app"}*\n${apps}`,
          fr
            ? "*2. Activez votre compte*\nOuvrez l’application, touchez « Activer mon compte », puis saisissez votre e-mail et le code ci-dessous (valable 72 h)."
            : "*2. Activate your account*\nOpen the app, tap “Activate my account”, then enter your email and the code below (valid for 72 hours).",
          shortcut(locale, t.link),
          guide(locale, t.installPage),
          fr ? "Ne partagez jamais ce code." : "Never share this code.",
        ),
        t.email,
        shown(t.code),
      ];
    case "credentials":
      return [
        blocks(
          hello(
            locale,
            t.name,
            fr ? "votre compte est prêt." : "your account is ready.",
          ),
          `*${fr ? "1. Installez l’application" : "1. Install the app"}*\n${apps}`,
          fr
            ? "*2. Connectez-vous*\nOuvrez l’application, puis saisissez l’e-mail et le mot de passe provisoire ci-dessous (appui long sur un message, puis Copier)."
            : "*2. Sign in*\nOpen the app, then enter the email and temporary password below (long-press a message, then Copy).",
          guide(locale, t.installPage),
        ),
        t.email,
        t.password,
        fr
          ? `*3. Choisissez votre mot de passe*\nÀ la première connexion, l’application vous demande d’en choisir un. Le mot de passe provisoire est valable jusqu’au ${at(locale, t.expiresAt)}. Ne partagez jamais ces messages.`
          : `*3. Choose your password*\nOn your first sign-in, the app asks you to choose one. The temporary password is valid until ${at(locale, t.expiresAt)}. Never share these messages.`,
      ];
    case "reset":
      return [
        blocks(
          hello(
            locale,
            t.name,
            fr
              ? `voici votre code pour réinitialiser votre mot de passe (valable ${t.minutes} min).`
              : `here is your code to reset your password (valid for ${t.minutes} min).`,
          ),
          fr
            ? "Dans l’application : « Mot de passe oublié ? », puis « J’ai déjà un code »."
            : "In the app: “Forgot password?”, then “I already have a code”.",
          shortcut(locale, t.link),
          fr
            ? "Ce n’était pas vous ? Ignorez ce message."
            : "Not you? Ignore this message.",
          apps,
        ),
        shown(t.code),
      ];
    case "password-changed":
      return [
        blocks(
          hello(
            locale,
            t.name,
            fr
              ? `votre mot de passe a été modifié le ${at(locale, t.changedAt)}.`
              : `your password was changed on ${at(locale, t.changedAt)}.`,
          ),
          fr
            ? "Ce n’était pas vous ? Prévenez votre responsable immédiatement."
            : "Not you? Tell your manager right away.",
          apps,
        ),
      ];
    case "update":
      return [
        blocks(
          hello(
            locale,
            t.name,
            fr
              ? "une nouvelle version de l’application est disponible (corrections et améliorations)."
              : "a new version of the app is available (fixes and improvements).",
          ),
          fr
            ? "Touchez votre lien pour mettre à jour :"
            : "Tap your link to update:",
          apps,
          fr
            ? "Vos identifiants ne changent pas."
            : "Your sign-in details do not change.",
        ),
      ];
  }
}
