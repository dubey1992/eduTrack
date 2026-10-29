# Analytics

How a school's figures move over time: attendance, teaching, test scores,
fees and the roll, week by week or month by month. Planned in seven phases
(below); **A1, the foundation, is built** (2026-10-29). Python backend only.

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
  and is drawn as a gap, never as 0%.

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

Flutter has the data layer only so far, under
`lib/features/analytics/data/`: models, API and repository. No screen yet;
that is A2.

## The phases

| | Phase | State |
|---|---|---|
| A1 | Foundation: measures, periods, snapshots, the API | **built** |
| A2 | School Analytics screen: trend charts per measure | next |
| A3 | Student early warning: attendance and marks falling together | to decide |
| A4 | Academic analytics: subjects and classes over terms | |
| A5 | Finance: collection against what fell due, per currency | to decide |
| A6 | Transport: trips run, riders, late trips | |
| A7 | Platform analytics for the Super Admin | |

These are still open, and each is asked when its phase is reached:

- A2: the chart package (`fl_chart` is the likely choice) and whether A2 or
  A3 comes first.
- A3: the early-warning rules, and who sees a flagged child.
- A5: whether to forecast fees at all.
