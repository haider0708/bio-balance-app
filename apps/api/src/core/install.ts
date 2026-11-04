import type { Locale } from "../email/templates";

export interface Stores {
  ios: string | null;
  android: string | null;
}

/** TestFlight itself, in the App Store: an iPhone needs it before it can open the app's link. */
export const TESTFLIGHT_STORE =
  "https://apps.apple.com/app/testflight/id899247664";

/** Where the Android app is downloaded from: the latest signed APK that scripts/publish-apk.sh puts on the server. */
export const apkUrl = () => {
  const base = process.env.API_PUBLIC_URL?.replace(/\/$/, "");
  return base ? `${base}/download/biobalance.apk` : null;
};

/** The page that shows the install steps again (the same steps as the welcome message). */
export const installPageUrl = () => {
  const base = process.env.API_PUBLIC_URL?.replace(/\/$/, "");
  return base ? `${base}/install` : null;
};

/** The words of the welcome message's install part, in the person's language: by email, by WhatsApp. */
export const installWords = {
  fr: {
    android: "Si vous avez un téléphone Android",
    androidDo:
      "Téléchargez l’application ici, ouvrez le fichier, puis autorisez l’installation depuis cette source si le téléphone le demande :",
    iphone: "Si vous avez un iPhone",
    iphoneStore:
      "1. Installez l’application gratuite TestFlight depuis l’App Store :",
    iphoneApp: "2. Puis ouvrez ce lien et touchez Installer :",
    signIn: "Vos informations de connexion",
    help: "Besoin d’aide pour l’installation ?",
  },
  en: {
    android: "If you have an Android phone",
    androidDo:
      "Download the app here, open the file, then allow the installation from this source if the phone asks:",
    iphone: "If you have an iPhone",
    iphoneStore: "1. Install the free TestFlight app from the App Store:",
    iphoneApp: "2. Then open this link and tap Install:",
    signIn: "Your sign-in details",
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
