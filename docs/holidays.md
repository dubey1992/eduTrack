# Holidays and working days

A working day is a **weekday that is not covered by a holiday**, per school.
`HolidayService` owns that definition and everything date-driven asks it.

The whole matrix below is pinned by `HolidayRestrictionsTest`, so a later
change cannot quietly widen or narrow it.

## What a closed day stops

All of these answer `409` with a message naming the reason - never a silent
failure.

| Action | Code |
|---|---|
| Mark student attendance | `ATTENDANCE_ON_HOLIDAY` / `NON_WORKING_DAY` |
| Mark staff attendance | `ATTENDANCE_ON_HOLIDAY` / `NON_WORKING_DAY` |
| File a daily teaching report | `TEACHING_REPORT_ON_HOLIDAY` / `NON_WORKING_DAY` |
| Start a transport trip | `TRIP_RULE` |
| Apply for leave falling entirely on closed days | `LEAVE_ON_NON_WORKING_DAYS` |

A holiday names itself ("Attendance cannot be marked on Founders Day - it is a
holiday."); a weekend says the school is closed.

## What it does not stop

- **Opening the register.** It loads and names the holiday. Blocking the read
  would leave a teacher staring at an error with no explanation.
- **Leave spanning a holiday.** Allowed, and the holiday is not spent: only the
  working days inside the range are marked as leave.
- **Everything that is not a teaching day** - announcements, messages,
  payments, admissions, staff records, timetable edits, transport master data,
  syllabus. The calendar has no say over these.

## Weekends count as closed

Until Phase 18 only *holidays* were enforced, so a Saturday register could be
taken - and then counted by nothing, because every working-day figure already
excluded weekends. Both halves are now enforced, which is what lets a report's
denominator agree with the screen that refuses the mark.

## The week belongs to the school

Built 2026-10-20. It was Monday to Friday everywhere until then, in one line
of application code - which was wrong for every school that does not keep that
week. A school in the Gulf running Sunday to Thursday had attendance refused
on its own working days, allowed on its days off, and every rate in every
report computed against a week it does not keep.

`schools.working_days` is seven characters of '1' and '0', **Monday first** -
`date.weekday()` order, so the index is the weekday and there is no arithmetic
to get wrong. A Sunday-to-Thursday week is therefore `1111001`, which looks
odd written down and is the only ordering with that property. A string rather
than a bitmask because two languages and the occasional human read the column:
`1111100` is a week anybody can check at a glance, and 124 is not.

`school/week.py` is the only thing that parses it. Everything else asks a
`WorkingWeek`, and every date-driven module in the product already went
through `HolidayService.working_dates`, so the week became the school's by
changing where that one line reads from.

Four things worth keeping:

- **Anything unreadable is the default week**, not an error. This is asked on
  every attendance mark and every report row; a column somebody edited by hand
  into nonsense should degrade to the week the product assumed for its first
  year, not take the school offline. A school that runs no days would refuse
  every mark on every date with a message about being closed, which reads
  exactly like the product being broken - so a client may not send one, and a
  stored one is ignored.
- **The timetable carries all seven days now**, and refuses a period on a day
  the school does not run. Without that second half, opening the enum would
  let anybody put a Saturday period on a Monday-to-Friday school's grid: a
  cell nobody can ever teach, and a teaching report that can never be filed
  against it.
- **The messages had to change with it.** "Attendance cannot be marked on a
  weekend" is not true for a school whose Friday is its day off, and for a
  six-day school the day off is Sunday alone. Five of them now say what is
  actually the case.
- **Changing it never rewrites history.** It changes what every figure counts
  from that moment, and it is audited, because it moves every working-day
  denominator the school has.

The grid a teacher sees follows their own school's week, from the session. A
Super Admin belongs to no school and picks one, so their grid follows the
school they picked - otherwise they would be shown Monday-to-Friday columns
for a school that keeps Sunday to Thursday, and the server would refuse every
cell they tried to fill.

**Still Monday to Friday in one place:** a school that runs a half-day - a
Saturday morning - has no way to say so. Every day is on or off.

## Declaring a holiday after the fact

Allowed - a closure nobody knew about on the morning is a real correction - but
never silently. Creating or moving a holiday returns `affected_records`:

```json
"affected_records": { "attendance": 12, "staff_attendance": 3, "teaching_reports": 0 }
```

Those records stay where they are and stop counting towards every working-day
figure. The count is there so an admin can go and clear them rather than
discovering the discrepancy in a report months later.

## Adding a date-driven feature

Ask `HolidayService::isWorkingDay()` - not `holidayOn()` alone, which was the
gap that let weekends through. For a range, `workingDates()` gives every day
the school ran, which is the only correct denominator for a rate.
