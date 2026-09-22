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

Default measured workload: 100 requests/s for five minutes, then 200/s for thirty seconds. Each iteration makes one initial request. An explicit `retryable` sale response may cause at most two additional attempts using the same serialized command and operation ID. Other failures are not retried. The retry counter is retained, HTTP errors remain measured, and sale-operation latency includes the retry delay; every sale must finish accepted. A single ramping-arrival-rate scenario holds 100 requests/s for five minutes, steps immediately to 200/s for thirty seconds, and tags both phases separately. The same VU pool retains its connections and account/store cursors through that transition; separate cold-client runs remain reconnection stress evidence. Read mix: scoped snapshots, paginated sale history, monthly rankings, inbox and inventory; 10% sales. The initial fixture cursor represents a previously downloaded cache. Each VU retains per-account/store cursors, applies snapshot pages before advancing them, and restarts expired pages. A sale's committed cursor never substitutes for a completed read. Fixture selection spans all 500 stores/5,000 accounts.

For a route smoke check only, set `STEADY_DURATION=10s BURST_DURATION=5s STEADY_RATE=5 BURST_RATE=10`. Short smoke runs are not capacity evidence. k6 is pinned to 2.3.0 with the official Linux x64 checksum.

Record p95 reads ≤300 ms and writes ≤700 ms separately for steady and burst workloads, HTTP/business failures and dropped iterations. Preserve k6 output, database counts/size, CPU/RAM/I/O, host specification, image/commit and server logs with credentials excluded. After load, the verifier compares lot quantities/versions to movements, balances to points entries and sales to revisions. Verify on the reference VPS with its deployed API topology and workers before claiming 500-store readiness. Host measurements do not establish VPS capacity.

For the isolated full-stack VPS lab, `SYNTHETIC_PROXY=yes` distributes the 500 synthetic stores over reserved benchmark IPs. This option refuses all URLs except `https://load.biobalance.invalid:<port>`. The lab resolves that host to loopback, trusts its test CA, and has a private Nginx configuration trusting the synthetic header only from its Docker gateway. Production Nginx must never trust this header. Rate limits remain enabled; do not use a certificate-verification bypass or point this workload at the live API.

`vps-qualification.sh smoke|acceptance` runs against that prepared lab, verifies the two-million-sale minimum and certificate trust, captures resource usage, and stops if shared-host reserves fall below 12 GiB disk/1.5 GiB available memory or the live API fails three probes. It records failed thresholds and runs the ledger verifier even after a failed measurement. The load generator shares the reference host; include its overhead in the interpretation.

If the initial generator is interrupted between historical batches, `LOAD_RESUME_SEED=yes` can resume the same isolated database. It requires 5,000 synthetic-only accounts, the expected directory/lot counts, equal committed history counts at a 50,000-sale boundary, no sessions, no balance/cursor projections, and no accepted API operations. An already exercised load database is rejected. No existing history is removed or rewritten; this option is not an application-data migration.

## Local persistence benchmark

```sh
cd apps/mobile
flutter test test/performance/local_workflows_benchmark.dart
```

This records host timings in `build/local-benchmark.json`: four cached stores, 200 products/600 lots/100 recent sales each, 120 durable queued sales, cached search, store switching and SQLite reopen. It excludes native startup and rendering. Physical device gates and capture procedure are in `tests/performance/devices.md`.

Pour réutiliser la base synthétique conservée après expiration des sessions, appliquer les migrations puis exécuter `LOAD_OWNER_DATABASE_URL=... node tests/load/refresh-sessions.cjs`. Le script vérifie les identités `load-N@example.test`, renouvelle les seules sessions des fixtures et reprend les curseurs courants ; il ne reconstruit ni ne supprime les historiques.

## External client for the shared VPS

A co-located k6 client competes with the API for the shared eight CPUs. Preserve those diagnostic results. For an external measurement, keep the same application images, dataset, workload, TLS checks, resource guards and latency thresholds. The lab's JSON responses use gzip at level 1; account-access routes on production remain outside that compression location.

Install `vps-qualification.sh` as `/opt/biobalance-load-lab/qualify-external.sh`. Copy only the synthetic `fixtures/load.json`, the public test certificate and a k6 hosts configuration mapping `load.biobalance.invalid` to `127.0.0.1` into a private local directory as `fixtures.json`, `ca.pem` and `k6-config.json`. Keep fixture permissions at 0600. Refresh expired synthetic sessions/cached cursors before copying when needed; preserve all business history.

Open the private tunnel in another terminal:

```sh
ssh -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -N \
  -L 127.0.0.1:18443:127.0.0.1:18443 go2code
VPS_LOAD_CLIENT_DIR=/absolute/private/client-directory \
  bash tests/load/vps-client-qualification.sh
```

The client starts the server-side resource guard, runs the unchanged five-minute steady and thirty-second burst scenarios, stops if that guard fails, and sends the k6 result before signaling completion. The observer has an eight-minute deadline and always checks the database ledgers. Both client thresholds and server/ledger exit status must pass. External timings include the network/tunnel round trip; save them alongside the topology and resource traces. Close the owned tunnel, archive results, and remove only the disposable lab after verification.
