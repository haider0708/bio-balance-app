# Publishing on the App Store and Google Play

Everything the stores check inside the app is done (see [mobile-release.md](mobile-release.md)). This page is what you fill in on the store websites, and the decisions to take before the first submission.

## Decisions before submitting

1. **Who publishes.** Publish as an **organization** (the BioBalance company), not as a person, on both stores. Both need a **D-U-N-S number** for the company (free from Dun & Bradstreet, allow up to two weeks). On Google Play this also avoids the rule for new *personal* accounts: a closed test with at least 12 testers for 14 days before any public release.
2. **Who can find the app.** BioBalance is invitation-only: accounts are created by the admin or a responsable. Apple often refuses such apps in the public store ("limited audience", guideline 4.2/3.2). Ask Apple for **Unlisted App Distribution** (a form in App Store Connect after the first build is uploaded): the app passes the same review but is only reachable by its link, which you send to the network. On Google Play the app can be public (reviewers accept sign-in-only apps when they get a test account) or limited to testers.
3. **The Android signing key.** The phones already have test copies signed with `~/.biobalance/signing/biobalance-release.jks`. When Play asks how to sign the app, choose **use your own app signing key** and upload this keystore (Play shows the exact command, `pepk`). Phones that installed an APK can then update from Play without reinstalling; otherwise they must uninstall the APK first.
4. **The support mailbox.** The privacy, terms and deletion pages show `biobalance@galylio.com` (set `SUPPORT_EMAIL` in `/etc/biobalance/backend.env` to change it). Someone must read it: the stores and the law expect answers to data requests.
5. **Accounts for the reviewers.** Create, in production, a separate demo setup so reviewers never touch real data: a region "Démo", a store "Para Démo" with some stock, a **responsable** and a **team member** with simple passwords. Do not give an admin account (it needs the authenticator code). Give both accounts in the review notes below. Keep them active while the review lasts.

## Rules in force in 2026 (checked October 2026)

| Store | Rule | BioBalance |
|---|---|---|
| Apple | Builds must come from **Xcode 26** with the iOS 26 SDK (since 28 April 2026) | Install Xcode 26 on the Mac before `flutter build ipa` |
| Apple | The **new age-rating questionnaire** (4+, 9+, 13+, 16+, 18+) must be answered, or submissions are blocked | Answer "none" everywhere → **4+** |
| Apple | **Trader status** (EU Digital Services Act) must be declared for every account, even outside the EU | Declare **trader** (a company): address, phone and email shown on the EU page; or leave the EU out of the countries |
| Apple | Unlisted distribution is only granted to an app already **submitted to App Review**; say it in the review notes | The review notes below already say it |
| Apple | Account deletion in the app (5.1.1(v)), privacy manifest, purpose texts for camera/photos, test account (2.1) | Done in the app; give the accounts |
| Google | New apps and updates must **target API 36** (Android 16) from 31 August 2026 | Targets 36 |
| Google | **16 KB memory pages** for native code | All libraries aligned |
| Google | **Android developer verification**: package names registered to a verified developer (Play apps are registered automatically; enforced country by country from 30 Sept 2026, everywhere in 2027) | Publish `tn.biobalance.app` from the organization account. The test copies (`tn.biobalance.app.resp1`…) install with `adb`, which stays allowed |
| Google | Photo/video permissions only for apps whose core is media; foreground-service declaration; data safety; account-deletion link; financial-features declaration | No media permission; short service only; answers below |
| Google | New **personal** developer accounts: closed test with 12 testers for 14 days before production | Use an **organization** account (D-U-N-S) |

