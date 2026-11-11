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

- A point of sale sells once it is approved; its team members sign in once they are approved: the account is created then, with a **generated password sent by email and WhatsApp together** (see "Team accounts and their first password").
- Stock is never official until the admin approves its declaration.

## Stock

One quantity per product per place (point of sale or grossiste). **No lots, no expiry dates, no prices.** Every change is kept in an append-only history. **A sale can never take a store below zero:** the server refuses it (`OUT_OF_STOCK`), and the sale screen shows what is in stock and caps the quantity. While the phone is offline the sale is kept and checked when it is sent. A team member can read the stock of their own store only.

- **Opening stock, counted once:** the responsable counts, enters quantities and takes photos. The admin sees the photos next to the numbers and approves, corrects some quantities, or rejects. When the admin counts a grossiste herself, the stock applies at once. A place whose count is waiting or approved cannot declare again (`ALREADY_COUNTED`) unless the admin allowed a recount; only a rejected count can be sent again. A place with nothing on its shelves declares "no stock" (no photo needed). Later stock moves only through restocks and sales.
- **Quick restock:** a low-stock product on the responsable's dashboard (or on the stock-attention list) has an Order button that sends the request in two taps.

## Restock

One cycle, shown the same way to everyone: **Requested → With the grossiste → On its way → Paper sent, to verify → Delivered** (since 3.6).

1. **Who orders:** the responsable for a point of sale or a grossiste of the region, the order manager for any place, a buyer for their own para, the admin for anything.
2. **The admin routes it:** sends it directly (BioBalance has unlimited stock), or gives a store's order to any grossiste, of any region. Before choosing, the admin sees each grossiste's stock for the order ("Has everything", or "Short of 1 product: Niacinamide 2/6"). The order manager can prepare this as a proposal the admin approves in one tap.
3. For an order given to a grossiste, the responsable of the grossiste's region, the order manager or the admin says what really leaves it: stock leaves at that moment, and never more than requested or held.
4. **Papers:** the admin, the order manager, the responsable of the place's region, a buyer of the para and the person chosen to receive add papers (photos or PDF, ten at most) until the order is closed. **A paper added to an order on its way by anyone but the admin is its delivery paper**: the order becomes "Paper sent, to verify" and the admin is told. No counting at the store.
5. **The admin decides:** on any order on its way or with its paper sent, **Mark as delivered**: the quantities received start at what was sent and can be corrected, a paper is optional (the ones on the order are used), a note can be added. She can also ask for the paper again.
6. **Only then does the destination gain stock.** A grossiste that supplied the order lost the goods when they were shipped.

**The admin changes quantities at every step, with a reason:** what the order asks for before it leaves (add, change or take out a product; everyone on the order is told), what arrived when marking it delivered, and what arrived after delivery (no time limit; only the difference reaches the stock, never below what was already sold). Every change is listed on the order: when, by whom, why, and from what to what.

The admin can also restock a grossiste herself: she enters what BioBalance delivered, adds photos or the paper, and the goods are added at once (the same when she receives a delivery to a grossiste).

## Sales and rewards

- A sale is products and quantities, no prices. The phone picks the sale's identifier, so a retry never counts twice; with no connection the sale is kept on the phone and sent later.
- **Rewards** are set by the admin only: TND per unit sold, for a **product** or a whole **family** (serums, hair care…), for a **period**. Values can change week to week; two values for the same target never cover the same day. A product's own value beats its family's. The reward is fixed when the sale is recorded. **Safety:** a rate above 10 TND per unit must be confirmed by the admin (the form shows what it means), above 100 TND it is refused, and one sale earning more than 50 TND alerts the admins at once. When a wrong rate was used, the admin **re-prices** the sale from its detail screen: the sale, its units and the stock stay, the seller's wallet follows by a correction, and the seller is told.
- After each sale the team member sees a congratulation screen with the TND earned and today's total. They keep a history and can **correct or cancel** a sale (48 hours for them; responsable and admin at any time). Corrections adjust stock and the wallet, and are kept in the sale's history.

## Wallet and payouts

Rewards credit the team member's wallet. They can **request a payout** up to what is available (requested amounts are held), **only in whole steps of 5 TND**: the sheet has no typing, only a **+** and a **−** button (hold to repeat) from 5 TND up to the most that is available, then the request. Under 5 TND available the button is off and says a payout starts at 5 TND. The server refuses any other amount (`PAYOUT_STEP`) and tells the app the step (`payoutStepMillimes` in `GET /v1/wallet`). The admin pays them outside the app, then **approves**, entering the date and an optional reference; only then is the amount deducted. A declined or cancelled request releases the hold. If corrections lower the balance below a pending request, the approval is refused.

