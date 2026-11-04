import { createHash } from "node:crypto";
import { Controller, Get, Header, Res } from "@nestjs/common";
import type { Response } from "express";
import { Public } from "../../core/http";
import { TESTFLIGHT_STORE } from "../../core/install";
import { SettingsService } from "../../core/settings";

/** What the page says, in each language (the visitor's phone language picks one). */
const words = {
  fr: {
    title: "Installer BioBalance",
    intro:
      "Installez l’application, puis connectez-vous avec l’email et le mot de passe provisoire reçus.",
    android: "Android",
    androidSteps: [
      "Touchez « Télécharger BioBalance ».",
      "Ouvrez le fichier téléchargé.",
      "Si le téléphone bloque l’installation, touchez Paramètres et autorisez l’installation depuis cette source, puis revenez et touchez Installer.",
      "Ouvrez BioBalance.",
    ],
    download: "Télécharger BioBalance",
    iphone: "iPhone",
    iphoneSteps: [
      "Installez l’application gratuite TestFlight depuis l’App Store.",
      "Revenez ici et touchez « Ouvrir dans TestFlight ».",
      "Touchez Installer, puis Ouvrir.",
    ],
    testflight: "Installer TestFlight",
    open: "Ouvrir dans TestFlight",
    next: "Ensuite : connectez-vous avec l’email et le mot de passe provisoire reçus. L’application vous demandera de choisir votre propre mot de passe.",
  },
  en: {
    title: "Install BioBalance",
    intro:
      "Install the app, then sign in with the email and temporary password you received.",
    android: "Android",
    androidSteps: [
      "Tap “Download BioBalance”.",
      "Open the downloaded file.",
      "If the phone blocks the installation, tap Settings and allow installing from this source, then go back and tap Install.",
      "Open BioBalance.",
    ],
    download: "Download BioBalance",
    iphone: "iPhone",
    iphoneSteps: [
      "Install the free TestFlight app from the App Store.",
      "Come back here and tap “Open in TestFlight”.",
      "Tap Install, then Open.",
    ],
    testflight: "Install TestFlight",
    open: "Open in TestFlight",
    next: "Then sign in with the email and temporary password you received. The app will ask you to choose your own password.",
  },
} as const;

/** Picks the visitor's language, puts their phone's section first, and shows the version that is on offer. */
const script = `
const fr=(navigator.language||"fr").toLowerCase().startsWith("en")?"en":"fr";
document.documentElement.lang=fr;
const apple=/iPhone|iPad|iPod/.test(navigator.userAgent)||(navigator.platform==="MacIntel"&&navigator.maxTouchPoints>1);
const first=document.getElementById(apple?"iphone":"android");
if(first)first.parentNode.insertBefore(first,document.getElementById("intro").nextSibling);
fetch("/download/latest.json").then(r=>r.ok?r.json():null).then(v=>{
 const el=document.getElementById("version");
 if(v&&el)el.textContent=" ("+v.version+", "+Math.round(v.bytes/1048576)+" MB)";
}).catch(()=>{});`;

const hash = createHash("sha256").update(script).digest("base64");
const esc = (v: string) =>
  v.replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ]!,
  );

/** The page with both languages in it; CSS shows the one the script picks (French without a script). */
export function renderInstallPage(stores: {
  ios: string | null;
  android: string | null;
}): string {
  const both = (f: (w: (typeof words)["fr"]) => string, tag = "span") =>
    (["fr", "en"] as const)
      .map(
        (l) =>
          `<${tag} lang="${l}">${f(words[l] as unknown as (typeof words)["fr"])}</${tag}>`,
      )
      .join("");
  const list = (key: "androidSteps" | "iphoneSteps") =>
    (["fr", "en"] as const)
      .map(
        (l) =>
          `<ol lang="${l}">${words[l][key].map((s) => `<li>${esc(s)}</li>`).join("")}</ol>`,
      )
      .join("");
  const android = stores.android
    ? `<section id="android"><h2>${both((w) => esc(w.android))}</h2>${list("androidSteps")}<a class="go" href="${esc(stores.android)}">${both((w) => esc(w.download))}<small id="version"></small></a></section>`
    : "";
  const iphone = stores.ios
    ? `<section id="iphone"><h2>${both((w) => esc(w.iphone))}</h2>${list("iphoneSteps")}<a class="alt" href="${TESTFLIGHT_STORE}">${both((w) => esc(w.testflight))}</a><a class="go" href="${esc(stores.ios)}">${both((w) => esc(w.open))}</a></section>`
    : "";
  return `<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex"><title>BioBalance</title>
<style>
body{margin:0;background:#fff;color:#1f2a24;font-family:Arial,Helvetica,sans-serif;display:flex;justify-content:center}
main{width:100%;max-width:460px;padding:32px 20px 48px}
.brand{color:#146c43;font-weight:700;font-size:15px}
h1{font-size:24px;margin:20px 0 8px}
h2{font-size:18px;margin:0 0 8px}
p,li{font-size:15px;line-height:1.6}
section{margin-top:24px;padding:16px;border:1px solid #dfe6e1;border-radius:12px}
ol{margin:0 0 14px;padding-left:20px}
a{display:block;margin-top:10px;padding:14px;border-radius:10px;font-size:16px;font-weight:700;text-align:center;text-decoration:none}
a small{display:block;font-weight:400;font-size:12px}
.go{background:#146c43;color:#fff}
.alt{background:#fff;color:#146c43;border:2px solid #146c43}
.next{color:#5d665f;margin-top:24px}
html[lang=fr] [lang=en],html[lang=en] [lang=fr]{display:none}
</style></head>
<body><main><div class="brand">BioBalance</div><h1>${both((w) => esc(w.title))}</h1><p id="intro">${both((w) => esc(w.intro))}</p>
${android}${iphone}
<p class="next">${both((w) => esc(w.next))}</p></main>
<script>${script}</script></body></html>`;
}

@Controller("install")
export class InstallPageController {
  constructor(private readonly settings: SettingsService) {}

  @Public()
  @Get()
  @Header("Content-Type", "text/html; charset=utf-8")
  @Header("Cache-Control", "no-cache")
  async show(@Res({ passthrough: true }) res: Response) {
    res.setHeader(
      "Content-Security-Policy",
      `default-src 'none'; style-src 'unsafe-inline'; script-src 'sha256-${hash}'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
    );
    return renderInstallPage((await this.settings.get()).stores);
  }
}
