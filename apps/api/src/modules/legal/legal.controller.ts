import { Controller, Get, Header, Headers, Query, Res } from "@nestjs/common";
import type { Response } from "express";
import { Public } from "../../core/http";

/**
 * The public pages the app stores ask for: the privacy policy, the terms of use, help and how
 * to delete an account. Plain HTML, French or English (from `?lang=` or the browser), no script.
 */
type Lang = "fr" | "en";

const UPDATED = "2026-10-10";

/** The mailbox people write to; the sender of the app's emails unless told otherwise. */
function contact() {
  const configured = process.env.SUPPORT_EMAIL?.trim();
  if (configured) return configured;
  const sender = /<([^>]+)>/.exec(process.env.SMTP_FROM ?? "")?.[1];
  return sender ?? "biobalance@galylio.com";
}

const escape = (s: string) =>
  s.replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ]!,
  );

/**
 * The contact address as a link. Cloudflare would otherwise rewrite it into a script-decoded
 * placeholder, which these script-free pages could never decode: `email_off` keeps it as is.
 */
const mailLink = (email: string) =>
  `<!--email_off--><a href="mailto:${escape(email)}">${escape(email)}</a><!--/email_off-->`;

interface Page {
  title: string;
  intro: string;
  sections: [heading: string, paragraphs: string[]][];
}

function privacy(lang: Lang, email: string): Page {
  const mail = mailLink(email);
  return lang === "fr"
    ? {
        title: "Politique de confidentialité",
        intro:
          "BioBalance est l’application professionnelle du réseau de partenaires BioBalance : points de vente, responsables de région et administrateurs. Cette page explique quelles données nous traitons, pourquoi, et quels sont vos droits.",
        sections: [
          [
            "Qui sommes-nous",
            [
              `Le service est exploité par BioBalance. Pour toute question sur vos données : ${mail}.`,
              "Les comptes sont créés uniquement sur invitation, par un administrateur ou un responsable de région. L’application ne s’adresse pas aux enfants.",
            ],
          ],
          [
            "Les données que nous traitons",
            [
              "<b>Compte</b> : nom, adresse email, téléphone (facultatif), rôle, région et point de vente, langue choisie, mot de passe (enregistré uniquement sous forme chiffrée irréversible) et, pour les administrateurs, le secret de la validation en deux étapes (chiffré).",
              "<b>Activité professionnelle</b> : ventes enregistrées (produits, quantités, date et heure), stocks, comptages et réapprovisionnements, récompenses, portefeuille et demandes de paiement, annonces lues et progression des formations.",
              "<b>Photos</b> : photos de stock et de bons de livraison que vous choisissez de prendre comme preuve. L’appareil photo sert aussi à lire les codes-barres des produits ; les images de lecture ne sont pas enregistrées.",
              "<b>Données techniques</b> : journaux de sécurité (adresse IP, date, résultat d’une connexion) pour protéger les comptes contre les tentatives répétées.",
              "Nous n’utilisons ni publicité, ni pistage, ni outil d’analyse tiers, et nous ne vendons aucune donnée.",
            ],
          ],
          [
            "Pourquoi",
            [
              "Faire fonctionner le service que votre organisation utilise : enregistrer les ventes, suivre le stock, calculer et payer les récompenses, envoyer les annonces et les formations, et sécuriser l’accès. La base légale est l’exécution du contrat professionnel entre BioBalance et ses partenaires, et l’intérêt légitime de sécuriser le service.",
            ],
          ],
          [
            "Qui y a accès",
            [
              "Chaque personne voit ce que son rôle permet : un membre d’équipe ses propres ventes et son portefeuille, un responsable sa région, l’administrateur tout le réseau. La séparation est appliquée par la base de données elle-même.",
              "Nos prestataires techniques, uniquement pour faire fonctionner le service : l’hébergement du serveur, la protection réseau (Cloudflare) et l’envoi des emails (codes d’invitation et de réinitialisation).",
            ],
          ],
          [
            "Combien de temps",
            [
              "Les données du compte sont gardées tant que le compte existe. Quand un compte est supprimé, ce qui identifie la personne est effacé immédiatement. Les enregistrements commerciaux (ventes, mouvements de stock, récompenses payées) sont conservés sans nom pour la comptabilité, le temps exigé par la loi.",
            ],
          ],
          [
            "Sécurité",
            [
              "Les échanges sont chiffrés (HTTPS), les mots de passe sont hachés (Argon2id), les administrateurs utilisent la validation en deux étapes, les captures d’écran de l’application sont bloquées sur Android et l’accès est cloisonné par région.",
            ],
          ],
          [
            "Vos droits",
            [
              `Vous pouvez consulter et corriger vos informations dans l’application (Réglages), et supprimer votre compte depuis Réglages → Supprimer mon compte, ou en écrivant à ${mail}. Vous pouvez aussi demander une copie de vos données ou vous opposer à un traitement, conformément à la loi tunisienne n° 2004-63 sur la protection des données personnelles et, le cas échéant, au RGPD.`,
            ],
          ],
        ],
      }
    : {
        title: "Privacy policy",
        intro:
          "BioBalance is the business app of the BioBalance partner network: points of sale, regional managers and administrators. This page explains what data we process, why, and your rights.",
        sections: [
          [
            "Who we are",
            [
              `The service is run by BioBalance. For any question about your data: ${mail}.`,
              "Accounts are created by invitation only, by an administrator or a regional manager. The app is not directed at children.",
            ],
          ],
          [
            "The data we process",
            [
              "<b>Account</b>: name, email address, phone (optional), role, region and point of sale, chosen language, password (stored only as an irreversible hash) and, for administrators, the two-step verification secret (encrypted).",
              "<b>Business activity</b>: recorded sales (products, quantities, date and time), stock, counts and restocks, rewards, wallet and payout requests, announcements read and training progress.",
              "<b>Photos</b>: pictures of stock and delivery papers you choose to take as proof. The camera also reads product barcodes; scanning images are not stored.",
              "<b>Technical data</b>: security logs (IP address, time, result of a sign-in) to protect accounts against repeated attempts.",
              "We use no advertising, no tracking and no third-party analytics, and we sell no data.",
            ],
          ],
          [
            "Why",
            [
              "To run the service your organisation uses: record sales, follow stock, compute and pay rewards, send announcements and training, and keep access secure. The legal basis is the business contract between BioBalance and its partners, and the legitimate interest of securing the service.",
            ],
          ],
          [
            "Who can see it",
            [
              "Each person sees what their role allows: a team member their own sales and wallet, a regional manager their region, the administrator the whole network. The separation is enforced by the database itself.",
              "Our technical providers, only to run the service: server hosting, network protection (Cloudflare) and email delivery (invitation and reset codes).",
            ],
          ],
          [
            "How long",
            [
              "Account data is kept while the account exists. When an account is deleted, what identifies the person is erased at once. Business records (sales, stock movements, rewards paid) are kept without a name for the accounts, as long as the law requires.",
            ],
          ],
          [
            "Security",
            [
              "Traffic is encrypted (HTTPS), passwords are hashed (Argon2id), administrators use two-step verification, screenshots of the app are blocked on Android and access is separated by region.",
            ],
          ],
          [
            "Your rights",
            [
              `You can read and correct your details in the app (Settings), and delete your account from Settings → Delete my account, or by writing to ${mail}. You may also ask for a copy of your data or object to a processing, under Tunisian law no. 2004-63 on personal data protection and, where it applies, the GDPR.`,
            ],
          ],
        ],
      };
}