Most rejections (Apple's own figures) come from crashes, broken links and **missing or dead test accounts**: keep the review accounts working and the pages below reachable during the whole review.

## Listing

| | Français | English |
|---|---|---|
| Name | BioBalance | BioBalance |
| iOS subtitle (30) | Ventes, stock et récompenses | Sales, stock and rewards |
| Play short description (80) | Le réseau BioBalance : ventes, stock, récompenses et analyses, en temps réel. | The BioBalance network: sales, stock, rewards and analytics, in real time. |
| iOS keywords (100) | biobalance,parapharmacie,ventes,stock,inventaire,récompenses,réseau,points de vente,commission | biobalance,parapharmacy,sales,stock,inventory,rewards,network,retail,commission,dashboard |
| Category | Business / Entreprise | Business |
| Price | Free | Free |
| Privacy policy | https://api.galylio.com/privacy | https://api.galylio.com/privacy?lang=en |
| Terms (iOS EULA field optional) | https://api.galylio.com/terms | https://api.galylio.com/terms?lang=en |
| Account deletion (Play) | https://api.galylio.com/account-deletion | |
| Support URL | https://api.galylio.com/support | https://api.galylio.com/support?lang=en |

**Description (FR)**

> BioBalance est l’application des partenaires du réseau BioBalance : points de vente, responsables de région et administrateurs.
>
> • Vendeurs : enregistrez une vente en quelques secondes (recherche ou code-barres), même sans connexion, et voyez tout de suite ce qu’elle vous rapporte. Suivez votre portefeuille et demandez vos paiements.
> • Responsables : suivez les ventes et le stock de votre région, comptez le stock avec photo, commandez les réassorts et recevez les livraisons.
> • Administrateurs : validez ce qui attend, fixez les récompenses, gérez les régions, les points de vente et les grossistes, et analysez tout : chaque chiffre s’ouvre sur ce qui le compose, par région, point de vente, vendeur et produit.
>
> Annonces et formations, notifications, français et anglais, mode sombre, téléphone et tablette.
>
> L’accès se fait sur invitation de votre responsable ou de l’administrateur BioBalance.

**Description (EN)**

> BioBalance is the app of the BioBalance partner network: points of sale, regional managers and administrators.
>
> • Team members: record a sale in seconds (search or barcode), even offline, and see at once what it earns you. Follow your wallet and ask for payouts.
> • Regional managers: follow sales and stock in your region, count stock with a photo, order restocks and receive deliveries.
> • Administrators: approve what waits, set rewards, manage regions, points of sale and wholesalers, and analyse everything: every number opens on what makes it, by region, point of sale, seller and product.
>
> Announcements and training, notifications, French and English, dark mode, phone and tablet.
>
> Access is by invitation from your manager or the BioBalance administrator.

## App Store privacy (“App Privacy”)

Data **linked to the user**, used **only for App Functionality**, **not used for tracking**:

| Apple category | What |
|---|---|
| Contact Info → Name, Email Address, Phone Number | the account |
| Identifiers → User ID | the account |
| User Content → Photos or Videos | proof photos of stock and delivery papers |
| User Content → Other User Content | sales, stock counts, restocks |

Not collected: location, contacts, health, financial info, browsing, search history, diagnostics, advertising data. **Tracking: No.** Age rating: 4+ (no objectionable content). The same answers are in the app's privacy manifest.

## Google Play “Data safety”

- Data collected: **Personal info** (name, email address, phone number, user IDs), **Photos**, **App activity → Other user-generated content** (sales, counts). All **required for app functionality**, **not shared** with third parties, **encrypted in transit**, and **deletable by the user** (in the app and at `/account-deletion`).
- No data sold, no ads (**Contains ads: No**), no location.
- **App access**: all functionality needs an account → give the reviewer accounts (decision 5).
- **Content rating**: questionnaire → no violence, no user-to-user chat, no gambling → *Everyone*.
- **Target audience**: 18 and over (business app). **News app**: no. **Government app**: no. **Financial features**: none (rewards are commissions paid by the company, not a financial service).
- **Foreground service**: if asked, the app uses none of the special types (only a *short service* for the background alert check).

## Review notes (paste in both stores)

> BioBalance is a business app for the BioBalance partner network (parapharmacy points of sale in Tunisia). Accounts are created by invitation only; there is no public sign-up.
>
> Test accounts:
> • Team member (records sales): [email] / [password]
> • Regional manager (stock, restocks, region analytics): [email] / [password]
>
> The app is intended for unlisted distribution to the members of our network (we will send the unlisted distribution request once this build is in review).
>
> To try it: sign in as the team member, tap “New sale”, add a product and record the sale: the reward is shown. Sign in as the regional manager to see the region's dashboard; every number opens its analytics.
> The camera is used to scan product barcodes and to photograph stock as proof. Account deletion: Settings → Delete my account.

## Checklist for each release

1. Raise `version:` in `pubspec.yaml` (`3.1.2+38`…), run `flutter analyze && flutter test` and the API tests.
2. Deploy the API first (`scripts/deploy-vps.sh`): the new app may use new endpoints.
3. Android: `flutter build appbundle --release` → Play Console → a testing track first, then Production.
4. iOS: `flutter build ipa --release` on the Mac → Transporter → TestFlight → submit.
5. Regenerate screenshots only when screens changed (`STORE_SHOTS=1 flutter test test/store_screenshots_test.dart`).
