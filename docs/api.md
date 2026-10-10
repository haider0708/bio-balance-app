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

`POST /v1/me/delete` with `{ password }` erases what identifies the person (name, email, phone, password, two-step secret, sessions, codes, notifications, training progress), cancels their waiting payout requests and suspends the account for good; sales, stock and rewards stay, under "Compte supprimé #XXXX". The last active admin gets `LAST_ADMIN`. A deleted account cannot be reactivated, invited, edited or moved (`ACCOUNT_DELETED`); the admins are notified (`account.deleted`).

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
| POST | `/v1/users/:id/resend-invite` | admin, responsable |
| POST | `/v1/users/:id/suspend` | admin, responsable |

## media

| Method | Path | Who |
|---|---|---|
| GET | `/v1/media/:id` | any signed-in role |

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
| GET | `/v1/reports/insights` | admin, responsable (legacy: apps up to 2.7) |
| GET | `/v1/reports/sales` | admin, responsable |
| GET | `/v1/reports/sales.csv` | admin, responsable |
| GET | `/v1/reports/stock` | admin, responsable |
| GET | `/v1/reports/stock/attention` | admin, responsable |

**Analytics.** `GET /v1/analytics/overview` takes a *lens*: `from`, `to` (at most 400 days) and any of `regionId`, `groupId`, `pdvId`, `sellerId`, `productId`, `family`, plus `sort` (`units` | `sales` | `reward`). It answers, for that lens: `subject` (the names and details behind the ids; 404 when one is not visible to the caller), `totals` (sales, units, reward, stores, sellers, products, units per sale, silent stores, and voided / corrected / sent-late sales), `previousTotals` and `change` against the period just before, `series` (per hour for one day, per day up to 62 days, per week beyond), `hours` (Tunis clock), `weekdays`, `breakdowns` (regions, groups, stores, sellers, products, families — up to 100 rows each, with the three measures now and before; a breakdown the lens already fixes is left out), `stock` (for a product: where it sits, stores and grossistes; for a store: what it holds; otherwise what runs out within a week and what does not move; days left at the pace of four weeks), `money` (admin only: owed to the team, waiting payouts, payouts approved in the period) and `insights` (keys the app words). A responsable always gets their own region. `GET /v1/analytics/stores` lists every store of a region or group (pending and suspended too) with its sales, change, team, last sale and stock alerts. `GET /v1/sales` accepts `groupId`, `family` and `status`, and `GET /v1/reports/sales.csv` accepts the whole lens, so the ledger and the spreadsheet show exactly the numbers on screen.

## restock

| Method | Path | Who |
|---|---|---|
| GET | `/v1/restocks/:id` | any signed-in role |
| POST | `/v1/restocks/:id/approve` | admin |
| POST | `/v1/restocks/:id/assign` | admin |
| POST | `/v1/restocks/:id/cancel` | admin, responsable |
| POST | `/v1/restocks/:id/receipt` | admin (grossiste orders), responsable, vendeur |
| PUT | `/v1/restocks/:id/receiver` | responsable |
| POST | `/v1/restocks/:id/reject-receipt` | admin |
| POST | `/v1/restocks/:id/send-direct` | admin |
| POST | `/v1/restocks/:id/ship` | admin, responsable of the grossiste's region |

## rewards

| Method | Path | Who |
|---|---|---|
| GET | `/v1/payouts` | vendeur, admin |
| POST | `/v1/payouts` | vendeur |
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

Round three: `GET /v1/approvals/history`, `GET /v1/reports/insights`, `POST /v1/stock/adjust`, `POST /v1/stock/declarations/:id/review`, `POST|GET /v1/stock/recounts` (+ `/:id/approve|reject`), `POST /v1/users/:id/cancel-invite`; `GET /v1/notifications` accepts `category`.
