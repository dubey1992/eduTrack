# Fee Management (plan)

**Status (2026-10-29): F1 "Fee Set-up" and F2 "Dues" built (backend); F3-F5
planned.** See "F1 as built" and "F2 as built" at the end. What a school charges its
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
| `reminder_days_before` | int, 0-30 | 3 (0 = off) | the nightly reminders job |
| `remind_when_overdue` | bool | true | the nightly reminders job |
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
- **paying more than is owed is refused.** No advance or credit balance in
  v1 *(engineering choice)*: a credit balance is a liability the school has
  to track, and refunds come with it.

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

Both run in the nightly job, one message per guardian per day with every due
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
3. **No advance payments or credit balance**, so no refunds in v1.
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
- `waived` dues keep `balance = amount - discount - paid` until F4 decides
  how a waiver is recorded.
- Overdue and "after today" use the school's own date (docs/timezones.md).
