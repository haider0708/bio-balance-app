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

Create the three responsables (one per region) and the grossistes from the app: **Network → New account**. They receive an email with an activation code.

### An administrator lost their phone or password

```bash
sudo ADMIN_EMAIL=admin@example.com biobalance-compose run --rm reset-admin
sudo cat /opt/biobalance/infrastructure/production/setup/admin-reset.json   # new password + new authenticator link; then delete it
```

This ends their sessions and touches no business data.

## Environment keys

`API_PUBLIC_URL` (for example `https://api.galylio.com`) is used by the API and the worker to put the "copy your code" link in emails.


`API_IMAGE` (set by the deploy script), `DATABASE_URL` (restricted application role), `MIGRATION_DATABASE_URL` (owner), `POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB`, `MFA_ENCRYPTION_KEY` (32 random bytes, base64 — losing it locks the admin's authenticator), `SMTP_HOST`/`SMTP_PORT`/`SMTP_SECURE`/`SMTP_REQUIRE_TLS`/`SMTP_FROM`/`SMTP_USER`/`SMTP_PASSWORD`, `WORKER_CONCURRENCY`.

## Backups and restore

`biobalance-backup.timer` takes a dump and a copy of the media volume each night into `/srv/biobalance-backups` (budget and retention in `backup.env`). `scripts/verify-restore.sh` restores the latest copy into a throwaway database and counts rows: run it after any change to the schema or the backup scripts. Backups on this VPS do not survive losing the whole server; copy them elsewhere if that matters.

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

## Limits and load tests

`scripts/dev/stress.mjs` (races, replays, abuse, hostile input, uploads, load) and `scripts/dev/timing.mjs` (every main screen's request, cold and warm) run against a **local** server only. `scripts/dev/volume.sql` fills the local database with 300 000 sales (a year of heavy activity) first.

With that volume (local laptop, one API process): a month of reports or the home of any role answers in about 20 ms; a full year of reports by store, seller or day in 0.25–0.6 s; a full year by product or insights in 2–3 s (the database checks row-level security on 600 000 sale lines). Reports cover at most 400 days. If years of data ever make this slow, add a daily summary table per store and product, filled by the same code that records sales.
