# Project status (the living file: both machines update it)

Last updated: 2026-10-12, by the Linux session.

## Versions and what runs

| Part | Version | Where |
|---|---|---|
| App (Android, iPhone, web) | `3.3.0+40` | Android: Google Play closed test; web console: https://admin.galylio.com; iPhone: not published yet |
| Server (API + worker) | commit `30b483a0` or later | https://api.galylio.com (the deploy guard records what runs: `/opt/biobalance-deployed-api` on the server) |
| GitHub release | `v3.3.0` (APK + AAB + checksums) | github.com/haider0708/bio-balance-app/releases |

## Where each store stands

- **Google Play:** closed test (track "Alpha", tester list "Testeurs Beta") **approved by Google** on 2026-10-12. 12 testers added. Next: the owner sends the opt-in link (Console > Tests fermés > Testeurs > Copier le lien); the 14-day clock starts when 12 testers have joined; then "Demander un accès en production" (the account is a personal one, so this rule applies). Listing, data safety, content rating, privacy, financial/health/ads declarations are done.
- **App Store:** not started on Apple's side. The Apple Developer account exists (a **person**, so the seller shown is the owner's own name). The Mac has Xcode, Flutter and CocoaPods. The iPhone app **compiles in CI** (Xcode 26.6) but has never run on a simulator or an iPhone. Steps: `docs/app-store-steps.md`.
- **Push alerts:** Android via Firebase is live on the server (not yet verified on a real phone). iPhone needs the Apple push key (`docs/runbook.md`, "iPhone alerts"); the server code is ready.

## Next steps, in order

1. Mac: run `scripts/mac-setup.sh`, then follow `docs/app-store-steps.md` (simulator, real iPhone, TestFlight, App Review, unlisted distribution request).
2. Owner: send the Play opt-in link to 12 testers; check email for Google messages.
3. Linux: add the Mac's public SSH key to the server when the owner pastes it; configure the Apple push key when it exists.
4. When testers report problems: fix in shared code with both CI jobs green, raise `+N`, build, upload to the Play test (and TestFlight).
5. After 14 days with 12 testers: production access request (Play).

## Things deliberately left as they are

- The demonstration region "Démo" exists in production for the store reviewers (accounts in the owner's private files). It counts in the admin's totals (filter by region). Remove with `docs/runbook.md` ("The demonstration region") only after both stores have approved.
- No iOS background alerts until the Apple push key is configured.
- Dependencies held back on purpose: go_router 18 and flutter_local_notifications 22 (major versions; revisit with tests).

## Log

- 2026-10-12: 3.3.0 (Android push, instant delivery through LISTEN/NOTIFY); demonstration region; Play closed test approved; hand-off to the Mac (`docs/mac-handoff.md`, `scripts/mac-setup.sh`, `docs/app-store-steps.md`); CI builds iPhone and Android on every push; deploy guard for two machines; this file and `CLAUDE.md`.
- 2026-10-11: 3.2.0 (drafts instead of "leave without saving", iPhone push code), 3.2.1 (cleanup, CI repaired, first GitHub release).
- Earlier history: `docs/project-history.md`.