function terms(lang: Lang, email: string): Page {
  const mail = mailLink(email);
  return lang === "fr"
    ? {
        title: "Conditions d’utilisation",
        intro:
          "Ces conditions s’appliquent à l’application BioBalance, réservée aux partenaires du réseau BioBalance invités par un administrateur ou un responsable.",
        sections: [
          [
            "Votre compte",
            [
              "Votre compte est personnel. Gardez votre mot de passe secret et prévenez votre responsable ou l’administrateur si vous pensez qu’il est connu de quelqu’un d’autre.",
            ],
          ],
          [
            "Ce que vous enregistrez",
            [
              "Les ventes, comptages et photos doivent correspondre à la réalité. Une vente peut être corrigée par son vendeur pendant 48 heures, puis par un responsable ou l’administrateur ; chaque correction est gardée dans l’historique.",
            ],
          ],
          [
            "Récompenses",
            [
              "Les récompenses par unité vendue sont fixées par l’administrateur pour des périodes données. Elles sont versées après approbation d’une demande de paiement. Une vente annulée ou corrigée ajuste la récompense correspondante.",
            ],
          ],
          [
            "Accès",
            [
              "L’administrateur peut suspendre un accès en cas d’usage abusif ou quand une personne quitte le réseau. Vous pouvez supprimer votre compte à tout moment depuis les Réglages.",
            ],
          ],
          ["Contact", [`Questions : ${mail}.`]],
        ],
      }
    : {
        title: "Terms of use",
        intro:
          "These terms apply to the BioBalance app, reserved for partners of the BioBalance network invited by an administrator or a regional manager.",
        sections: [
          [
            "Your account",
            [
              "Your account is personal. Keep your password secret and tell your manager or the administrator if you think someone else knows it.",
            ],
          ],
          [
            "What you record",
            [
              "Sales, counts and photos must match reality. A sale can be corrected by its seller for 48 hours, then by a manager or the administrator; every correction is kept in the history.",
            ],
          ],
          [
            "Rewards",
            [
              "Rewards per unit sold are set by the administrator for given periods. They are paid after a payout request is approved. A cancelled or corrected sale adjusts its reward.",
            ],
          ],
          [
            "Access",
            [
              "The administrator may suspend access in case of misuse or when a person leaves the network. You can delete your account at any time from Settings.",
            ],
          ],
          ["Contact", [`Questions: ${mail}.`]],
        ],
      };
}

