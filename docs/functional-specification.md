# BioBalance: functional specification

BioBalance runs the network of BioBalance parapharmacies: who sells where, what each place holds, how stock gets replenished, and what each salesperson earns. The app speaks **French and English** (the person chooses; it defaults to French) and shows amounts in TND.

## People

| Role | Count | What they do |
|---|---|---|
| **Admin** | few | Sees everything, approves everything, sets rewards, pays out, writes announcements and training. Signs in with a password and an authenticator code. |
| **Responsable** | 3, one per region (Nord, Centre, Sud) | Creates the group(s) and points of sale (PDV) of their region, adds teams, declares stock, requests restocks, receives deliveries, and handles the **grossistes** of their region (see below). Sees only their own region. |
| **Team member** (vendeur) | any | Works in one point of sale. Records sales, sees the reward each sale earned, keeps a wallet. |

### Regions are managed by the admin

The admin creates, renames and deletes regions (**More → Regions**, or **Regions** in the web sidebar). A region is deleted only when nothing is left in it: no store, group, grossiste or person. A region has **one responsable**, and a responsable always has a region.

- **Responsables:** created for a region, and moved between regions. Moving one into a region that already has a responsable asks the admin to **swap** the two; nothing happens without that confirmation. A suspended responsable can be moved anywhere (this is how a region is emptied before it is deleted).
- **Stores, groups and grossistes** can be moved to another region. Everything attached goes with it: a store's team, stock, sales, past deliveries and photos; a group takes all its stores; a grossiste keeps its stock. Reports from before the move show it in its new region. A move is refused while the place has a restock in progress, a count waiting, or a recount request ("finish or cancel them first"). A store leaves its group when it moves, or joins one of the new region. Both regions' responsables are told.
- **Grossistes supply any region:** the admin may give a store's order to a grossiste of another region. That region's responsable (or the admin) ships it, because the goods leave their stock; the store's own responsable receives it and the admin approves, as always.

Regions are separate: a responsable never sees another region's points of sale, people, stock, sales, deliveries or grossistes (enforced in the database, not only in the app).

### Grossistes are warehouses, not accounts

A **grossiste** is a record: a name, an address, a city, a phone number, its region, one to five photos, and the stock it holds. It has **no login and no email**; nobody signs in as a grossiste. The admin creates and edits grossistes (and may suspend or, if unused, remove them). The responsable of the region sees them and manages their stock; other regions never see them.

| | Admin | Responsable of the region |
|---|---|---|
| Create, edit, suspend, remove | yes | no |
| First stock count | yes, with photos, applied at once | yes, with photos; the admin approves |
| Recount later | corrects directly (reason required) | asks; the admin allows it once |
| Restock (goods arriving from BioBalance) | yes, with photos, applied at once | asks BioBalance, then records the delivery with photos; the admin approves |
| Ship goods to a store | yes | yes |

Photos are the proof that the goods are really there, for both roles.

## Approvals

Everything a responsable creates **works immediately but stays inactive until the admin approves it**, item by item: a group, a point of sale, each team member, the opening stock of a place, a delivery receipt. A rejection carries a reason and the creator can fix and resubmit. The admin has one **approvals inbox** for all of it.

- A point of sale sells once it is approved; its team members sign in once they are approved (they then receive an email with an activation code).
- Stock is never official until the admin approves its declaration.

## Stock

One quantity per product per place (point of sale or grossiste). **No lots, no expiry dates, no prices.** Every change is kept in an append-only history. **A sale can never take a store below zero:** the server refuses it (`OUT_OF_STOCK`), and the sale screen shows what is in stock and caps the quantity. While the phone is offline the sale is kept and checked when it is sent. A team member can read the stock of their own store only.

- **Opening stock, counted once:** the responsable counts, enters quantities and takes photos. The admin sees the photos next to the numbers and approves, corrects some quantities, or rejects. When the admin counts a grossiste herself, the stock applies at once. A place whose count is waiting or approved cannot declare again (`ALREADY_COUNTED`) unless the admin allowed a recount; only a rejected count can be sent again. A place with nothing on its shelves declares "no stock" (no photo needed). Later stock moves only through restocks and sales.
- **Quick restock:** a low-stock product on the responsable's dashboard (or on the stock-attention list) has an Order button that sends the request in two taps.

## Restock

1. The responsable asks for products for a point of sale **or a grossiste** of the region.
2. For a store, the admin either **gives it to a grossiste** of the same region or **sends it directly** (BioBalance has unlimited stock); for a grossiste, the admin sends it directly. The admin can adjust quantities first.
3. For an order given to a grossiste, the responsable (or the admin) says what really leaves it: stock leaves at that moment, and never more than requested or held.

