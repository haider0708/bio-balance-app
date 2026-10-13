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

Scan the `totpUri` in an authenticator app. Then, from a checkout, load the catalog (safe to repeat):

```bash
API_URL=https://api.galylio.com ADMIN_EMAIL=… ADMIN_PASSWORD=… ADMIN_OTP=123456 node scripts/import-catalog.mjs
```

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


`API_IMAGE` (set by the deploy script), `DATABASE_URL` (restricted application role), `MIGRATION_DATABASE_URL` (owner), `POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB`, `MFA_ENCRYPTION_KEY` (32 random bytes, base64 — losing it locks the admin's authenticator), `SMTP_HOST`/`SMTP_PORT`/`SMTP_SECURE`/`SMTP_REQUIRE_TLS`/`SMTP_FROM`/`SMTP_USER`/`SMTP_PASSWORD`, `WORKER_CONCURRENCY`, `SUPPORT_EMAIL`, and for push alerts `FCM_SERVICE_ACCOUNT` (Android) and `APNS_KEY_ID`/`APNS_TEAM_ID`/`APNS_KEY_P8`/`APNS_TOPIC` (iPhone), below.

### Push alerts

The worker sends each new notification to the person's phones within milliseconds: the database signals it (`LISTEN notification_new`, a trigger on `Notification`), it claims the new rows, words them in the person's language and hands them to Google (Android) or Apple (iPhone). A slow 30-second timer covers a missed signal. A phone whose platform has no key on the server keeps using its own 15-minute background check, so nothing is ever left silent.

**Android (Firebase Cloud Messaging)** — set up on 2026-10-12 with the Firebase project `bio-balance-8b7c4`:
- The app carries the project's public identifiers in code (`lib/core/alerts/fcm_io.dart`), so no Gradle plugin or `google-services.json` is needed to build it.
- The server holds the service-account key: `FCM_SERVICE_ACCOUNT` in `/etc/biobalance/backend.env` is the downloaded JSON key, base64 encoded (`base64 -w0 key.json`). To replace it: Firebase console → Project settings → Service accounts → Generate new private key, put the new value in the file, `sudo biobalance-compose up -d`, then delete the old key in Google Cloud → IAM → Service accounts. A backup of the file before this change is `/etc/biobalance/backend.env.before-fcm` (it holds the other secrets: remove it when no longer needed).
- Check: sign in on an Android phone, allow notifications, record a sale from another phone: the responsable's phone shows it at once. A refused key shows as `PUSH_FAILED` in `docker logs biobalance-worker-1`.

#### iPhone alerts (Apple push)

Without these keys iPhones check for alerts by themselves when iOS lets them (a few times a day), and see everything when the app opens. With them, an alert reaches a closed iPhone within seconds. Once the Apple developer account exists:

1. developer.apple.com → Certificates, Identifiers & Profiles → **Keys** → **+** → name it "BioBalance push", tick **Apple Push Notifications service (APNs)**, Continue → Register → **Download** the `AuthKey_XXXXXXXXXX.p8` file (it can be downloaded only once: keep it with the signing keys). Note the **Key ID** and the **Team ID** (top right of the page).
2. On the server: `base64 -w0 AuthKey_XXXXXXXXXX.p8` and add to `/etc/biobalance/backend.env`:
   `APNS_KEY_ID=<Key ID>`, `APNS_TEAM_ID=<Team ID>`, `APNS_KEY_P8=<the base64 text>` (`APNS_TOPIC` defaults to `tn.biobalance.app`).
3. `sudo biobalance-compose up -d` (the API and the worker restart with the key).
4. Check: sign in on an iPhone, allow notifications, record a sale from another phone: the responsable's iPhone shows it. A refused key shows as `PUSH_FAILED` with `status` 403 in `docker logs biobalance-worker-1`.

The app registers for push in Xcode automatically: with automatic signing, the Push Notifications capability is added to the App ID at the first build (`ios/Runner/Runner.entitlements`).

## Backups and restore

`biobalance-backup.timer` takes a dump and a copy of the media volume each night into `/srv/biobalance-backups` (budget and retention in `backup.env`). `scripts/verify-restore.sh` restores the latest copy into a throwaway database and counts rows: run it after any change to the schema or the backup scripts. Backups on this VPS do not survive losing the whole server, so a copy leaves it every day: `scripts/pull-backups.sh` copies the newest finished backup to `~/.biobalance/backups` on the Mac (checked against its checksums, the last 14 kept, FileVault-encrypted disk); `scripts/pull-backups.sh --install` makes the Mac do it at 09:30 each day (log: `~/.biobalance/backups/pull.log`). To restore from such a copy, send its `database.dump` and `media.tar.gz` back to the server and follow the steps below.

To restore by hand: stop `api1 api2 worker`, `pg_restore --clean --if-exists` the dump into the database as the owner, restore the media volume, start the services.

## Monitoring

`biobalance-monitor.timer` checks every few minutes: services healthy, memory and load, jobs failing or stuck, backup freshness, the public HTTPS endpoint and the certificate (more than 7 days left). The GitHub workflow `operations-monitor.yml` checks from outside and emails incidents.

## Troubleshooting

| Symptom | Look at |
|---|---|
| App says "service unavailable" | `sudo biobalance-compose ps`, then `logs api1`; errors carry a `correlationId` the app can show |
| Nobody receives emails | `logs worker`; jobs table: `SELECT status, count(*) FROM "Job" GROUP BY 1` (failed email jobs keep a safe error code) |
| Photos fail to upload | Apache `LimitRequestBody` and Nginx `client_max_body_size` for `/v1/media` (90 MiB); disk space under the `media` volume |
| 429 on sign-in | Intended after repeated failures (15-minute window); clear with `DELETE FROM "LoginAttempt"` if a person is locked out by mistake |
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

## The demonstration region

For the store reviewers and for showing the app: a region **Démo** with a responsable, four stores and their teams, a grossiste, stock, 60 days of sales with their rewards, a restock, payouts and an announcement. It is built with the server's own services (so stock, wallets and rewards add up) and its dates are then put where they belong. It is a real region in the real database: **the admin's totals, "owed to the team" included, count it** (filter by region to leave it out), until it is removed.

Build it (take a database dump first; the passwords are what the reviewers type, so they are set in the shell and never on a command line). The worker is stopped meanwhile so that nothing built here can alert or mail anyone:

```sh
sudo bash -s <<'SCRIPT'
export DEMO_RESPONSABLE_PASSWORD=... DEMO_VENDEUR_PASSWORD=...
biobalance-compose stop worker
biobalance-compose run --rm -e DEMO_RESPONSABLE_PASSWORD -e DEMO_VENDEUR_PASSWORD demo node dist/demo.js seed
biobalance-compose start worker
SCRIPT
```

Remove all of it (the database is left exactly as it was before; tested):

```sh
sudo biobalance-compose run --rm demo node dist/demo.js purge
```

Accounts: `demo-responsable@galylio.com` and `demo-vendeur@galylio.com` (the store *Para Démo Lac*); the four other team members have no known password. The seeding needs the database owner (`MIGRATION_DATABASE_URL`) because the history is append-only. For the demo only, it adds earlier periods of the reward rates already in force (note "Historique de démonstration") so the old sales earned rewards; the removal takes them away with the rest.

