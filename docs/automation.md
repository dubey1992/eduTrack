# Less Manual Work: Automation Plan

**Status (2026-11-05): plan only. Nothing is built until the user approves it.**

Customers will not keep an app that asks for the same thing twice, or one
that waits for someone to remember a chore. This plan lists where the product
still makes people do work it could do for them. For each place it says what
the system would do instead, and how the way people already work stays
unbroken.

## What is already automatic (not repeated here)

| Area | Already done by the system |
|---|---|
| Attendance alerts | Absent (and optionally present) messages to guardians on submit |
| Staff attendance | Fingerprint punches and the 100 m check-in mark staff present; leave days are never marked present |
| Syllabus | Filing a teaching report ticks its topic covered |
| Fees | Dues follow structures (`sync_fee_dues`), reminders (`send_fee_reminders`), late fines (`apply_late_fines`), numbered receipts, credit balance |
| Transport | Boarding alerts, SOS, trips left open are closed (`close_open_trips`), old GPS points purged |
| Results | Grades worked out from the grade scale; weak areas and one next step per student |
| Analytics | Snapshots recorded hourly; early-warning list |
| Payroll | Unpaid days pro-rated from attendance and leave; payslips emailed on finalize |
| Imports | Students, staff, fleet, tests and marks from a spreadsheet |

`school/tests/test_automation_chains.py` stays the list of chains that must
remain automatic. Every slice below adds to it.

## Rules every automation follows (so nothing breaks)

1. **The manual way stays.** Every automation is a shortcut on top of the
   existing screen. No screen loses a button, and no API changes shape.
   Clients that do not know about a new field keep working.
2. **Suggest, then the person confirms, wherever money or a child's record
   is involved.** The system may draft a payroll run, propose a timetable,
   or prefill a report. Finalizing pay, publishing marks, promoting a class
   and approving leave stay a person's decision. Nothing is auto-approved.
3. **Every automation has a switch per school**, in Settings → Automation,
   with a sensible default. Schools already live keep today's behaviour
   until an admin switches it on (decision D1).
4. **The system signs its work.** Whatever an automation creates or changes
   is written to the audit log as `System (automation name)`, with what it
   changed. People can see why something happened.
5. **Nothing is touched twice.** Every job checks what it has already done
   (the same way `sync_fee_dues` does), so a cron that runs twice, or a
   person who did the step by hand first, never gets duplicates.
6. **Same hosting.** Jobs run from the existing every-minute `work_queue`
   cron or one new hourly command. No new infrastructure.
7. **Nothing on a holiday or weekend.** Reminders and drafts respect the
   holiday calendar and each school's own time zone.

## The slices, in the order recommended

### A1. Teaching reports in one tap (biggest daily saving)

**Today:** each teacher files a report for every period they teach, every
day: class, subject, topic and notes, typed or picked each time. Six periods
a day across 30 teachers comes to about 180 forms a day.

**Instead:**
- The report opens **already filled** from the timetable: class, subject and
  period, plus the **next untaught syllabus topic** for that class in
  sequence order.
- A **"Taught as planned"** button files it unchanged. Editing is still
  allowed.
- **"Today's reports"** on the teacher's home lists each of today's periods
  with its prefilled topic. The teacher ticks the ones taught as planned and
  files them together. Each is still saved as its own report, so the HOD
  review, send-back and coverage reports are unchanged.
- A **reminder** to any teacher with periods still unreported at a
  school-set time (default 4 pm). It goes as an app push, then into the
  in-app inbox. It never goes to a teacher on approved leave (the rule found
  in the insights sweep), and it respects the check-in gate.

**Stays the same:** one report per period, the HOD review, the
check-in-required rule, and the existing form for anyone who prefers it.

**Size:** M. No table changes. The topic suggestion uses
`syllabus_scope.for_level` and existing progress.

### A2. Start the new year in one step (seasonal, needed before April 2027)

**Today:** a new academic year starts empty, because classes, sections,
class teachers, timetable, fee structures and terms all belong to one year.
The school rebuilds all of it by hand before it can promote anyone. This is
days of work in the busiest weeks of the year.

**Instead:** a **"Prepare 2027-28"** wizard, offered on the Setup Guide and
the Academic Years screen once next year exists:
1. **Classes and sections**: copy last year's, with their class teachers
   (untick any to drop, add new ones).
2. **Terms**: same pattern, dates moved on by a year.
3. **Fee structures**: copy each class and route amount, with due dates
   moved on by a year. An optional "+ x %" raise is shown before saving.
4. **Timetable**: copy each section's week onto its copy. Clashes are
   impossible because the same grid was valid last year.
5. Hand over to the existing **Promotion** wizard, with each class already
   paired with its next-year class.

Every step shows a preview, writes in one transaction, and can be skipped.
Last year is never modified. The wizard refuses to copy into a year that
already has the item, and only offers to fill what is missing (rule 5).

