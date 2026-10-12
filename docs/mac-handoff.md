# Hand-off to the Mac session (iPhone app and App Store)

Read this first. It says where the project stands and what the Mac session is for. There are no secrets in it.

## The project

BioBalance: sales, stock, restocks and rewards for a parapharmacy network. Flutter app (`apps/mobile`, phone, tablet and web console), NestJS 12 + Prisma 7 + PostgreSQL 17 server (`apps/api`). Production: https://api.galylio.com (server), https://admin.galylio.com (web console). Repository: github.com/haider0708/bio-balance-app, branch `main`, current release `v3.3.0` (app version `3.3.0+40` in `apps/mobile/pubspec.yaml`). Everything is documented in `docs/` (start with `mobile-release.md` and `store-publishing.md`).

## State on 2026-10-12

- **Android:** done and submitted. Closed test under Google review on Google Play (package `tn.biobalance.app`); 12 testers added; the 14-day countdown starts when they have joined. Nothing to do here from the Mac.
- **Server:** deployed (push alerts for Android through Firebase, a demo region "Démo" with reviewer accounts). Deploys are done from the Linux PC, not from here (`scripts/deploy-vps.sh` needs ssh access to the server).
- **iPhone app: never compiled.** It was built on Linux, where Xcode does not exist: the Swift code (`ios/Runner/AppDelegate.swift`, `SceneDelegate.swift`) was only syntax-checked, and the Xcode project file was edited by hand (`ios/Runner.xcodeproj/project.pbxproj`, entitlements, `Info.plist`). **The first real build may fail; fixing that is the first job.**

## What this session is for, in order

1. `cd apps/mobile && flutter pub get --enforce-lockfile && flutter build ios --release --no-codesign`. Fix whatever fails (Swift, project file, plugins). Then run `flutter analyze && flutter test`.
2. Signing: `cp ios/Flutter/Signing.xcconfig.example ios/Flutter/Signing.xcconfig`, put the Apple Team ID in it (the file is git-ignored). Xcode 26 or later is required; Xcode → Settings → Accounts with the Apple Developer account. Bundle identifier `tn.biobalance.app`, iOS 15+, iPhone portrait, iPad all orientations.
3. `flutter build ipa --release`, upload with Transporter, test through TestFlight (internal testers need no review).
4. App Store Connect: create the app (name BioBalance; if taken, a close variant), listing texts and privacy answers from `docs/store-publishing.md`, screenshots already made in `~/.biobalance/store/iphone-6.9` and `ipad-13` on the Linux PC (regenerate on the Mac with `STORE_SHOTS=1 flutter test test/store_screenshots_test.dart` if needed; they land in `build/store`), review notes, then submit for review and ask Apple for **Unlisted App Distribution** (the app is invitation-only; Apple often refuses such apps in the public store).
5. Push alerts for iPhone: the server code is ready (`apps/api/src/push/apns.ts`); it needs an Apple push key (.p8) configured on the server (`docs/runbook.md`, "iPhone alerts"). The Linux session does that part.

## Things the iPhone app does that Apple will look at

- Account deletion inside the app (Settings → Delete my account) and at `https://api.galylio.com/account-deletion`; privacy policy `https://api.galylio.com/privacy`; terms `/terms`; support `/support`.
- Privacy manifest `ios/Runner/PrivacyInfo.xcprivacy` (no tracking). Age rating 4+. No export-compliance question (`ITSAppUsesNonExemptEncryption` is false). EU trader status must be declared in App Store Connect.
- Reviewer accounts (the same two as for Google Play, in the demo region): team member `demo-vendeur@galylio.com`, regional manager `demo-responsable@galylio.com`. The passwords are in the git-ignored file `.local-credentials-v2/demo-accounts.json` on the Linux PC; ask the owner for them.

## Working agreements

- Use plain language in summaries. Think before implementing; test everything; keep the code clean, matching the surrounding style.
- Commit and push every fix from the Mac to `main`; then on the Linux PC `git pull`, so the two stay equal. Never commit secrets, signing files or `Signing.xcconfig`.
- The Apple Team ID, Apple ID and certificates stay on the Mac.
- The API and the web console are deployed from the Linux PC only.
