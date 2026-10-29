# Analytics

How a school's figures move over time: attendance, teaching, test scores,
fees and the roll, week by week or month by month. Planned in seven phases
(below). **A1, the foundation, and A2, the screen, are built** (2026-10-29).
Python backend only.

Phase 20 ruled trend charts out of the reports. Starting this plan
(2026-10-29) is the decision to have them.

## The one rule

**A point on a chart is the report's own figure for that period.**

Analytics computes almost nothing itself. For each week or month in the
range it runs the report that owns the figure (`school/reports/`) over just
that period and reads one total. So:

- the chart can never disagree with the report a head teacher prints;
- every rate keeps the reports' denominator, the days the school actually ran
  (docs/reports.md);
- a period with no working day, such as a week of holidays, has **no value**
  and is drawn as a gap, never as 0%;
- so does an attendance period in which no register was taken at all. The
  report says 0% with every day "not marked" beside it; a chart has no room
  for that, and 0% alone reads as an empty school. This is the dashboard
  trend's rule too: nobody was absent, nobody was counted. A register of
  nothing but absences is still 0%.

## The measures

| Key | What | Unit | Who may chart it | Narrowed by |
|---|---|---|---|---|
| `student_attendance_rate` | Student attendance report, total rate | percent | Admins | class |
| `staff_attendance_rate` | Staff attendance, across everyone; a half day is half a day | percent | Admins, HOD, Accountant | department |
| `teaching_coverage_rate` | Periods reported against the timetable | percent | Admins, HOD | - |
| `syllabus_topics_completed` | Topics completed in the period | count | Admins, HOD | class |
| `test_average` | Class performance, average over every published mark | percent | Admins, HOD | class |
| `fees_collected` | Valid receipts in the period | money | the `fees` matrix row | - |
| `active_students` | Students on roll (snapshot) | count | Admins | - |
| `active_staff` | Staff whose account is active (snapshot) | count | Admins | - |
| `fee_outstanding` | Owed on dues already due (snapshot) | money | the `fees` matrix row | - |
| `fee_overdue` | The part of it past its due date (snapshot) | money | the `fees` matrix row | - |

"Admins" are Super Admin, Group Admin and School Admin. Each audience is the
audience of the matching report, so a chart never shows a figure its reader
could not already print. A head of department is held to their own
departments whatever they ask for, exactly as in the reports.

The staff rate across the school is not rounded per person first. One
person's 3½ days rounds to 4 on their own row of the report; across a staff
room, the halves are added as they are.

**Money** is never added across currencies. A money point carries one amount
per currency (`amounts: [{currency_code, amount}]`), and a chart draws one
line per currency.

## Snapshots: the four figures history cannot give back

Most figures are stored with their own date (marks, receipts, completions)
and can be counted for any past period. Two kinds cannot:

- **The roll.** A student who leaves keeps no leaving date, so "how many
  students did we have in March" cannot be answered later.
- **What was owed.** A fee due keeps only a running `paid_amount`, so
  "outstanding at the end of March" would quietly count April's payments.

So `record_analytics_snapshots` writes them down. It runs hourly from cron
(docs/deployment.md, section 5) and dates each row by the school's own
calendar. One row per school per day goes in `analytics_school_days`, and
one per school, day and currency in `analytics_school_fee_days`; a second
run the same day replaces the row. Owed is counted by the outstanding-fees
report itself, as at that day. A school owing nothing records 0 in its own
currency, so its chart reads 0 and not "no data".

A period reads its **last** snapshot. A period from before the first one has
no value: these charts begin the day the command first ran, and nothing
before that is guessed. Deleting these rows loses chart history, never data.

## The API

`GET /api/v1/analytics/measures` lists what the caller may chart:
`{data: [{key, label, unit, snapshot}]}`. Fee measures appear only where
the school has Fee Management on.

`GET /api/v1/analytics/series` takes these parameters:

