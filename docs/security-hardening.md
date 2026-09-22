# BioBalance security and signing

Decision, 22 September 2026: BioBalance uses the VPS for its application, database, media and notification inbox. Firebase is removed from the mobile dependencies, backend, worker and deployment configuration. Android distribution will use both Google Play and private APKs.

## Implemented boundaries

| Threat | Control in this version | Practical boundary |
|---|---|---|
| Unauthorized accounts or stores | Revocable sessions, administrator MFA, current permissions inside transactions, scoped media/exports, database RLS | A genuine app is never a substitute for user authorization |
| Repeated operations or concurrent edits | Stable operation identity/payload checks, versions, bounded transaction retries, append-only ledgers | Lost responses can be retried without repeating accepted stock/points effects |
| Bulk scraping and resource abuse | PostgreSQL account budgets shared across replicas and sessions; stricter export/snapshot limits; Nginx IP/connection/body/time limits; existing password/upload quotas | An authorized person can still copy information they are allowed to read; this bounds volume rather than promising impossible extraction prevention |
| Network interception | Release HTTPS requirement, ordinary certificate/hostname validation, TLS 1.2/1.3 at Nginx, cleartext disabled in Android release and iOS ATS, no automatic API redirects, same-origin credentialed requests | Certificate pinning is not configured; compromised devices or compromised trusted certificate authorities remain outside this claim |
| Unofficial updates or modified packages | Separate RSA-4096 app/upload keys; checked-in public certificate fingerprints; signature and whole-bundle entry verification; APK v2 signatures | App signing proves the package publisher to the installer, not the authenticity of an arbitrary HTTP client |
| Reverse engineering | Flutter release obfuscation, R8 shrinking, private symbol output, packaged ELF debug-section checks | URLs, public certificates and client behavior are discoverable; no backend authority or reusable shared API secret is placed in the APK |
| Accidental data disclosure | Android secure window flag, iOS app-switcher cover, OS-protected token storage, disabled cache/outbox backups, no-store API/media responses, redacted logs | iOS screenshots cannot be universally blocked; SQLite and downloaded media still rely on the OS application sandbox/device encryption rather than SQLCipher |
| Server resource exhaustion | Private database ports, restricted DB identity, container resource limits and media isolation, bounded payloads/timeouts, compressed JSON bodies refused | A single VPS still requires upstream network/DDoS protection from its hosting provider |

Request budgets are centralized in `apps/api/src/shared/infrastructure/request-budget.ts`. One-minute windows allow 1,200 requests per account in total, with category ceilings of 360 reads, 180 writes, 600 sync operations, 600 media requests, and 12 reports/exports or initial snapshot creations. Snapshot pages use the ordinary read budget. Sync batches consume their operation count. Windows can permit a burst around a boundary; these are not strict sliding-window limits. Rejected requests do not prolong the window. HTTP 429 includes a French message and `Retry-After`; queued work stays under its original identity. Logout remains available even after a budget is exhausted. Expired counters are removed by maintenance.

At Nginx, generic traffic is limited to 50 requests/second per IP with a burst of 100; identity and upload routes have separate stricter policies, including case variants. Logout uses the general flood limit independently of the login/recovery limit. These values allow shared store connections, but unusually large shared networks may need measured tuning. The ingress must overwrite forwarded headers, and API ports must remain private. Bypassing Nginx bypasses its IP limits, not the API's account limits.

## Android keys and distribution

The initial private key material was created locally at `/home/haydar/.local/share/biobalance/signing` with owner-only permissions. It is outside the repository, Docker context and release packages. Passwords are randomly generated and read from protected local files; they are never printed or passed as literal command-line arguments. Signed builds disable reusable Gradle daemons; automatic Gradle heap dumps are disabled, and dump files are excluded from Git/Docker. Only the public certificate fingerprints are versioned in `config/signing/android-certificates.json`.

