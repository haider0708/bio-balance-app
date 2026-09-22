# Reproducible synthetic API load

Never run this scenario against partner data or production. It creates and mutates real records in an isolated database ending in `_load_test`; the seeder refuses an existing populated database and never deletes history.

## Dataset and commands

Node 24, PostgreSQL 17 and the repository migrations are required. From the repository root:

```sh
bash scripts/setup-load-db.sh
bash scripts/install-k6.sh
npm run build
DATABASE_URL=postgresql://biobalance_app:local-app-only@127.0.0.1:54329/biobalance_load_test \
LOAD_OWNER_DATABASE_URL=postgresql://biobalance:local-development-only@127.0.0.1:54329/biobalance_load_test \
  bash scripts/run-load.sh
```

The setup creates 125 organizations, 500 stores, 5,000 accounts, 200 products, 300,000 lots, 2,000,000 sales and their revisions, movements, points entries, audit entries and changes. Sessions last 12 hours, are synthetic, and are written only to `.artifacts/load-fixtures.json` with mode 0600. Historical operation hashes are marked synthetic; replay tests use newly submitted operations, not generated historical commands. No email, push or real user accounts are needed.

The runner starts two isolated API processes with `NODE_ENV=production`, a shared temporary synthetic MFA key, and separate ephemeral ports. k6 distributes requests directly across both; this excludes Nginx, TLS and workers. It records process CPU, memory and event-loop lag, shuts down only its own processes, and runs the ledger verifier even after a failed threshold. `API_INSTANCES=1` allows diagnostic comparison. `LOAD_PROFILE=yes` writes 40-second CPU profiles; profiling runs are diagnostic, not acceptance measurements. Results are saved under `.artifacts/evidence/step10/`; archive each run before repeating it.

Default measured workload: 100 requests/s for five minutes, then 200/s for thirty seconds. Each iteration makes one request. Read mix: scoped snapshots, paginated sale history, monthly rankings, inbox and inventory; 10% sales. The initial fixture cursor represents a previously downloaded cache. Each VU retains per-account/store cursors, applies snapshot pages before advancing them, and restarts expired pages. A sale's committed cursor never substitutes for a completed read. Fixture selection spans all 500 stores/5,000 accounts.

For a route smoke check only, set `STEADY_DURATION=10s BURST_DURATION=5s STEADY_RATE=5 BURST_RATE=10`. Short smoke runs are not capacity evidence. k6 is pinned to 2.3.0 with the official Linux x64 checksum.

Record p95 reads ≤300 ms and writes ≤700 ms separately for steady and burst workloads, HTTP/business failures and dropped iterations. Preserve k6 output, database counts/size, CPU/RAM/I/O, host specification, image/commit and server logs with credentials excluded. After load, the verifier compares lot quantities/versions to movements, balances to points entries and sales to revisions. Verify on the reference VPS with both API instances and workers before claiming 500-store readiness. Host measurements do not establish VPS capacity.

## Local persistence benchmark

```sh
cd apps/mobile
flutter test test/performance/local_workflows_benchmark.dart
```

This records host timings in `build/local-benchmark.json`: four cached stores, 200 products/600 lots/100 recent sales each, 120 durable queued sales, cached search, store switching and SQLite reopen. It excludes native startup and rendering. Physical device gates and capture procedure are in `tests/performance/devices.md`.

Pour réutiliser la base synthétique conservée après expiration des sessions, appliquer les migrations puis exécuter `LOAD_OWNER_DATABASE_URL=... node tests/load/refresh-sessions.cjs`. Le script vérifie les identités `load-N@example.test`, renouvelle les seules sessions des fixtures et reprend les curseurs courants ; il ne reconstruit ni ne supprime les historiques.
