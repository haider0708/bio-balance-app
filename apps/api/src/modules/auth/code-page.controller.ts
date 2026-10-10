import { createHash } from "node:crypto";
import { Controller, Get, Header, Res } from "@nestjs/common";
import type { Response } from "express";
import { Public } from "../../core/http";

/**
 * The page a code email links to. The code travels in the address after `#`,
 * which browsers never send to a server, so it is not logged anywhere. A real
 * "Copy" button lives here because an email cannot copy to the clipboard.
 */
const script = `
const raw=decodeURIComponent(location.hash.slice(1));
const kind=raw[0]==="r"?"r":"i";
const code=raw.slice(2).replace(/[^A-Za-z0-9]/g,"").toUpperCase();
const lang=(navigator.language||"en").startsWith("fr")?"fr":"en";
const words={
 en:{title:"Your code",copy:"Copy the code",copied:"Copied",open:"Open the BioBalance app",hint:"Copy the code, open the app and tap Paste.",none:"This link is not valid. Use the code from your email."},
 fr:{title:"Votre code",copy:"Copier le code",copied:"Copié",open:"Ouvrir l’application BioBalance",hint:"Copiez le code, ouvrez l’application et touchez Coller.",none:"Ce lien n’est pas valide. Utilisez le code de votre email."}
}[lang];
document.documentElement.lang=lang;
document.getElementById("title").textContent=words.title;
const box=document.getElementById("code");
if(code.length!==8){box.textContent=words.none;box.className="none";}
else{
 const shown=code.slice(0,4)+"-"+code.slice(4);
 box.textContent=shown;
 const copy=document.getElementById("copy");copy.hidden=false;copy.textContent=words.copy;
 copy.onclick=async()=>{try{await navigator.clipboard.writeText(shown);}catch(e){const r=document.createRange();r.selectNodeContents(box);const s=getSelection();s.removeAllRanges();s.addRange(r);document.execCommand("copy");}copy.textContent=words.copied;};
 const open=document.getElementById("open");open.hidden=false;open.textContent=words.open;
 const path="app/code?k="+kind+"&c="+code;
 const apple=/iPhone|iPad|iPod/.test(navigator.userAgent)||(navigator.platform==="MacIntel"&&navigator.maxTouchPoints>1);
 open.href=apple?"biobalance://"+path:"intent://"+path+"#Intent;scheme=biobalance;package=tn.biobalance.app;end";
 document.getElementById("hint").textContent=words.hint;
}`;

const hash = createHash("sha256").update(script).digest("base64");
const page = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex"><title>BioBalance</title>
<style>
body{margin:0;background:#fff;color:#1f2a24;font-family:Arial,Helvetica,sans-serif;display:flex;justify-content:center}
main{width:100%;max-width:420px;padding:40px 20px;text-align:center}
.brand{color:#146c43;font-weight:700;font-size:15px}
h1{font-size:22px;margin:24px 0 16px}
#code{font-family:Consolas,monospace;font-size:36px;letter-spacing:5px;font-weight:700;padding:18px 8px;border:1px solid #dfe6e1;border-radius:10px;user-select:all}
#code.none{font-size:16px;letter-spacing:0;font-weight:400;font-family:inherit;color:#b3261e}
a,button{display:block;width:100%;box-sizing:border-box;margin-top:14px;padding:16px;border-radius:10px;font-size:17px;font-weight:700;text-decoration:none;cursor:pointer}
button{background:#146c43;color:#fff;border:0}
a{background:#fff;color:#146c43;border:2px solid #146c43}
[hidden]{display:none}
p{color:#5d665f;font-size:14px;margin-top:18px}
</style></head>
<body><main><div class="brand">BioBalance</div><h1 id="title"></h1><div id="code"></div>
<button id="copy" hidden></button><a id="open" hidden></a><p id="hint"></p></main>
<script>${script}</script></body></html>`;

@Controller("c")
export class CodePageController {
  @Public()
  @Get()
  @Header("Content-Type", "text/html; charset=utf-8")
  show(@Res({ passthrough: true }) res: Response) {
    res.setHeader(
      "Content-Security-Policy",
      `default-src 'none'; style-src 'unsafe-inline'; script-src 'sha256-${hash}'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
    );
    return page;
  }
}
