import type { Locale } from "../email/templates";

export interface Stores {
  ios: string | null;
  android: string | null;
}

/** TestFlight itself, in the App Store: an iPhone needs it before it can open the app's link. */
export const TESTFLIGHT_STORE =
  "https://apps.apple.com/app/testflight/id899247664";

/** The page that shows the install steps again (the same steps as the welcome message). */
export const installPageUrl = () => {
  const base = process.env.API_PUBLIC_URL?.replace(/\/$/, "");
  return base ? `${base}/install` : null;
};

/** The words of the welcome message's three steps, in the person's language: by email, by WhatsApp. */
export const installWords = {
  fr: {
    install: "1. Installez l’application",
    android: "Sur Android",
    androidDo: "Ouvrez Google Play et touchez Installer :",
    iphone: "Sur iPhone",
    iphoneStore:
      "a) Installez d’abord l’application gratuite TestFlight, depuis l’App Store :",
    iphoneApp: "b) Puis ouvrez ce lien et touchez Installer :",
    signIn: "2. Connectez-vous",
    signInDo: "Ouvrez BioBalance et saisissez ces informations :",
    choose: "3. Choisissez votre mot de passe",
    help: "Besoin d’aide pour l’installation ?",
  },
  en: {
    install: "1. Install the app",
    android: "On Android",
    androidDo: "Open Google Play and tap Install:",
    iphone: "On iPhone",
    iphoneStore: "a) First install the free TestFlight app from the App Store:",
    iphoneApp: "b) Then open this link and tap Install:",
    signIn: "2. Sign in",
    signInDo: "Open BioBalance and enter these details:",
    choose: "3. Choose your password",
    help: "Need help installing?",
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
      lines: [w.iphoneStore, TESTFLIGHT_STORE, w.iphoneApp, stores.ios],
    },
  ].filter((b) => !!b);
}
