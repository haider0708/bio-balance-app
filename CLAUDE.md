# BioBalance: instructions for Claude (read automatically at the start of every session)

This file is the shared memory of the project. It lives in Git, so the Linux PC and the Mac see the same one. Claude's own per-machine memory is not shared: **what matters is written here and in `docs/`.**

## At the start of every session

1. `git pull` (use `git pull --rebase`). Never start work on a stale copy.
2. Read [docs/project-status.md](docs/project-status.md): where things stand, what is deployed, what is pending, who is doing what.
3. Read [docs/project-history.md](docs/project-history.md) once per session when you need the why behind a decision. The detailed docs: `docs/architecture.md`, `api.md`, `functional-specification.md`, `security.md`, `runbook.md`, `mobile-release.md`, `store-publishing.md`, `app-store-steps.md`.

## At the end of every session (or after any change worth remembering)

1. Update `docs/project-status.md` (state, what changed, what is next, date) and anything in `docs/` that the change made stale.
2. Commit with a message that explains the change; `git push`. Then say plainly what is done, deployed and left.
3. The other machine gets it with `git pull`. If it is not pushed, it does not exist for the other machine.

## The project in one paragraph

BioBalance runs a network of parapharmacies: points of sale and their teams, stock, restocks, sales and the rewards sellers earn (French and English, TND in millimes). `apps/api`: NestJS 12, Prisma 7, PostgreSQL 17 (row-level security keeps regions apart). `apps/mobile`: one Flutter 3.47.5 app for Android, iPhone and the web console (admin.galylio.com). Production: api.galylio.com on a shared VPS behind Cloudflare. Package/bundle id `tn.biobalance.app`. Roles: ADMIN (the owner, with two-step sign-in), RESPONSABLE (one per region), VENDEUR (team member of one store). A grossiste is a warehouse record, not an account.

## Two machines, one repository

- **Linux PC** (the owner's main machine): the server (API, worker, database), Android builds and the Android signing key, the web console, and the server deploys. **Mac**: the iPhone app (Xcode, signing, TestFlight, App Store).
- **Both** can edit, test, commit, push, and deploy, through the scripts only: `scripts/deploy-vps.sh` (API) and `scripts/deploy-web.sh` (web console). They refuse to run unless the checkout is on `main`, fully committed, **equal to GitHub's main**, and not older than what the server runs; they take a server lock so two deploys cannot overlap (`scripts/deploy-guard.sh`). Never deploy by hand, and never bypass the guard unless the owner asks for a rollback (`FORCE_DEPLOY=1`).
- The one-time setup of a machine: `scripts/mac-setup.sh` (Mac). A machine that deploys needs `ssh go2code` (its own key, never copied) and, for the API, Node 24 and Docker for the tests.
- One codebase, two stores: `apps/mobile/lib` is shared by Android, iPhone and web, so a change there ships to all three. iPhone-only changes belong in `apps/mobile/ios/` or behind `defaultTargetPlatform == TargetPlatform.iOS`; do not remove the Android path. The GitHub checks build **both** apps (`ios` and `android` jobs) on every push: never release while one is red. See `docs/mac-handoff.md`.

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
- The test region "Démo" holds the store reviewers' accounts in production. It is hidden from the admin and nothing done there reaches the real network, but do not remove it or change its passwords while a store review is open (`docs/runbook.md`, "The test region").

## How the owner likes to work

Plain-language answers and short final summaries; think before implementing; pro, clean, tested work; the owner trusts careful engineering over speed. Ask before anything that needs the owner's own logins (Apple, Google Play, GitHub settings, Cloudflare, Firebase). Be honest about what was and was not verified (for example "compiled, not run on a device"). Never say something works without having checked it.
