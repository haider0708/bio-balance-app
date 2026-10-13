# Project status (the living file: both machines update it)

Last updated: 2026-10-13 (night), by the Linux session.

## Versions and what runs

| Part | Version | Where |
|---|---|---|
| App code | `3.3.2+42` (iPhone 3.3.1+41, Android Play test 3.3.0+40: see below) | iPhone: 3.3.1 (41) submitted to App Review on 2026-10-13 (App Store Connect app 6822445997); web console: https://admin.galylio.com (runs 3.3.1, deployed with server fa37aa85); Android: the Play closed test still has `3.3.0+40` |
| Server (API + worker) | commit `fa37aa85` | https://api.galylio.com (the deploy guard records what runs: `/opt/biobalance-deployed-api`) |
| GitHub release | `v3.3.0` (APK + AAB + checksums) | github.com/haider0708/bio-balance-app/releases |

## Production data (since 2026-10-13)

The network was emptied for its real start (`docs/runbook.md`, "The test region"): production holds **the admin**, the **catalogue** (51 products) and the **reward rates**, plus the **test region "Démo"** with the two store-review accounts and 60 days of demonstration data. The test region is hidden from the admin and nothing done there reaches the real network; it approves its own submissions and keeps selling by itself. Backup of what was there before: `/srv/biobalance-backups/pre-deploy/before-fresh-start-20261013T150508Z*`.

## Where each store stands

- **Google Play:** closed test (track "Alpha", tester list "Testeurs Beta") approved on 2026-10-12, 12 testers. The 14-day clock runs once 12 testers have joined; then "Demander un accès en production" (personal account rule). The testers use the review accounts (test region). **Before the next Android upload:** update the Data safety form (add *App info and performance → Crash logs*, not linked, see `docs/store-publishing.md`).
- **App Store:** the account holder is "Karim Tajer" (individual), so that is the seller name shown. Signing works without an Apple ID in Xcode, through the App Store Connect API team key (Admin) kept in `~/.biobalance/appstore/` on the Mac: `scripts/ios-release.sh` builds, signs (cloud signing; the team has no device and no free distribution certificate) and checks the push entitlement; `--upload` sends it. `tn.biobalance.app` is registered with Push Notifications. **Next:** the owner creates the app in App Store Connect (`docs/app-store-steps.md`, step 3), then upload, TestFlight, listing, App Privacy, review, unlisted request.
- **Push alerts:** iPhone (Apple key "BioBalance push") and Android (Firebase) are both configured on the server. Proven: foreground and background alerts and taps in the iPhone simulator; on Android, the inbox and taps on the emulator. Not yet seen on a real phone through Apple/Google.

## Next steps, in order

1. Owner: create the app in App Store Connect; then the Mac uploads the build (`scripts/ios-release.sh --upload`), and TestFlight on any iPhone (sign-in, a sale, camera, push with the app closed).
2. Owner (Cloudflare, optional): remove the stray `v=DMARC1; p=none;` TXT on `galylio.com` itself (the real one is on `_dmarc`); later raise DMARC to `quarantine`.
3. Android: **`3.3.2+42` is built and signed, ready to upload to the Play closed test** (`~/.biobalance/releases/BioBalance-3.3.2.aab` on the Linux PC; release notes in the log below). **Before uploading, the owner updates the Data safety form** (add *App info and performance → Crash logs*, not linked to the user; see `docs/store-publishing.md`). After uploading, the testers get the update from Play; the 14-day clock is not reset by an update.
4. Once the minimum version matters (old builds must stop): set `MIN_APP_BUILD` on the server, and `IOS_STORE_URL` once the App Store page exists.
5. After both stores approve: keep the test region for later reviews, or remove it (`demo.js purge`).

## Things deliberately left as they are

- Dependencies held back on purpose: go_router 18 and flutter_local_notifications 22 (major versions; revisit with tests).
- The iPhone app links the Firebase libraries (needed by Android, not used on iPhone); Firebase Analytics is not linked.
- Plugin `open_filex` has no Swift Package support yet, so the iPhone build still needs CocoaPods.

## Log

