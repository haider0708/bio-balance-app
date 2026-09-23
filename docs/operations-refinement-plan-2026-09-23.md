# BioBalance — operational refinement plan

Status: implementation and validation in progress after explicit approval. The release candidate is 1.1.7+11; the installed apps remain 1.1.6+10 until verification and installation. The user confirmed: implement first, then reset business data including groups/stores, keeping all four accounts, credentials/MFA and the 51-product catalog. No production reset has yet occurred.

## 1. Confirmed roles and scope

The three installations remain independent sessions of the same application and backend. Package labels never grant permissions.

| Role | Responsibilities |
|---|---|
| Administrator | Network/group/store reporting, partner access, teams, suspension/archive, order preparation and dispatch, delivery-issue resolution, global catalog/training and audit |
| Responsible person | All stores in their group, teams, inventory, replenishment requests, actual delivery reception, store settings, points/rewards and deliberate announcements |
| Salesperson | Assigned stores, new sales, their own sale corrections/returns, personal points, reward requests and training |

The owner confirmed that sellers retain their own corrections/returns and reward requests. Remove delivery reception and management actions from their UI and server permissions. The responsible person performs routine physical reception. Admin preparation/dispatch never substitutes for physical reception or adds store stock.

Administrator location is explicit: network → group → store. Keep the group selector in the upper-left header; stores are entered from their group's list. Changing group clears the previous store. Every dashboard, list, chart, export, alert and detail route carries its own validated scope and period. Old responses cannot populate a different selection. Back restores the preceding scope, filter and scroll position.

## 2. Findings in the current code

| Area | Verified existing behavior | Remaining change |
|---|---|---|
| Email codes | Invitation expiry 48 hours; recovery expiry 30 minutes; expiry/use checked again inside the transaction; conditional consumption prevents double use; resend replaces older codes | Retain enforcement; show expiry/used guidance and cover simultaneous/boundary cases |
| Reporting | Server-scoped sales totals, units, top five products by net units, Tunisian date filters, sale/store/seller attribution | Test each drill-down and archived-entity history; keep the group summary concise and store analysis complete |
| Dashboard alerts | Rows call the comparison/store callback, explaining the reported redirect | Open the exact alert with its cause and permitted resolution action |
| Lifecycle | Memberships can be disabled; last responsible person is protected | Groups/stores lack suspension/archive fields and centralized inherited access rules |
| Orders | Create, prepare, dispatch and receive exist; physical receipt is unique per delivery | Add explicit amendment/cancellation/incident operations and state validation |
| Missing delivery | A zero-unit receipt currently finalizes that delivery as received | Add a separate non-reception report that does not finalize reception or add stock |
| Cancelled orders | UI has a cancelled status; dashboard/supply queries use `status != received` | Exclude cancelled quantities from active counters/supply and disallow invalid transitions |
| Notifications | Per-recipient inbox and read timestamps exist | Bell has no unread badge; its count must be available without opening the inbox |
| Seller access | Seller memberships currently include `receive`; personal dashboard shows deliveries | Migrate effective permissions and remove delivery/order/management destinations |

Relevant code: `identity.service.ts`, `dashboard.service.ts`, `dashboard_screen.dart`, `attention_screen.dart`, `group.service.ts`, `operations.service.ts`, `order-fulfillment-query.ts`, `notifications.service.ts`, `notifications_view_model.dart`, and `scope_screen.dart`.

## 3. Email-code rules

- A code becomes invalid at the earlier of its expiration or successful use. Opening the email/link or entering a wrong password must not consume it.
- Validating and consuming the code, activating access/changing the password and writing the security audit happen in one transaction. Two devices cannot successfully consume it twice.
- Resending invalidates previous unused codes. Activation also checks that the issuer, group and invitation are still authorized.
- Keep code hashing, bounded attempts and password-recovery session revocation. The app's clock is not authoritative.
- Use clear French messages for expired/already-used codes and a route back to login or requesting a fresh code. Account actions require connectivity.

## 4. Dashboards and actionable alerts

Network dashboard: active groups/stores, net sales, net units, recorded sales, trend, best products and pending work. Group view: concise totals, stores and issues labelled by store. Store view: complete sales/product/stock/order/team analysis. Seller view: personal sales, points, rewards and training.

Every value shows scope and period. Current stock and pending work are separate from period-based sales. Returns reduce the original sale period; historical sales remain reportable after a store/member is archived. Do not count cancelled orders as pending. Best-product ranking states its measure (net units); opening a product or sales metric retains scope/date filters. Unknown/offline data is never displayed as a confirmed zero.

An alert detail must show the group, store, relevant product/lot/order, exact condition, quantities, occurrence time and current state. The destination must remain stable under refresh and be accessible directly from the dashboard or notification.