## Search, filters and sorting

Every list that shows data has the same three tools, built once (`lib/core/widgets/list_tools.dart`) so they behave alike everywhere: a **search box** (a magnifier, a clear button; case and accents are ignored, so "serum" finds "Sérum", and every word typed must be found), **filter chips** (a status, a kind, "low", "out of stock", "paid"…) and a **sort menu** (name, newest or oldest, pieces, amount, balance…). They work on what is on the phone, instantly. Lists that load page by page (notifications, approval history) keep fetching pages while a search has few matches, so it does not stop at a false "nothing found".

Where: stores, groups and people of the network (the admin's people filter has every role: responsable, seller, buyer, order manager, and a status chip); regions; warehouses (sort by pieces in stock, by number of products); the stock of a place (all, low, out; sort by name, most or fewest pieces, family); products of the catalogue (family chips, sort by name or family), rewards, the new-sale product search; approvals (to do and history); restocks, returns, transfers (search by number, store, person or product; sort by date or pieces); payouts (to pay, history with paid, rejected, cancelled chips, and wallets with balance chips; sort by amount, balance, earned, paid), a seller's own wallet activity (rewards, corrections, payouts; sort by date or amount); notifications; announcements; courses (to do, done; published, draft; sort by name or length); the stock needing attention (out, low; most urgent or fewest pieces).

## Announcements and training

- **Announcements** (admin): a title and message for a chosen audience (everyone; roles; regions; specific points of sale), optionally pinned, sent now or scheduled, with a live count of who will receive it and read receipts.
- **Training**: courses made of ordered lessons (reading, video file or link, PDF), shown to chosen roles/regions once published, with each person's progress visible to the admin.

## Reports and history

### Analytics: every number opens what it is made of

Every number of the admin's and the responsable's dashboards can be tapped (phone and web): units sold today, the last 7 days, rewards of 30 days, active points of sale, each bar of the daily chart, each top product, store and group, and every number on a region's page. It opens the **analytics** for that question: a period (today, yesterday, 7, 30 or 90 days, this or last month, or any dates up to 400 days) narrowed to any of region, group, point of sale, team member, product and family.

The analytics page shows, for that question:
- **Headline numbers** — units, sales, rewards, units per sale, selling stores, selling team members — each against the period just before. Tapping units, sales or rewards decides what the curve and the rankings show.
- **What changed after the fact** — sales cancelled, corrected, or sent later from a phone without connection — each opening the sales concerned.
- **The curve** hour by hour (one day), day by day, or week by week; a day or a week opens on its own. **When customers buy**: by hour (Tunis clock) and by day of the week.
- **What the numbers say**: plain sentences (best family, stores going up or down, stores that sold nothing, best hour and weekday, best seller, products running out, stock that does not move, reward per unit).
- **Where, who and what**: rankings of regions, groups, points of sale, team members, products and families, with share and change. Each row opens the same question narrowed to it, so the admin goes from the network to a region, a store, a seller and a product in a few taps; each filter shows as a chip that can be removed, and "Filter" adds one.
- **Stock**: for a product, where it sits (each store and grossiste, days left at the current pace); for a store, what it holds and how long each product lasts; otherwise what runs out within a week and what does not move.
- **Rewards in money** (admin): owed to the team members, waiting for payment, paid in the period.
- **The sales themselves**, newest first, cancelled ones included, each opening the sale with its products and corrections. A spreadsheet export gives exactly the same lines.

Store, group, product and team member pages have a chart button to their analytics; the region page has "Analytics of the region". **All points of sale** lists every store of the scope side by side — selling, without a sale, stock running low, waiting for approval — with units, change, team, last sale and stock alerts, searchable and sortable (biggest drop, longest without a sale). On the web each question has its own address (`/explore?…`), so it can be bookmarked or sent to a colleague. The Reports tab is this analytics page for the whole scope, starting with this month. Groups count their stores' sales including those made before the store joined.

### History

The stock-attention list (nearly out, each with an Order button for the responsable). The admin's home splits "needs attention" by kind and opens a page per region (responsable, numbers, groups, stores, grossistes, top products and stores). The audit log of who changed what is kept for the developer only; it is not in the app.

**Sales history** is read by month and day (totals per day, open a day for its sales, search by product), so a list of hundreds stays readable. **Rewards:** a product's own rate always overrides its family's rate. **Notifications:** the responsable is told about every sale of their stores; phones check for new notifications about every 15 minutes even when the app is closed (no push service needed).

## Round three: what changed

- **Approvals** has a Pending and a History tab (who decided, when, why). Nothing is shown when nothing waits.
- **Stock:** old negative rows were brought to zero by correction entries; the admin can correct any place's quantities with a reason (kept in the history, the people in charge are told). A grossiste's count is checked by the responsable of the region before the admin approves; a recount needs the admin's permission, used once.
- **Dashboards:** top 5 products and stores with "see more" (30 and 10), stock warnings summarised per store, group pages list their stores, the buttons follow the tab (new store, new group, new member).
- **Reports** compare with the previous period and explain the numbers (replaced in 2.8 by the analytics above).
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

## Phones, tablets and the app stores (3.0)

- **Account deletion.** Everyone can delete their own account in Settings → Delete my account, with their password. Their name, email, phone, password, notifications and training progress are erased at once and they can no longer sign in; sales, stock counts and rewards already paid stay in the records under "Compte supprimé". Waiting payout requests are cancelled (the sheet shows the balance still to be paid), and sales still waiting on the phone must be sent first. The last admin cannot delete their account. The admins are told.
- **Privacy, terms, help and deletion pages** in French and English at `https://api.galylio.com/privacy`, `/terms`, `/support`, `/account-deletion`, linked from the sign-in screen and Settings.
- **Tablets (iPad, Android tablets):** a side rail replaces the bottom bar, pages keep a readable width and forms a narrow column; every orientation. **Phones** stay upright.
- **Nothing lost by mistake:** a sale being built, a stock count or a restock order is kept as a draft when the person leaves (since 3.2; it used to ask first).
- **Code links** from the emails open the app on iPhone too.
- The version in Settings is the one of the build.

## Opening and documents (3.1)

- **Opening animation:** when the app starts, the leaf drops into water (a dip, two ripples, a light across the leaves), bubbles rise, and "BioBalance — Back to nature" appears letter by letter. It starts exactly where the phone's own launch screen leaves off, follows light and dark mode, lasts under two seconds (about one on the web) and becomes a still image when the phone asks for reduced motion. A code link that opened the app while it was closed is still followed afterwards.
- **Documents as proof:** wherever photos prove goods (stock counts, grossiste photos, restock orders, shipments and deliveries), a PDF can be added too — a delivery note or an invoice, up to 12 MB, with the photos (five in all). Documents show as a "PDF" card with their name and open in the phone's viewer (a new tab on the web); photos still open full screen.

## Platform notes (3.1.1)

- **Alerts while the app is closed** work on Android (the phone checks every 15 minutes) and, since 3.2, on iPhone (Apple push with the server key, otherwise a check when iOS allows).
- **iPhone and iPad** use the system page slide with the swipe from the left edge to go back, on every screen (work in progress is kept as a draft since 3.2).
- **Photos and documents** opened once are kept on the phone (up to 200 MB, files over 15 MB are not kept), so they open at once and spare mobile data; signing out removes them.

## Drafts and alerts (3.2)

- **Drafts instead of "Leave without saving?"**: a sale being built, a stock count (with its photos and note) and a restock request are kept on the phone at every change. Leaving by the back button or the iPhone swipe never blocks and never loses anything ("Kept as a draft"); opening the screen again brings the work back ("Your unfinished entry is back", with **Start over**). A sale draft lasts 12 hours (only what is still in stock comes back, never more than the store holds), a count or a request a week. Drafts belong to the account that made them and go when it is deleted.
- **iPhone alerts**: with the Apple key on the server (docs/runbook.md), alerts reach a closed iPhone within seconds, in the person's language, with the unread number on the app icon; many at once become one summary. Without it, the iPhone checks by itself when iOS allows. Tapping an alert, on iPhone or Android, opens the notifications.
- **Badge and polling**: the unread number refreshes every minute only while the app is in front, and stops at sign-out; lists kept for the whole session (regions, catalogue) are reloaded when another account signs in on the same phone.
- **Pending sales** are only ever sent with the account that recorded them.
- The admin's "rewards in effect today" follows the Tunis day (it showed the day before between midnight and 1 am).
- The note of a stock correction is no longer written twice in its notification.

## Push alerts on Android (3.3)

- **Instant alerts on Android**: a new notification (a sale in a responsable's region, an approval, a delivery, an announcement) reaches the phone within a second or two, in the person's language, even with the app closed and without any battery cost (Android shows it itself). Tapping it opens the notifications. While the app is open the bell updates at once and the alert shows as a banner.
- Phones without Google services, or whose person refused notifications, keep the 15-minute background check. Nobody receives an alert twice: once push is registered the background check stays quiet.


## Stock, supplier choice, history and hours (2026-10-17)

- **Counts**: a declared count is in stock at once, so sellers can sell while the admin has not decided. A waiting count can be edited by its responsable (it is on hold for the admin meanwhile); an approved one can be corrected for 3 days, with a reason, and the admin is told. A rejected count removes its stock. When approving, the admin may correct quantities and add products. Stock never goes below what was sold.
- **Supplier choice**: a global switch (admin) plus a permission per responsable. A permitted responsable names the grossiste of a store's restock; the order still goes to the admin, who approves it in one tap or assigns another.
- **History**: an approved or rejected decision can be put back to waiting or have its quantities corrected for 6 hours; after that it is locked. Payouts are never reopened.
- **Working hours**: set by the admin per weekday in Tunis time; outside them only the admin works; others can sign in and see the closed screen with the opening time.

## Who does what with counts and orders (2026-10, second round)

The admin can do everything a responsable can, for any store (except recording sales, which stay with the team member).

| | Responsable (her region) | Admin |
|---|---|---|
| Opening count | Declares it; it is on hold for the admin while she edits it | Declares it (approved at once); edits any waiting or approved count: add, remove, change |
| Correcting an approved count | Asks first (within 3 days, with a reason); after the admin approves she has 48 hours to correct, once | Edits directly, with a reason, at any time |
| Sold units | Cannot remove units that were sold: a message names the product and the minimum | Same rule (the stock adjustment exists for the rest) |
| Order | Orders for her stores, or names the grossiste when allowed; the admin approves | Orders for any store: delivered now (proof, stock at once) or sent (the responsable confirms, the admin approves) |
| Pasting a list | Matches a delivery note or a list to the catalogue | Same |

Two people editing a count at once cannot overwrite each other: the second save is refused and asks to reload.

## A team member's page, tappable numbers, opening screen (2026-10)

- **A salesman's page** (admin and responsable) shows what he sold: Today / 7 days / 30 days, his units, sales and rewards (each opens its detail), his latest sales (each opens the sale, where the admin corrects it), "All sales" and "Full analysis".
- **Tappable numbers** on the dashboards show a small chevron: every one opens the sales behind it.
- **Opening screen:** calmer bubbles that never cross the name, a soft glow behind the mark, and a quiet progress line when the app is still waiting after the animation.
- **More menu:** compact rows, so every entry fits on one screen.

## Planning for the responsables (2026-11)

A responsable keeps a calendar of **visits** to the stores and grossistes of their own region: what for (stock count, delivery, training, follow-up, other), when, for how long, a note. The admin only **reads** them (the "Planning" overview and each visit); nobody else sees them.

- **Calendar:** a week strip and the day's visits (Planning, in More; a card on the home screen shows where they are or the next visit). Planning in the past is refused; two visits at the same time ask for a confirmation; at most twenty a day. A planned visit can be moved, changed or cancelled.
- **Alerts:** the phone is told 60 minutes before a visit (none, 15, 30, 60 or 120 minutes: their choice), the evening before at 20:00 about tomorrow's visits (can be turned off), and when a planned visit was not started by the end of the day (it becomes *missed*, 23:30). A visit planned after its reminder time is not reminded: the person has just seen it.
- **Calendar app:** Planning → settings gives a secret, read-only link. Added to Apple or Google Calendar, the visits appear there and update by themselves, with the same alert; calendar apps refresh every few hours, so the alerts of BioBalance are the reliable ones. "Make a new link" cancels the old one.
- **Proof of presence:** on a visit, **I'm here** and **I'm leaving** read the phone's position **once, at the tap** (the app open; never in the background, never a trail). The server compares it with the place's position: within **150 m**, widened by the reading's own doubt (at most 100 m more), the visit is *at the place*; otherwise *away* (the distance is kept); a reading worse than 200 m or none is *no position*. Arriving away or without a position is allowed **with a written reason**; leaving never asks one. A check made without a connection waits on the phone and is sent later with the moment of the tap (marked *sent late* after 15 minutes). The app marks a position given by a location-faking app. It is **evidence, not proof**: it says where the phone was.
- **Where a place is:** the first time, the responsable can save the position of the place they are at (a reading better than 50 m); after that only the admin changes it (and can lock it). The test region (the store reviewers' accounts) accepts any position.
- **An unplanned visit** ("I'm at a place now") records the visit and the arrival at once.
- **The admin's overview:** per responsable and period, visits planned, done, missed, and how many check-ins were at the place, away or without a position, with the average time on site; each visit shows its check-in and check-out, the reason, the flags and an "Open in Maps" link.
- **Privacy:** positions and visits are kept **12 months** then erased; the privacy page says so. A deleted account's calendar link and settings go and its planned visits are cancelled; its past check-ins stay without a name until the 12 months end.

## Transfers between paras of a group (2026-11)

Paras of the **same group** (a group is a set of paras of one region) can exchange products. The two paras settle it **by phone**, then someone records it in the app; **the admin approves the quantities** and only then does the stock move.

- **Who records:** a team member of either para (their own para is one side: "My para sends" or "My para receives"), the responsable of the region (any two paras of a group), or the admin. A team member always speaks for their own para, whatever the screen says.
- **What:** the two paras (the second is chosen among the first one's group: a para without a group has no one to exchange with), the products and quantities (never more than the sender holds), **one photo** as proof, an optional note. The **admin's own transfer** needs no photo and no approval: the stock moves at once.
- **Then:** it waits for the admin (Approvals, type *Transfer*, with its photo and lines). Meanwhile either para's team members or the responsable can **change the quantities** or **cancel**; each change is written down (who, from what to what) and the first quantities stay visible. The admin approves as it is, **corrects the quantities while approving**, or refuses with a reason.
- **Stock:** checked when it is recorded, when it is changed, and again when the admin approves (a sale in between can make it impossible: the admin is told which products fall short and can approve a smaller quantity). The movement is one transaction: out of the sender, into the receiver, with a history line on each side (`TRANSFER_OUT`, `TRANSFER_IN`). Nothing moves before approval.
- **A transfer nobody decides in 3 days expires** (the people who made it are told). A decided transfer cannot be changed.
- **Who sees it:** a team member the transfers of their own para, the responsable their region's, the admin all. Everybody concerned is told of the outcome (the creator, the responsable, the teams of both paras).
- **Not included:** prices, delivery tracking, partial approvals, stock reserved while waiting, exchanges between different groups.

## Returns (2026-11)

## Team accounts and their first password (2026-11)

For team members (sellers, buyers, or both) there is no activation code any more.

- **Who makes them:** the responsable of the region adds a member to a para (name, email, WhatsApp number, what they do); the admin approves. The admin can also create one directly (active at once). Responsables, the order manager and the admin are still invited with a code.
- **The password:** when the account is made (at the admin's approval, or at once for the admin's own creation) the system generates a temporary password (ten characters, no look-alike letters, always a capital, a small letter and a digit). It is sent **by email and by WhatsApp together**, with the sign-in email, the app's download links and the date it stops working. It is shown to nobody else: not to the admin, not to the responsable.
- **First sign-in:** the person signs in with the email and that password, and the app asks them to **choose their own** before anything else (the server refuses every other request until they have). The temporary password then stops working.
- **A week:** the temporary password expires after 7 days; signing in with it then says so. The manager's person page shows "Temporary password valid until …" or "expired".
- **Send a new password** (the old one stops working at once, signed-in sessions end) replaces "send the invitation again". Changing the email or the number of someone who has not signed in yet does the same, to the new contacts. An unused invitation can be cancelled (the account is removed and the email is free again); an approval taken back kills the password that was sent.
- **Forgot the password:** the usual code, for everyone.

## The order manager (2026-11)

## The buyer (2026-11)

The **buyer** (*Acheteur*) works in one para and does one thing: the para's orders. It is not the order manager (who works across the whole network).

- **Two ways to be one:** an account of its own, **buyer only** (no sales, no wallet, no rewards), or a **seller who also buys**: the same account, with a switch. The responsable of the region (or the admin) chooses when adding a team member (*What this person does*: Seller, Buyer, Seller and buyer; a new member still waits for the admin's approval) and can change it any time from the person's page. Several buyers per para are allowed.
- **Changing it:** a seller can become a buyer too (or stop), a buyer can start selling. Someone who stops selling must have **nothing left in the wallet** (no balance, no payout waiting): pay first, so no reward is stranded. The person is told, and it is written down. The app notices at the next opening or return to the app.
- **What a buyer does:** sees its own para's stock (units, low, out) and what is running low; **places an order for its own para** (never another para or a grossiste, and it cannot choose the grossiste); sees the orders of its para; cancels its own order while it waits; **receives the delivery** with the paper as justification (unless the responsable named someone else to receive it), after which the admin approves and only then does the stock arrive.
- **Who is told:** the responsable of the region (who can cancel it while it waits), the order manager and the admin, as for any request. The rest of the flow is unchanged.
- **Never:** sales, wallet, other paras, people, approvals, transfers, returns, planning. Closed to the web console (phone only), like a seller.

A fourth kind of account, **Gestionnaire des commandes** (`ORDERS`), is created by the admin (name, email, phone; no region, no para) and signs in like a responsable. It works on stock and orders, never on money or people.

- **Sees:** every para of the network: units, products low (5 or fewer) and out, what sold in the last 7 days, orders still open, the days a product would last at that pace, and who to call (the para's team and its responsable, with a call button and a WhatsApp button). The board puts the worst paras first and can keep only those low or out. Also the transfers and returns (read only), the grossistes and the catalog.
- **Asks a para:** "Ask what they need" tells the team and the responsable of the para (an optional short message); at most once every 30 minutes per para.
- **Orders:** creates an order for any para or grossiste (it goes to the admin like a responsable's), and receives the responsables' requests (told when one is made). On a requested order it **proposes** a source: a grossiste (with what each holds, like the admin sees) or BioBalance direct, with quantities it may lower (never above what was asked), a note and papers. Nothing moves: the admin sees the proposal on the order and in the Approvals inbox, and **approves it in one tap** (the order is routed exactly as proposed) or **refuses it with a reason** (the order manager is told; the order stays waiting). The admin can still route the order his own way.
- **Follows it:** ships an order a grossiste was given (the stock leaves the grossiste then), attaches papers (invoice, preparation or delivery note; up to 10 per order, until it is closed) and marks it **delivered** with the delivery paper. The place's team still confirms the receipt with its own paper and the admin approves it: **only then does the stock arrive.** It can cancel the orders it created while they wait.
- **Never:** money (prices, rewards, wallets, payouts), sales, accounts and people, approvals, stock declarations or corrections, planning. The database itself shows it none of those (checked by tests that count rows, not by the screens).

A **return** takes quantities out of one para's stock. It has its own section (Returns, in More and in the web console's sidebar) and is for nothing else: no reasons, no destination to pick, no photo.

- **The responsable asks:** for a para of their own region, the products and quantities (never more than the para holds) and an optional note. The admin is told; nothing moves yet. Until the admin decides, the responsable can **change the quantities** (each change is written down, the first quantities stay visible) or **cancel**. A team member has no returns.
- **The admin controls it:** approves as it is, **corrects the quantities** while approving, **moves it to another para instead** (the quantities leave this para and enter the one he picks, in any region), or refuses with a reason. Nobody decided in 3 days: it expires, and the responsable is told. The stock is checked again at approval (a sale in between can make it impossible; the admin is told which products fall short).
- **The admin acts directly,** on any para of any region, from the same screen: **take out only**, **move to another para**, or **add only** (quantities put into a para, no stock needed elsewhere). It applies at once, with no request and no approval, and the responsable of the para (and of the receiving para) is told.
- **Set the quantities he wants:** from the same screen the admin picks any para and **sets its real quantities** (every product, up or down, products can be added), and only has to write a **note**. It is the existing stock correction (`POST /v1/stock/adjust`, also under a para's stock screen → *Correct*): applied at once, kept in the history with the note, the responsable of the para is told.
- **Stock:** one transaction, with a history line each (`RETURN_OUT`, `RETURN_IN`, reference `StockReturn`), and never below zero. Returns appear in the admin's Approvals (type *Return*) and its history.
- **Not included:** reasons, prices or credit notes, a grossiste confirming receipt, customer returns (a sale is corrected from the sale). A move between paras of one group, recorded by a team member with a photo, is a *transfer*, not a return.
