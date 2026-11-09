import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import {
  Controller,
  Get,
  Header,
  Headers,
  NotFoundException,
  Param,
  Query,
  Res,
  StreamableFile,
} from "@nestjs/common";
import type { Response } from "express";
import { Public } from "../../core/http";
import { SettingsService } from "../../core/settings";

type Lang = "fr" | "en";

/** The pictures of the app's own screens (`GUIDE_SHOTS=1 flutter test test/guide_screenshots_test.dart`). */
const GUIDE_DIR = join(__dirname, "../../../guide");
const SHOTS = [
  "1-sign-in",
  "2-activate",
  "3-choose-password",
  "4-home",
] as const;

/** What the page says, in each language. */
const words = {
  fr: {
    title: "Installer BioBalance",
    intro: "Quatre étapes, deux minutes. Suivez les images.",
    s1: "1. Installez l’application",
    android: "Android",
    androidDo: "Touchez le bouton, puis Installer, puis Ouvrir.",
    play: "Ouvrir Google Play",
    iphone: "iPhone",
    iphoneDo: "Touchez le bouton, puis Obtenir, puis Ouvrir.",
    appStore: "Ouvrir l’App Store",
    s2: "2. Connectez-vous",
    s2do: "Vous avez reçu un email et un mot de passe provisoire : saisissez-les, puis touchez « Se connecter ».",
    s3: "3. Choisissez votre mot de passe",
    s3do: "Choisissez un mot de passe à vous (8 caractères au moins), écrivez-le deux fois, puis touchez « Enregistrer et continuer ».",
    code: "Vous avez reçu un code à la place ?",
    codeDo:
      "Sur l’écran de connexion, touchez « Activer mon compte ». Saisissez votre email et le code, choisissez un mot de passe, puis touchez « Activer mon compte ».",
    s4: "4. C’est prêt",
    s4do: "Votre accueil s’ouvre. La prochaine fois, connectez-vous avec votre email et votre mot de passe.",
    alt: [
      "Écran de connexion",
      "Écran d’activation du compte",
      "Écran pour choisir son mot de passe",
      "Écran d’accueil",
    ],
    other: "English",
  },
  en: {
    title: "Install BioBalance",
    intro: "Four steps, two minutes. Follow the pictures.",
    s1: "1. Install the app",
    android: "Android",
    androidDo: "Tap the button, then Install, then Open.",
    play: "Open Google Play",
    iphone: "iPhone",
    iphoneDo: "Tap the button, then Get, then Open.",
    appStore: "Open the App Store",
    s2: "2. Sign in",
    s2do: "You received an email and a temporary password: enter them, then tap “Sign in”.",
    s3: "3. Choose your password",
    s3do: "Choose a password of your own (at least 8 characters), type it twice, then tap “Save and continue”.",
    code: "Did you receive a code instead?",
    codeDo:
      "On the sign-in screen, tap “Activate my account”. Enter your email and the code, choose a password, then tap “Activate my account”.",
    s4: "4. You are ready",
    s4do: "Your home screen opens. Next time, sign in with your email and your password.",
    alt: [
      "Sign-in screen",
      "Account activation screen",
      "Screen to choose your password",
      "Home screen",
    ],
    other: "Français",
  },
} as const;

/** Puts the visitor's phone first: an iPhone sees the App Store before Google Play. */
const script = `
const apple=/iPhone|iPad|iPod/.test(navigator.userAgent)||(navigator.platform==="MacIntel"&&navigator.maxTouchPoints>1);
const first=document.getElementById(apple?"iphone":"android");
const list=document.getElementById("stores");
if(first&&list)list.insertBefore(first,list.firstChild);`;

const hash = createHash("sha256").update(script).digest("base64");
const esc = (v: string) =>
  v.replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ]!,
  );

