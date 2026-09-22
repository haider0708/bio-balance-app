# Isolated deployment validation

From the repository root, with Docker Compose ≥2.24.4, Node 24, the pinned Flutter toolchain, Python 3, OpenSSL, ffmpeg and ffprobe available:

```sh
npm ci
(cd apps/mobile && flutter pub get --enforce-lockfile)
bash tests/deployment/run.sh
```

The harness uses only project `biobalance-release-lab`, a database ending in `_deployment_test`, private database/media volumes and loopback ports 18080/18443/18025. It does not remove volumes, overwrite existing lab credentials, or affect the development database. Repeated runs retain their data and renew only the existing manager/outsider fixture sessions after checking the exact isolated database name and synthetic account markers. Production inputs and real recipients are never used.

Images are fully built before containers start. The rollback uses application source `a8b4610` with the corrected runtime packaging and the current additive schema; set `ROLLBACK_REF` to another reviewed compatible commit for a future exercise. The test records continuous authorized reads while replacing both APIs, then both workers. It verifies image identity, repeats the accepted sale, returns to the current images and checks stock/points/media again.

The fixture provisions an administrator through the real bootstrap command and logs in with TOTP. Consecutive serial probes wait for a new TOTP counter, preserving the server's replay protection. It creates a store/product, receives ten units, sells six with a repeated submission, processes an image and H.264 video in the constrained media worker, verifies protected delivery and ranges, and sends a synthetic invitation to Mailpit. Flutter interrupts and resumes a real video through Nginx after reopening SQLite, using the server's opaque ETag and a final SHA-256 check.

The recovery checks exercise stale leases, failure diagnostics, guarded failed-job replay, rolling restarts, local certificate replacement, a database/media backup, and isolated restoration. Restored files must match stored size/SHA-256; representative stores, sales, revisions, movements, stock versions, points and media fingerprints are compared with the source snapshot.

Evidence is stored under `.artifacts/evidence/step11/`. Credentials, tokens, certificates and backups are private under `.artifacts/deployment-lab/` and must not be uploaded as CI artifacts. The local certificate test verifies installation/reload; real ACME issuance, renewal, VPS firewall/SSH, remote monitoring and production SMTP require deployment inputs and remain pending. Firebase is not used; closed-app OS alerts are deferred. Same-server backup does not prove recovery from complete VPS loss.
