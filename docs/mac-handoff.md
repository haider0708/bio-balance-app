# Hand-off to the Mac session (iPhone app and App Store)

Read this first. It says where the project stands and what the Mac session is for. There are no secrets in it.

## Start here

0. `git pull`, then read `CLAUDE.md` (the shared rules and the start-of-session / end-of-session routine) and `docs/project-status.md` (where things stand). Claude reads `CLAUDE.md` by itself when the project is opened.
1. Run `bash scripts/mac-setup.sh` (installs and checks everything, prepares signing and the server connection, builds the app once). It prints a public SSH key for the owner to give to the Linux session.
2. Follow [app-store-steps.md](app-store-steps.md): every step to the App Store, with who does what and the exact answers for each form.
3. Obey the rules in "One codebase, two stores" below.
4. Secrets (reviewer passwords, server access) are in the private file the owner hands you; they are not in this repository.

## The project

BioBalance: sales, stock, restocks and rewards for a parapharmacy network. Flutter app (`apps/mobile`, phone, tablet and web console), NestJS 12 + Prisma 7 + PostgreSQL 17 server (`apps/api`). Production: https://api.galylio.com (server), https://admin.galylio.com (web console). Repository: github.com/haider0708/bio-balance-app, branch `main`, current release `v3.3.0` (app version `3.3.0+40` in `apps/mobile/pubspec.yaml`). Everything is documented in `docs/` (start with `mobile-release.md` and `store-publishing.md`).

## State on 2026-10-12

- **Android:** done and submitted. Closed test under Google review on Google Play (package `tn.biobalance.app`); 12 testers added; the 14-day countdown starts when they have joined. Nothing to do here from the Mac.
- **Server:** deployed (push alerts for Android through Firebase, a demo region "Démo" with reviewer accounts). Deploys are done from the Linux PC, not from here (`scripts/deploy-vps.sh` needs ssh access to the server).
- **iPhone app: compiles, never run.** It was written on Linux, where Xcode does not exist, but the GitHub check `ios` (a Mac machine, Xcode 26.6, `flutter build ios --release --no-codesign`) **builds it successfully** on every push (`Runner.app`, about 30 MB). What has *not* been exercised: signing and capabilities (push), archiving, and running on a real iPhone or in the simulator. Expect the real problems there, not in compilation.

## What this session is for

Get the iPhone app signed, tested on a simulator and a real iPhone, uploaded to TestFlight, submitted to App Review, and distributed as an **unlisted** app. The full procedure, with the answers to give in App Store Connect, is [app-store-steps.md](app-store-steps.md). Android is already in a Google Play closed test and is not this session's concern.

## Things the iPhone app does that Apple will look at

- Account deletion inside the app (Settings → Delete my account) and at `https://api.galylio.com/account-deletion`; privacy policy `https://api.galylio.com/privacy`; terms `/terms`; support `/support`.
- Privacy manifest `ios/Runner/PrivacyInfo.xcprivacy` (no tracking). Age rating 4+. No export-compliance question (`ITSAppUsesNonExemptEncryption` is false). EU trader status must be declared in App Store Connect.
- Reviewer accounts (the same two as for Google Play, in the demo region): team member `demo-vendeur@galylio.com`, regional manager `demo-responsable@galylio.com`. The passwords, the server access and where everything lives are in a **private file that is not in this repository** (the repository is public): the owner gives it to you directly (`mac-handoff-private.md`).

## One codebase, two stores: how not to break Android while fixing iPhone

Both apps are built from the **same Dart code** in `apps/mobile/lib`. Only the native shells differ.

| Where | Shared by | Rule |
|---|---|---|
| `apps/mobile/lib/**` (screens, logic, API calls) | Android, iPhone, web console | A change here ships to **all three**. Keep it platform-neutral; if iPhone needs different behaviour use `defaultTargetPlatform == TargetPlatform.iOS` (or `Platform`), never remove the Android path. |
| `apps/mobile/ios/**` (Swift, Info.plist, entitlements, Xcode project) | iPhone only | Free to change. Android cannot be affected. |
| `apps/mobile/android/**` | Android only | **Do not touch** from the Mac session unless the owner asks. |
| `apps/mobile/pubspec.yaml` / `pubspec.lock` | all | A new package or a version bump affects every platform: prefer none; if unavoidable, say so and check the Android build. |
| `apps/api/**`, `infrastructure/**`, `scripts/**` | the server | Not for the Mac session. Tell the owner and the Linux session instead. |

Before every commit, run `flutter analyze && flutter test` (the tests are platform-neutral and cover both). The GitHub checks (`.github/workflows/ci.yml`) then build **both** apps on every push: the Android build on Linux (`android` job) and the iPhone build on a Mac machine (`ios` job). **Do not merge or release while either is red.** A change in shared code that was only tried on iPhone is not finished until the Android job is green.

Version numbers are shared: `version: 3.3.0+40` in `pubspec.yaml` gives Android its version code and iPhone its build number. Raise the number after `+` for every upload to either store (and the part before it for a real new version). Android is already in a Google Play test under `3.3.0+40`: do not change shared behaviour casually, since the testers are using it.

Native code that exists for one platform must stay inert on the other:
- iPhone push (`AppDelegate.swift`, channel `biobalance/push`) is only called when `defaultTargetPlatform == iOS` (`lib/core/alerts/push.dart`).
- Android push (Firebase, `lib/core/alerts/fcm_io.dart`) is only used on Android, and the web build uses a stand-in (`fcm_stub.dart`).

## Working agreements

- Use plain language in summaries. Think before implementing; test everything; keep the code clean, matching the surrounding style.
- Commit and push every fix from the Mac to `main` (small commits, one concern each); then on the Linux PC `git pull`, so the two stay equal. Never commit secrets, signing files or `Signing.xcconfig`.
- The Apple Team ID, Apple ID and certificates stay on the Mac.
- The API and the web console are deployed from the Linux PC only.