- `measure`: required, one of the keys above.
- `interval`: `week` (Monday to Sunday) or `month`; the default is `month`.
- `from` and `to`: optional, and neither may be in the future at the school.
  With no range, the chart covers the last 12 periods, the current one
  included. The first and last periods are cut to the range.
- At most 24 months or 53 weeks per request, because each period runs a
  report.
- `school_id`: required for a Super Admin, and a Group Admin must name a
  branch. Anyone else charts their own school whatever they send.
- `class_section_id` and `department_id`: optional; each measure ignores the
  ones it does not take.

```json
{
  "measure": "student_attendance_rate", "label": "Student attendance", "unit": "percent",
  "interval": "week", "from": "2026-08-31", "to": "2026-09-11",
  "points": [
    {"from": "2026-08-31", "to": "2026-09-06", "working_days": 0, "value": null},
    {"from": "2026-09-07", "to": "2026-09-11", "working_days": 5, "value": 60}
  ]
}
```

The errors are the reports' own, and a switched-off fees module gives 403
`MODULE_DISABLED`.

## The screen (A2)

Analytics, under Overview in the menu, is `/analytics` in
`lib/features/analytics/`. It offers the same people as Reports, except the
Transport Manager, who has no chart until A6.

- The top row has the school or branch picker, By week / By month and the
  range (the last 12 periods by default). Below it, one chip per measure the
  API lists.
- Each chart shows the latest figure, the change from the period before it,
  the highest and lowest, and for flows (fees collected, topics completed) a
  total over the range. Percentages change by points.
- Below each chart is a bar per period. A gap is a hairline and a dash, with a
  note saying why. A year of weeks scrolls sideways on a narrow screen.
- Money gets one chart per currency.
- A table under the charts lists every point exactly, newest first.
- A range with no figure at all says which of three reasons it is: the
  school did not run, the figure is not recorded yet (snapshots), or the
  school ran and nothing was recorded.
- A Group Admin picks a branch. Charts for the whole group together are not
  available yet.

The bars are plain widgets, like the dashboard's attendance trend. No chart
package was added.

## On the Dashboard

The Dashboard has a **Trends** row after its figure cards, so the trends are
there the moment anyone signs in.

- **Which figures:** up to four, in this order, of those the person may
  chart: student attendance, staff attendance, fees collected, students on
  roll. A head of department sees staff attendance alone; an accountant sees
  staff attendance and fees.
- **Each card:** the latest month, its change on the month before, and six
  small monthly bars. Money charts its first currency and says how many
  more there are.
- **Opening a card:** a tap opens the full chart on the Analytics page, on
  the same figure and school (`/analytics?measure=...&school_id=...`).
- **Why six months:** the Analytics page's twelve are too many here. Each
  month is a report run on the server, and this is the page everyone lands
  on.
- **Loading and failures:** each card loads by itself. Loading and failures
  are a quiet line with Retry, never an error panel above the Dashboard's
  own figures. Refresh reloads the trends too.
- **Who sees the row:** exactly the people the Analytics menu entry allows
  (`AppNav`).
- **Which school:** a Group Admin looking at the whole group sees their own
  school's trends, with its name in the heading, until they pick a branch.
  A Super Admin picks a school first.

## Student early warning (A3)

Built 2026-10-29, from three decisions made the same day: flag students
whose figures are low or falling; show them to admins, class teachers and
heads of department; let each school set the lines.

**The four signals.** Each is a sentence with its numbers, written by the
server, in `school/early_warning.py`:

| Signal | Fires when | Needs |
|---|---|---|
| Low attendance | under the school's line (default 75%) over the last 30 working days | 10 marked days |
| Falling attendance | down by the school's drop (default 10 points) on the 30 working days before | 10 marked days in each |
| Low test average | under the Assessments pass mark (default 33%) over the last 90 days | 2 results |
| Falling test average | down by the drop on the 90 days before | 2 results in each |

One signal is **at risk**, two or more **high risk**. The thresholds are two
settings on the Reports module, in Module Settings: "attendance below" and
"a drop of". The pass mark is the Assessments one the school already has.