/** The page in one language, with the pictures of the app's own screens. */
export function renderInstallPage(
  stores: { ios: string | null; android: string | null },
  lang: Lang = "fr",
): string {
  const w = words[lang];
  const other = lang === "fr" ? "en" : "fr";
  const picture = (i: number) =>
    `<img src="/install/img/${lang}/${SHOTS[i]}.jpg" alt="${esc(w.alt[i]!)}" width="260" loading="lazy">`;
  const android = stores.android
    ? `<div id="android" class="store"><h3>${esc(w.android)}</h3><p>${esc(w.androidDo)}</p><a class="go" href="${esc(stores.android)}">${esc(w.play)}</a></div>`
    : "";
  const iphone = stores.ios
    ? `<div id="iphone" class="store"><h3>${esc(w.iphone)}</h3><p>${esc(w.iphoneDo)}</p><a class="go" href="${esc(stores.ios)}">${esc(w.appStore)}</a></div>`
    : "";
  return `<!doctype html>
<html lang="${lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex"><title>BioBalance</title>
<style>
body{margin:0;background:#fff;color:#1f2a24;font-family:Arial,Helvetica,sans-serif;display:flex;justify-content:center}
main{width:100%;max-width:460px;padding:24px 20px 56px}
.top{display:flex;justify-content:space-between;align-items:center}
.brand{color:#146c43;font-weight:700;font-size:15px}
.lang{font-size:14px;color:#146c43;text-decoration:none;font-weight:700;margin:0;padding:0}
h1{font-size:26px;margin:20px 0 8px}
h2{font-size:19px;margin:0 0 8px}
h3{font-size:16px;margin:0 0 4px}
p{font-size:15px;line-height:1.6;margin:0 0 10px}
section{margin-top:28px;padding:18px 16px;border:1px solid #dfe6e1;border-radius:14px}
.store{margin-top:14px}
img{display:block;margin:14px auto 4px;border:1px solid #dfe6e1;border-radius:14px;max-width:100%;height:auto}
a.go{display:block;margin-top:8px;padding:14px;border-radius:10px;font-size:16px;font-weight:700;text-align:center;text-decoration:none;background:#146c43;color:#fff}
.alt{background:#f3f7f4;border-radius:10px;padding:12px;margin-top:16px}
.alt p{margin:0 0 4px}
</style></head>
<body><main><div class="top"><div class="brand">BioBalance</div><a class="lang" href="/install?lang=${other}">${esc(w.other)}</a></div>
<h1>${esc(w.title)}</h1><p>${esc(w.intro)}</p>
<section><h2>${esc(w.s1)}</h2><div id="stores">${android}${iphone}</div></section>
<section><h2>${esc(w.s2)}</h2><p>${esc(w.s2do)}</p>${picture(0)}
<div class="alt"><p><strong>${esc(w.code)}</strong></p><p>${esc(w.codeDo)}</p>${picture(1)}</div></section>
<section><h2>${esc(w.s3)}</h2><p>${esc(w.s3do)}</p>${picture(2)}</section>
<section><h2>${esc(w.s4)}</h2><p>${esc(w.s4do)}</p>${picture(3)}</section>
</main>
<script>${script}</script></body></html>`;
}

/** The visitor's language: the link's own (`?lang=en`), else the phone's, else French. */
const pick = (query: string | undefined, header: string | undefined): Lang =>
  query === "en" || query === "fr"
    ? query
    : /^\s*en/i.test(header ?? "")
      ? "en"
      : "fr";

@Controller("install")
export class InstallPageController {
  constructor(private readonly settings: SettingsService) {}

  @Public()
  @Get()
  @Header("Content-Type", "text/html; charset=utf-8")
  @Header("Cache-Control", "no-cache")
  @Header("Vary", "Accept-Language")
  async show(
    @Res({ passthrough: true }) res: Response,
    @Query("lang") lang?: string,
    @Headers("accept-language") accept?: string,
  ) {
    res.setHeader(
      "Content-Security-Policy",
      `default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; script-src 'sha256-${hash}'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
    );
    return renderInstallPage(
      (await this.settings.get()).stores,
      pick(lang, accept),
    );
  }

  /** One of the four pictures: only those names, in those two languages. */
  @Public()
  @Get("img/:lang/:file")
  @Header("Content-Type", "image/jpeg")
  @Header("Cache-Control", "public, max-age=86400")
  async picture(@Param("lang") lang: string, @Param("file") file: string) {
    const name = file.replace(/\.jpg$/, "");
    if (
      (lang !== "fr" && lang !== "en") ||
      !file.endsWith(".jpg") ||
      !(SHOTS as readonly string[]).includes(name)
    )
      throw new NotFoundException();
    try {
      return new StreamableFile(await readFile(join(GUIDE_DIR, lang, file)));
    } catch {
      throw new NotFoundException();
    }
  }
}
