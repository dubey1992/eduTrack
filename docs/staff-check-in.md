# Staff check-in from the phone

Decided with the owner on 2026-10-25. Built the same day in the Python
backend (`school/check_in.py`) and the Teacher app (the card at the top of
Today, `features/check_in/`).

## Why

Fingerprint readers are something a school asks for (docs/biometric.md).
Without them, nobody could mark their own attendance: the office or the HOD
marked the staff register on the web. Now every member of staff can check
in and out from their phone, at school.

## The rules, as decided

| Question | Answer |
|---|---|
| Proof of being at school | The phone's location, within the school's radius of its map pin. |
| Radius | 100 m by default; each school may set 25-1000 m. |
| What a check-in does | Marks the day **present**, with the time. |
| Check-out | Yes, as on the web. May be done again; the last time stands. |
| Late | Not a status. Derived on the register from the school's first period, as for punches and office marks. |
| Who | Every role with an employment record. A Super Admin has none and is told so. |
| Gate in front of the class register? | No. Check-in is the first card on Today and keeps asking, but a forgotten tap never holds up students' attendance. |

## Endpoints

All three act on the caller only - there is no person or school to name.

- `GET staff-attendance/me` - today on the school's own clock: `enabled`,
  `radius_m`, `school_day`, `on_leave`, `status`, `check_in`, `check_out`,
  `late`, `working_hours`, `marked_by_someone_else`, `can_check_in`,
  `can_check_out`, `blocked_reason`.
- `POST staff-attendance/me/check-in` and `.../check-out` - body
  `{latitude, longitude, accuracy_m?}`; answer is the day as above.

Refusals, each a 422 with its own code: `OUTSIDE_SCHOOL` (with the
distance), `LOCATION_TOO_VAGUE` (accuracy worse than the radius),
`NO_SCHOOL_LOCATION`, `ALREADY_CHECKED_IN`, `NOT_CHECKED_IN`, `ON_LEAVE`,
`CHECK_IN_OFF`; plus the register's own `ATTENDANCE_ON_HOLIDAY` and
`NON_WORKING_DAY`, `NO_STAFF_RECORD`, and 403 `MODULE_DISABLED` when Staff
Attendance is switched off.

## How it sits with the register

- A check-in is a row on the staff register like any other, `marked_by`
  the person themselves. The office's register then shows the day as
  submitted and corrects rather than submits - the same path fingerprint
  punches already take.
- An office mark made first is respected: **absent** becomes present on a
  proven arrival; **half day** stays; **leave** refuses the check-in.
- Approved leave and closed days refuse it too.

## Settings

Two settings on the Staff Attendance module (`school/modules.py`), on the
school's settings screen: **Staff check in and out from the app** (on by
default) and **Check-in distance from school (metres)** (100).

## Privacy

The coordinates are used for the one comparison and never stored. The audit
log (`staff_attendance.checked_in` / `checked_out`) keeps the time and how
far from school the phone was. The Teacher app asks for location only while
in use, at the tap; background location stays removed from its manifest.

## Not yet

- The other roles' home screens in the same app (decision pending: one
  staff app, the Driver app kept separate).
- A reminder if nobody has checked in by the first bell (needs push, T6).