These rules are deliberate:

- **Attendance is counted over the days a student was marked**, not over
  every working day. A register nobody took says nothing about the child,
  and counting it would flag a whole class whose teacher forgot.
- **The test average is the Student Performance report's own**, so it uses
  published results only, ignores absences, and weighs subjects evenly. A
  flag can always be checked against that report.
- **On the line is not under it.** 75% with a 75% line is not flagged.
- **Only current students are listed.** Someone who has left is not.
- **No signal without enough to go on.** One test is not a trend.

**Who sees what** (`GET /api/v1/analytics/early-warning`):

| Who | Students | Signals |
|---|---|---|
| Super / Group / School Admin | the whole school (one at a time for those spanning schools) | all |
| Class teacher | their own classes | all |
| Head of department | any student | test signals from their departments' subjects only, plus their own class in full if they have one |
| Anyone else | refused (403) | - |

A teacher with no class sees an empty list, not an error. A school with
Reports switched off has no early warning (403 `MODULE_DISABLED`). Without
Attendance or Assessments switched on, that module's signals are left out.

The list is paginated and highest risk first. `summary` carries `as_of`,
the thresholds, the windows and the whole list's counts, whatever `level`
filter was asked for.

**On screen:**

- **Early Warning page:** under Overview. Level chips show their counts, the
  lines in use are stated, and each student is a card with their reasons.
- **Dashboard banner:** "3 students at high risk, 8 at risk - Review" at the
  top, opening the list. It shows nothing when nobody is flagged or the
  count fails to load.

## Subjects and classes, term by term (A4)

Built 2026-10-29. "Subjects & classes" is the second view on the Analytics
page, beside "Trends". It is offered to admins and heads of department, the
Class Performance report's own audience. It shows one academic year, term
by term:

- **By subject:** each subject's average across every class that takes it.
- **By class:** each class's average across its subjects.
- **Each class, by subject:** every pairing, with how many students are
  under the school's weak line in the latest term.

How the figures are made:

- **Each term is the Class Performance report run over that term's dates.**
  So the figures are what the school prints, from published results only,
  with absentees left out rather than scored nought.
- **The two roll-ups weigh each term by the marks it counted**, as the
  report's own total does.
- **A term with no result is a dash, never 0%.**
- **Only terms that have begun are shown.** The one still running is
  marked "(so far)".
- **"Change" compares the last two terms that have a figure.**

**Colours:** red is under the Assessments pass mark, amber is under the weak
line. The legend states both numbers, because they are the school's own
settings.

**API:** `GET /api/v1/analytics/academic?school_id=&academic_year_id=`. With
no year, it uses the school's current year. A year belonging to another
school is ignored, and the current year is used instead. The response
carries:

- the school's list of years, so the picker needs no second call, and a
  head of department needs no access to the academic-years screen;
- `pass_mark` and `weak_below`.

**Access:**

- A head of department sees only their own departments' subjects.
- Teachers, staff, accountants and transport managers are refused.
- A school without Class Tests & Assessments gets 403 `MODULE_DISABLED`.

## Finance (A5)

Built 2026-10-29, from the user's answers that day:

- look ahead only at what is scheduled;
- show all four views;
- show them to whoever can see fees.

"Finance" is the third view on the Analytics page. It is offered to anyone
the permissions matrix lets read fees, in a school that uses Fee Management.
The endpoint is `GET /api/v1/analytics/finance?school_id=&from=&to=`, which
covers the last 12 months by default and at most 24. It is built in
`school/finance_analytics.py`.

| Section | What it says |
|---|---|
| Collected by month | what fell due (after discounts), what came in (valid receipts), and how much of that month's dues is **paid so far**, which keeps rising as families pay late |
| Falling due next | the next 3 months' **scheduled**, unpaid dues from the fee plans - not a forecast |
| Overdue by age | 1-30 / 31-60 / 61+ days past due on each month's last recorded night |
| By class, today | charged, paid, owed and overdue per class, by each student's class now, with most owed first |
| Fees and payroll | fees collected in the month against the payroll finalized for it (net pay), shown only to someone who may read payroll |

