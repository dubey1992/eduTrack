# Dashboard enhancement

**Status (2026-11-18): built. The first pass used only data the app already
had; the four decisions it raised were answered on 2026-11-18 and built as
D1-D4 below (four migrations).**

Asked for 2026-11-17, with a prototype
(`school365ai_dashboard_enhancement_prototype.html`). The prototype is a
picture of the idea, not a specification: its figures, its "Delivered" count,
its date lock and its salary advances are invented. The rule given was to
build what the existing application supports and to name the rest, never to
fill a gap with sample data.

```
FEATURE:        Dashboard enhancement
OBJECTIVE:      One click to the everyday jobs; every figure opens its page;
                today's fee money per person who took it; this month's SMS
                and WhatsApp by status
DATABASE:       none
API:            GET /dashboard gains collections_today and messages_this_month;
                GET /reports/fee-collection gains received_by and payment_mode
                filters, a credit_amount per row and totals.by_staff
FLUTTER:        Quick actions panel, clickable cards, "Collected today, by
                person", "SMS & WhatsApp - <month>", /reports deep links,
                a Today button and two filters on the fee collection report
AUTHORIZATION:  every piece behind the gate of the screen it summarises
TESTS:          backend test_dashboard_enhancement.py; Flutter
                dashboard_enhancement_test.dart, report_filters_test.dart
```

## What was already there

| Asked for | Found | Built |
|---|---|---|
| Total strength | "Students - on the roll" (active students) | nothing new; the card now opens the student list |
| Boys / girls | **no gender on students anywhere** | nothing - see Open decisions |
| Quick access | the sidebar's own access rules (`NavItem.allows`) | a Quick actions panel reusing them |
| Date lock | **nothing** | nothing - see Open decisions |
| WhatsApp / SMS report | the message log: queued, sent, failed, skipped; category `fee` | a monthly summary; no "delivered" |
| Employee-wise collection | every receipt has `received_by`, `payment_mode`, `credit_amount` | a per-person summary, today, and a per-person filter on the report |
| Advance from a parent | fee credit (F6): the part of a receipt held for later | shown as "held as credit", inside the amount |
| Salary advance | **nothing** in payroll | nothing - see Open decisions |
| Collection report filters | date range, CSV and PDF | Today, received by, payment mode, a link that opens it set up |

## The rules as built

**Quick actions.** Collect fees, Collection report (today), Receipts, Find a
student, Messages, Fees owed. Each shows only when the person may open its
screen - the sidebar entry's own rule, so a switched-off module or a matrix
set to "none" removes it - and a fee report also needs the right to read
fees. Shown only with one school in view. There is no Date lock button: a
button for a control that does not exist would be a promise the app cannot
keep.

**Clickable cards.** Each card the server sends opens its page by key
(`dashboard_links.dart`): students to the student list, attendance to the
register, trips to the trips, payroll cards to Payroll, fees collected to
this month's collection report, fees due and students overdue to the
outstanding report, and so on. A card whose page this person may not open,
or that has no page, stays a plain figure - never a link to a refusal. A
report opened from a branch picked in the dashboard's filter reports on that
branch.

**Collected today, by person.** Valid receipts dated today at the school,
grouped by who took them and by currency - the fee collection report's own
grouping (`reports.fees.by_staff`), so the panel and the report agree. Each
receipt counts once, under one person: the lines add up to the day's total
and nothing is counted twice. Per person: receipts, amount, the part paid in
cash (what they hand over), and the part **held as credit** - money a family
paid ahead of what it owes (F6). Credit is inside the amount, never added to
it; accounting-wise it is what the school owes the family until a fee uses
it, exactly as F6 already records it. Cancelled receipts are left out of the
money and counted beside it. Receipts with nobody recorded are shown as "Not
recorded" and cannot be narrowed to. Gate: the fee cards' own (fees module on,
fees readable, one school in view).

**Messages this month.** SMS and WhatsApp created this month at the school,
on the school's calendar, by the log's statuses: sent (the provider accepted
it), waiting (queued), failed, not sent (skipped - usually no number on
file). In-app and email are left out: they have no provider status. Fee
messages (category `fee`) are counted beside. **There is no "delivered"
figure**, because no provider reports delivery back yet; the panel says so
under the counts, and says so in red when the school's SMS goes through a
gateway that delivers nothing. Gate: whoever reads the message log - the
communication module on and readable (School Admin by default; an Accountant
only if the matrix grants it).

**The fee collection report.** `received_by` (a user id) and `payment_mode`
(a fee payment mode) narrow it, cancelled receipts included, so the count
beside the lines is that person's own. A person from another school matches
nothing - no "no such user", which would say which ids exist. The PDF prints
the filters at the top. `totals.by_staff` lists each person's receipts, money,
cash and credit; a group report lists each branch's people as they are. The
screen opens from a link (`/reports?report=fee-collection&school_id=..&from=..
&to=..&received_by=..&payment_mode=..`), and anything in a link it cannot use
is ignored rather than refused.

## D1-D4, decided 2026-11-18

**D1 - students' gender.** `students.gender`: male, female, other, or null
("not given"). On the add and edit forms and the import (an optional last
column - a file from the older template still imports). The dashboard shows
Boys, Girls and "Other or not given", one query over the active roll, so the
three always add up to the Students card; the third card shows only when it
is not zero, in amber while some are not given.

**D2 - delivery reports.** Every Twilio message asks for a StatusCallback at
`PUBLIC_API_URL/webhooks/twilio/status` (https only). The webhook checks
Twilio's signature against the platform account's auth token (every school
sends through it, docs/platform-messaging.md) and records `delivery_status`
(delivered, read, undelivered), `delivered_at` and `delivery_error`. A report
never moves a message backwards; an unknown id is answered the same and
changes nothing. `status` still says what School365ai did (sent = the
provider took it). The dashboard counts delivered and not delivered among the
sent - a sent message with no report is neither; the message log shows the
report, and no longer labels "sent" as "Delivered" or its rate as "Delivery
Rate". Meta's own webhook is not built: no school sends through Meta since
platform messaging.

**D3 - the fee books' date lock.** `schools.fees_locked_until`, set by a
School Admin, Group Admin or Accountant who manages fees (not the Super
Admin). Nothing dated on or before it: a receipt or refund by its own date, a
cancellation by its receipt's date, a discount, revoked discount, waiver or
late fine by today. Refused with `FEES_LOCKED`, naming the date and who can
reopen. Never in the future; moving it back or clearing it needs a reason;
every change is in the audit log (`fees.locked` / `fees.unlocked`). Nothing
outside the fee books is touched. A Date lock quick action, and a line above
Receipts.

**D4 - advances paid to staff.** `staff_advances` (amount, paid on, mode,
monthly recovery, first recovery month, reason) and
`payslip_lines.staff_advance_id`. Each payroll run adds an "Advance recovery"
deduction line per advance still owed, oldest first: the monthly amount, or
what is left, or what the payslip can bear, whichever is least - never
below zero. Recovered = the lines on finalized and paid runs; a draft's line
is pending and is rebuilt with the draft, so nothing is counted twice.
Repaid is worked out, not stored. Cancelled (with a reason) only while
nothing is recovered. Recorded by whoever manages payroll; it is not fee
money, so the date lock does not apply. The Payroll screen's Advances tab.
