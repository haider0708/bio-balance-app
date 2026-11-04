import type { Locale } from "../email/templates";

export interface Stores {
  ios: string | null;
  android: string | null;
}

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

/** The install steps of the welcome message, in the person's language: the same words by email, by WhatsApp and on the page. */
export const installWords = {
  fr: {
    install: "1. Installez l’application",
    android: "Android",
    androidSteps:
      "Touchez le lien pour télécharger BioBalance, ouvrez le fichier, puis autorisez l’installation depuis cette source si le téléphone le demande.",
    iphone: "iPhone",
    iphoneSteps:
      "Installez d’abord l’application gratuite TestFlight (App Store), puis ouvrez le lien ci-dessous et touchez Installer.",
    signIn: "2. Connectez-vous",
    help: "Besoin d’aide pour l’installation ?",
  },
  en: {
    install: "1. Install the app",
    android: "Android",
    androidSteps:
      "Tap the link to download BioBalance, open the file, then allow the installation from this source if the phone asks.",
    iphone: "iPhone",
    iphoneSteps:
      "First install the free TestFlight app (App Store), then open the link below and tap Install.",
    signIn: "2. Sign in",
    help: "Need help installing?",
  },
} as const satisfies Record<Locale, object>;