The admin can also restock a grossiste herself: she counts what BioBalance delivered, photographs it, and the goods are added at once.
4. The responsable, **or a team member the responsable chooses**, photographs the signed delivery paper and enters the quantities actually received.
5. The admin compares photo and numbers, then approves as counted, corrects, or asks for a recount.
6. **Only then does the destination gain stock**: the approved quantities are added. A grossiste that supplied the order lost them when they were shipped.

## Sales and rewards

- A sale is products and quantities, no prices. The phone picks the sale's identifier, so a retry never counts twice; with no connection the sale is kept on the phone and sent later.
- **Rewards** are set by the admin only: TND per unit sold, for a **product** or a whole **family** (serums, hair care…), for a **period**. Values can change week to week; two values for the same target never cover the same day. A product's own value beats its family's. The reward is fixed when the sale is recorded.
- After each sale the team member sees a congratulation screen with the TND earned and today's total. They keep a history and can **correct or cancel** a sale (48 hours for them; responsable and admin at any time). Corrections adjust stock and the wallet, and are kept in the sale's history.

## Wallet and payouts

Rewards credit the team member's wallet. They can **request a payout** up to what is available (requested amounts are held). The admin pays them outside the app, then **approves**, entering the date and an optional reference; only then is the amount deducted. A declined or cancelled request releases the hold. If corrections lower the balance below a pending request, the approval is refused.

## Announcements and training

- **Announcements** (admin): a title and message for a chosen audience (everyone; roles; regions; specific points of sale), optionally pinned, sent now or scheduled, with a live count of who will receive it and read receipts.
- **Training**: courses made of ordered lessons (reading, video file or link, PDF), shown to chosen roles/regions once published, with each person's progress visible to the admin.

## Reports and history

Dashboards per role, sales reports grouped by day, region, point of sale, seller, product or family with a spreadsheet export, a stock-attention list (nearly out, each with an Order button for the responsable). Reports compare with the previous period, draw a daily chart and let you tap a row to narrow it (store → seller → product). The admin's home splits "needs attention" by kind and opens a page per region (responsable, numbers, groups, stores, grossistes, top products and stores). The audit log of who changed what is kept for the developer only; it is not in the app.

**Sales history** is read by month and day (totals per day, open a day for its sales, search by product), so a list of hundreds stays readable. **Rewards:** a product's own rate always overrides its family's rate. **Notifications:** the responsable is told about every sale of their stores; phones check for new notifications about every 15 minutes even when the app is closed (no push service needed).

## Round three: what changed

- **Approvals** has a Pending and a History tab (who decided, when, why). Nothing is shown when nothing waits.
- **Stock:** old negative rows were brought to zero by correction entries; the admin can correct any place's quantities with a reason (kept in the history, the people in charge are told). A grossiste's count is checked by the responsable of the region before the admin approves; a recount needs the admin's permission, used once.
- **Dashboards:** top 5 products and stores with "see more" (30 and 10), stock warnings summarised per store, group pages list their stores, the buttons follow the tab (new store, new group, new member).
- **Reports** have tabs (Overview, Stores, Products, Team, Stock, Details): comparison with the previous period, plain-language insights, weekday and family mix, rankings with share and change, days of stock left at the current pace, and stock that does not move.
- **Notifications** can be filtered (unread, sales, stock, restocks, payments, network, announcements).
- **Invitations** can be cancelled before the account exists; after that the account is deactivated.

## Admin console on the web

The administrator can work from a browser at https://admin.galylio.com/ with the same account (password and authenticator code). It is the phone app built for the web, so every admin function exists in both. Differences on the web:

- Team members who try to sign in are told to use the phone app.
- Administrators and responsables sign in on the web (team members use the phone). A collapsible sidebar groups the sections of their role (Overview, Operations, Insights, Commerce, Content, Places, Account); a responsable sees their own region only. Under 900 px wide it becomes a drawer. Page content is capped at a comfortable width on very large monitors.
- Reports export downloads a CSV file; PDFs open in a new tab; training videos play from a downloaded copy.
- Text can be selected and copied, and the page is exposed to screen readers.
- Every page has its own address: reload, bookmarks and the browser's back and forward buttons work. A detail page opened without its context (for example a person's page after a reload) returns to its list; an unknown address shows a "page not found" screen.
- Dashboards use the width: four figures per row and regions side by side on a large screen.
- Alerts when the page is closed are not available (they need the phone).
