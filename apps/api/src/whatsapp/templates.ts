import type { Locale } from "../email/templates";

export type WhatsAppTemplate =
  | { kind: "invite"; code: string; name: string }
  | { kind: "reset"; code: string; name: string; minutes: number }
  | { kind: "password-changed"; name: string; changedAt: Date };

const at = (locale: Locale, date: Date) =>
  new Intl.DateTimeFormat(locale === "fr" ? "fr-TN" : "en-GB", {
    timeZone: "Africa/Tunis",
    dateStyle: "medium",
    timeStyle: "short",
    hourCycle: "h23",
  }).format(date);

/** The WhatsApp text of each message that is also sent by email: short, with the code on its own line. */
export function renderWhatsApp(locale: Locale, t: WhatsAppTemplate): string {
  if (locale === "fr") {
    switch (t.kind) {
      case "invite":
        return `Bonjour ${t.name}, votre compte BioBalance est prêt.\n\nCode d’activation :\n*${t.code}*\n\nDans l’application BioBalance, touchez « Activer mon compte », saisissez votre email et ce code, puis choisissez votre mot de passe. Le code est valable 72 heures.\n\nNe le partagez avec personne.`;
      case "reset":
        return `Bonjour ${t.name}, voici votre code pour réinitialiser votre mot de passe BioBalance :\n\n*${t.code}*\n\nIl est valable ${t.minutes} minutes. Si vous ne l’avez pas demandé, ignorez ce message.\n\nNe le partagez avec personne.`;
      case "password-changed":
        return `Bonjour ${t.name}, votre mot de passe BioBalance a été modifié le ${at(locale, t.changedAt)}.\n\nSi ce n’est pas vous, prévenez votre responsable tout de suite.`;
    }
  }
  switch (t.kind) {
    case "invite":
      return `Hello ${t.name}, your BioBalance account is ready.\n\nActivation code:\n*${t.code}*\n\nIn the BioBalance app, tap “Activate my account”, enter your email and this code, then choose your password. The code is valid for 72 hours.\n\nDo not share it with anyone.`;
    case "reset":
      return `Hello ${t.name}, here is your code to reset your BioBalance password:\n\n*${t.code}*\n\nIt is valid for ${t.minutes} minutes. If you did not ask for it, ignore this message.\n\nDo not share it with anyone.`;
    case "password-changed":
      return `Hello ${t.name}, your BioBalance password was changed on ${at(locale, t.changedAt)}.\n\nIf this was not you, tell your manager right away.`;
  }
}