| Alert | Action |
|---|---|
| Low/out-of-stock | Product stock and outstanding supply, then a replenishment draft |
| Stock discrepancy | Movement history and audited reconciliation |
| Approaching/expired lot | Exact lot, expiry and appropriate damage/withdrawal workflow |
| Missing/partial/damaged delivery | Delivery issue, expected versus actual quantities, reason and follow-up |
| Reward awaiting handover | Exact request and fulfillment/rejection actions |
| Synchronization conflict | Exact pending operation, cause and authorized resolution |

Reading a notification does not resolve its underlying alert. Operational alerts resolve when their condition is corrected. Delivery issues close through a recorded decision; no generic dismiss action may pretend that stock or a physical receipt has been corrected. Resolved history remains available, without duplicate alerts on every refresh.

## 5. Groups, stores and team lifecycle

Introduce explicit active, suspended and archived states for groups/stores, with record versions, actor, timestamp and reason. Suspension blocks access to that workspace and its operations for responsible people/sellers; the admin can inspect history and reactivate it. Suspending a group applies to its stores without rewriting their individual membership choices. Reactivation must not restore memberships that were separately disabled.

Use archive for deletion of entities with business history. Remove them from ordinary active lists but preserve attributed sales, stock movements, receipts, points and audits. Restrict permanent deletion to unused drafts or entities proven to have no business dependencies. Do not expose a generic cascading database delete.

Before archival, display outstanding deliveries, orders, reward reservations and recorded stock, and require their disposition. Suspension can be immediate; unresolved work stays visible to the admin. Protect the last platform administrator and the last responsible person of an active group.

Distinguish removing a member from one group/store from disabling their account everywhere. An action in one group must not unexpectedly remove another group's access. Show scope and affected counts before confirmation.

Enforce lifecycle rules in shared server authorization, transaction/RLS context, invitation activation, synchronization, files/exports and notification workers. Hiding buttons alone is insufficient. On reconnect, an offline device with revoked access must block affected submissions and retain them for review under the original actor.

## 6. Orders and physical deliveries

An order is a store's request. A delivery is an identified physical shipment; one order may have several deliveries. A receipt is the recorded arrival of one shipment. Keep those identities distinct.

Administrator list: **Toutes**, **À préparer**, **Expédiées**, **Problèmes**, **Terminées**, with group/store filters and optional grouping. Show order reference, group, store, date, status, units and one relevant next action. Responsible list uses the same history with **Nouvelle commande** and clearly marked receptions.

Order detail shows product photographs, requested quantities, shipment quantities, actual accepted quantities and the remainder; progressive disclosure keeps the main screen compact. Include a chronological history of amendments, dispatches, reception and incidents.

| Action | Rule and stock effect |
|---|---|
| Submit request | Responsible person chooses product quantities; admin is notified; no stock change |
| Amend/prepare | Admin adjusts the planned quantities with a recorded revision/reason; preserve the original request and already fulfilled quantities |
| Dispatch | Create a unique shipment containing the actual quantities sent; no store stock change |
| Receive | Responsible person confirms actual quantities, lots and expiries; one atomic receipt adds stock once |
| Report not received | Reason/date and admin notification; shipment remains unresolved, no receipt and no stock change |
| Partial/problem reception | Record actual accepted units and differences, with traceable damaged/non-sellable units; missing/damaged supply remains an issue to settle |
| Follow-up shipment | Admin sends only the remaining approved supply, after accounting for actual accepted units and quantities still in transit |
| Cancel | Cancel an unfulfilled request/remainder with a reason; do not erase an existing shipment or receipt |

The admin resolves non-reception by tracing the shipment, marking it lost/returned with a reason, sending a replacement, or cancelling the unresolved remainder. Reporting a delay must not permanently consume the delivery's one reception. If the original shipment arrives later, verify its current state and settle any replacement before accepting an additional physical receipt.

Use explicit allowed transitions. Completed/cancelled orders cannot be prepared or dispatched again. Quantity amendments cannot reduce below settled/in-transit commitments. An accepted physical reception is corrected through audited adjustments/returns, never by deleting its stock effects.

Keep order states `requested`, `preparing`, `dispatched`, `partial`, `received` and `cancelled`, adding a terminal `closed_partial` for an accepted partial supply whose remainder is explicitly cancelled. Active delivery issues are separate from order state. Deliveries distinguish `dispatched`, `received`, `lost` and `returned`; issues distinguish open, in progress and resolved. A reported delay does not change a shipment into `received` or `lost` without a resolution decision.

