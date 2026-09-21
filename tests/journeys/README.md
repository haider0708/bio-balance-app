# Native acceptance journeys

The test harnesses use only databases whose names end in `_journeys_test`. All users, invitations, products and media are synthetic. They start a real Nest server with restricted PostgreSQL credentials. Test-only endpoints exist only in the harness process, bind to loopback, require a random per-run key, and are never imported by the application.

## Run on an Android emulator

```sh
npm ci
npm run db:generate
bash scripts/setup-journey-db.sh
cd apps/mobile && flutter pub get --enforce-lockfile && cd ../..
npm run test:journeys
npm run test:android-restart
```

Requirements: Node 24, pinned Flutter, Java 17, Android SDK/emulator, PostgreSQL 17 on port 54329, and ffmpeg/ffprobe on PATH. `FLUTTER_BIN`, `ANDROID_HOME`, `ADB_BIN` and `TEST_DEVICE` may select local tools; device defaults to `emulator-5554`. The host API is reached through Android's `10.0.2.2` alias. For the role journey on a macOS iOS simulator, set `TEST_DEVICE` to its UDID and `TEST_API_HOST=127.0.0.1`; this configuration is prepared but has not been executed locally. Physical devices require a separate network configuration and are not implied by these tests.

The scripts preserve existing database fixtures and create unique identities per run. They never clear the application database; a fresh account owns each journey. Run only against a dedicated test application/emulator: the role journey clears test login credentials, and the restart probe intentionally force-stops `tn.biobalance.app`.

## Coverage and assertions

| Scenario | Evidence |
|---|---|
| Administrator → manager → seller | Real MFA login, manager invitation/activation, store setup, catalog, training publication, opening receipt, pricing/points, staff invitation, reward, replenishment/dispatch/reception, sale/correction/return, redemption/handover, announcement/inbox and access revocation from an open editor |
| Business effects | Original seller attribution, three revisions, one physical delivery receipt, fulfilled product reward, 21 remaining stock units, 20 points, no reservation |
| Actual Android process termination | Persist an offline sale, record its ID/payload checkpoint, force-stop the process, relaunch, assert identical outbox bytes before sync and one server acceptance (stock 7/version 3, points 30) |
| Native camera denied | Permission pre-denied on the emulator; camera error state and manual product selection remain usable |
| Native video | Process H.264 through the real worker component, stream/play, verify downloaded bytes, reopen offline with a file-backed player and advancing playback position |
| Storage exhaustion | `storage_fault_test.dart` limits actual SQLite pages, verifies atomic rollback, preservation of the existing outbox and draft, then successful recovery |
| UI navigation race | Completing a save during Back's exit animation cannot pop the previous screen |
| Layout/accessibility | Stock, sales, orders, rewards, team, training and catalog at narrow/landscape sizes, 200% text, keyboard inset and labeled actionable semantics |
| Transport faults | Separate `npm run test:mobile-sync`: lost accepted response, lost snapshot response, reopen SQLite, missing batches; unit/database suites cover concurrency, expired/revoked sessions, account switching and interrupted transfers |

The first phase intentionally loses its app connection after the acknowledged durable checkpoint. The harness verifies a running Android PID before force-stop and its absence afterward; Flutter may return zero even after this disconnect, so its first exit code is not treated as a test result. A missing checkpoint, unverified termination, failed second phase or incorrect database effects fails the harness.

The CI Android emulator job runs both native probes. Logs, reference hardware profiles, manual screen-reader use, physical camera scanning, iOS native execution and real FCM/APNs remain separate evidence; an emulator pass does not establish those release gates.
