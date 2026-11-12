# BioBalance: instructions for Claude (read automatically at the start of every session)

This file is the shared memory of the project. It lives in Git, so every machine sees the same one. Claude's own per-machine memory is not shared: **what matters is written here and in `docs/`.**

## At the start of every session

1. `git pull` (use `git pull --rebase`). Never start work on a stale copy.
2. Read [docs/project-status.md](docs/project-status.md): where things stand, what is deployed, what is pending, who is doing what.
3. Read [docs/project-history.md](docs/project-history.md) once per session when you need the why behind a decision. The detailed docs: `docs/architecture.md`, `api.md`, `functional-specification.md`, `security.md`, `runbook.md`, `mobile-release.md`, `store-publishing.md`, `app-store-steps.md`.

## At the end of every session (or after any change worth remembering)

1. Update `docs/project-status.md` (state, what changed, what is next, date) and anything in `docs/` that the change made stale.
2. Commit with a message that explains the change; `git push`. Then say plainly what is done, deployed and left.
3. Another machine gets it with `git pull`. If it is not pushed, it does not exist for it.

## The project in one paragraph

BioBalance runs a network of parapharmacies: points of sale and their teams, stock, restocks, sales and the rewards sellers earn (French and English, TND in millimes). `apps/api`: NestJS 12, Prisma 7, PostgreSQL 17 (row-level security keeps regions apart). `apps/mobile`: one Flutter 3.47.5 app for Android, iPhone and the web console (admin.galylio.com). Production: api.galylio.com on a shared VPS behind Cloudflare. Package/bundle id `tn.biobalance.app`. Roles: ADMIN (the owner, with two-step sign-in), RESPONSABLE (one per region), VENDEUR (team member of one store). A grossiste is a warehouse record, not an account.

## Machines and secrets

- The owner works from one machine at a time (today the Mac; the Linux PC is gone). **Secrets are not on any machine for good: they are on the server in `/etc/biobalance/secrets/` (root only)**, and `docs/secrets-and-new-machine.md` says what is where, how to set up a new machine, and what to do before a machine is sold.
- The server (API, worker, database), Android builds, the web console and the iPhone app (Xcode, TestFlight, App Store) are all built and deployed from whichever machine has the keys, through the scripts only: `scripts/deploy-vps.sh` (API), `scripts/deploy-web.sh` (web console), `scripts/publish-apk.sh` (direct APK), `scripts/ios-release.sh` and `scripts/testflight.mjs` (iPhone). The deploy scripts refuse to run unless the checkout is on `main`, fully committed, **equal to GitHub's main**, and not older than what the server runs; they take a server lock so two deploys cannot overlap (`scripts/deploy-guard.sh`). Never deploy by hand, and never bypass the guard unless the owner asks for a rollback (`FORCE_DEPLOY=1`).
- A machine that deploys needs `ssh go2code` (its own key, never copied) and, for the API, Node 24 and Docker for the tests. The one-time setup of a Mac: `scripts/mac-setup.sh`.
- One codebase, three targets: `apps/mobile/lib` is shared by Android, iPhone and web, so a change there ships to all three. iPhone-only changes belong in `apps/mobile/ios/` or behind `defaultTargetPlatform == TargetPlatform.iOS`; do not remove the Android path. The GitHub checks build **both** apps (`ios` and `android` jobs) on every push: never release while one is red. See `docs/mac-handoff.md`.

## Before a change is "done"

- App: `cd apps/mobile && flutter analyze && flutter test` (add a test for new behaviour). API: `cd apps/api && npm run format:check && npx tsc -p tsconfig.json --noEmit && npx vitest run` (needs the local database: `docker compose -f infrastructure/development/compose.yml up -d` after every reboot, then `bash scripts/setup-test-db.sh` after a migration). A change that touches the API shape also runs the contract test (README.md, "Check it").
- User-visible text goes in `apps/mobile/lib/l10n/*.arb` (French and English, then `flutter gen-l10n`); server error codes and notification wording are in `lib/core/l10n/server_text.dart` and `apps/api/src/core/notice-text.json` (a test keeps them equal).
- Look at screens (the screenshot tests write PNGs to `apps/mobile/build/screenshots`), light and dark, phone and tablet, French and English.
- The version is `version: X.Y.Z+N` in `apps/mobile/pubspec.yaml`; raise `+N` for every upload to either store.

## Rules that have bitten before

- Never commit secrets: no passwords, keys, `.env`, signing files, `Signing.xcconfig`, `mac-handoff-private.md`, `.local-credentials-v2/`. **The repository is public.** Secrets live in the owner's private files and on the server (`/etc/biobalance/backend.env`).
- Money is whole millimes (BigInt on the server). Days are Tunis days (UTC+1, no daylight saving): use `tunisDay`, never `toISOString().slice(0, 10)`. Raw SQL day parameters are cast `::date`.
- The history tables (stock movements, sale revisions, wallet entries, audit) are append-only by database trigger.
- Prisma interactive transactions time out at 15 seconds; PostgreSQL regex repetition counts stop at 255.
- Cloudflare breaks script-free pages that show email addresses unless wrapped in `<!--email_off-->`; the pages are sent `no-transform`.
- Never `pkill -f` a pattern that appears in your own command line (it kills your own shell); never `pkill -f flutter`.
- The server is **shared with other, unrelated sites**: touch only BioBalance's containers, images, volumes and folders.
- The router (`routerProvider`) must refresh only when signing in or out (or a password must be chosen), never on every update of the session: the app asks the server who is signed in each time it comes back to the foreground (after the camera, the gallery, the file chooser), and a refresh throws away the page the person is on when that page needs the object handed over by the previous screen (`extra`: the order of "Add papers"). That made every photo, gallery and PDF upload in the restock screens fall back to the order (found on the owner's Samsung, 2026-11-10; `test/resume_keeps_page_test.dart`).
- On Android the position is read with `Geolocator.getCurrentPosition`, never `getPositionStream`: the stream needs the plugin's foreground service, which the manifest removes (the app never tracks; Google Play would ask for a declaration). With the stream the phone was never asked and every reading came back empty: no check-in was ever recorded in production until 3.6.0 (found on the owner's Samsung, 2026-11-12; `lib/features/planning/location_service.dart`). A change to the position code is tried on a real phone.
- There is no demonstration region any more (removed 2026-11-09; the code is in the git tag `demo-region-last`). Store reviewers get accounts created for the review (`docs/store-publishing.md`, decision 5).

## How the owner likes to work

Plain-language answers and short final summaries; think before implementing; pro, clean, tested work; the owner trusts careful engineering over speed. Ask before anything that needs the owner's own logins (Apple, Google Play, GitHub settings, Cloudflare, Firebase). Be honest about what was and was not verified (for example "compiled, not run on a device"). Never say something works without having checked it.
