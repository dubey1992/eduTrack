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

The week is Monday to Friday, matching the Phase 10 timetable. A school that
runs a different week (Sunday to Thursday in the Gulf, or a six-day week) needs
a per-school working-days setting; that is not built.

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
