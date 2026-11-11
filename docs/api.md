# API reference

Every route is under `https://api.galylio.com`, JSON in and out, `Authorization: Bearer <token>` except where marked *anyone*. Errors have the shape `{ "code", "message", "fields?", "correlationId" }`; `code` is stable and is what the app translates. Amounts are whole millimes (1 TND = 1000). The "Who" column is enforced by the server; row-level security in the database additionally keeps each region apart.


## auth

| Method | Path | Who |
|---|---|---|
| POST | `/v1/auth/activate` | anyone |
| POST | `/v1/auth/forgot-password` | anyone |
| POST | `/v1/auth/login` | anyone |
| POST | `/v1/auth/logout` | any signed-in role |
| POST | `/v1/auth/reset-password` | anyone |
| GET | `/v1/me` | any signed-in role |
| PATCH | `/v1/me` | any signed-in role |
| POST | `/v1/me/password` | any signed-in role |
| POST | `/v1/me/delete` | any signed-in role (deletes their own account) |
| POST | `/v1/me/push-device` | any signed-in role (this phone receives push alerts) |

`POST /v1/me/delete` with `{ password }` erases what identifies the person (name, email, phone, password, two-step secret, sessions, codes, notifications, training progress), cancels their waiting payout requests and suspends the account for good; sales, stock and rewards stay, under "Compte supprimé #XXXX". The last active admin gets `LAST_ADMIN`. A deleted account cannot be reactivated, invited, edited or moved (`ACCOUNT_DELETED`); the admins are notified (`account.deleted`).

`POST /v1/me/push-device` with `{ token, platform: "IOS" | "ANDROID", sandbox? }` ties the phone's Apple device token (hexadecimal) or Firebase registration token to the current session (the last account signed in on a phone gets its alerts; ten phones per person at most). It answers `{ push }`: true when this server sends push alerts to that platform, in which case the app turns its own background check off. Signing out, a new password or a deleted account ends the session, and the alerts stop with it. The worker pushes each new notification once, in the person's language (`apps/api/src/core/notice-text.json`, the same wording as the app), with the unread count (on the iPhone icon, and as the notification count on Android); more than three at once become one summary, alerts older than half an hour are never sent, and a phone the push service reports as gone is forgotten.

## Public pages

