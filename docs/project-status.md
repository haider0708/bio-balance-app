# Project status (the living file: both machines update it)

Last updated: 2026-10-13 (evening), by the Mac session.

## Versions and what runs

| Part | Version | Where |
|---|---|---|
| App code | `3.3.1+41` | iPhone: built and signed, not uploaded yet; web console: https://admin.galylio.com (runs 3.3.1); Android: the Play closed test still has `3.3.0+40` |
| Server (API + worker) | commit `8fa240c7` | https://api.galylio.com (the deploy guard records what runs: `/opt/biobalance-deployed-api`) |
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
3. Android: the next Play upload (`3.3.1+41` or later) carries every fix since 3.3.0 (Linux PC, with the upload key) after the Data safety update.
4. Once the minimum version matters (old builds must stop): set `MIN_APP_BUILD` on the server, and `IOS_STORE_URL` once the App Store page exists.
5. After both stores approve: keep the test region for later reviews, or remove it (`demo.js purge`).

## Things deliberately left as they are

- Dependencies held back on purpose: go_router 18 and flutter_local_notifications 22 (major versions; revisit with tests).
- The iPhone app links the Firebase libraries (needed by Android, not used on iPhone); Firebase Analytics is not linked.
- Plugin `open_filex` has no Swift Package support yet, so the iPhone build still needs CocoaPods.

## Log

- 2026-10-13 (Mac, afternoon): **Test region** (hidden from the admin by row-level security, nothing reaches the real network, self-approving, self-selling, demo accounts restored after deletion, password change refused); **production emptied and rebuilt** with it. Notifications: per-sale alerts inbox-only, evening summary at 20:30 (regions and network), new reward rates and new courses announced, correct singular/plural and dates (`docs/notifications.md`). Minimum app version (`/v1/app-config`, "Update required" screen). App error reports (Settings → App errors). Off-site backups to the Mac (`scripts/pull-backups.sh`, daily). Apple push key on the server. Fixes found by running the apps: bottom sheets' last button under the iPhone home bar, product rows growing when selected, a push race in the test shop, demo payout dates. Deploy removes its build-stage image. Privacy policy names the alert token, error reports, Apple and Google. Server 8fa240c7 and web console deployed.
- 2026-10-13 (Mac, morning): Mac ready (MacPorts: `gh`, CocoaPods; `SSL_CERT_FILE` and `LANG` in `~/.zprofile`). iPhone fixes: alerts shown while the app is open, privacy manifest (device ID). Shared fixes: French zero, grouped unit counts, "30-day rewards", analytics rows of three. CocoaPods/Swift Package files committed. Cleanup of server images, failed CI runs and a stale cache.
- 2026-10-12: 3.3.0 (Android push, instant delivery through LISTEN/NOTIFY); demonstration region; Play closed test approved; hand-off to the Mac; CI builds iPhone and Android on every push; deploy guard for two machines; this file and `CLAUDE.md`.
- 2026-10-11: 3.2.0 (drafts, iPhone push code), 3.2.1 (cleanup, CI repaired, first GitHub release).
- Earlier history: `docs/project-history.md`.