**Size:** L. No new tables. Copies use the existing services, so every
validation still applies.

### A3. Payroll drafts itself

**Today:** an accountant opens Payroll on the first of each month and
generates the run.

**Instead:** on a school-set day (default the 1st), the system **generates
the draft run** for last month from attendance and leave, then tells the
accountant it is ready to review. Finalize and Pay stay manual. If
attendance changes afterwards, the draft shows a "figures changed,
regenerate" note, using the existing `regenerate`.

**Size:** S. No table changes.

### A4. Nudges instead of chasing people

One hourly command, `send_nudges`, with each kind switchable:

| Nudge | To | When |
|---|---|---|
| Register not taken | Class teacher, then the admin's list | School-set cut-off (default 10 am) |
| Staff not in yet | Admin: one list with one-tap Present/Absent/Leave | Cut-off, excluding staff on leave or already punched in |
| Leave waiting for a decision | Approver; the School Admin after 24 h | Pending over N hours. **Never auto-approved** |
| Report waiting for HOD review | HOD | Pending over N days |
| Absent 3 school days in a row | Class teacher (and early warning) | After the third day's register |
| Fee structure missing for a class | Accountant | When a class has students and no structure for the year |
| Driver has not started the trip | Transport manager | 15 min past the first stop's pickup time |

Each nudge is sent once per item per day (rule 5), only on working days
(rule 7), and through the existing `notifications` and push channels.

**Size:** M. One small table, `nudges_sent`, so a nudge is never sent
twice (decision D2).

### A5. Timetable: draft it and cover absences

**Today:** the timetable is built one cell at a time. When a teacher is on
leave, their periods quietly go untaught.

**Instead:**
- **Auto-fill draft.** The school states each class's load: subject,
  periods per week and teacher. The system fills only the **empty** cells,
  avoiding teacher clashes, breaks and each teacher's maximum per day. It
  shows the result as a preview to accept or adjust. Existing cells are
  never moved.
- **Cover for absences.** When leave is approved, the admin sees the
  affected periods with a **suggested free teacher** for each, from the same
  department first and with the lightest load that day. One tap confirms.
  The substitute sees the period on their Today screen and files the report
  for it. The absent teacher is not chased (already the rule).

**Size:** L. The auto-fill needs a `class_subject_loads` table, and cover
needs `timetable_substitutions`. That changes the database, so it needs
approval (decision D3).

### A6. Communication that runs itself

- **Scheduled announcements**: write now, send on a chosen date and time.
- **A holiday added** can tell guardians and staff on its own (switch, off
  by default).
- **A weekly summary for the principal** each Monday: attendance, fees
  collected and due, reports filed, and students on early warning. It is a
  short email linking to the full reports (decision D4, because Phase 20
  chose "no scheduled reports").
- **Birthday wishes** to students and staff (switch, off by default).

**Size:** M. Scheduled sending needs one column (`send_at`) on
announcements.

### A7. Fees: small gaps

The fee cycle is already automatic. What remains:
- Fee structures are copied for the new year (in A2).
- **A student joining mid-year** gets dues only from the month they join
  (to verify against `fees/dues.py` before building).
- **Assigning a bus route** adds the route's transport dues, and removing
  it stops future ones (to verify the same way).
- An optional **monthly statement** to guardians with dues outstanding.

**Size:** S–M, depending on what the verification finds.

## Order and rough size

| Order | Slice | Saves | Size | Database change |
|---|---|---|---|---|
| 1 | A1 Teaching reports in one tap | Every teacher, every day | M | none |
| 2 | A4 Nudges | Admins chasing people | M | `nudges_sent` |
| 3 | A3 Payroll drafts itself | Accountant, monthly | S | none |
| 4 | A2 New year in one step | Admin, days each March | L | none |
| 5 | A7 Fee gaps | Accountant | S–M | to verify |
| 6 | A6 Communication | Admin | M | `send_at` column |
| 7 | A5 Timetable draft and cover | Admin, weekly | L | 2 tables |

A2 must be finished by **February 2027**, before schools close 2026-27.

## How each slice is shipped

Each slice follows the project's usual process: short plan, backend with
ALLOW/DENY and school-isolation tests, Flutter with widget tests, any
migration in its own commit, a live demo, then deploy with the user's
go-ahead. Each slice also adds:
- a test proving the **manual path still works unchanged** with the
  automation switched off;
- a test proving the job **does nothing the second time** it runs;
- an entry in `test_automation_chains.py`.

## Decisions needed from the user

- **D1:** Schools already live: are new automations **off until an admin
  switches them on** (recommended), or on for everyone?
- **D2:** Approve the small `nudges_sent` table (A4).
- **D3:** Approve the two timetable tables (A5), or leave A5 out for now.
- **D4:** Is a weekly principal summary email acceptable despite Phase 20's
  "no scheduling"?