For each product, remaining dispatch is the current approved quantity minus accepted units, units still committed to active shipments and an explicitly cancelled remainder, bounded below by zero. Track damaged/refused/surplus units separately rather than silently satisfying the request with them. The order closes only when no approved remainder, active shipment or unsettled reception issue remains. Existing accepted zero-unit receipts retain their identity/history; do not automatically reinterpret or reopen them during migration.

Example: request 20, dispatch 15 → stock unchanged. Receive 12 → stock +12, 3 missing, 5 not dispatched. Resolve the missing shipment before treating its 3 units as available for replacement. With no remaining transit commitments, 8 units remain to fulfill. A retry of the 12-unit receipt must not add another 12.

## 7. Notifications and UI

Give the bell a small unread count (bounded display such as 99+), an accessible label and no badge when the count is zero. Count authorized unread notifications across the account's accessible stores; show the group/store on each inbox item. Opening a notification marks that notification read and navigates to its exact authorized target. Read state must not close operational work.

Use one account-bound foreground notification state, refreshed through the existing communication/sync lifecycle with bounded retries. Avoid independent polling timers in each screen, stop background polling, and show cached state offline. Handle simultaneous devices, logout, permission changes, expired sessions, duplicate events and cursor ties. Automatic operational notifications go to responsible people/admin; sellers receive deliberate announcements from their responsible person.

Preserve white/mint/emerald surfaces, product photographs, clear outline icons, readable compact rows, labelled actions and short reduced-motion-aware transitions. Prefer verbs such as **Expédier**, **Confirmer la réception**, **Signaler non reçue**, **Modifier les quantités**, **Annuler le reliquat** and **Archiver** over ambiguous **Valider** buttons.

Seller navigation remains **Accueil, Ventes, Récompenses, Formation**. Remove delivery and management tiles/routes/actions from seller screens and enforce the same restriction server-side. Responsible/admin screens expose only actions valid for the selected record's state.

## 8. Synchronization and compatibility

- Retain operation IDs, payload bytes, dependencies, account/store ownership and pending drafts through upgrades.
- Save the local command and provisional effects in one SQLite transaction. Keep confirmed reporting separate from pending local activity.
- Retry the same command without regenerating its ID. Server deduplication and unique physical-receipt constraints prevent repeated effects after lost responses or simultaneous devices.
- Check record versions and current permissions within the accepting transaction. Conflicts block their dependents while unrelated operations can continue.
- Apply server data, acknowledgments and removal of provisional effects atomically. Persist cursors and backoff; snapshots remain bound to account/store and access is rechecked.
- Group/store lifecycle changes must invalidate affected cached access and protected routes. Offline devices cannot learn suspension until they reconnect; queued work is preserved and quarantined rather than silently accepted or deleted.
- Previously queued seller reception commands must not be rewritten under a manager's identity. Expose them for authorized review and check whether the shared physical receipt was already accepted before any corrective operation.
- Permission changes, suspension/archive, dispatch/cancellation decisions and reward reservation/fulfillment require online confirmation. Sales and downloaded-delivery reception retain their established offline path for authorized roles, visibly pending until accepted.
- Notification-read state may queue separately without blocking sales. No background refresh may change the user's navigation context.

## 9. Implementation order and acceptance evidence

1. Lock typed role/lifecycle/order/incident contracts and state transitions; add expiry/concurrency regression tests.
2. Add additive PostgreSQL/SQLite migrations and centralized access checks, preserving live history and legacy outbox envelopes.
3. Complete order amendment/cancellation, issue reporting, follow-up fulfillment and transactional notifications. Fix pending-order/supply calculations.
4. Connect exact alert details/actions, scope-preserving dashboard drill-downs and the shared unread bell.
5. Apply seller restrictions and the complete role-specific UI, including loading/empty/error/offline/permission-loss states.
6. Run domain/database, contracts, migration, Flutter, Android journeys and visual/layout checks. Verify all three installed accounts without resetting their data.
7. Back up and deploy compatible backend changes, then install a new signed Android version and record actual test evidence. Record unavailable physical/iOS checks separately.

Required scenarios: code deadline/first use/resend/concurrent consumption; network→group→store switching under slow responses; product and sales drill-down reconciliation; each alert resolution; every order state/action and cancelled-counter case; receipt/partial/non-reception/replacement/late-original arrival; simultaneous receivers; disabling and restoring a group/store/member with pending work; cross-group denial; unread counts across devices; seller denied management via direct API calls; offline save, process termination, response loss, retries, access loss, database migration and low-storage failures. Review narrow/landscape screens, keyboard, 200% text, semantic labels and reduced motion.

No claim of being free of future bugs is a release gate. Release evidence must show the defined behaviors, integrity invariants and recovery scenarios passing; failures and pending external checks remain explicit.