function deletion(lang: Lang, email: string): Page {
  const mail = mailLink(email);
  return lang === "fr"
    ? {
        title: "Supprimer votre compte BioBalance",
        intro:
          "Vous pouvez supprimer votre compte vous-même, à tout moment, depuis l’application.",
        sections: [
          [
            "Dans l’application",
            [
              "Ouvrez <b>Réglages</b> → <b>Supprimer mon compte</b>, confirmez avec votre mot de passe. La suppression est immédiate et définitive.",
            ],
          ],
          [
            "Sans l’application",
            [
              `Écrivez à ${mail} depuis l’adresse de votre compte, avec l’objet « Suppression de compte ». Nous supprimons le compte sous 30 jours et vous le confirmons.`,
            ],
          ],
          [
            "Ce qui est supprimé",
            [
              "Votre nom, votre adresse email, votre téléphone, votre mot de passe, vos sessions, vos notifications et votre progression de formation. Les demandes de paiement en attente sont annulées : demandez le paiement de votre solde avant de supprimer votre compte.",
            ],
          ],
          [
            "Ce qui est gardé",
            [
              "Les enregistrements commerciaux auxquels vous avez participé (ventes, mouvements de stock, récompenses déjà payées) restent, sans votre nom, pour la comptabilité du réseau, le temps exigé par la loi.",
            ],
          ],
        ],
      }
    : {
        title: "Delete your BioBalance account",
        intro:
          "You can delete your account yourself, at any time, from the app.",
        sections: [
          [
            "In the app",
            [
              "Open <b>Settings</b> → <b>Delete my account</b> and confirm with your password. Deletion is immediate and final.",
            ],
          ],
          [
            "Without the app",
            [
              `Write to ${mail} from your account's address, with the subject "Account deletion". We delete the account within 30 days and confirm it to you.`,
            ],
          ],
          [
            "What is deleted",
            [
              "Your name, email address, phone, password, sessions, notifications and training progress. Payout requests still waiting are cancelled: ask for your balance to be paid before deleting your account.",
            ],
          ],
          [
            "What is kept",
            [
              "The business records you took part in (sales, stock movements, rewards already paid) stay, without your name, for the network's accounts, as long as the law requires.",
            ],
          ],
        ],
      };
}

function support(lang: Lang, email: string): Page {
  const mail = mailLink(email);
  return lang === "fr"
    ? {
        title: "Aide BioBalance",
        intro: `Une question, un problème avec l’application ? Écrivez à ${mail} : nous répondons sous deux jours ouvrés.`,
        sections: [
          [
            "Obtenir un compte",
            [
              "Les comptes sont créés sur invitation : demandez à votre responsable de région (ou à l’administrateur) de vous ajouter. Vous recevez un email avec un code ; dans l’application, touchez « Activer mon compte », saisissez le code et choisissez votre mot de passe.",
            ],
          ],
          [
            "Mot de passe oublié",
            [
              "Sur l’écran de connexion, touchez « Mot de passe oublié ? » et suivez le code reçu par email.",
            ],
          ],
          [
            "Supprimer votre compte",
            [
              'Réglages → Supprimer mon compte. Détails sur <a href="/account-deletion?lang=fr">cette page</a>.',
            ],
          ],
        ],
      }
    : {
        title: "BioBalance help",
        intro: `A question, a problem with the app? Write to ${mail}: we answer within two working days.`,
        sections: [
          [
            "Getting an account",
            [
              "Accounts are created by invitation: ask your regional manager (or the administrator) to add you. You receive an email with a code; in the app, tap “Activate my account”, enter the code and choose your password.",
            ],
          ],
          [
            "Forgotten password",
            [
              "On the sign-in screen, tap “Forgot your password?” and follow the code sent by email.",
            ],
          ],
          [
            "Deleting your account",
            [
              'Settings → Delete my account. Details on <a href="/account-deletion?lang=en">this page</a>.',
            ],
          ],
        ],
      };
}

