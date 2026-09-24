# Operational refinements — implementation record

Candidate: **1.1.7+11**. The backend and migrations are deployed; all three signed Android installations are updated. The live reset remains pending final journey checks and reconnection of the Samsung. This record is updated with execution evidence before handover.

## Approved reset and preservation

The owner explicitly requested implementation first, then removal of groups, stores and test business data. All four User rows, passwords, MFA state, 51 products and catalog media must remain identical. Existing responsible accounts receive unused group-creation grants. The seller keeps their existing account and joins the newly created store through a fresh invitation. Sessions are revoked and only the three BioBalance Android installations are cleared at the final reset. Authenticator and other applications remain untouched.

Use `scripts/reset-business-keep-accounts.sql`, never the older administrator-only reset. It locks an explicit reviewed table inventory, checks account/catalog counts, uses one transaction, preserves User/Product/catalog MediaAsset rows through bidirectional SQL comparisons, and writes a maintenance audit linked to the backup. It cannot run from the application API. It fails closed on a changed schema or unexpected dependency.

## Delivered behavior

- Invitation/recovery codes expire at their deadline or first successful use. The final conditional update rechecks expiry; tests cover simultaneous use and expiry during validation.
- Effective seller access excludes reception and management, including legacy grants, API writes, snapshots, order reads and UI. Own-sale corrections/returns and rewards remain available.
- Admin suspension/archive for groups and stores, reason/version/audit, impact preview, inherited access checks, and historical admin reads. Archival requires settling stock, orders, shipments, incidents and reward reservations. Group/store lifecycle does not rewrite separately disabled memberships. Existing last-responsible protection remains enforced.
- Exact alert pages from dashboards/inbox, with product/stock or delivery follow-up actions. Orders have scoped lists, explicit preparation/dispatch, amendments preserving original requested quantities, cancellation of only the free remainder, receipts, incidents and audit history.
- Missing delivery is an incident, with no receipt or stock change. It can still arrive later. Partial shortages remain committed until the admin settles the issue. Lost/returned shipments release supply for replacements, and an already replaced original cannot be received again accidentally.
- Receipt lines distinguish accepted sellable units, accepted damaged stock and units refused to the carrier. Damaged/refused/surplus differences require a reason. Only accepted sellable units, capped at the shipment quantity, satisfy approved supply; actual surplus stock remains traceable with an open issue. New/legacy offline receipt projections use the same buckets and version increments as the server.
- Shared account-bound foreground notification feed, unread bell badge, tied-date pagination, exact destinations and invalidation when the authorized audience changes. In-app notifications remain the agreed channel; no Firebase dependency is added.
- Stable operation IDs/payloads, transactional acknowledgments and permission checks. Retrying an uncertain online action settles the original payload and explicitly reports when later edited values have not been submitted.

## Additive migration and compatibility notes

`202609240001_operational_refinements`: lifecycle fields, original/cancelled order lines, scoped delivery issues, removal of seller reception grants. `202609240002_notification_targets`: typed destinations, unread index and active-group RLS read conditions. `202609240003_operation_indexes`: unique lifecycle operation identities and unresolved-order issue index.

Legacy v1/v2 queued envelopes and accepted results remain readable. An old zero-line reception that was already accepted is not reopened or rewritten. A newly submitted zero-line reception is handled as a non-reception report. Receipt condition is optional; historical lines default to sellable. All API instances must be updated before installing the candidate: older APIs cannot interpret the newly introduced command types. Keep the prior images/environment for pre-rollout recovery; after accepting new commands, prefer a compatible forward fix over routing the candidate to an old API.

## Verified evidence

- Fresh restricted-role PostgreSQL suite: **117 passed**, including identity/security, transactions, media, workers, notifications and eight operational regressions.
- Flutter analyzer: **no issues**. Full Flutter suite: **267 passed**, four environment-dependent tests skipped here and executed through their dedicated harnesses.
- HTTP contract harness: **64 endpoints passed**, generated Dart decoding, protected images/ranges, lifecycle, exact alerts and inbox included.
- Real HTTP + SQLite + PostgreSQL recovery: **2 passed**; five dependent operations, six movements, three revisions, stock 7 sellable / 1 damaged at version 7, 20 points. Missing-batch sale creates no artificial receipt.
- Operations tooling: **6 passed**; release/backup/signing tooling: **38 passed**; catalog tooling: **14 passed**.
- VPS backup `20260923T205016Z-46c079ba`: checksums verified. Isolated restore verified **102 original/thumbnail media files** against sizes and SHA-256.
- The three migrations and reset were rehearsed on the isolated restore. Result: **4 accounts, 51 products, 51 catalog assets, 2 creation grants, 0 groups/stores/sales/sessions**. Full credential/catalog row comparisons passed. The live application database was untouched by this rehearsal.
- Android role journeys: **2 passed**, with actual database effects for all three roles, manager-only reception, seller corrections/returns, reward handover, announcements and access removal while editing.
- Manual screenshot review: orders, notifications, store access settings, order editor and stock entry are readable at phone width; layout tests include landscape/200% text. Lifecycle and mixed-condition receipt captures were also reviewed; form actions now remain above the keyboard.

## Execution still in progress

Native Android role/restart journeys; additional uncertain-response and lifecycle/receipt screenshot checks; generated drift verification; commit/push/CI; immutable images and compatible VPS rollout; signed three-app installation; final quiesced backup/reset and exact post-reset counts. Final evidence and any unavailable platform checks must be stated explicitly. Physical iOS, public store publishing, off-server backup and HA are outside this update.

## Final local checks

Full Flutter rerun after presentation review: **267 passed**, analyzer clean. The notification list now includes group/store labels, and navigation captures the freshly authorized target without switching the originating workspace. Receipt discrepancies display expected/accepted/damaged/refused/surplus quantities; unresolved commitments are labelled as engaged quantities rather than incorrectly calling them all in transit.

The native Android restart harness passed: force-stop/relaunch preserves the account, original outbox ID and payload; one accepted sale yields stock 7/version 3 and 30 points. A downloaded, integrity-verified H.264 training video plays offline on Android. Generated contract drift check passed. These are emulator results; they do not claim reference-device performance measurements.

Implementation commit `505795b` contains the backend and migrations. Backend images were built from that commit; subsequent changes are mobile presentation and evidence only. CI run `35919781530` passed backend and iOS checks while Android checks continued. Final CI outcome, deployment and phone/reset results are recorded in the handover evidence.

## Deployment and installation checkpoint

- Backend image `biobalance-api:505795b` and media image `biobalance-media:505795b` run on the existing VPS. All eight BioBalance services are healthy; 23 migrations applied. The application database role remains non-superuser with no RLS bypass, and DeliveryIssue uses forced row-level security. HTTPS health returns 200; unauthenticated protected endpoints return 401.
- Signed APK/AAB sets for Admin, Responsable and Vendeur were built from clean source `471a2cc` with version **1.1.7+11**. All three were installed over the Samsung copies; package UIDs and app data were retained. Admin and Responsable workspace launches passed before the phone disconnected. Vendeur launch and the final cache reset await reconnection.
- CI run `35920326511` passed backend, Android analysis/build and unsigned iOS compilation. The Android role journey exposed an account-switch timing assumption: a locally saved receipt was not necessarily synchronized before logging out. The test now asserts authoritative opening stock, order acceptance and physical reception before dependent cross-account work. The business effects and permissions assertions remain unchanged; the amended journey is being rerun.
- No live business data has been cleared at this checkpoint. [Manual retest instructions](manual-retest-1.1.7.md) describe the intended clean setup after the authorized reset.
