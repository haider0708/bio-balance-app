import { createHash } from "node:crypto";
import { Body, Controller, Get, Header, Post, Req, Res } from "@nestjs/common";
import type { Response } from "express";
import { z } from "zod";
import { Database } from "../../core/database";
import { type AuthRequest, Public, parse } from "../../core/http";
import { AuthService } from "./auth.service";
import { tokenHash } from "./codes";
import { claimSetupLink } from "./setup-link";

/**
 * The page behind a new administrator's link (`/s#token`). The token travels after `#`, so no
 * server or log ever sees it in a URL; the page claims it with one POST, which shows the QR code
 * once and erases it.
 */
const script = `
const token=decodeURIComponent(location.hash.slice(1));
history.replaceState(null,"",location.pathname);
const lang=(navigator.language||"en").startsWith("fr")?"fr":"en";
const words={
 en:{title:"Set up your authenticator",hint:"Open an authenticator app (Google Authenticator, Microsoft Authenticator, Authy…), choose “Scan a QR code” and scan this. This page works only once: do not close it before your app shows a 6-digit code.",key:"Or type this key in the app:",used:"This link was already used or has expired. Ask the person who invited you for a new one."},
 fr:{title:"Configurez votre application d’authentification",hint:"Ouvrez une application d’authentification (Google Authenticator, Microsoft Authenticator, Authy…), choisissez « Scanner un code QR » et scannez ce code. Cette page ne fonctionne qu’une fois : ne la fermez pas avant que votre application affiche un code à 6 chiffres.",key:"Ou saisissez cette clé dans l’application :",used:"Ce lien a déjà été utilisé ou a expiré. Demandez-en un nouveau à la personne qui vous a invité."}
}[lang];
document.documentElement.lang=lang;
document.getElementById("title").textContent=words.title;
const box=document.getElementById("box");
fetch("/v1/setup-link/claim",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({token})})
 .then(r=>r.ok?r.json():Promise.reject())
 .then(j=>{
   box.innerHTML=j.svg;
   document.getElementById("hint").textContent=words.hint;
   document.getElementById("keylabel").textContent=words.key;
   document.getElementById("key").textContent=j.key.replace(/(.{4})/g,"$1 ").trim();
 })
 .catch(()=>{box.textContent=words.used;box.className="none";});`;

const scriptHash = createHash("sha256").update(script).digest("base64");
const page = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>BioBalance</title>
<style>
body{margin:0;background:#fff;color:#1f2a24;font-family:Arial,Helvetica,sans-serif;display:flex;justify-content:center}
main{width:100%;max-width:440px;padding:40px 20px;text-align:center}
.brand{color:#146c43;font-weight:700;font-size:15px}
h1{font-size:21px;margin:24px 0 16px}
#box svg{width:100%;max-width:300px;height:auto;border:1px solid #dfe6e1;border-radius:10px}
#box.none{color:#b3261e;font-size:16px;padding:12px}
p{color:#5d665f;font-size:14px;margin-top:18px;line-height:1.5}
#key{font-family:Consolas,monospace;font-size:18px;font-weight:700;letter-spacing:1px;color:#1f2a24;word-break:break-all;user-select:all}
</style></head>
<body><main><div class="brand">BioBalance</div><h1 id="title"></h1><div id="box"></div>
<p id="hint"></p><p id="keylabel"></p><div id="key"></div></main>
<script>${script}</script></body></html>`;

@Controller()
export class SetupLinkController {
  constructor(
    private readonly db: Database,
    private readonly auth: AuthService,
  ) {}

  @Public()
  @Get("s")
  @Header("Content-Type", "text/html; charset=utf-8")
  show(@Res({ passthrough: true }) res: Response) {
    res.setHeader(
      "Content-Security-Policy",
      `default-src 'none'; style-src 'unsafe-inline'; script-src 'sha256-${scriptHash}'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
    );
    res.setHeader("Referrer-Policy", "no-referrer");
    return page;
  }

  @Public()
  @Post("v1/setup-link/claim")
  async claim(@Body() raw: unknown, @Req() req: AuthRequest) {
    await this.auth.throttle(`setup:${tokenHash(req.ip ?? "unknown")}`, 20);
    return claimSetupLink(
      this.db,
      parse(z.object({ token: z.string().max(100) }), raw).token,
    );
  }
}