Every figure is per currency. A school billing in two currencies gets two
blocks, never one blended total. Cancelled and waived dues, and cancelled
receipts, count as nothing.

**Overdue by age is recorded nightly.** A due keeps only what has been paid
so far, so a past month's arrears cannot be counted again later. The
snapshot (`analytics_school_fee_days`) records the three ages beside the
totals. Rows from before that carry `ages_recorded = false` and are never
charted, so the chart starts from the first night after A5 went live.

## Transport (A6)

Built 2026-10-29, from the user's answers that day:

- a bus is late at a stop when it arrives **more than 10 minutes** after the
  stop's scheduled time;
- show all four views;
- show them to the Transport Usage report's audience: admins and the
  Transport Manager.

"Transport" is the fourth view on the Analytics page, for a school that
uses Transport. The Transport Manager now gets the Analytics menu, landing
on this view; the other views stay hidden from them. The endpoint is
`GET /api/v1/analytics/transport?school_id=&from=&to=`, covering the last
12 months by default and at most 24. It is built in
`school/transport_analytics.py`.

For each route, month by month:

| Part | What it says |
|---|---|
| Service | days a trip ran out of the school's working days, trips completed, trips cancelled |
| Riders | riders on the trips' lists, how many boarded (marked boarded or dropped), no-shows (marked absent) |
| On time at stops | each stop reached against its scheduled pickup or drop time: more than 10 minutes after is late, and early is never late; the share on time and the average lateness of the late ones |
| Trip length | the average and longest completed trip, in minutes |

Above the routes, **Stops most often late** lists, over the whole range, up
to ten stops that were ever more than 10 minutes late, worst first.

Times are the school's own. A stop's schedule is a time on the school's
clock, so each recorded arrival is turned into the school's time before it
is compared. A stop with no scheduled time for the trip's direction counts
neither as on time nor as late.

## Platform (A7)

Built 2026-10-29. "Platform" is the first view on the Analytics page for the
Super Admin, and the page opens on it, since it needs no school picked. No
other role sees it. The endpoint is
`GET /api/v1/analytics/platform?from=&to=`, covering the last 12 months by
default and at most 24, on the platform's calendar (`PLATFORM_TIMEZONE`),
since the months belong to no school. It is built in
`school/platform_analytics.py`.

| Part | What it says |
|---|---|
| Now | active and inactive schools; students on roll, staff and accounts that can sign in, across every school |
| Month by month | new schools, sign-ins and the distinct people signing in, SMS / WhatsApp / email sent and failed, payments received from schools per currency (paid and part-paid), early access and demo requests |
| Each school | its category, roll, last sign-in, and sign-ins and messages sent over the last 30 days; active customers first, busiest first, so a school that has gone quiet sits low. A list of its own, `GET /api/v1/analytics/platform/schools?q=&category=&page=&per_page=`, searchable by name or city and filterable by category |
| Modules | how many active schools have each switchable module on |

Payments are never added across currencies. A school nobody has signed in
to shows "Never" for its last sign-in.

Every figure is made of live and trial schools only
(docs/school-categories.md). Demo and testing schools are counted once, as
"not counted", and are listed, labelled, below the customers in the
per-school table.

## The phases

| | Phase | State |
|---|---|---|
| A1 | Foundation: measures, periods, snapshots, the API | **built** |
| A2 | School Analytics screen: trend charts per measure | **built** |
| A3 | Student early warning: low or falling attendance and test results | **built** |
| A4 | Academic analytics: subjects and classes over terms | **built** |
| A5 | Finance: collection against what fell due, per currency | **built** |
| A6 | Transport: trips run, riders, late trips | **built** |
| A7 | Platform analytics for the Super Admin | **built** |

These are still open, and each is asked when its phase is reached:

