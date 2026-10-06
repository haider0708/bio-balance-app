# BioBalance: functional specification

BioBalance runs the network of BioBalance parapharmacies: who sells where, what each place holds, how stock gets replenished, and what each salesperson earns. The app speaks **French and English** (the person chooses; it defaults to French) and shows amounts in TND.

## People

| Role | Count | What they do |
|---|---|---|
| **Admin** | few | Sees everything, approves everything, sets rewards, pays out, writes announcements and training. Signs in with a password and an authenticator code. |
| **Responsable** | 3, one per region (Nord, Centre, Sud) | Creates the group(s) and points of sale (PDV) of their region, adds teams, declares stock, requests restocks, receives deliveries. Sees only their own region. |
| **Grossiste** | any | A wholesaler with one depot, working for **one region** and handled by that region's responsable (a restock can only be assigned to a grossiste of its own region). Declares the depot stock, prepares and ships the orders assigned to them, can request stock from BioBalance. |
| **Team member** (vendeur) | any | Works in one point of sale. Records sales, sees the reward each sale earned, keeps a wallet. |

Regions are separate: a responsable never sees another region's points of sale, people, stock, sales or deliveries (enforced in the database, not only in the app).

## Approvals

Everything a responsable or grossiste creates **works immediately but stays inactive until the admin approves it**, item by item: a group, a point of sale, each team member, the opening stock of a place, a delivery receipt. A rejection carries a reason and the creator can fix and resubmit. The admin has one **approvals inbox** for all of it.

- A point of sale sells once it is approved; its team members sign in once they are approved (they then receive an email with an activation code).
- Stock is never official until the admin approves its declaration.

## Stock

One quantity per product per place (point of sale or depot). **No lots, no expiry dates, no prices.** Every change is kept in an append-only history. **A sale can never take a store below zero:** the server refuses it (`OUT_OF_STOCK`), and the sale screen shows what is in stock and caps the quantity. While the phone is offline the sale is kept and checked when it is sent. A team member can read the stock of their own store only.

- **Opening stock, counted once:** the responsable (or grossiste) counts, enters quantities and takes a photo. The admin sees the photo next to the numbers and approves, corrects some quantities, or rejects. There is no recount: a place whose count is waiting or approved cannot declare again (`ALREADY_COUNTED`); only a rejected count can be sent again. A place with nothing on its shelves declares "no stock" (no photo needed). Later stock moves only through restocks and sales.
- **Quick restock:** a low-stock product on the responsable's dashboard (or on the stock-attention list) has an Order button that sends the request in two taps.

## Restock

1. The responsable asks for products for a point of sale (a grossiste can ask for the depot).
2. The admin either **assigns it to a grossiste** or **sends it directly** (BioBalance has unlimited stock). The admin can adjust quantities first.
3. The grossiste prepares and ships (cannot ship more than requested or held).
4. The responsable, **or a team member the responsable chooses**, photographs the signed delivery paper and enters the quantities actually received.
5. The admin compares photo and numbers, then approves as counted, corrects, or asks for a recount.
6. **Only then does stock move**: the destination gains the approved quantities and, for a grossiste, the depot loses them.

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
