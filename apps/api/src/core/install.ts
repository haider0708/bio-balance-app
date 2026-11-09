import type { Locale } from "../email/templates";

export interface Stores {
  ios: string | null;
  android: string | null;
}

/** The page with the install steps and screenshots of the app, in the person's language. */
export const installPageUrl = (locale: Locale = "fr") => {
  const base = process.env.API_PUBLIC_URL?.replace(/\/$/, "");
  return base ? `${base}/install?lang=${locale}` : null;
};

/** The words of the welcome message's three steps, in the person's language: by email, by WhatsApp. */
export const installWords = {
  fr: {
    install: "1. Installez l’application",
    android: "Sur Android",
    androidDo: "Ouvrez Google Play et touchez Installer :",
    iphone: "Sur iPhone",
    iphoneDo: "Ouvrez l’App Store et touchez Obtenir :",
    activate: "2. Activez votre compte",
    signIn: "2. Connectez-vous",
    signInDo: "Ouvrez BioBalance et saisissez ces informations :",
    choose: "3. Choisissez votre mot de passe",
    help: "Guide avec captures d’écran :",
  },
  en: {
    install: "1. Install the app",
    android: "On Android",
    androidDo: "Open Google Play and tap Install:",
    iphone: "On iPhone",
    iphoneDo: "Open the App Store and tap Get:",
    activate: "2. Activate your account",
    signIn: "2. Sign in",
    signInDo: "Open BioBalance and enter these details:",
    choose: "3. Choose your password",
    help: "Guide with screenshots:",
  },
} as const satisfies Record<Locale, object>;

/** One block per phone, each a title and lines (text, then the link on its own line): the same for every channel. */
export function installBlocks(
  locale: Locale,
  stores: Stores,
): { title: string; lines: string[] }[] {
  const w = installWords[locale];
  return [
    stores.android && {
      title: w.android,
      lines: [w.androidDo, stores.android],
    },
    stores.ios && {
      title: w.iphone,
      lines: [w.iphoneDo, stores.ios],
    },
  ].filter((b) => !!b);
}

/** The words of the "update your app" message: for people who already have an account. */
export const updateWords = {
  fr: {
    subject: "Mettez à jour BioBalance",
    heading: "Une nouvelle version de BioBalance est disponible",
    intro: (name: string) =>
      `Bonjour ${name}, mettez l’application à jour pour continuer à l’utiliser.`,
    news: "Corrections et améliorations.",
    android: "Sur Android",
    androidDo: "Ouvrez Google Play et touchez Mettre à jour :",
    iphone: "Sur iPhone",
    iphoneDo: "Ouvrez l’App Store et touchez Mettre à jour :",
    same: "Vos identifiants ne changent pas : gardez le même email et le même mot de passe.",
  },
  en: {
    subject: "Update BioBalance",
    heading: "A new version of BioBalance is available",
    intro: (name: string) =>
      `Hello ${name}, please update the app to keep using it.`,
    news: "Fixes and improvements.",
    android: "On Android",
    androidDo: "Open Google Play and tap Update:",
    iphone: "On iPhone",
    iphoneDo: "Open the App Store and tap Update:",
    same: "Your sign-in details do not change: use the same email and password.",
  },
} as const satisfies Record<Locale, object>;

export function updateBlocks(
  locale: Locale,
  stores: Stores,
): { title: string; lines: string[] }[] {
  const w = updateWords[locale];
  return [
    stores.android && {
      title: w.android,
      lines: [w.androidDo, stores.android],
    },
    stores.ios && { title: w.iphone, lines: [w.iphoneDo, stores.ios] },
  ].filter((b) => !!b);
}