- `app.jks`: signs private APKs and must also become the Google Play **app signing key**.
- `upload.jks`: signs AAB uploads. Google Play signs the APKs it distributes with the app signing key, not this upload key.
- `identity.json` and the password files: private build configuration. Retain these together with both keystores in a secure encrypted backup before public distribution. No external backup has been made by this task.

During the first Play App Signing enrollment, select the option to supply your existing app signing key and follow Google's current PEPK export/import procedure. Do not allow Play to generate a different app signing key if cross-channel updates must work. Register the separate upload certificate. Verify the app-signing SHA-256 shown in Play Console against the reviewed file. Use one increasing version-code sequence for APK and Play releases. Test upgrades in both directions before the pilot. Future Play key upgrades require an explicit cross-channel signing-lineage plan.

Once the real API domain is configured:

```sh
python3 scripts/build-signed-android.py config/mobile/android.local.json /home/haydar/.local/share/biobalance/signing
```

Signed releases require a clean, committed checkout. The build checks the expected key identities before compiling, signs APK/AAB with their respective keys, verifies every bundle entry, checks APK integrity/certificate and native alignment/debug sections, and generates checksums. A changed signing identity requires an explicit update to the reviewed public fingerprints. The provisioning script refuses to overwrite any existing directory; do not create a replacement app key to solve a password/path error.

Private symbol files are kept under `.artifacts/private-symbols/` and must be retained securely for crash symbolication. They are not copied into the APK. Treat AABs, source packages and any Play debug metadata as developer artifacts; distribute only the intended APK to private users. Compilation-only and signature-test artifacts target `https://api.example.invalid` and cannot serve as pilot releases.

## iOS

A real Apple developer team, distribution certificate/profile and macOS/Xcode host are still required. `scripts/build-mobile-release.sh` exports the IPA; `scripts/verify-ios-signature.py` verifies its code signature, team, bundle identifier, entitlements and disabled debugger entitlement. The privacy cover and ATS settings are implemented but require native iOS verification. No Apple signing identity has been invented or generated on this Linux host.

## Notifications without Firebase

Messages are committed to the authorized VPS inbox. The open notification screen refreshes every four seconds, and reopening it retrieves current messages. Staff still receive only deliberate manager announcements; automatic operational messages remain scoped to managers/admin. The client makes no push-provider registration calls. New events do not enqueue unavailable push work. Legacy push jobs are drained with an explicit `push.skipped / inbox_only` diagnostic; no successful device-delivery receipt is fabricated and inbox history is retained.

Android does not guarantee that an arbitrary background connection remains alive after the app closes. Reliable closed-app Android alerts need a separately chosen OS push approach; that feature is deferred. Apple APNs could be called directly from the VPS without Firebase if later requested and configured. Email invitations/recovery continue through SMTP. SMTP is unrelated to Firebase.

## Remaining activation and verification

- Configure the owned API domain, publicly trusted TLS certificate, SMTP and VPS firewall/SSH/monitoring; run the existing renewal/restore procedures on that VPS.
- Securely back up the Android signing identity, enroll Play App Signing with the matching key, and verify real cross-channel upgrades and verified account links.
- Obtain the Apple team/signing environment and run iOS build, ATS, privacy, media and device tests.
- To require server-verifiable proof of the official client/device, integrate and validate Play Integrity and Apple App Attest using their respective platform accounts. Neither requires Firebase. Private APK acceptance and offline synchronization must be tested explicitly. There is no fake fallback based on an app name, User-Agent, embedded secret or self-reported signature. **Attestation is not active in this version.**
- TLS certificate/public-key pinning would require the real domain, active and backup pins, a rotation/recovery plan and coverage of both Dart transfers and native video. It is not represented as implemented.
- Perform a deployment-specific penetration test and physical-device verification before production acceptance. Existing automated checks provide evidence of the tested scenarios, not a guarantee against all vulnerabilities.

Off-server business-data backups and high availability remain deferred. Local restore tests do not establish recovery from total VPS loss. Signing-key backup is a separate release prerequisite because losing the private app key can prevent private APK updates.