function render(page: Page, lang: Lang, path: string) {
  const other: Lang = lang === "fr" ? "en" : "fr";
  const updated =
    lang === "fr" ? `Mise à jour : ${UPDATED}` : `Last updated: ${UPDATED}`;
  const body = page.sections
    .map(
      ([h, ps]) =>
        `<h2>${escape(h)}</h2>${ps.map((p) => `<p>${p}</p>`).join("")}`,
    )
    .join("");
  return `<!doctype html>
<html lang="${lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escape(page.title)} · BioBalance</title>
<style>
:root{color-scheme:light dark;--ink:#111318;--muted:#5b6270;--brand:#0c6b45;--bg:#f7f8fa;--card:#fff;--line:#e6e8ec}
@media (prefers-color-scheme:dark){:root{--ink:#f3f4f6;--muted:#a3aab5;--brand:#3ddb97;--bg:#0b0c0e;--card:#141518;--line:#2a2c31}}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,Arial,sans-serif}
main{max-width:760px;margin:0 auto;padding:32px 20px 64px}
.top{display:flex;justify-content:space-between;align-items:center;margin-bottom:28px}
.brand{color:var(--brand);font-weight:800;letter-spacing:-.2px}
.lang{color:var(--brand);font-weight:600;text-decoration:none;border:1px solid var(--line);border-radius:999px;padding:4px 12px;font-size:14px}
article{background:var(--card);border:1px solid var(--line);border-radius:18px;padding:28px 24px}
h1{font-size:28px;line-height:1.2;letter-spacing:-.6px;margin:0 0 8px}
h2{font-size:18px;margin:28px 0 6px}
p{margin:8px 0}.muted{color:var(--muted);font-size:14px}
a{color:var(--brand)}
nav{margin-top:24px;display:flex;gap:16px;flex-wrap:wrap;font-size:14px}
</style></head>
<body><main><div class="top"><span class="brand">BioBalance</span><a class="lang" href="${path}?lang=${other}">${other.toUpperCase()}</a></div>
<article><h1>${escape(page.title)}</h1><p class="muted">${updated}</p><p>${page.intro}</p>${body}</article>
<nav><a href="/support?lang=${lang}">${lang === "fr" ? "Aide" : "Help"}</a><a href="/privacy?lang=${lang}">${lang === "fr" ? "Confidentialité" : "Privacy"}</a><a href="/terms?lang=${lang}">${lang === "fr" ? "Conditions" : "Terms"}</a><a href="/account-deletion?lang=${lang}">${lang === "fr" ? "Supprimer un compte" : "Delete an account"}</a></nav>
</main></body></html>`;
}

function language(query?: string, accept?: string): Lang {
  if (query === "fr" || query === "en") return query;
  return (accept ?? "").toLowerCase().startsWith("en") ? "en" : "fr";
}

@Controller()
export class LegalController {
  private send(res: Response, html: string) {
    res.setHeader(
      "Content-Security-Policy",
      "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    );
    // Public, unchanging text: browsers and Cloudflare may keep it for an hour.
    // "no-transform": Cloudflare leaves the page as written (no injected script or rewritten addresses).
    res.setHeader("Cache-Control", "public, max-age=3600, no-transform");
    res.setHeader("Vary", "Accept-Language");
    return html;
  }

  @Public()
  @Get("privacy")
  @Header("Content-Type", "text/html; charset=utf-8")
  privacy(
    @Query("lang") q: string | undefined,
    @Headers("accept-language") accept: string | undefined,
    @Res({ passthrough: true }) res: Response,
  ) {
    const lang = language(q, accept);
    return this.send(res, render(privacy(lang, contact()), lang, "/privacy"));
  }

  @Public()
  @Get("terms")
  @Header("Content-Type", "text/html; charset=utf-8")
  terms(
    @Query("lang") q: string | undefined,
    @Headers("accept-language") accept: string | undefined,
    @Res({ passthrough: true }) res: Response,
  ) {
    const lang = language(q, accept);
    return this.send(res, render(terms(lang, contact()), lang, "/terms"));
  }

  @Public()
  @Get("support")
  @Header("Content-Type", "text/html; charset=utf-8")
  support(
    @Query("lang") q: string | undefined,
    @Headers("accept-language") accept: string | undefined,
    @Res({ passthrough: true }) res: Response,
  ) {
    const lang = language(q, accept);
    return this.send(res, render(support(lang, contact()), lang, "/support"));
  }

  @Public()
  @Get("account-deletion")
  @Header("Content-Type", "text/html; charset=utf-8")
  deletion(
    @Query("lang") q: string | undefined,
    @Headers("accept-language") accept: string | undefined,
    @Res({ passthrough: true }) res: Response,
  ) {
    const lang = language(q, accept);
    return this.send(
      res,
      render(deletion(lang, contact()), lang, "/account-deletion"),
    );
  }
}
