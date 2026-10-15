# Runbook

Everything here is for the operator of the shared go2code VPS (`ssh go2code`). Secrets live in `/etc/biobalance/backend.env` (root, 0600) and are never committed. The wrapper `sudo biobalance-compose …` runs Docker Compose with the right files.

## Deploy

```bash
git switch main && git pull
scripts/deploy-vps.sh
```

It refuses a dirty tree, uploads the commit, builds the image on the server, saves a database dump to `/srv/biobalance-backups/pre-deploy/`, applies migrations, restarts the API, worker and Nginx, and waits for `https://api.galylio.com/health`. If the new version does not become healthy it prints the previous image, which you restore in `backend.env`.

Apache's vhost is installed from `infrastructure/production/shared-vps/apache-https.conf` into `/etc/apache2/sites-available/biobalance-ssl.conf`; after changing it run `sudo apache2ctl configtest && sudo systemctl reload apache2`.

## First administrator and first data

On an empty system nobody can sign in. Create the admin once:

```bash
cd /opt/biobalance/infrastructure/production && mkdir -p setup
sudo ADMIN_EMAIL=admin@example.com biobalance-compose run --rm bootstrap-admin
sudo cat setup/admin-setup.json   # password + authenticator link; copy it somewhere safe, then delete the file
```

Scan the `totpUri` in an authenticator app. Then load the product catalogue (see "The product catalogue").

Create the three responsables (one per region) from the app: **Network → New account**. They receive an email with an activation code. Grossistes are not accounts: create them from **More → Grossistes → New grossiste** (name, address, phone, region, photos), then count their first stock.

### An administrator lost their phone or password

```bash
sudo ADMIN_EMAIL=admin@example.com biobalance-compose run --rm reset-admin
sudo cat /opt/biobalance/infrastructure/production/setup/admin-reset.json   # new password + new authenticator link; then delete it
```

This ends their sessions and touches no business data.

## The admin web page

The administrator can also work from a browser: **https://admin.galylio.com/**. It is the same app as the phone's, built for the web from the same code (`apps/mobile`), with the same screens, languages and sign-in (the administrator also enters an authenticator code). Administrators and responsables can sign in there, each with their own sidebar; team members are told to use the phone app.

- It is served by the existing nginx container from `/opt/biobalance-web` on the server (mounted read-only at `/admin/`), through the same Apache and Cloudflare as the API. The page and the API share one address, so no cross-site settings are needed.
- Publish a new version: `scripts/deploy-web.sh` (builds locally, uploads, checks). No restart is needed. Nginx re-checks the files on every visit, so people get the new version on their next reload.
- Changes to the nginx settings (`shared-vps/nginx.conf`, the `/admin/` block with its security headers) go out with `scripts/deploy-vps.sh`.
- Rolling back: check out the older commit and run `scripts/deploy-web.sh` again.

## Environment keys

`API_PUBLIC_URL` (for example `https://api.galylio.com`) is used by the API and the worker to put the "copy your code" link in emails.


