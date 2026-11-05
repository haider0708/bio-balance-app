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

/** The words of the "update your app" message: for people who already have an account. */
export const updateWords = {
  fr: {
    subject: "Mettez à jour BioBalance",
    heading: "Une nouvelle version de BioBalance est disponible",
    intro: (name: string) =>
      `Bonjour ${name}, mettez l’application à jour pour continuer à l’utiliser.`,
    news: "Nouveautés : retrait de gains par paliers de 5 TND, recherche et filtres dans toutes les listes.",
    android: "Sur Android",
    androidDo: "Ouvrez Google Play et touchez Mettre à jour :",
    iphone: "Sur iPhone",
    iphoneDo:
      "Ouvrez l’application TestFlight et touchez Mettre à jour à côté de BioBalance. Si vous ne la trouvez pas, ouvrez ce lien et touchez Installer :",
    same: "Vos identifiants ne changent pas : gardez le même email et le même mot de passe.",
  },
  en: {
    subject: "Update BioBalance",
    heading: "A new version of BioBalance is available",
    intro: (name: string) =>
      `Hello ${name}, please update the app to keep using it.`,
    news: "What’s new: payouts in steps of 5 TND, search and filters on every list.",
    android: "On Android",
    androidDo: "Open Google Play and tap Update:",
    iphone: "On iPhone",
    iphoneDo:
      "Open the TestFlight app and tap Update next to BioBalance. If you cannot find it, open this link and tap Install:",
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
