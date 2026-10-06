# Architecture

```
apps/api      NestJS 12 · Prisma 7 · PostgreSQL 17        the server
apps/mobile   Flutter 3.47 · Riverpod · go_router          Android and iOS app (French/English)
infrastructure/production   Docker image, compose, Nginx, Apache/Cloudflare notes, systemd timers
scripts       backup, restore check, monitoring, TLS, catalog import
data          the initial catalog (51 products with photos)
```

## Server

A modular monolith. Each module owns its routes, rules and queries:

`auth` (sessions, MFA for the admin, activation and reset codes) · `directory` (groups, points of sale, people, depots) · `catalog` · `media` (streamed uploads, content checked by real bytes) · `stock` (ledger and declarations) · `restock` · `rewards` (rules and wallet) · `sales` · `messaging` (notifications and announcements) · `training` · `reporting` (dashboards, approvals inbox, reports, audit).

Shared kernel in `core/`: errors, the `Database` wrapper, auth guard and roles, audit, notifications, dates, money.

### One request, one transaction, one identity

`Database.run(actor, work)` opens a transaction and first tells PostgreSQL who is calling (`app.role`, `app.user_id`, `app.region_id`, `app.pdv_id`, `app.depot_id`). Row-level security policies (in the baseline migration) read those settings, and the application's database role cannot bypass them. So a region is isolated **even if a query forgets its filter**; tests prove it by querying with forged filters. Trusted server work (jobs, sign-in lookups) runs as `SYSTEM`.

### Data integrity in the database itself

- Foreign keys and check constraints (quantities, amounts, one active responsable per region).
- An exclusion constraint makes overlapping reward periods for the same product/family impossible.
- Append-only triggers on stock movements, sale revisions, wallet entries and the audit log.
- Stock changes are single atomic statements (`INSERT … ON CONFLICT DO UPDATE SET quantity = quantity + delta`), so two phones selling at once never lose an update; decisions lock the row they decide.
- A simulation test runs a month of activity across the three regions and then checks that stock equals the sum of movements, wallets equal what was earned minus paid, rewards equal their lines and nothing crosses regions.

### Background work

A small PostgreSQL job queue (`FOR UPDATE SKIP LOCKED`, leases, retries with backoff) delivers emails (French/English), scheduled announcements and cleanup. Emails carry one-time 8-character codes valid only with the person's email address; the code is removed from the job once handled.

## Mobile app

Feature-first folders (`features/<feature>`: models, repository, screens), Riverpod for state, go_router with a different tab layout per role, gen-l10n for French/English, and a hand-built design system (`core/theme`, `core/widgets`).

- **Online first.** Reads go to the server; the catalog is cached on the phone.
- **Offline selling.** A sale made without a connection is saved in a small outbox and sent when the server answers, with the same identifier, so it can never be counted twice. Everything else (approvals, stock, payouts) needs a connection by design.
- **Photos** are resized on the phone and uploaded before the form is sent.
- **Tests:** widget tests with a fake server (sign-in, selling, offline outbox, language), screenshot rendering for visual review, and a **contract test** that runs the app's real repositories against a real API with a realistic world and checks every response parses and means what it should.

## Deployment

One Docker image (`API_IMAGE`) runs as two API processes and one worker behind Nginx, with PostgreSQL. On the shared go2code VPS, Apache terminates HTTPS behind Cloudflare and forwards to Nginx on loopback. See the [runbook](runbook.md).