`API_IMAGE` (set by the deploy script), `DATABASE_URL` (restricted application role), `MIGRATION_DATABASE_URL` (owner), `POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB`, `MFA_ENCRYPTION_KEY` (32 random bytes, base64 — losing it locks the admin's authenticator), `SMTP_HOST`/`SMTP_PORT`/`SMTP_SECURE`/`SMTP_REQUIRE_TLS`/`SMTP_FROM`/`SMTP_USER`/`SMTP_PASSWORD`, `WORKER_CONCURRENCY`, `SUPPORT_EMAIL`, `MIN_APP_BUILD` (the oldest app build still allowed: older phones show "Update required"; 0 allows all) with `IOS_STORE_URL` (the App Store page, once it exists) and `PLAY_STORE_URL` (defaults to the Play page), and for push alerts `FCM_SERVICE_ACCOUNT` (Android) and `APNS_KEY_ID`/`APNS_TEAM_ID`/`APNS_KEY_P8`/`APNS_TOPIC` (iPhone), below.

### Push alerts

The worker sends each new notification to the person's phones within milliseconds: the database signals it (`LISTEN notification_new`, a trigger on `Notification`), it claims the new rows, words them in the person's language and hands them to Google (Android) or Apple (iPhone). A slow 30-second timer covers a missed signal. A phone whose platform has no key on the server keeps using its own 15-minute background check, so nothing is ever left silent.

**Android (Firebase Cloud Messaging)** — set up on 2026-10-12 with the Firebase project `bio-balance-8b7c4`:
- The app carries the project's public identifiers in code (`lib/core/alerts/fcm_io.dart`), so no Gradle plugin or `google-services.json` is needed to build it.
- The server holds the service-account key: `FCM_SERVICE_ACCOUNT` in `/etc/biobalance/backend.env` is the downloaded JSON key, base64 encoded (`base64 -w0 key.json`). To replace it: Firebase console → Project settings → Service accounts → Generate new private key, put the new value in the file, `sudo biobalance-compose up -d`, then delete the old key in Google Cloud → IAM → Service accounts. A backup of the file before this change is `/etc/biobalance/backend.env.before-fcm` (it holds the other secrets: remove it when no longer needed).
- Check: sign in on an Android phone, allow notifications, record a sale from another phone: the responsable's phone shows it at once. A refused key shows as `PUSH_FAILED` in `docker logs biobalance-worker-1`.

#### iPhone alerts (Apple push)

Set up on 2026-10-13 (key "BioBalance push"; the previous file is `/etc/biobalance/backend.env.bak-20261013-apns`). Without these keys iPhones check for alerts by themselves when iOS lets them (a few times a day), and see everything when the app opens. With them, an alert reaches a closed iPhone within seconds. To set them up again:

1. developer.apple.com → Certificates, Identifiers & Profiles → **Keys** → **+** → name it "BioBalance push", tick **Apple Push Notifications service (APNs)**, Continue → Register → **Download** the `AuthKey_XXXXXXXXXX.p8` file (it can be downloaded only once: keep it with the signing keys). Note the **Key ID** and the **Team ID** (top right of the page).
2. On the server: `base64 -w0 AuthKey_XXXXXXXXXX.p8` and add to `/etc/biobalance/backend.env`:
   `APNS_KEY_ID=<Key ID>`, `APNS_TEAM_ID=<Team ID>`, `APNS_KEY_P8=<the base64 text>` (`APNS_TOPIC` defaults to `tn.biobalance.app`).
3. `sudo biobalance-compose up -d` (the API and the worker restart with the key).
4. Check: sign in on an iPhone, allow notifications, record a sale from another phone: the responsable's iPhone shows it. A refused key shows as `PUSH_FAILED` with `status` 403 in `docker logs biobalance-worker-1`.

The app registers for push in Xcode automatically: with automatic signing, the Push Notifications capability is added to the App ID at the first build (`ios/Runner/Runner.entitlements`).

## Backups and restore

`biobalance-backup.timer` takes a dump and a copy of the media volume each night into `/srv/biobalance-backups` (budget and retention in `backup.env`). `scripts/verify-restore.sh` restores the latest copy into a throwaway database and counts rows: run it after any change to the schema or the backup scripts. Backups on this VPS do not survive losing the whole server, so a copy leaves it every day: `scripts/pull-backups.sh` copies the newest finished backup to `~/.biobalance/backups` on the Mac (checked against its checksums, the last 14 kept, FileVault-encrypted disk); `scripts/pull-backups.sh --install` makes the Mac do it at 09:30 each day (log: `~/.biobalance/backups/pull.log`). To restore from such a copy, send its `database.dump` and `media.tar.gz` back to the server and follow the steps below.

To restore by hand: stop `api1 api2 worker`, `pg_restore --clean --if-exists` the dump into the database as the owner, restore the media volume, start the services.

## App error reports

The apps report the errors they meet (release builds; platform, version and the error, never who). The admin reads them in Settings → *App errors* (`GET /v1/client-errors`); they are kept 30 days. A new kind of error after a release is the first thing to look at.

## Monitoring

`biobalance-monitor.timer` checks every few minutes: services healthy, memory and load, jobs failing or stuck, backup freshness, the public HTTPS endpoint and the certificate (more than 7 days left). The GitHub workflow `operations-monitor.yml` checks from outside and emails incidents.

## Troubleshooting

| Symptom | Look at |
|---|---|
| App says "service unavailable" | `sudo biobalance-compose ps`, then `logs api1`; errors carry a `correlationId` the app can show |
| Nobody receives emails | `logs worker`; jobs table: `SELECT status, count(*) FROM "Job" GROUP BY 1` (failed email jobs keep a safe error code) |
| Photos fail to upload | Apache `LimitRequestBody` and Nginx `client_max_body_size` for `/v1/media` (90 MiB); disk space under the `media` volume |
| 429 on sign-in | Intended after repeated failures (15-minute window); clear with `DELETE FROM "LoginAttempt"` if a person is locked out by mistake |
| Nothing reaches the server (apps and web console fail) but `sudo biobalance-compose ps` shows everything healthy | The **domain**: `dig +short api.galylio.com @1.1.1.1` must show Cloudflare addresses (104.21.x / 172.67.x), not `127.0.0.1`; `dig +short NS galylio.com @8.8.8.8` must show the Cloudflare nameservers; `curl -s https://rdap.verisign.com/com/v1/domain/galylio.com` shows the expiry. Parked nameservers (`parkpage.foundationapi.com`) mean the registration expired or is on hold: renew at the registrar (Gransy / Regtons). Expiry now 2027-10-14 |
| Restart one thing | `sudo biobalance-compose up -d --force-recreate api1` (never `down -v`: it deletes the database) |

## Reset to an empty system

Only for a deliberate wipe, with a fresh dump taken first. Stop `api1 api2 worker`, then as the owner: `DROP SCHEMA public CASCADE; CREATE SCHEMA public;`, run `scripts/provision-role.sql` after migrating, start the services and create the admin again.

## Abuse and race checks

`scripts/dev/stress.mjs` (races, replays, abuse, hostile input, uploads, load) runs against a **local** server only. Reports and analytics cover at most 400 days.

## Load test

Checks that the dashboards and analytics stay fast on a large network (300 stores, a year of 300 000 sales), against a scratch database — never a real one:

```sh
P="docker compose -f infrastructure/development/compose.yml exec -T postgres psql -U biobalance -q"
$P -d postgres -c 'CREATE DATABASE biobalance_perf_test'
(cd apps/api && DATABASE_URL=postgresql://biobalance:local-development-only@localhost:54329/biobalance_perf_test npx prisma migrate deploy)
$P -d biobalance_perf_test -v app_password=local-app-only < scripts/provision-role.sql
$P -d biobalance_perf_test < scripts/perf-seed.sql
cd apps/api && TEST_DATABASE_URL=postgresql://biobalance_app:local-app-only@localhost:54329/biobalance_perf_test \
  TEST_OWNER_DATABASE_URL=postgresql://biobalance:local-development-only@localhost:54329/biobalance_perf_test \
  PERF=1 npx vitest run test/perf.test.ts --disableConsoleIntercept
```

Measured 2026-10-10: dashboards 0.3–0.6 s, analytics of 30 days 0.8 s (a region 0.5 s), a whole year against the year before 4 s, stores board 0.08 s, sales ledger 0.03 s. The analytics read the lens's sale lines once into transaction-scoped working tables (`lens_line`, `lens_sale`) and compute every ranking from them; raw SQL compares `day` columns with `::date` parameters so the day indexes are used.

## Drafts, alerts and deploys (3.2)

- Deploys restart one API at a time (the other keeps answering) and restart nginx only when its settings changed: no more "502" during a deploy.
- Photo downloads have their own, higher limit than uploads: a page full of photos no longer hits "too many requests".
- The Apache log lines start with the time (`biobalance-access.log`).

## The test region

The store reviewers' accounts live in one region marked as the **test region** (`Region.sandbox`, at most one): **Démo**, with its responsable `demo-responsable@galylio.com`, a group, the shop *Para Démo Lac* and its team member `demo-vendeur@galylio.com`, a grossiste, stock, 60 days of sales with their rewards, restocks, payouts and an announcement. The passwords are in the owner's private hand-off; Apple and Google have them.

What makes it a test region (tested in `test/sandbox.test.ts` and `test/sandbox-life.test.ts`):

- **The admin does not see it**: every row-level policy hides it from the admin (`app_admin_sees`), so no screen, total, report, export, approval or list shows it. The admin can look at it with Settings → *Show the test region* (the app then sends `X-BioBalance-Sandbox: show`; only an admin is listened to).
- **Nothing done there reaches the real network**: no alert to any admin (enforced in `notify`: an action by its people or its automation never notifies an admin, even the one who created the account), no email to its accounts, its audit entries are filed under it (so the audit log leaves them out), announcements sent only to it are left out of the admin's list, and the admin's announcements, courses and reward news do not reach it.
- Its accounts cannot change their password or get a reset code (`DEMO_ACCOUNT`), so one reviewer never locks out the next. If a reviewer deletes one, it is deleted like any account and **comes back three minutes later**, history intact (a `demo-restore` job).
- **It looks after itself** (the worker): what it submits (stores, members, stock counts, recounts, restocks, payouts) is approved a minute later, and a demo account a reviewer deactivated (as the responsable) is active again a minute later; its shop keeps selling through the day (a fixed plan per hour, stock topped up, nothing pushed).

Rebuild everything for the real start (take a dump first; it keeps the admins, the catalogue and the reward rates, empties everything else, and builds the test region again with the review accounts' **current** passwords; the worker leaves the region alone while it is built):

```sh
sudo biobalance-compose run --rm demo node dist/demo.js fresh-start --delete-everything
```

Remove only the test region when the store reviews are over (the rest is left exactly as it was; tested):

```sh
sudo biobalance-compose run --rm demo node dist/demo.js purge
```

Build it on an empty network instead: `demo.js seed` with `DEMO_RESPONSABLE_PASSWORD` and `DEMO_VENDEUR_PASSWORD` set in the shell (never on a command line). These commands need the database owner (`MIGRATION_DATABASE_URL`) because the history is append-only.

Done on 2026-10-13: the network was emptied (backup: `/srv/biobalance-backups/pre-deploy/before-fresh-start-20261013T150508Z*`) and the test region rebuilt; production then held the admin, the two review accounts, the catalogue (51 products) and the reward rates.

### Emptying one real region

`demo.js clear-region CODE --delete-everything-in-it` empties **one** real region (its stores, groups, grossistes, people, sales, stock, restocks, rewards earned, payouts, photos and every history line, with the admin's alerts about them) and keeps the region itself, the admins, the catalogue, the reward rates and **every other region, the test region included**. It refuses a test region (use `purge`). One transaction (all or nothing), the integrity checks stay on, the append-only guards of the history are lifted only inside it. Take a dump first:

```sh
sudo bash -s <<'SCRIPT'
mkdir -p /srv/biobalance-backups/manual
docker exec biobalance-postgres-1 sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > /srv/biobalance-backups/manual/before-clear-REGION-$(date -u +%Y%m%dT%H%M%SZ).dump
biobalance-compose run --rm -T demo node dist/demo.js clear-region REGION --delete-everything-in-it </dev/null
SCRIPT
```

## The product catalogue

The products live in `apps/api/catalog`: `products.json` (one entry per barcode: name, family, line, size, description, use, ingredients, and the `sources` where each fact and photo was checked) and `images/<barcode>.jpg` (1000×1000, the product cropped to fill the frame on white). Names follow the supplier list's style without the brand prefix (`SUPER SERUM PURE VITAMINE C 30ML`). Every barcode is checked against the supplier list and at least one shop (pharma-shop.tn shows it in the address; lifepharmacy.com ends its addresses with its last digits).

To change a product: edit the file (and its photo), commit, deploy, then on the server:

```sh
sudo biobalance-compose run --rm catalog                                   # shows what would change
sudo biobalance-compose run --rm catalog node dist/catalog.js refresh --apply
```

It matches by barcode, never touches stock, sales, rates or whether a product is active, creates a product for a new barcode, and changes nothing when run again. Locally: `cd apps/api && npm run catalog -- --apply`.
