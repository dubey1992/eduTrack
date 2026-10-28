# Fee Management (plan)

**Status (2026-11-01): all five steps built - F1 "Fee Set-up", F2 "Dues",
F3 "Collection & receipts", F4 "Discounts, waivers and late fines" and F5
"Reminders, reports and dashboard". The module is complete.** See "F1 as
built" to "F5 as built" at the end. What a school charges its
students, what each student owes, the payments the office takes, receipts,
discounts, late fines, reminders and reports, behind its own module switch.
Built on the Python backend only; Laravel's migrations still create the
tables, as for Payroll (`docs/payroll.md`).

CLAUDE.md lists Fee management as *future/optional, do not implement unless
explicitly requested*. It was requested on 2026-10-28 ("the Fees Management
feature is missing... plan to implement this feature with module settings").
The four rules that shape the database were decided by the product owner the
same day, question by question. Everything marked *engineering choice* follows
from them and is named so it can be challenged before any code is written.

```
FEATURE:        Fee Management, as a switchable module
OBJECTIVE:      Charge students by class and bus route in installments, take
                payments at the office with numbered receipts, apply discounts
                and late fines, remind guardians, and report what is collected
                and what is owed
DATABASE:       fee_heads, fee_structures, fee_installments, fee_concessions,
                student_fee_dues, fee_receipts, fee_receipt_allocations,
                fee_receipt_sequences; students.admission_date (new, nullable)
API:            /fees/heads, /fees/structures, /fees/students/{id}, /fees/dues,
                /fees/concessions, /fees/receipts, /fees/reports/*
FLUTTER:        A "Fees" sidebar group: Fee Setup, Collect Fees, Receipts,
                Discounts, Fee Reports; a Fees tab on a student's record
AUTHORIZATION:  SCHOOL_ADMIN and ACCOUNTANT manage (own school), GROUP_ADMIN
                their scope, SUPER_ADMIN read only; module switch + matrix row
VALIDATION:     amounts > 0 with 2dp, installments sum to the structure amount,
                due dates inside the academic year, payment <= what is owed,
                one structure per class/route + head + year
BUSINESS RULES: below
TESTS:          ALLOW/DENY per endpoint and role, cross-school DENY, the dues
                arithmetic, receipt numbering under concurrency, cancellation,
                fines job, reminders, PDF; Flutter unit/widget + one end-to-end
                accountant flow (set up -> collect -> receipt)
DEPENDENCIES:   Students, Academic Years, Classes & Sections, Promotion
                (enrollments), Transport routes and assignments, School
                currency and timezone, Communication, the queue, Reports
```

## The four decisions (2026-10-28)

1. **Per class, per year, in installments.** The school names its fee heads
   (Tuition, Admission, Exam, Library...). For each class and academic year it
   sets an amount per head and how it is split: monthly, quarterly, per term,
   yearly or one-time, each installment with its own due date. Every student
   in that class is charged automatically.
2. **Discounts and late fines.** Per-student discounts, fixed or a
   percentage, each with a reason. A late fine added once an installment is
   overdue past a grace period. Both can be switched off.
3. **Recorded at the office.** The Accountant or an admin records money
   received - cash, bank transfer, UPI, cheque, card, online transfer -
   part-payments allowed, and the app issues a numbered PDF receipt. A wrong
   receipt is cancelled with a reason, never deleted. **No payment gateway.**
4. **The bus fee comes from the route.** Each route has a fee; students
   assigned to it are charged automatically, and a route change changes their
   future dues.

## Who can do what

| | Accountant | School Admin | Group Admin | Super Admin | Everyone else |
|---|---|---|---|---|---|
| Fee heads, structures, installments, route fees | own school | own school | their scope | - | - |
| Discounts, waivers | own school | own school | their scope | - | - |
| Record a payment, print a receipt | own school | own school | their scope | - | - |
| Cancel a receipt | own school | own school | their scope | - | - |
| Read dues, receipts, reports | own school | own school | their scope | every school | - |

The matrix row is editable per role like every other module
(docs/settings.md), so a school can give office **Staff** "manage" to let a
front-desk clerk collect fees, or **Teachers** "view". Out of the box only
the two roles above see it *(engineering choice: a family's money is not
every teacher's business)*.

## The module and its settings

New module `fees` ("Fee Management") in `school/modules.py`, switchable.

**Not granted by default** *(engineering choice)*. Every school on the
platform today would otherwise find a new sidebar group the morning it ships,
with nothing set up behind it. The Super Admin grants it per school, and the
School Admin may then switch it off like any other module. Off means hidden
plus `403 MODULE_DISABLED`, and the automatic jobs (fines, reminders) skip
that school.

| Setting | Type | Default | What reads it |
|---|---|---|---|
| `late_fine_amount` | int (whole currency units) | 0 = no fines | the nightly fines job |
| `late_fine_grace_days` | int, 0-90 | 7 | the nightly fines job |
| `reminder_days_before` | int, 0-30 | 3 (0 = off) | the hourly reminders job (F5) |
| `remind_when_overdue` | bool | true | the hourly reminders job (F5) |
| `allow_part_payment` | bool | true | Record Payment |

Module settings only hold whole numbers and on/off switches today, which is
why the fine is in whole units. A fine in cents would need a new setting
type; not worth it for v1.

## What is charged

**Fee heads** - per school, a name unique within the school (case-blind,
because PostgreSQL is not), active or retired. One head, **Transport**,
exists in every school and cannot be renamed or retired: route fees hang
off it.

**Fee structures** - one row per *(academic year, class, head)*, or per
*(academic year, bus route, Transport)*: an amount, a frequency, and its
**installments** (label, due date, amount). Frequency fills the installments
in for the Accountant to adjust:

| Frequency | Installments offered |
|---|---|
| monthly | one per month of the academic year, due on a chosen day |
| quarterly | four |
| per term | one per academic term (the terms Assessments already defines) |
| yearly / one-time | one |

The installments must add up to the amount *(rounding goes on the last)*,
and every due date falls inside the academic year. A structure is a
**draft** until published; publishing charges the students.

## What each student owes: dues

A **due** is one line on a student's account: one installment of one head,
its amount, any discount, what has been paid, and a status (`pending`,
`partial`, `paid`, `waived`, `cancelled`). A late fine is a line of its own,
pointing at the installment it is for, so a statement shows it plainly
rather than folding it into the fee. Every due carries the school's
`currency_code` (CLAUDE.md section 5).

**When dues are created** - always from the published structure, never typed:

- a structure is published: every active student enrolled in that class (or
  assigned to that route) that year;
- a student is added, moved to another class, or promoted: the new class's
  dues for that year;
- a student is given a bus route or moved to another one.

**Who joins late pays from when they joined.** Only installments due on or
after the student's **admission date** are charged. Students have no such
date today, so this adds an optional `admission_date` to the student form,
defaulting to the day the record is created *(engineering choice)*.

**Changes never rewrite history.**

- Editing a published structure changes only **unpaid** dues. A partly paid
  due cannot drop below what has been paid; a paid one is never touched.
- **A student who moves class or route**: the old class's or route's unpaid
  dues that fall due *after* the move are cancelled and the new one's are
  created. Anything already overdue stays owed.
- **A student who leaves** (status left/inactive): unpaid dues falling due
  after that day are cancelled; overdue ones stay owed. A graduated student
  is treated the same way at year end.
- Every one of these is a transaction and is audited.

## Discounts and waivers

A **discount** belongs to one student for one academic year: fixed or a
percentage, on one head or on all of them, with a reason (sibling,
scholarship, staff child...). It applies to that student's unpaid dues and
to any dues created later that year, and never takes a due below zero or
below what has been paid. Removing it restores the unpaid dues.

A **waiver** forgives one due outright, with a reason - for a fine charged
in error, or a hardship case. Both are audited with who and why.

## Late fines

A nightly job, per school with the module on and `late_fine_amount` above
0: every installment still unpaid `late_fine_grace_days` after its due date
gets **one** fine line, once - no compounding, no daily accrual
*(engineering choice; a per-day fine can be added later)*. "Overdue" is
judged in the school's own timezone (docs/timezones.md). Paying the
installment does not remove its fine; waiving the fine does.

## Taking a payment

**Collect Fees**: find the student (name, admission number, class), see
everything owed, oldest first, and record a payment:

- date (not in the future), amount, mode, reference (cheque number, UTR,
  card slip), note;
- the amount is spread over the dues **oldest first**, and the Accountant
  can untick lines to pay specific ones instead;
- a part-payment is allowed unless `allow_part_payment` is off;
- ~~paying more than is owed is refused~~ - **since F6, the rest is held as
  the student's credit** and pays their next fees (see "F6 as built").

The receipt number is **sequential per school and academic year, with no
gaps and no reuse**: `RCPT-2026-00001`. It is taken from a counter row
locked inside the payment's transaction, so two clerks saving at the same
moment cannot get the same number. The PDF reuses the receipt engine Super
Admin payments already have (`school/receipts.py`): school name, student,
class, what was paid against which installment, mode, balance still owed.
It is printable, downloadable and optionally emailed to the guardian.

**Cancelling a receipt** needs a reason. The receipt stays in the list,
stamped *Cancelled*, its number never reused, and the dues it paid go back
to owing. Nothing about money is ever deleted.

## Reminders

Through the existing Communication module and its **fee reminder** template
(docs/communication.md), so the wording, channels (SMS / WhatsApp / email /
app) and guardian contacts are the ones the school already set up:

- `reminder_days_before` days before a due date, to every guardian with an
  unpaid due that day;
- once when a due becomes overdue (`remind_when_overdue`).

Both run in the hourly job (F5), one message per guardian per day with every due
listed *(engineering choice: three installments due together are one text,
not three)*. With Communication switched off, nothing is sent. The hand-sent
fee reminder stays, and now fills in the amount and due date from the
student's real dues.

## Reports

In the Reports screen, PDF and CSV, with the previous-period column like the
other reports (docs/reports.md):

- **Collection** - by date range, by mode, by collector, by head.
- **Outstanding & defaulters** - by class, with how overdue (0-30, 31-60,
  60+ days), guardian contact and total owed.
- **Student statement** - one student's full ledger for a year, printable for
  a parent.
- **Discounts & waivers** - what was forgiven, to whom, why, by whom.

Dashboard cards for the School Admin and Accountant: collected this month,
outstanding, overdue students.

## Screens (Flutter, web portal)

| Screen | What it does |
|---|---|
| Fee Setup | Heads; per year, a class x head grid of structures with their installments; route fees; publish |
| Collect Fees | Student search -> dues -> record payment -> receipt |
| Receipts | All receipts, search and filter, reprint, cancel |
| Discounts | Per-student discounts for the year; waivers |
| Student record -> Fees tab | That student's ledger and receipts |
| Fee Reports | The four reports above |

Every screen with loading, empty and error states, field-level validation,
in-app confirmation dialogs (never browser popups), and success messages.

**The phone apps get nothing in v1** *(engineering choice)*. Collection
happens at an office desk, and there is no parent app (CLAUDE.md lists it as
future).

## API

| Endpoint | Who |
|---|---|
| `GET/POST /fees/heads`, `PATCH /fees/heads/{id}` | manage |
| `GET/POST /fees/structures`, `GET/PATCH/DELETE /fees/structures/{id}` (draft only), `POST .../publish` | manage |
| `GET /fees/students/{id}` - dues, discounts, receipts | view |
| `GET /fees/dues` - paginated, filter by class, status, overdue | view |
| `POST /fees/dues/{id}/waive` | manage |
| `GET/POST /fees/concessions`, `DELETE /fees/concessions/{id}` | manage |
| `GET/POST /fees/receipts`, `GET /fees/receipts/{id}`, `GET .../pdf`, `POST .../cancel` | view / manage |
| `GET /fees/reports/{collection,outstanding,statement,concessions}` (+ `?format=pdf|csv`) | view |

School context always comes from the signed-in user, never the client's
`school_id` (CLAUDE.md section 10). Every list is paginated and filtered
server-side.

## Tables

| Table | Holds | Key constraints |
|---|---|---|
| `fee_heads` | name, is_transport, is_active | unique (school, lower(name)) |
| `fee_structures` | year, class **or** route, head, amount, currency_code, frequency, status | unique (school, year, class, head) and (school, year, route, head); exactly one of class/route |
| `fee_installments` | structure, label, due_date, amount, sequence | sum = structure amount |
| `fee_concessions` | student, year, head (nullable = all), type, value, reason, created_by | |
| `student_fee_dues` | student, year, head, installment (nullable for fines), fine_for_due_id, label, due_date, amount, discount, paid, currency_code, status | index (school, status, due_date), (student, year) |
| `fee_receipts` | student, number, date, amount, currency_code, mode, reference, note, received_by, status, cancelled_by/at/reason | unique (school, number) |
| `fee_receipt_allocations` | receipt, due, amount | |
| `fee_receipt_sequences` | school, year, last_number | unique (school, year); row-locked |
| `students.admission_date` | new, nullable date | |

Every amount is `DECIMAL(12,2)` beside a `currency_code`. Every write that
touches more than one row is one transaction. Every change is in the audit
log.

## Build order - five slices, each shippable

| Slice | Delivers | Shippable because |
|---|---|---|
| **F1 Set-up** | module + matrix row, fee heads, structures, installments, route fees, publish (no charging yet) | a school can enter its fee book |
| **F2 Dues** | charging on publish/admission/class change/route change/leaving/promotion, admission date, student Fees tab, dues list | the school sees who owes what |
| **F3 Collection** | Collect Fees, receipts, numbering, PDF, email, cancellation | the office takes money - the day-one need |
| **F4 Adjustments** | discounts, waivers, nightly late fines | |
| **F5 Reminders & reports** | nightly reminders, the four reports, dashboard cards | |

Each slice gets the usual: migration, models, validation, ALLOW/DENY and
cross-school tests, Flutter data/state/UI with widget tests, a live demo in
the browser, then production.

## Choices you can overrule before F1 starts

1. **Not granted by default** - the Super Admin switches it on per school.
2. **Only Admin and Accountant** see fees out of the box (the matrix can widen it).
3. ~~No advance payments or credit balance~~ - overruled 2026-10-28: credit
   is held and refunded (F6).
4. **One late fine per installment**, not per day.
5. **`admission_date` is added to students** to charge mid-year joiners fairly.
6. **No phone-app screens** in v1.
7. **One reminder message per guardian per day**, listing every due.

Also: CLAUDE.md section 3 still lists Fee management as future/out of scope,
and section 17's phase plan has no fees phase. Both should be updated when
this plan is approved.

## F1 as built (2026-10-28)

Backend (Python) and the Laravel migration
`2026_10_28_100000_create_fee_set_up_tables.php` (`fee_heads`,
`fee_structures`, `fee_installments`). Code: `school/fees/` (service,
requests, resources, plan), `school/views/fees.py`, `FeePolicy`. Tests:
`test_fees_set_up_api.py`, `test_fees_plan.py`.

Endpoints, all under `/api/v1/`:

| Endpoint | Does |
|---|---|
| `GET fees/heads?school_id=` | `{"data": [head]}`, Transport first, then active by name, then retired. Not paginated (at most 50) |
| `POST fees/heads`, `PATCH/DELETE fees/heads/{id}` | create, rename / retire / restore, delete an unused one |
| `GET fees/structures?academic_year_id=&kind=class\|route` | `{"data": [structure]}`, classes by level then routes by name, each by head. Not paginated |
| `POST fees/structures`, `GET/PUT/DELETE fees/structures/{id}` | create (draft), read, replace amount + frequency + installments, delete a draft |
| `POST fees/structures/{id}/publish`, `POST fees/structures/publish` | publish one (again = no-op), or every draft of a year (`{"published": n}`) |
| `GET fees/installment-plan?academic_year_id&frequency&amount&due_day=10` | suggested installments; nothing saved |

What differs from, or was settled beyond, the plan above:

- **No module settings yet.** The five settings listed under "The module and
  its settings" arrive with the slices that read them (F3-F5).
- **Unique keys are on the year, not the school**: `(academic_year, class,
  head)` and `(academic_year, route, head)` - a year already belongs to one
  school. "Exactly one of class or route" is checked by the application, not
  a CHECK constraint (MySQL and PostgreSQL differ there).
- **Head names are case-blind unique in the application**, under a row lock
  on the school (which also guards the 50-head cap); the database key on
  `(school_id, name)` is case-sensitive on PostgreSQL.
- **Editing a published fee is allowed in F1** (PUT) because nothing is
  charged yet. F2 turns that edit into "update the unpaid dues only".
- **Publishing in F1 only changes the status.** No dues are created until F2.
- **A retired head cannot be used for a new fee**; existing fees keep it.
- **PUT, not PATCH, on `fees/structures/{id}`** (the API table above said
  PATCH): the amount, frequency and installments are replaced whole, as the
  form edits them as one. The year, class or route, and head are fixed.
- **Deleting a class, a bus route or an academic year with fees** is refused
  with 409 `HAS_DEPENDENT_RECORDS` ("This class has fees set up for it.
  Delete its fees first."). A year's or class's published fees cannot be
  deleted in F1, so such a year or class can no longer be deleted either.
- **School context**: a school-bound user always works in their own school.
  A Super Admin or Group Admin names one with `school_id`; naming none on
  `GET fees/heads` lists every school in their scope that has the module on
  (as payroll's lists do), and on `POST fees/heads` is a 422. Structures,
  publish-all and the plan take the school from the academic year. Another
  school's record by id is a 403; another school's id inside a form or
  filter is "The selected ... is invalid." (422).
- **Money** goes out as strings with two decimals (`"12000.00"`), as
  payroll does; due dates as `YYYY-MM-DD`.
- **Plan details**: quarterly installments use `due_day` like monthly ones;
  every suggested due date is kept inside the academic year; an amount too
  small to give each installment a cent is a 422.

## F2 as built (2026-10-29)

Backend (Python) and the Laravel migration
`2026_10_29_090000_create_student_fee_dues_table.php` (`student_fee_dues`,
`students.admission_date`). Code: `school/fees/dues.py` (the reconcile),
`school/fees/ledger.py` (statement and balances), resources and the two views
in `school/views/fees.py`, the `sync_fee_dues` command. Tests:
`test_fees_dues.py` (charging), `test_fees_dues_api.py` (reading, access,
admission date).

**One reconcile.** `FeeDueService.sync_student(student, year)` (bulk:
`sync_many`) works out what a student should be paying for a year and brings
the ledger in line. It is idempotent and runs in the triggering write's
transaction. Expected = nothing unless the student is `active` and their
enrollment that year is not `left`; otherwise every installment of every
published fee of their **enrollment's** class that year, plus the published
Transport fee of the route they ride **now** (if enrolled that year), each due
on or after the day they joined (`admission_date`, else the school-local date
the record was created). Then: missing dues are created; a cancelled due for
an expected installment is revived (same row - the unique key is one per
student per installment); a `pending` due with nothing paid, no longer
expected and due **after** the school's today is cancelled with a reason
(`left`, `class_changed`, `route_changed`, else `fee_changed`); a `pending`
due follows its installment's amount, date and label; a `partial` one takes
max(new amount, paid); `paid` and `waived` are never touched.

**Where it is called** (each inside the triggering transaction):

| Trigger | Students | Years | Audit `entity_type` |
|---|---|---|---|
| Publish one fee | enrolled in its class that year, or riding its route and enrolled that year, plus anyone it already charges | the fee's | `fee_structure` |
| Publish all of a year | the union over the drafts, each once | that year | `academic_year` |
| PUT a published fee | as publish | the fee's | `fee_structure` |
| Student create / PATCH (only when `class_section_id`, `status` or `admission_date` changed) / activate / deactivate | that student | every year they are enrolled in or owe in that has not ended | `student` |
| Promotion run | everyone in the batch | the year closing (all), the year opening (promoted and retained) | `promotion` |
| Bus route assign (only when the route changed) / unassign | that student | years with a published fee for the old or new route that have not ended | `transport_assignment` |
| `sync_fee_dues --school ID [--year ID]` | everyone enrolled in the year | the given year, or every year with a published fee | `academic_year` (no user) |

One `fee_dues.synced` audit row per action that changed something, with
`new_values` = `{created, revived, cancelled, updated}`; a no-op writes none.
The bulk paths read the published installments once per year and the
students, enrollments, routes and dues in one query each, then write with one
bulk insert and one bulk update.

**Moving mid-year: from the day of the move (decided 2026-10-28, the
product owner's choice).** A student who moves class or bus route mid-year
is charged the *new* one's installments only from the day of the move
onward - never two classes, or two routes, for the same month. Migration
`2026_10_29_100000_add_since_dates_for_fees.php` adds
`student_enrollments.class_since` and
`student_transport_assignments.route_since` (nullable dates), set to the
school-local today by `StudentEnrollmentService.sync_current_year` when an
existing enrollment's class changes within the year, and by
`StudentTransportService.assign` when the route changes. A new enrollment
(admission, promotion into the next year) and a student's first route leave
them null, so the joining date counts. A class installment is expected only
if due on or after max(joining date, `class_since`); a route installment
likewise with `route_since`. The old class's or route's dues falling due
after today are cancelled as before; anything already due stays owed. Moving
back sets the date again, so the original class's lines that fell due while
the student was away stay cancelled rather than revived.

**Editing a published fee: installments in place.** The dues point at the
installments (foreign key, restrict), so a PUT on a *published* fee no longer
replaces them wholesale: installment N keeps its row and takes the new label,
date and amount; extra rows are added (and charged); dropping an installment
from the end is refused while any student holds a non-cancelled due for it -
422 on `installments`, "Installment N already has students charged. Change
its amount or date instead of removing it." - and allowed once only
cancelled dues point at it (those are deleted with it). Drafts are still
replaced wholesale.

**API** (all `/api/v1/`, FeePolicy.view, module switch as F1):

- `POST fees/structures/{id}/publish` -> the structure plus
  `"charged": {"students", "dues_created"}` (students who gained a due; dues
  created + revived). `POST fees/structures/publish` -> `{"published",
  "students", "dues_created"}`. Every structure resource gains
  `students_count` - distinct students holding a non-cancelled due of it (a
  student who left still counts while they owe it); 0 for drafts.
- `GET fees/students/{id}?academic_year_id=` -> the statement: student (class
  and section from that year's enrollment), year, currency, every due
  (cancelled ones included, ordered by due date then head name) with
  `balance` and `is_overdue`, and totals that leave cancelled dues out. Year
  defaults to the school's current year, else the latest the student owes in,
  else the school's latest. 404 unknown student, 403 another school's, 422 a
  year that is not the student's school's.
- `GET fees/balances?academic_year_id=&school_id=&school_class_id=&class_section_id=&search=&owing=1&overdue=1&page=&per_page=`
  -> the usual paginated envelope. Rows are enrollments of the year whose
  student is active or holds a non-cancelled due; totals are correlated
  subqueries (query count does not grow with the page). `next_due_date` is
  the earliest still-owed due on or after today. Ordered by class level,
  class name, section name, roll number (the enrollment's, compared as text),
  name.
- Students: `admission_date` on create and PATCH (ISO date, 1950-01-01 to
  the school's today + 365 days, null clears) and in the student resource
  (and in `contract/shapes.py`).

**Known limits, left on purpose:**

- **The bus fee follows the route ridden now**, in every running year. A
  past year is never touched by a route change, but the repair command run
  over an ended year would use today's route.
- ~~`waived` dues keep `balance = amount - discount - paid` until F4 decides
  how a waiver is recorded.~~ F4: a waived or cancelled due owes 0.
- Overdue and "after today" use the school's own date (docs/timezones.md).

## F3 as built (2026-10-30)

Backend (Python) and the Laravel migration
`2026_10_30_090000_create_fee_receipts_tables.php` (`fee_receipts` with a
frozen `balance_before`, `fee_receipt_allocations`, `fee_receipt_sequences`).
Code: `school/fees/receipts.py` (FeeReceiptService), `school/fees/receipt_pdf.py`,
`school/fees/words.py` (amount in words), the request classes and resources
beside F1/F2's, five views in `school/views/fees.py`, the
`fee_receipt_email` job in `school/jobs.py`. Tests: `test_fees_receipts.py`
(rules, numbering, concurrency, cancelling, the reconcile, email, PDF, words)
and `test_fees_receipts_api.py` (list, access).

**Module setting** `fees.allow_part_payment` (bool, default on) - the first
fees setting. Off: a payment must settle every installment it touches.

**Endpoints** (all `/api/v1/`, FeePolicy and the module switch as F1/F2: view
for reads, manage for writes; Super Admin reads only):

| Endpoint | Does |
|---|---|
| `POST fees/receipts` | `{student_id, receipt_date, amount, payment_mode, reference?, note?, allocations?: [{due_id, amount}], email_to_guardian?}` -> 201 receipt + `email_queued` |
| `GET fees/receipts` | paginated; `school_id, academic_year_id, student_id, search, payment_mode, status, from, to`; newest `receipt_date` then id first |
| `GET fees/receipts/{id}` | the receipt |
| `GET fees/receipts/{id}/pdf` | `application/pdf`, attachment `RCPT-....pdf` |
| `POST fees/receipts/{id}/cancel` | `{reason}` 3-500 chars -> 200 receipt; again -> 409 `FEE_RECEIPT_CANCELLED` |
| `POST fees/receipts/{id}/email` | 202 `{"queued": true}`; no guardian email -> 422 on `guardian_email` |
| `GET fees/students/{id}` | gains `receipts` - the student's receipts numbered in the statement's year, newest first, cancelled included |

The receipt resource: id, receipt_number, receipt_date, amount, currency_code,
payment_mode(+_label), reference, note, status (`valid`/`cancelled`), student
{id, name, admission_number, class_name, section_name} (class from the
enrollment in the receipt's year), academic_year {id, name}, received_by,
allocations [{due_id, label, due_date, amount}] oldest first, cancelled_at/by,
cancel_reason, emailed_at, `balance_before` / `balance_after` (as at the
receipt, in its currency, frozen), `student_balance` (owed now, every year),
created_at.

**Rules as built:**

- **Numbers**: `RCPT-{year token}-{n:05d}`, the token being the academic
  year's name with every run of non-alphanumerics made one hyphen
  (`2026-27` -> `RCPT-2026-27-00001`). The year is the school's year whose
  dates contain `receipt_date` - not necessarily the year of the dues paid;
  none -> 422 on `receipt_date`. Sequential per (school, that year).
- **No race, no gap**: the counter row is read with `SELECT ... FOR UPDATE`
  inside the payment's transaction (created race-safely: insert in a
  savepoint, on a unique-key clash re-read the other payment's row and wait
  on its lock). A second clerk blocks until the first commits and takes the
  next number; a payment that fails rolls its number back. Unique key
  (school, receipt_number) behind it. Tested with two real threads.
- **Locks**: the student row first (the same row the F2 reconcile locks, so
  payments and reconciles of one student take turns), then the dues, then
  the counter.
- **Spreading** (no `allocations`): open dues (pending/partial), oldest due
  date then id, across every year. More than owed -> 422 on `amount`
  ("This is more than {student} owes (INR 4,000.00). Advance payments are
  not taken."). Dues in two currencies are never spread over -> 422 on
  `allocations`, choose the installments.
- **Chosen** (`allocations`): each due must be the student's (else "The
  selected installment is invalid."), pending or partial (paid / waived /
  cancelled named), not listed twice, amount > 0 and <= its balance, one
  currency, and the lines must add up to `amount`. All problems under
  `allocations`.
- After paying: `paid` when nothing is left, else `partial`. The receipt's
  currency is the dues' (fee) currency.
- `receipt_date` ISO, not after the school's today; mode one of cash,
  bank_transfer, upi, cheque, card, online_transfer; a cheque needs
  `reference`.
- **Cancelling** takes each allocation back off its due (never below 0) and
  recomputes pending/partial/paid; a due that is `cancelled` or `waived`
  keeps that status and only its paid amount moves (the reconcile never
  cancels a due with money on it, so a cancelled due holds money only from a
  receipt that has itself since been cancelled; a waiver is F4's to undo).
  Then the F2 reconcile runs for the student over the affected years that
  have not ended - so a due that is unpaid again, no longer expected (the
  student moved class or route) and falling due after today is cancelled as
  F2 would have; one already due stays owed. Audited as `fee_dues.synced`
  with `entity_type` `fee_receipt` when it changes anything.
- **F2 change**: a part-paid due whose fee is cut to (or below) what was
  paid now becomes `paid` (amount = paid), instead of staying `partial` with
  nothing left to pay.
- **Email**: the `fee_receipt_email` job (database queue, cron-drained) sends
  the PDF to `students.guardian_email` and sets `emailed_at`; an address
  removed since queueing is logged and skipped.
- **Audit**: `fee_receipt.created` (number, amount, currency, mode,
  allocations), `fee_receipt.cancelled` (old status; new status, number,
  reason, allocations).
- Deleting an academic year that has receipts dated in it -> 409
  `HAS_DEPENDENT_RECORDS`.

**The PDF** (product owner, 2026-10-28: "high level and attractive, no
information missed"): A4; a blue (#2563EB) header band with the school's logo
(fetched with a 3 s timeout, at most 2 MB, png/jpeg/gif, any failure logged
and the logo left out), name, address line, phone, email, registration
number; "FEE RECEIPT" and the number on the right. A red CANCELLED box with
reason, who and when on a cancelled one. Receipt details (number, date,
academic year, mode + reference, received by) beside the student (name,
admission no., class - section, roll no., guardian, guardian mobile). Items
table (#, fee type, installment, due date, amount) with zebra rows; total
received and the amount in words ("Indian Rupees Two Thousand and Fifty Paise
Only"; unknown currency codes print as the code with "Hundredths"); owed
before / paid now / still owed after, as frozen on the receipt; the note;
footer with "computer-generated", issued date-time in the school's timezone,
"Powered by School365ai". Empty optional fields are left out, never "None".

## F4 as built (2026-10-31)

Backend (Python) and the Laravel migration
`2026_10_31_090000_add_fee_adjustments.php`: `fee_concessions`, and on
`student_fee_dues` the columns `kind` (`installment` | `late_fine`),
`fine_for_due_id` (unique, nullOnDelete), `waived_at`, `waived_by`,
`waive_reason`, with `fee_structure_id` and `fee_installment_id` made
nullable (a fine has neither; `->change()`, native in Laravel 11+, on both
engines - NULLs never collide in the (student, installment) unique key).
Code: `school/fees/concessions.py` (ConcessionService, WaiverService),
`school/fees/fines.py` (LateFineService), the discount step in
`school/fees/dues.py`, the `apply_late_fines` command. Tests:
`test_fees_adjustments.py` (rules, fines job) and
`test_fees_adjustments_api.py` (list, form, statement, access).

**Decisions (product owner, 2026-10-28):**

- **A discount** is per student per academic year, fixed or a percentage,
  on one fee type or all of them (`fee_head_id` null), with a reason. **A
  fixed amount comes off each installment** of the matching fee types (500 on
  a 12-installment Tuition = 500 off each); a percentage is of each
  installment's amount (rounded half-up to the cent). Several on one
  installment add up, never beyond `amount - paid`.
- **Part of the reconcile.** The F2 reconcile works every owed due's
  `discount_amount` out afresh from the student's active concessions for the
  year, after pricing and cancelling. So a new discount reaches the dues at
  once (same transaction), dues created later that year arrive discounted,
  and revoking gives the dues back. Paid, waived and cancelled dues keep the
  discount they had (a paid one is never reopened, either way). Late fines
  are never discounted.
- **A waiver** forgives one pending or part-paid due (installment or fine)
  outright: status `waived`, balance 0, who/when/why kept; a part-paid one
  keeps its paid amount.
- **Late fines**: module settings `late_fine_amount` (whole units, 0 = off,
  max 1,000,000) and `late_fine_grace_days` (0-90, default 7). Hourly
  `apply_late_fines [--school ID]`: each installment still owed whose
  `due_date + grace < the school's today` gets **one** fine due, once ever.

**Rules as built, and what was settled beyond the decisions:**

- **Balance** = amount - discount - paid, except **waived and cancelled owe
  0** (the F2 statement showed a cancelled line's full amount as its
  balance; it now shows 0.00). Statement totals: `charged` (not cancelled),
  `discount`, `paid`, `balance`, `overdue`, and new `waived` = sum of
  amount - discount - paid over waived dues (a waived due takes no more
  money, so this is what was forgiven). The balances list sums only dues
  still owed.
- **A due a discount takes to nothing stays `pending` (or `partial`) with
  balance 0.00** rather than becoming `paid`: it was not paid, and only an
  open due follows the concessions - so revoking a 100% scholarship charges
  the installments again. Such a due is never overdue, never fined, never
  waivable (nothing owed) and skipped when a payment is spread. A part-paid
  due whose remainder a discount covers likewise stays `partial`. (The F3
  rule "fee cut to what was paid -> paid" now looks at amount - paid only.)
- **Fines**: `kind` `late_fine`, `fine_for_due_id` = the installment due,
  fee type and year and currency the installment's, label `Late fine -
  {installment label}` (cut to 130), due date = the school-local day it was
  added, amount = the setting at that moment. Fined only: installments
  pending/partial with something left to pay; students `active` whose
  enrollment in that year is not `left`; schools with the module on. The
  database's unique key on `fine_for_due_id` backs "once"; the job also
  locks the students' rows (as payments do) and skips installments already
  fined. Paying the installment later keeps the fine; waiving the fine
  forgives it; a waived fine is never re-added. The reconcile ignores fines
  entirely, so a class or route change, leaving, or `sync_fee_dues` never
  cancels one. A fine is paid like any due, oldest first by its own date.
- **Editing a published fee** that drops installments deletes their
  cancelled dues as before; a fine pointing at one is unlinked
  (`fine_for_due_id` null, as the migration's nullOnDelete does) and stays
  owed.
- **Audit**: `fee_concession.created` (kind, value, reason, fee type, dues
  updated), `fee_concession.revoked` (with the optional reason),
  `fee_due.waived` (old status and balance; forgiven, reason) and the usual
  `fee_dues.synced` with `entity_type` `fee_concession`;
  `fee_late_fines.applied` once per school per run that added fines
  (`{fines, students, amount_each, grace_days, date}`, no user).

**Endpoints** (all `/api/v1/`, FeePolicy and the module switch as before):

| Endpoint | Does |
|---|---|
| `GET fees/concessions` | paginated, newest first; `academic_year_id, student_id, school_id, include_revoked`; active only by default |
| `POST fees/concessions` | `{student_id, academic_year_id, fee_head_id?, kind, value, reason}` -> 201 discount |
| `DELETE fees/concessions/{id}` | optional `{reason}` (3-255) -> 200 discount, revoked; again -> 409 `FEE_CONCESSION_REVOKED` |
| `POST fees/dues/{id}/waive` | `{reason}` 3-255 -> 200 due (as in the statement); not owed -> 409 `FEE_DUE_NOT_WAIVABLE` |
| `GET fees/students/{id}` | each due gains `kind`, `fine_for_due_id`, `waive_reason`, `waived_at`; totals gain `waived`; top level gains `concessions` (active, that year) |

The discount resource: id, student {id, name, admission_number, class_name
(that year's)}, academic_year {id, name}, fee_head {id, name} or null, kind,
value, reason, created_by, created_at, revoked_at, revoked_by, currency_code
(the school's), `dues_affected` - the student's installment dues that year of
its fee type (any, for all types), not cancelled, carrying a discount now; 0
once revoked.

Validation: student and year the actor's and one school's (another school's
-> "invalid", 422); the student enrolled in the year or owing in it; fee type
the school's and active (Transport allowed); kind `fixed` | `percent`; value
> 0 with 2 decimals, a percentage at most 100; reason 3-255 characters
(trimmed). A record of another school by id -> 403.

## F5 as built (2026-11-01)

Backend (Python) and the Laravel migration
`2026_11_01_090000_create_fee_reminder_logs_table.php` (`fee_reminder_logs`).
Code: `school/fees/reminders.py` (FeeReminderService), the
`send_fee_reminders` command, `school/reports/fees.py` (the three reports),
`school/fees/statement_pdf.py`, `fee_cards()` in `school/dashboard.py`, and
the fill-in in `SendNoticeRequest`. Tests: `test_fees_reminders.py` and
`test_fees_reports_api.py`. The whole module is now built; the plan's four
"reports" became three reports in the Reports screen plus the student
statement PDF.

**Module settings** `reminder_days_before` (int 0-30, default 3, 0 = off)
and `remind_when_overdue` (bool, default on).

**Reminders** - hourly `send_fee_reminders [--school ID] [--dry-run]`
(cron line in docs/deployment.md), every school with fees on:

- On the school's own today: **upcoming** - dues still owed falling due on
  today + `reminder_days_before` (when above 0); **overdue** - dues still
  owed that fell due yesterday, the first day they are overdue (when
  `remind_when_overdue`). Installments and late fines alike. "Still owed":
  pending or part-paid with something left after discount and payments, of a
  student who is active and has not left in that due's year. A due a
  discount covers in full is never mentioned.
- **One message per guardian per kind per day.** Dues are grouped by
  guardian key: `m:` + the digits of `guardian_mobile`, else `e:` + the
  lower-cased `guardian_email` (hashed past 120 characters), else `s:` + the
  student id - so siblings sharing a mother's number, written any way, get
  one message. The guardian is reached on the first-named student's contact
  details (the ones the group shares).
- **Wording**: the `fee.reminder` template with its new `{fee_details}`
  token (docs/communication.md): every student, every due label and what is
  left on it, "Now overdue." first on an overdue one; `{student_name}` names
  every child, `{amount}` is the total per currency, `{due_date}` the day.
- **Sending**: `notify_guardian` - the school's channels, providers and
  message log; rows are recorded and `send_message` jobs queued, so the
  command never waits on a provider. Communication module off: the school is
  skipped, nothing recorded anywhere (the switched-off rule). A guardian
  with no number is a `skipped` message, as for any alert, and still counts
  as reminded.
- **Never twice**: a `fee_reminder_logs` row (school, guardian_key, kind,
  reminder_date = the school's today, student_ids as "1,2", dues_count) is
  written in the same transaction as the messages, under a unique key on
  the first four - a second run that day finds the row and sends nothing;
  two overlapping runs collide on the key and one backs off.
- **Audit**: `fee_reminders.sent` once per school per run that reminded
  anybody, no user, `{date, upcoming, upcoming_due_date, overdue,
  overdue_due_date, students, dues, messages}`.

**The hand-sent fee reminder** (Communication Center): to one student, with
Fee Management on, a missing `amount` becomes everything the student still
owes in the school's currency and a missing `due_date` the earliest date
among those dues. A value typed is kept. A student owing nothing, a group
audience, or a school without fees: both fields are required, as before.

**Reports** - `reports/fee-collection`, `reports/fee-outstanding`,
`reports/fee-concessions`; the rows, totals and rules are in
docs/reports.md "Fee reports". Read by the roles the matrix lets read fees
(plus "reports"), the Super Admin for a named school, a Group Admin over the
branches with fees on; fees off -> 403 `MODULE_DISABLED`.

**Student statement PDF** - `GET fees/students/{id}/statement.pdf?academic_year_id=`
(FeePolicy.view, year resolved exactly as `GET fees/students/{id}`):
`application/pdf`, attachment `statement-{admission number}-{year token}.pdf`
(`statement-ADM-1-2026-27.pdf`; anything not a letter or digit in the
admission number becomes a hyphen). The receipt's look: the blue band with
logo and contact lines and "FEE STATEMENT / Academic year 2026-27"; the
student (name, admission no., class - section from that year's enrollment,
roll no., status when not active, admission date, guardian, mobile, email)
beside the statement facts (year, its dates, statement date, currency) and
the account in figures (charged, less discounts, less paid, less waived,
balance due, of which overdue); every due of the year - fee type, item, due
date, amount, discount, paid, balance, status ("Paid", "Part paid,
overdue", "Covered by discount", "Waived" with its reason, "Cancelled" struck
through with why) - late fines shaded, with a totals line; the discounts in
force; every receipt dated in the year with mode, reference and who took it,
cancelled ones struck through; footer with the issue time in the school's
timezone. Figures in the statement's currency are printed without the code
(the section titles name it); a line in another currency carries its code.

**Dashboard** - three cards (`fees_collected`, `fees_outstanding`,
`fees_overdue`) for School Admin, Accountant, Group Admin and a Super Admin
looking at one school, where fees are on; docs/reports.md "The dashboard".

**Known limits, left on purpose:**

- **"Outstanding as at" a past day counts payments made since**: the ledger
  keeps balances, not their history. Rebuilding a past balance from receipts
  is possible but was not asked for.
- **A guardian group is reached on the first student's details.** Siblings
  grouped by mobile with different emails get the email copy at the first
  child's guardian email only.
- **The hand-sent fill-in** takes the school's current currency only; dues
  in an older currency are not added in.

## F6 as built (2026-11-02) - credit balance

Asked for on 2026-10-28, after "a parent pays 2-3 months in advance - then
what?": every installment of a published fee is charged when it is
published, so paying ahead already worked. The gap was afterwards. A paid
installment was never touched, so a route change, a class change or leaving
after paying ahead kept the old money on lines that no longer applied, and
the new route was charged on top. And paying more than was owed was refused.
Both are now **held as credit**.

Laravel migration `2026_11_02_090000_create_student_fee_credits_table.php`:
`student_fee_credits` (one signed row per movement - a student's credit in a
currency is the sum of their rows in it) and `fee_receipts.credit_amount`.
Code: `school/fees/credit.py`, with hooks in `dues.py` (release, apply) and
`receipts.py` (overpaid, take back). Tests: `test_fees_credit.py`.

**Where credit comes from**

- *released* - an installment paid ahead (in full or part, falling due
  after today) that stopped applying: the reconcile cancels it with its
  usual reason and its money goes to credit. One already due stays paid -
  that month was the student's. The receipts that paid it still name it.
- *overpaid* - a spread payment for more than the student owes pays
  everything and the rest is credit. A student who owes nothing can still
  pay: all of it is credit, in the school's currency. Chosen installments
  must still add up to the payment exactly.
- *returned* - see cancelling, below.

**Where it goes**

- *applied* - automatically, oldest due first, same currency only, at the
  end of every reconcile (publishing, a class or route change, admitting,
  leaving, a discount added or ended) and after a receipt is cancelled. So a
  route change's money pays the oldest line still owed, then the new route.
  Credit may leave a line part-paid even with part payments switched off:
  that setting is about money at the counter. No receipt and no number - no
  money came in - and the line shows "... from credit".
- *refunded* - `POST fees/students/{id}/credit/refund` (amount, refund date
  not in the future, mode, reference - required for a cheque - reason, and
  the currency, the school's by default). Never more than is held. Audited
  as `fee_credit.refunded`.
- *reversed* - a cancelled receipt takes back the credit it made.

**Cancelling a receipt** takes all of its money back: off each line it paid,
as far as the line still holds it, and the rest - its credit part, and what
was released from those lines since - off the credit. If the credit has
since paid other lines, those give it back (*returned*, newest first) and
are owed again. If the money was refunded, it cannot come back:
`409 FEE_RECEIPT_CREDIT_REFUNDED`, and nothing changes.

**Where it shows**: the statement (`credit` per currency, `paid_from_credit`
per line), a Credit card on the student's fees page with its History
(`GET fees/students/{id}/credit`, paginated) and Refund; the receipt
(`credit_amount`, "Held as credit" on the screen and the PDF; "still owed
after" counts only the part that paid fees); the statement PDF ("Credit held
for the next fees"); the Outstanding report's totals (`credit_held` per
currency as at the end of the period - money the school owes families if it
is never used). The reconcile's audit row adds `released`,
`credit_released` and `credit_applied` when credit moved.

Who: as fees - School Admin and Accountant read and refund; anyone who may
read a student's fees sees the credit; another school's student is a 403.