`GET /privacy`, `/terms`, `/support`, `/account-deletion` (*anyone*): HTML in French or English (`?lang=fr|en`, else the browser's language), no script. The contact address is `SUPPORT_EMAIL`. `GET /c` is the page the code emails link to (opens the app on Android and iPhone).

## catalog

| Method | Path | Who |
|---|---|---|
| GET | `/v1/products` | any signed-in role |
| POST | `/v1/products` | admin |
| GET | `/v1/products/:id` | any signed-in role |
| PATCH | `/v1/products/:id` | admin |
| GET | `/v1/products/barcode/:code` | any signed-in role |
| GET | `/v1/products/families` | any signed-in role |
| POST | `/v1/products/import` | admin |

## directory

| Method | Path | Who |
|---|---|---|
| GET | `/v1/regions/overview` | admin (regions with their responsable and counts) |
| POST | `/v1/regions` | admin |
| PATCH | `/v1/regions/:id` | admin (rename) |
| DELETE | `/v1/regions/:id` | admin (only when empty) |
| POST | `/v1/users/:id/move` | admin (a responsable to another region; `swap` to exchange with its responsable) |
| POST | `/v1/pdvs/:id/move` | admin (`regionId`, optional `groupId` of the new region) |
| POST | `/v1/groups/:id/move` | admin (with all its stores) |
| POST | `/v1/depots/:id/move` | admin |
| GET | `/v1/depots` | admin, responsable (own region) |
| GET | `/v1/depots/:id` | admin, responsable (own region) |
| POST | `/v1/depots` | admin |
| PATCH | `/v1/depots/:id` | admin |
| DELETE | `/v1/depots/:id` | admin (only if never used) |
| GET | `/v1/groups` | admin, responsable |
| POST | `/v1/groups` | responsable |
| PATCH | `/v1/groups/:id` | admin, responsable |
| POST | `/v1/groups/:id/approve` | admin |
| POST | `/v1/groups/:id/reactivate` | admin |
| POST | `/v1/groups/:id/reject` | admin |
| POST | `/v1/groups/:id/resubmit` | responsable |
| POST | `/v1/groups/:id/suspend` | admin |
| GET | `/v1/pdvs` | admin, responsable, vendeur |
| POST | `/v1/pdvs` | responsable |
| GET | `/v1/pdvs/:id` | admin, responsable, vendeur |
| PATCH | `/v1/pdvs/:id` | admin, responsable |
| POST | `/v1/pdvs/:id/approve` | admin |
| POST | `/v1/pdvs/:id/members` | responsable |
| POST | `/v1/pdvs/:id/reactivate` | admin |
| POST | `/v1/pdvs/:id/reject` | admin |
| POST | `/v1/pdvs/:id/resubmit` | responsable |
| POST | `/v1/pdvs/:id/suspend` | admin |
| GET | `/v1/regions` | any signed-in role |
| GET | `/v1/users` | admin, responsable |
| POST | `/v1/users` | admin |
| GET | `/v1/users/:id` | admin, responsable |
| PATCH | `/v1/users/:id` | admin, responsable |
| POST | `/v1/users/:id/approve` | admin |
| POST | `/v1/users/:id/reactivate` | admin |
| POST | `/v1/users/:id/reject` | admin |
| POST | `/v1/users/:id/resend-invite` | admin, responsable: a team member gets a **new generated password** (old one dead, sessions ended), anyone else a new code |
| POST | `/v1/users/:id/suspend` | admin, responsable |

## media

| Method | Path | Who |
|---|---|---|
| GET | `/v1/media/:id` | any signed-in role |

**Media.** Proof files (`purpose=PROOF`) may be JPEG, PNG, WebP or **PDF** (12 MB). `GET /v1/media/:id/info` returns `{ id, mime, fileName, size }` for whoever may open the file, so a client can show a document card without downloading it.

## messaging

| Method | Path | Who |
|---|---|---|
| GET | `/v1/messages` | admin |
| POST | `/v1/messages` | admin |
| DELETE | `/v1/messages/:id` | admin |
| GET | `/v1/messages/:id/recipients` | admin |
| POST | `/v1/messages/preview` | admin |
| GET | `/v1/notifications` | any signed-in role |
| POST | `/v1/notifications/:id/read` | any signed-in role |
| POST | `/v1/notifications/read-all` | any signed-in role |
| GET | `/v1/notifications/unread-count` | any signed-in role |

## reporting

| Method | Path | Who |
|---|---|---|
| GET | `/v1/approvals` | admin |
| GET | `/v1/audit` | admin |
| GET | `/v1/analytics/overview` | admin, responsable |
| GET | `/v1/analytics/stores` | admin, responsable |
| GET | `/v1/dashboard` | any signed-in role |
| GET | `/v1/reports/sales` | admin, responsable |
| GET | `/v1/reports/sales.csv` | admin, responsable |
| GET | `/v1/reports/stock` | admin, responsable |
| GET | `/v1/reports/stock/attention` | admin, responsable |

**Analytics.** `GET /v1/analytics/overview` takes a *lens*: `from`, `to` (at most 400 days) and any of `regionId`, `groupId`, `pdvId`, `sellerId`, `productId`, `family`, plus `sort` (`units` | `sales` | `reward`). It answers, for that lens: `subject` (the names and details behind the ids; 404 when one is not visible to the caller), `totals` (sales, units, reward, stores, sellers, products, units per sale, silent stores, and voided / corrected / sent-late sales), `previousTotals` and `change` against the period just before, `series` (per hour for one day, per day up to 62 days, per week beyond), `hours` (Tunis clock), `weekdays`, `breakdowns` (regions, groups, stores, sellers, products, families — up to 100 rows each, with the three measures now and before; a breakdown the lens already fixes is left out), `stock` (for a product: where it sits, stores and grossistes; for a store: what it holds; otherwise what runs out within a week and what does not move; days left at the pace of four weeks), `money` (admin only: owed to the team, waiting payouts, payouts approved in the period) and `insights` (keys the app words). A responsable always gets their own region. `GET /v1/analytics/stores` lists every store of a region or group (pending and suspended too) with its sales, change, team, last sale and stock alerts. `GET /v1/sales` accepts `groupId`, `family` and `status`, and `GET /v1/reports/sales.csv` accepts the whole lens, so the ledger and the spreadsheet show exactly the numbers on screen.

## restock

| Method | Path | Who |
|---|---|---|
| GET | `/v1/restocks/:id` | any signed-in role |
| POST | `/v1/restocks/:id/approve` | admin: `lines` are the quantities received (what is left out is what was sent) |
| POST | `/v1/restocks/:id/assign` | admin |
| POST | `/v1/restocks/:id/cancel` | admin, responsable |
| POST | `/v1/restocks/:id/receipt` | on an order on its way. Admin: marks it delivered at once, a paper is optional (with no `photoIds` the papers already on the order are used, at most five), `lines` are what arrived. The store's responsable, the chosen team member, a buyer of the para, the order manager: the paper (`photoIds`, photos or PDF, required) and a `note`; the order becomes RECEIVED ("paper sent, to verify") |
| POST | `/v1/restocks/:id/quantities` `{lines, note}` | admin, REQUESTED or ASSIGNED: what the order asks for (a product left out is removed), with the reason (required). `GET /v1/restocks/:id` lists every change in `changes [{at, by, delivered, note, lines [{productId, name, before, after}]}]` |
| PUT | `/v1/restocks/:id/receiver` | the store's responsable |
| POST | `/v1/restocks/:id/reject-receipt` | admin |
| POST | `/v1/restocks/:id/send-direct` | admin |
| GET | `/v1/restocks/:id/suppliers` | admin: every active grossiste with what it holds of the order's products (`missing`, `lines[].held`) |
| POST | `/v1/restocks/:id/ship` | admin, responsable of the grossiste's region |

## rewards

| Method | Path | Who |
|---|---|---|
| GET | `/v1/payouts` | vendeur, admin |
| POST | `/v1/payouts` | vendeur (`amountMillimes` a multiple of 5 000, else 400 `PAYOUT_STEP`; `GET /v1/wallet` carries `payoutStepMillimes`) |
| POST | `/v1/payouts/:id/approve` | admin |
| POST | `/v1/payouts/:id/cancel` | vendeur |
| POST | `/v1/payouts/:id/reject` | admin |
| GET | `/v1/reward-rules` | admin |
| POST | `/v1/reward-rules` | admin |
| DELETE | `/v1/reward-rules/:id` | admin |
| GET | `/v1/reward-rules/effective` | admin |
| GET | `/v1/wallet` | vendeur |
| GET | `/v1/wallet/entries` | vendeur |
| GET | `/v1/wallets` | admin |

## sales

| Method | Path | Who |
|---|---|---|
| GET | `/v1/sales/days` | vendeur, responsable, admin |
| GET | `/v1/sales/:id` | vendeur, responsable, admin |
| POST | `/v1/sales/:id/correct` | vendeur, responsable, admin |
| POST | `/v1/sales/:id/reprice` | admin |

## stock

| Method | Path | Who |
|---|---|---|
| GET | `/v1/stock/declarations` | admin, responsable |
| POST | `/v1/stock/declarations` | admin (applied at once), responsable |
| GET | `/v1/stock/declarations/:id` | admin, responsable |
| POST | `/v1/stock/declarations/:id/approve` | admin |
| POST | `/v1/stock/declarations/:id/reject` | admin |
| GET | `/v1/stock/locations/:id` | admin, responsable, vendeur (own store) |
| GET | `/v1/stock/locations/:id/products/:productId/movements` | admin, responsable |

## training

| Method | Path | Who |
|---|---|---|
| GET | `/v1/courses` | any signed-in role |
| POST | `/v1/courses` | admin |
| DELETE | `/v1/courses/:id` | admin |
| GET | `/v1/courses/:id` | any signed-in role |
| PATCH | `/v1/courses/:id` | admin |
| POST | `/v1/courses/:id/lessons` | admin |
| PUT | `/v1/courses/:id/lessons/order` | admin |
| GET | `/v1/courses/:id/progress` | admin |
| POST | `/v1/courses/:id/publish` | admin |
| POST | `/v1/courses/:id/unpublish` | admin |
| PUT | `/v1/courses/order` | admin |
| DELETE | `/v1/lessons/:id` | admin |
| PATCH | `/v1/lessons/:id` | admin |
| DELETE | `/v1/lessons/:id/complete` | any signed-in role |
| POST | `/v1/lessons/:id/complete` | any signed-in role |

Other changes: `GET /c` (public) is the page the code emails link to, with a Copy button; `GET /v1/stock/locations/:id` also serves a team member for their own store; grossistes carry a `regionId` (`POST /v1/users` needs it); `GET /v1/sales` accepts `productId`; `GET /v1/reports/sales` returns `previous` and `trend`; `GET /v1/reward-rules/effective` returns `source`.

Round three: `GET /v1/approvals/history`, `POST /v1/stock/adjust`, `POST /v1/stock/declarations/:id/review`, `POST|GET /v1/stock/recounts` (+ `/:id/approve|reject`), `POST /v1/users/:id/cancel-invite`; `GET /v1/notifications` accepts `category`.

## Changes of 2026-10-17 (v3.4 work)

- **Settings** (admin): `GET/PUT /v1/settings` (minimum build per platform, store links, working hours, supplier choice; audited). `GET /v1/app-config?platform=ios|android` (public) returns `minimumBuild`, `minimumBuilds`, `stores` and `closed` (null, or `{opensAt, time}` while the app is closed).
- **Working hours**: outside the hours set by the admin (Tunis time, never the phone's clock) every authenticated call of a non-admin, non-test-region account answers `423 SERVER_CLOSED` with `details {opensAt, time}`. Still answered: sign-in and the `auth/*` public routes, `GET /v1/me`, `POST /v1/auth/logout`, `POST /v1/me/push-device`, `POST /v1/me/password`, and `POST /v1/sales` for a sale whose `occurredAt` falls inside the hours (a phone that was offline). Background jobs keep running.
- **Stock counts**: stock changes when a count is declared (no longer at approval); `PUT /v1/stock/declarations/:id` edits it, `POST/DELETE .../:id/edit` hold it while its responsable edits (the admin gets `EDITING`); an approved count is corrected for 3 days with a reason; a rejected count removes its stock; the admin may add products when approving. `BELOW_SOLD` carries `details` (product, minimum).
- **Supplier choice**: `POST /v1/restocks/suppliers` (coverage only), `supplierId` on `POST /v1/restocks` (403 `SUPPLIER_CHOICE_OFF` unless the global switch and the personal permission are both on), `PUT /v1/users/:id/supplier-choice`, `canChooseSupplier` in `/v1/me`.
- **Changing a decision for 6 hours** (admin): `POST /v1/groups|pdvs|users/:id/reopen`, `POST /v1/stock/declarations/:id/amend|reopen`, `POST /v1/stock/recounts/:id/reopen`, `POST /v1/restocks/:id/reopen`. Payouts have none. (`POST /v1/restocks/:id/amend`, the quantities received of a delivered order, has no time limit since 3.6.) `GET /v1/approvals/history` items carry `change {options, until}` (null once locked). Error `DECISION_LOCKED`.
- **Setup link** for a new admin's authenticator: `GET /s` (page), `POST /v1/setup-link/claim` (public, one-time).

## Counts and orders, second round (2026-10)

- **Admin edits any count:** `PUT /v1/stock/declarations/:id` now also takes the admin, on a waiting or an approved count (any author, any time), with `reason` required once approved. A responsable's waiting count is taken over (her hold ends and she is told). The body may carry `revision`: a count saved meanwhile by someone else answers `409 STALE_COUNT`. Every count shows `revision` and `correction`.
- **Correcting an approved count (responsable):** `POST /v1/stock/declarations/:id/correction-request {reason}` (within 3 days of the approval, her own latest count). The admin approves it like a recount (`POST /v1/stock/recounts/:id/approve`, a refusal needs a note); the request shows in Approvals as `RECOUNT` with `meta.kind = CORRECTION`. After approval she has 48 hours and one save through `PUT /v1/stock/declarations/:id`; without it she gets `403 CORRECTION_NOT_APPROVED`. `correction` on the count: `{id, status: PENDING|APPROVED|REJECTED|USED|EXPIRED, note, until}`.
- **Sold units:** a change that would take stock below what was sold answers `409 BELOW_SOLD` with `details.products [{productId, name, minimum}]`.
- **Orders:** `POST /v1/restocks` as the admin takes any active store or grossiste, with `deliver: "now"` (default: delivery recorded, proof photos required, stock added) or `"later"` (stores only: sent, the responsable confirms the receipt, the admin approves). The admin can also receive any delivery (`POST /v1/restocks/:id/receipt`), which completes it.
- **Pasted lists:** `POST /v1/products/match {text}` (any signed-in user) reads a pasted list (barcode, name, quantity in several layouts) and returns each line as `MATCHED`, `UNSURE` (with `candidates`) or `MISSING`.
- **Counts keep the order they were entered in** (lines carry a place; older counts stay alphabetical).

## WhatsApp codes and phone numbers (2026-10)

- `phone` is **required** when creating an account (`POST /v1/users`, `POST /v1/pdvs/:id/members`) and is checked when it changes (`PATCH /v1/users/:id`): a Tunisian mobile, 8 digits, written with or without `+216` / `00216` / spaces; stored as `+216XXXXXXXX`. Errors: `PHONE_REQUIRED`, `PHONE_INVALID` (422).
- `GET/PUT /v1/settings` carry `whatsapp: {enabled}`; the GET adds `status`: `CONNECTED`, `DISCONNECTED` or `NOT_CONFIGURED`.

## Editing a person in full (2026-10)

`PATCH /v1/users/:id` takes `name`, `email`, `phone` and `pdvId` (a team member's store, in the same region). The **email and the phone are admin only** (they are where the codes go): a responsable can change a team member's name and store, nothing else (403). An administrator account is never edited here. When the email or the phone of someone who has not activated yet changes, the invitation is sent again to the new contacts and the old code stops working. The audit entry keeps the old and new email and phone.

`PATCH /v1/me` (a person's own profile) also reads the phone in every Tunisian format and stores `+216XXXXXXXX`; it cannot be emptied except by an administrator (`PHONE_REQUIRED`, `PHONE_INVALID`).

`POST /v1/code-status {code, kind: "i"|"r"}` (public, 40 a quarter hour per address): `{open}`, whether the code of an invitation (`i`) or a reset (`r`) link can still be used: not used, replaced, cancelled or expired, and its person active. The link page (`/c#i.CODE`) asks before it shows the code, and says the link is over when the answer is no (if the check cannot be made, the code is still shown).

## Reward rates: limits and re-pricing (3 November 2026)

- `POST /v1/reward-rules` refuses a rate above **100 TND per unit** (`422 REWARD_TOO_HIGH`). Above **10 TND** it answers `409 REWARD_CONFIRMATION_REQUIRED` (`details: {amountMillimes, thresholdMillimes}`) unless the body carries `confirmHigh: true`. Existing rules are not touched, and cancelling a rule always works.
- A sale that earns more than **50 TND** tells every admin at once (`sale.reward.high`).
- `POST /v1/sales/:id/reprice {reason}` (admin only) recomputes an active sale's reward from the rates of its own day, keeps the sale, its units and the stock, writes the wallet difference as a `CORRECTION` entry and a revision (old and new `unitRewardMillimes`), and tells the seller (`sale.repriced`). `409 NOTHING_TO_REPRICE` when the rates already match.

## Planning (2026-11)

| Method | Path | Who |
|---|---|---|
| GET | `/v1/visits?from&to[&responsableId&regionId&status]` | responsable (own), admin (read) |
| POST | `/v1/visits` `{targetKind: PDV\|DEPOT, targetId, kind, start, durationMinutes, note?, allowOverlap?}` | responsable |
| GET / PATCH | `/v1/visits/:id` | responsable (own), admin reads |
| POST | `/v1/visits/:id/cancel` | responsable |
| POST | `/v1/visits/:id/check-in` / `check-out` `{occurredAt?, latitude?, longitude?, accuracyMeters?, mocked?, reason?}` | responsable |
| POST | `/v1/visits/unplanned` `{id, targetKind, targetId, kind, ...same}` | responsable |
| PUT | `/v1/planning/positions/:pdv\|depot/:id` `{latitude, longitude, accuracyMeters?, locked?}` | responsable (once, ≤ 50 m), admin |
| GET / PUT | `/v1/planning/preferences` `{leadMinutes: 0\|15\|30\|60\|120, eveningSummary}` | responsable |
| GET / POST | `/v1/planning/calendar-link` / `calendar-link/rotate` | responsable |
| GET | `/v1/planning/overview?from&to[&regionId]` | admin |
| GET | `/cal/<43-character token>.ics` (public, secret link, `Cache-Control: private, no-store`) | calendar apps |

Visits: `status` PLANNED, ON_SITE, DONE, MISSED, CANCELLED; `revision` grows with every change (the calendar replaces its copy). Each event: `kind` CHECK_IN or CHECK_OUT, `verdict` VERIFIED, OUT_OF_RANGE, NO_FIX, NO_POSITION or SANDBOX, `distanceM`, `flags` (MOCK_LOCATION, LATE_SYNC, LOW_ACCURACY). Errors: `VISIT_OVERLAP` (409, resend with `allowOverlap`), `POSITION_REASON_REQUIRED` (422: arrival away or without a position needs `reason`), `POSITION_REQUIRED` (422, since 3.6: an arrival, planned or not, carries `latitude` and `longitude`), `WRONG_DAY` (an arrival is accepted at any time of the planned day; `TOO_EARLY` is gone and `canStartFrom` is the first minute of that day in Tunis), `POSITION_FIXED` (403), `LOW_ACCURACY`, `OUTSIDE_TUNISIA`, `PLACE_NOT_FOUND`, `TOO_MANY_VISITS`, `INVALID_LEAD`. A check-in or check-out sent twice returns the first; the phone picks the id of an unplanned visit.

## Transfers between paras of a group (2026-11)

| Method | Path | Who |
|---|---|---|
| GET | `/v1/transfers?status&pdvId` | team member, seller or buyer (own para), responsable (region), order manager and admin (all) |
| GET | `/v1/transfers/partners[?pdvId]` | the active paras of the same group (a team member: their own para's; a responsable or the admin pass `pdvId`) |
| POST | `/v1/transfers` `{fromPdvId, toPdvId, direction: SEND\|REQUEST, lines[{productId, quantity}], photoId?, note?}` | team member (seller or buyer) of either para, responsable, order manager, admin (applied at once only from the admin) |
| GET | `/v1/transfers/:id` | those who see it |
| POST | `/v1/transfers/:id/edit` `{lines}` | either para's team member, the responsable, the order manager, the admin (while PENDING) |
| POST | `/v1/transfers/:id/cancel` | the same |
| POST | `/v1/transfers/:id/approve` `{note?, lines?}` | admin (`lines` replaces the quantities: what the admin writes is what moves) |
| POST | `/v1/transfers/:id/reject` `{note}` | admin |

`status` PENDING, APPROVED, REJECTED, CANCELLED, EXPIRED. A transfer carries `number` (TR-YYYY-nnnnnn), `from`, `to`, `group`, `createdBy`, `photoId`, `lines[{productId, name, quantity, requestedQuantity}]`, `changes[]` (detail only), and what the caller may do: `canEdit`, `canCancel`, `canDecide`. A team member's `direction` follows their para (they send if it is `fromPdvId`). One photo is required except from the admin, whose transfer is created APPROVED. Errors: `NOT_SAME_GROUP`, `SAME_PLACE`, `PLACE_INACTIVE`, `GROUP_INACTIVE`, `TRANSFER_STOCK` (409, `details.products[{name, available, wanted}]`), `PHOTO_REQUIRED`, `INVALID_STATE`, `NO_LINES`, `DUPLICATE_PRODUCT`. Approvals: `/v1/approvals` lists `type: TRANSFER` (name "From → To", `meta {number, units, changed}`) and its history uses `transfer.approved` and `transfer.rejected`.

## Returns (2026-11)

## Team accounts and their first password (2026-11)

`POST /v1/users/:id/approve` (a team member) and `POST /v1/users` with `role` VENDEUR or ACHETEUR create the password and queue one `email` and one `whatsapp` job with `template: "credentials"` (`sealed`: the encrypted password, wiped when sent). `GET /v1/me` and the sign-in answer carry `mustChangePassword`; the people lists carry `mustChangePassword` and `passwordExpiresAt`, and `activated` means "chose their own password". While `mustChangePassword` is true only `GET /v1/me`, `POST /v1/me/password` and `POST /v1/auth/logout` answer; everything else is `403 PASSWORD_CHANGE_REQUIRED`. `POST /v1/me/password {next}` needs no `current` in that state (otherwise `current` is required). A temporary password past its 7 days is `401 TEMP_PASSWORD_EXPIRED` (sign-in, and a session opened before). Cancelling an invitation or reopening an approval also kills it.

## The order manager (2026-11)

## The buyer (2026-11)

Role `ACHETEUR` (a buyer only, region and para set) or a `VENDEUR` with `canOrder`. `GET /v1/me` returns `canOrder` (true for a buyer, and for a seller who may order).

| Method | Path | Who |
|---|---|---|
| POST | `/v1/pdvs/:id/members` `{name, email, phone, duties?: {sells, buys}}` | responsable (waits for the admin): `sells` only = VENDEUR, `buys` only = ACHETEUR, both = VENDEUR with `canOrder` |
| POST | `/v1/users` `{role: "ACHETEUR"\|"VENDEUR", pdvId, buys?, ...}` | admin (active at once) |
| POST | `/v1/users/:id/duties` `{sells, buys}` | responsable of the region, admin (`DUTIES_REQUIRED` 400 when both false; `WALLET_NOT_EMPTY` 409 when a seller with money left stops selling) |
| POST | `/v1/restocks` | buyer: `destId` must be its own para (404 otherwise); a seller without `canOrder` gets 403 |
| GET | `/v1/restocks`, `/v1/restocks/:id` | buyer: its para's orders only |
| POST | `/v1/restocks/:id/receipt`, `/cancel` | buyer: receives its para's delivery unless a `receiver` is named; cancels its own order while REQUESTED (the responsable can too) |
| GET | `/v1/stock/locations/:id` | buyer: its own para |

`PUT /v1/restocks/:id/receiver` accepts a buyer. Users lists (`GET /v1/users`) include buyers; notification `duties.changed`; audit `user.duties_changed {from, to}`.

Role `ORDERS`: created with `POST /v1/users {role: "ORDERS", name, email, phone}` (admin; active at once, no region, no para). Its sign-in is the responsable's.

| Method | Path | Who |
|---|---|---|
| GET | `/v1/orders/overview` | ORDERS, admin: `{orders: {requested, proposed, toShip, onTheRoad, delivered, toApprove}, paras: {total, low, out}, attention[]}` |
| GET | `/v1/orders/paras?regionId&groupId&q&low` | the same: `[{id, name, address, city, phone, region, group, stock: {products, units, low, out}, sold7Days, openOrders}]`, worst first; no money anywhere |
| GET | `/v1/orders/paras/:id` | the same, plus `stock.lines[{productId, name, family, quantity, level: OK\|LOW\|OUT, sold7Days, coverDays}]`, `orders[]`, `contacts[{id, name, role, phone}]`, `lastAskedAt` |
| POST | `/v1/orders/paras/:id/ask` `{message?}` | ORDERS (`TOO_SOON` 429 within 30 minutes) |
| POST | `/v1/restocks` | ORDERS too: any para or grossiste |
| POST | `/v1/restocks/:id/propose` `{source: BIOBALANCE\|GROSSISTE, depotId?, lines?, note?, photoIds?}` | ORDERS (REQUESTED only; a depot order is BIOBALANCE) |
| POST | `/v1/restocks/:id/approve-proposal` / `reject-proposal` `{note}` | admin |
| POST | `/v1/restocks/:id/documents` `{photoIds}` | ORDERS, admin, the responsable of the place's region, a buyer of the para, the chosen receiver (until closed; at most 10). On an order on its way, from anyone but the admin, it is the delivery paper: the order becomes RECEIVED and the admin is told |
| POST | `/v1/restocks/:id/delivered` `{photoIds?, note?}` | kept for older apps (once per order). ORDERS on an order on its way: RECEIVED, waiting for the admin; admin: only stamps `deliveredAt` |
| POST | `/v1/restocks/:id/ship` | ORDERS too, from any grossiste |

An order carries `proposal {source, supplier, by, at, note}` while it waits, `documentIds`, `deliveredAt`, `deliveredBy`, and each line `proposed`. Reads opened to ORDERS: `/v1/pdvs`, `/v1/groups`, `/v1/depots`, `/v1/restocks`, `/v1/transfers` (which it also writes since 3.6), `/v1/returns` (read only: `canEdit`, `canCancel`, `canDecide` all false). `/v1/approvals` shows `meta.proposal` and `meta.proposedBy` on a restock request. Notifications: `restock.proposed`, `restock.proposal_approved`, `restock.proposal_refused`, `restock.delivered`, `orders.asks`.

| Method | Path | Who |
|---|---|---|
| GET | `/v1/returns?status&pdvId` | responsable (their region's), a buyer (their own para's), order manager (read only), admin (all) |
| POST | `/v1/returns` `{pdvId, action: REMOVE\|MOVE\|ADD, toPdvId?, lines[{productId, quantity}], note?}` | responsable (`REMOVE` only, for a para of their region: waits for the admin), a buyer (`REMOVE` only, their own para), admin (any para, any action: applied at once) |
| GET | `/v1/returns/:id` | the same |
| POST | `/v1/returns/:id/edit` `{lines}` / `cancel` | responsable, a buyer of the para, admin (while PENDING) |
| POST | `/v1/returns/:id/approve` `{note?, lines?, toPdvId?}` | admin (`lines` replaces the quantities; `toPdvId` turns a take-out into a move) |
| POST | `/v1/returns/:id/reject` `{note}` | admin |

`status` PENDING, APPROVED, REJECTED, CANCELLED, EXPIRED; `action` REMOVE (take out of `para`), MOVE (out of `para`, into `to`), ADD (into `para`). A return carries `number` (RT-YYYY-nnnnnn), `para`, `to`, `createdBy`, `lines[{productId, name, quantity, requestedQuantity}]`, `changes[]` (detail only) and `canEdit`, `canCancel`, `canDecide`. Errors: `RETURN_STOCK` (409, `details.products[{name, available, wanted}]`), `INVALID_ACTION` (a move needs `toPdvId`; only a move has one), `PARA_NOT_FOUND`, `SAME_PLACE`, `PLACE_INACTIVE`, `INVALID_STATE`. `/v1/approvals` lists `type: RETURN`; the history uses `return.approved` and `return.rejected`.
