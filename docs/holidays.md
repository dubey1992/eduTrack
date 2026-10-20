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

## Half days - PLAN, not built

Decided 2026-10-20, awaiting the build. A school that runs a Saturday morning,
or a Saturday that is only a PT session, has no way to say so: every day is on
or off, and every day rings the same bells.

### What is already true

Worth knowing before anything is built, because it is most of the problem:

- **Nothing assumes a fixed number of periods per day.** "Periods today",
  "Reports filed" and the teaching coverage report all count the timetable
  entries that exist. A PT-only Saturday already reads correctly end to end -
  one entry, one period today, 0/1 reports filed, one period scheduled.
- **A half day already exists, and means something else.**
  `StaffAttendanceStatus.HALF_DAY` and `LeaveType.HALF_DAY` are properties of
  a *person* on a day, each worth 0.5. What is missing is a property of the
  *day*. Conflating the two is the main risk here.
- **Period times are school-wide.** `periods` is unique on
  (school, period_number) with no day in it. A Saturday whose periods are
  forty minutes rather than fifty-five cannot be expressed. **This is the only
  real schema gap.**

### The two decisions

**A school half-day counts as a full working day.** The school ran; a teacher
who was there all morning worked a full Saturday. Counting it as 0.5 would
score a teacher who never misses a day at about 92%, which reads as a bug -
and it would give HALF_DAY two meanings, so half-day leave on a half-day
Saturday would be a quarter of something.

This decision is what keeps the work small: **attendance, leave, payroll,
every report denominator and all of transport need no change whatsoever.**

**Two shapes, not arbitrary per-day periods.** A school defines a full day and
a half day - each with its own periods, at its own times - and says which days
use which. It is how schools describe it, and the freedom to give every
weekday its own bells is freedom nobody asked for and a ragged grid to draw.

### Schema

`schools.working_days` widens rather than gaining a companion: `'0'` closed,
`'1'` a full day, `'2'` a half day. Every value stored today is already valid,
and one column cannot contradict itself the way a second mask could - a day
marked "half" but not "working" is a state that simply cannot be written.

`periods` gains `day_shape` (`full` / `half`, default `full`), and its
uniqueness becomes (school, day_shape, period_number). Every existing row is a
full-day period, so a school that never uses this is untouched.

### The slices

**H1 - the shape. Built 2026-10-20.** `working_days` holds a third state
('2'), `periods` carries `day_shape`, and a timetable entry is refused when
its period's shape does not match the day's - a full day's period 7 on a
Saturday ending at noon is an hour that does not exist, and a teaching report
that can never be filed against it. Period numbers are unique per shape, so a
full day's period 1 and a half day's period 1 are different bells at different
times and neither is a duplicate.

Two things H1 had to include that the plan read as UI:

- **The app has to be able to read a half day**, or the edit form silently
  destroys one. `WorkingWeek.fromApiValue` falls back to Monday-to-Friday on
  anything it cannot parse; a client that did not know about '2' would read
  `1111120` as the default week and write that back on the next save. A test
  pins the round trip.
- **A half day is marked on its chip** ("Sa ½"), not only in the line
  underneath. It looks exactly like a full day otherwise, and turning one off
  and on again quietly makes it full - which is still true, and now visible.

Choosing a half day is still H2; nothing in the app can set one yet.

**H2 - saying so. Built 2026-10-20.** The week picker gained a second row
rather than a third state on the first: "which days do you run" and "which of
those are short" are two plain questions, and one chip cycling through three
answers is a guessing game while three buttons on each of seven days is
twenty-one targets for a setting most schools never touch. Only the days a
school runs appear in the second row, so a day cannot be marked short and
closed at once - the model cannot hold that and neither can the screen.

Manage Periods gained a Full day / Half day choice, **shown only to a school
that has a half day to put periods on**. Everybody else sees the form they had
before, which is the test that this cost nobody anything. The choice is made
when a period is created and fixed after: moving one between shapes would move
it to a different hour on a different set of days, which is a new period rather
than an edit to this one.

Both screens read `schoolWeekProvider`, which resolves a school user's own week
from the session and a Super Admin's picked school from the list - the same
resolution the grid uses, in one place now instead of two.

**H3 - the grid.** Two tables rather than one ragged one: full days with their
periods, half days with theirs. A school with no half days sees exactly what
it sees now, which is the test that this did not cost anybody anything.

### What this deliberately does not do

- **No fractional days anywhere.** See the first decision.
- **No per-day transport times.** A half day's drop trip leaves earlier, but
  trip times are not modelled per day today and this does not start.
- **No third shape.** A school needing "Saturday is PT only" uses the half-day
  shape with one period in it. If a school ever needs a genuinely different
  third day, that is when to reconsider - not before.

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
