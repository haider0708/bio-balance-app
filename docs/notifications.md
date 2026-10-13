# Notifications: who hears about what

Every alert is a row in the person's inbox (the bell). Most are also **pushed** to their phones (Apple on iPhone, Firebase on Android) within seconds; the few marked *inbox only* never wake a phone. The wording, in French and English, lives in `apps/api/src/core/notice-text.json` and `apps/mobile/lib/core/l10n/server_text.dart` (a test keeps them equal; `{units:unit|units}` gives the count with the right word, `{day}` a date as 13/10/2026). A tap opens the screen given in the last column (`routeForEntity` in `notifications_screen.dart`).

Rules that apply to all of them:

- Nobody is told about their own action (a seller who corrects their own sale, the admin who decides).
- Nothing done in the **test region** (the store reviewers' accounts) reaches the admin, by inbox, push or email; the admin's announcements, courses and reward news do not reach it either.
- Automation acting for someone (the test shop's sales) is never pushed.
- More than three new alerts at once for one person become one summary push ("You have 5 new notifications"); alerts older than 30 minutes are never pushed late.
- A signed-out phone gets nothing: its token is deleted at sign-out.

## Sales and the day

| Alert | When | Who | Push | Opens |
|---|---|---|---|---|
| `sale.recorded` | a team member records a sale | the region's responsable | inbox only | the sale |
| `sale.corrected` / `sale.voided` | a responsable or the admin corrects or cancels a sale | the seller | yes | the sale |
| `day.summary` | 20:30 Tunis, every day, for each region with an active store | its responsable: sales, units, rewards | yes | home |
| `day.summary_stock` | the same, when products are out of stock in the region's stores | its responsable, with the count | yes | home |
| `day.summary_none` | the same, when nothing was sold | its responsable | yes | home |
| `day.network` | 20:30 Tunis, when the network has an active store | the admins: the whole network | yes | home |

## Rewards and payouts

| Alert | When | Who | Push | Opens |
|---|---|---|---|---|
| `reward.new` | the admin sets a reward rate that applies today or later | every team member | yes | wallet |
| `payout.requested` | a team member asks for a payout | the admins | yes | payouts |
| `payout.approved` / `payout.rejected` | the admin decides | the team member | yes | wallet |

## Stock

| Alert | When | Who | Push | Opens |
|---|---|---|---|---|
| `stock.submitted` | a responsable declares a place's stock | the admins | yes | approvals |
| `stock.approved` / `stock.rejected` | the admin decides (or declares it themselves) | who declared it and the region's responsable | yes | the declaration |
| `stock.adjusted` | the admin corrects a place's stock | the region's responsable | yes | the place's stock |
| `recount.requested` | a responsable asks to count a place again | the admins | yes | approvals |
| `recount.approved` / `recount.rejected` | the admin decides | who asked and the region's responsable | yes | — |

## Restocks

| Alert | When | Who | Push | Opens |
|---|---|---|---|---|
| `restock.requested` | a responsable asks for a restock | the admins | yes | the restock |
| `restock.assigned` | the admin gives it to a grossiste | who asked | yes | the restock |
| `restock.to_prepare` | the same | the responsable of the grossiste's region (who ships) | yes | the restock |
| `restock.shipped` | it leaves the grossiste | who asked, the receiver, both regions' responsables | yes | the restock |
| `restock.shipped` | the admin sends it directly ("from BioBalance") | who asked | yes | the restock |
| `restock.shipped_info` | a responsable ships it | the admins | yes | the restock |
| `restock.receiver_assigned` | a responsable picks who receives it | that person | yes | the restock |
| `restock.received` | the delivery paper is sent | the admins | yes | the restock |
| `restock.completed` | the admin approves the receipt (stock moves) | who asked, the receiver, both regions' responsables | yes | the restock |
| `restock.receipt_rejected` | the admin asks for the receipt again | the receiver and who asked | yes | the restock |
| `restock.cancelled` | it is cancelled | everyone involved but who cancelled | yes | the restock |

## The network

| Alert | When | Who | Push | Opens |
|---|---|---|---|---|
| `group.submitted` / `pdv.submitted` | a responsable creates a group or a store | the admins | yes | approvals / the store |
| `group.*` / `pdv.*` (approved, rejected, suspended, reactivated) | the admin decides | who created it and the region's responsable | yes | the store |
| `member.submitted` | a responsable adds a team member | the admins | yes | approvals |
| `member.*` (approved, rejected, suspended, reactivated) | the admin decides | the responsable who added them (the member gets the invitation email) | yes | — |
| `pdv.moved.*` / `group.moved.*` / `depot.moved.*` | the admin moves them to another region | the responsables of both regions | yes | — |
| `responsable.moved` | the admin gives a responsable another region | that responsable (and the one replaced) | yes | — |
| `account.deleted` | someone deletes their account | the admins | yes | — |

## Announcements and training

| Alert | When | Who | Push | Opens |
|---|---|---|---|---|
| an announcement (its title) | the admin sends it, or its scheduled time comes | its audience (roles, regions, stores, people) | yes | the inbox |
| `course.published` | the admin publishes a course | the people it is for | yes | the course |

## Emails

Only codes and security: the invitation code (account approved), the password reset code, and "your password was changed". Never to an account of the test region.