- 2026-10-13 (Linux, night): **Android `3.3.2+42` built** for the Play closed test: version raised (build 41 went to the iPhone), all four GitHub checks green (backend, mobile, ios, android), `flutter analyze` clean and 104 app tests passing, signed App Bundle built against `https://api.galylio.com` with the upload key (certificate SHA-256 `67:EF:65:E6:…:A8:48:12`, as before), and checked on the matching APK: versionCode 42, versionName 3.3.2, targetSdk 36, 16 KB aligned. Files: `~/.biobalance/releases/BioBalance-3.3.2.aab` (78 MB) and `.apk`. Not uploaded yet (the owner uploads in the Play Console). Release notes for the testers: French "Livraisons : confirmation avec la photo du bon et une note, sans compter ; alertes plus calmes (résumé chaque soir à 20 h 30) ; chiffres plus lisibles ; écran « Mise à jour requise » et rapport d'erreurs ; catalogue aux noms clairs et photos nettes." English: the same in English. The server was not deployed (already up to date).

- 2026-10-13 (Mac, night): **iPhone app submitted to App Review** (3.3.1 build 41), all through the App Store Connect API key except App Privacy and the review contact (owner): French listing (an English page is refused, the name BioBalance is taken in English), Business, 4+, free, **Tunisia only** (no EU trader declaration needed), review notes with both demo accounts, 6 iPhone 6.9" and 6 iPad 13" screenshots of the real catalogue, manual release. Next: the unlisted distribution request (owner, text in `docs/app-store-steps.md` step 8), then release after approval.
- 2026-10-13 (Mac, late night): **Product catalogue** cleaned and refreshed in production (`docs/runbook.md`, "The product catalogue"): clear names, sharp photos cropped to the product, every barcode checked against the supplier list and Tunisian/Gulf shops; `catalog.js refresh` replaces the import script. **Deployed** server `fa37aa85` (audit fixes, simpler delivery receipt with its migration, catalogue) and the web console. App reviewed on the iPhone simulator and the Android emulator against a local server. Backup before: `before-fa37aa85.dump`.
- 2026-10-13 (Mac, late): **Restock receipt simplified** at the owner's request (`docs/functional-specification.md`, Restock): the store's responsable or the team member they choose confirms a delivery with the paper (photos or PDF) and a note, without counting; the admin enters the quantities received (starting at what was sent) and approves. Before giving an order to a grossiste, the admin sees each grossiste's stock for it. Older apps keep working (their counted quantities are pre-filled for the admin). Migration `202610190001_receipt_note`. Contract test run against a real server.
- 2026-10-13 (Mac, night): **Full audit** of the server (security, row-level isolation checked on the live database as the app's own role, every module's rules), the app (sign-in, offline sales, crash-prone code, every screenshot on phone and tablet, light and dark) and today's work. Fixed: the test region could still reach the real admin (the demo responsable deactivating the demo seller alerted the admin, who created that account) and showed in the admin's announcements list; a reviewer could lock out the demo seller by deactivating it (now reactivated after a minute); a forged page cursor and a sale id clash answered 500; the responsable of a supplying region could pick the receiver at another region's store; tablet region cards ran two texts together. Server 177 tests, app 101, analyzer clean.
- 2026-10-13 (Mac, afternoon): **Test region** (hidden from the admin by row-level security, nothing reaches the real network, self-approving, self-selling, demo accounts restored after deletion, password change refused); **production emptied and rebuilt** with it. Notifications: per-sale alerts inbox-only, evening summary at 20:30 (regions and network), new reward rates and new courses announced, correct singular/plural and dates (`docs/notifications.md`). Minimum app version (`/v1/app-config`, "Update required" screen). App error reports (Settings → App errors). Off-site backups to the Mac (`scripts/pull-backups.sh`, daily). Apple push key on the server. Fixes found by running the apps: bottom sheets' last button under the iPhone home bar, product rows growing when selected, a push race in the test shop, demo payout dates. Deploy removes its build-stage image. Privacy policy names the alert token, error reports, Apple and Google. Server 8fa240c7 and web console deployed.
- 2026-10-13 (Mac, morning): Mac ready (MacPorts: `gh`, CocoaPods; `SSL_CERT_FILE` and `LANG` in `~/.zprofile`). iPhone fixes: alerts shown while the app is open, privacy manifest (device ID). Shared fixes: French zero, grouped unit counts, "30-day rewards", analytics rows of three. CocoaPods/Swift Package files committed. Cleanup of server images, failed CI runs and a stale cache.
- 2026-10-12: 3.3.0 (Android push, instant delivery through LISTEN/NOTIFY); demonstration region; Play closed test approved; hand-off to the Mac; CI builds iPhone and Android on every push; deploy guard for two machines; this file and `CLAUDE.md`.
- 2026-10-11: 3.2.0 (drafts, iPhone push code), 3.2.1 (cleanup, CI repaired, first GitHub release).
- Earlier history: `docs/project-history.md`.
