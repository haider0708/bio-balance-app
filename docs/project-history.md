# Project history: decisions and why

For anyone (human or Claude) who needs the reasoning behind the code. What the system does: `functional-specification.md`; how it is built: `architecture.md`. No secrets here.

## The redesign (2026-10-06)

A full rebuild. The old design (stores with lots, expiry dates and prices) was dropped; its API survives only in Git history. The server's data was wiped and rebuilt (a backup of the old data is kept on the server).

**Business rules the owner approved**
- Roles: ADMIN (the owner, two-step sign-in), RESPONSABLE (one per region), VENDEUR (one store). Originally also a GROSSISTE account; removed in v2.6.0: a grossiste is a warehouse record with no login.
- A responsable creates groups, points of sale and team members; each waits for the admin's approval. (Later: the admin creates places and they are active at once.) The first stock of a place is a declaration with a photo, which the admin approves, correcting quantities if needed (the admin's own count applies at once). No lots, no expiry, no prices, no damaged-goods flow.
- Restocks: a responsable (or the admin for a warehouse) requests; the admin assigns a warehouse or sends directly ("BioBalance has unlimited stock"); it is shipped; the responsable or a person they pick photographs the paper and counts; the admin approves, corrects or rejects; **stock moves only on approval**. Warehouse stock leaves at shipping time and returns if a shipped order is cancelled.
- Rewards: admin-only. TND per unit sold, per product or per family, in dated periods that cannot overlap (a database exclusion constraint). A team member sees a celebration with the reward of each sale, a history, corrections (48 hours for the seller, any time for a responsable or the admin) and a wallet. Payouts need the admin's approval and only then deduct.
- Announcements: audience by role, region, store or person, pin, schedule, read receipts. Training: courses of lessons with audience and progress.
- Languages: French and English. Money: whole millimes, 1 TND = 1000.

**Later decisions**
- Regions are managed by the admin (create, rename, delete when empty); a responsable always has a region; stores, groups and warehouses move between regions with their history (v2.7.0). Warehouses can supply any region.
- The web console (admin.galylio.com) is the same Flutter app built for the web, for ADMIN and RESPONSABLE (team members are told to use the phone).
- Analytics (v2.8.0): a "lens" (period plus region, group, store, seller, product, family) behind every number; computed from transaction-scoped temporary tables for speed (v3.1.1: 30 days in 0.8 s, a year in 4 s at 300 stores and 300 000 sales).
- Account deletion (stores require it): anonymizes the person ("Compte supprimé #XXXX"), keeps the business records, cannot be undone. Public pages `/privacy`, `/terms`, `/support`, `/account-deletion`.
- Drafts (3.2.0): sales being built, stock counts and restock requests are saved on the phone at every change instead of asking "Leave without saving?".
- Push alerts (3.2.0 to 3.3.0): the database signals the worker the instant a notification is created (LISTEN/NOTIFY); the worker sends through Apple (iPhone) and Firebase Cloud Messaging (Android), each notification once, in the person's language. Phones without push keep a 15-minute background check.

## Architecture in short

NestJS 12 + Prisma 7 + PostgreSQL 17, one baseline migration then incremental ones. `Database.run(actor, work)` opens a transaction and tells PostgreSQL who is calling (`app.role`, `app.user_id`, `app.region_id`, `app.pdv_id`); forced row-level security does the isolation, so a forgotten filter cannot leak another region's data. Append-only triggers protect the history tables. A PostgreSQL job queue (FOR UPDATE SKIP LOCKED) runs emails, scheduled announcements, cleanup and push. Flutter: Riverpod, go_router, feature-first folders, generated localizations, a hand-built design system. Production: Docker Compose (two API containers, a worker, nginx, PostgreSQL) behind Apache and Cloudflare on a shared VPS.

## Milestones

- 2.0 to 2.6: the rebuild, the design system, the web console, warehouses without accounts.
- 2.7: regions management, console for responsables. 2.8: analytics behind every number.
- 3.0: store readiness (account deletion, legal pages, Android permissions, iOS privacy manifest, vector icons, tablet layouts). 3.1: animated opening, PDF proofs, 2026 store rules researched. 3.1.1: analytics 7x faster, on-phone media cache, dependency patches.
- 3.2: drafts, deploys with no downtime, CI repaired, first GitHub release. 3.3: instant Android push, instant delivery. Then the demonstration region, the Play closed test, and the two-machine workflow.

## Lessons worth keeping

- Test on real data volumes: the first analytics version timed out at 300 000 sales; temporary tables fixed it.
- A tool's own tests catch what review misses (a PostgreSQL regex limit, update return order, a push message that could have deleted every device).
- The Cloudflare proxy rewrites pages (analytics script, email obfuscation) unless told `no-transform`.
- Local `node_modules` once had a corrupted file; `npm ci` fixed it. If something impossible happens, suspect the disk or memory.
- CI had silently failed for days because the test font loader used a path that exists on one machine only: nothing machine-specific in tests.
- The shared server hosts other sites: never prune or restart outside BioBalance.
