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

## Edge cases (2026-10-25)

Every case the owner asked to be covered, what happens, and where it is
tested (`test_check_in_api.py`, `test_check_in_edges_api.py`,
`check_in_card_test.dart`).

| Situation | What happens |
|---|---|
| Phone more than the radius from school | Refused with the distance: "You are 474 m from school…" (`OUTSIDE_SCHOOL`). |
| Location accuracy worse than the radius | Refused, asked to step outside or near a window (`LOCATION_TOO_VAGUE`). |
| A fake-GPS / mock location app | Refused whatever distance it claims (`LOCATION_MOCKED`). Android reports it; the web never does. |
| A remembered, out-of-date fix (over 2 minutes) | Refused, asked to wait for it to update (`LOCATION_STALE`). |
| Location switched off on the phone | Nothing sent; the card offers **Turn on location**. |
| Location permission refused for good | Nothing sent; the card offers **Open settings**. |
| No internet | Nothing recorded; the card says so and that the time saved is when it reaches the school. No offline queue: the register's time is the server's. |
| Phone clock wrong | Irrelevant - every time is the school's clock on the server. |
| School has no map pin | Check-in unavailable, "ask the office" (`NO_SCHOOL_LOCATION`). |
| School switched app check-in off, or Staff Attendance off | Card hidden; the Home says attendance is marked in the office (`CHECK_IN_OFF`, `MODULE_DISABLED`). |
| Holiday or a day the school does not run | Card hidden; refused if called (`ATTENDANCE_ON_HOLIDAY`, `NON_WORKING_DAY`). |
| Approved full-day leave | Card hidden; refused (`ON_LEAVE`). Pending leave does not count. |
| Approved **half-day** leave | Allowed; the day becomes a **half day** (approval writes `leave`; check-in turns it into the half worked, which payroll already counts as half present, half leave). |
| Office marked absent first | Check-in makes it present. |
| Office marked half day first | Stays a half day; the time is added. |
| Office marked leave by hand | Refused. |
| Fingerprint reader checked them in first | Refused, naming the reader and its time. |
| Second check-in | Refused with the first time (`ALREADY_CHECKED_IN`). |
| Double tap / two phones at the same moment | One lands; the other is told "already checked in", never a server error. |
| Check-out before any check-in | Refused (`NOT_CHECKED_IN`). |
| Accidental check-out tap | The app asks "Check out now?" first. |
| Checking out again | Allowed after a warning; the last check-out counts. |
| Check-out from home | Refused like a check-in - same location proof. |
| Forgot to check out | Closed automatically once the school's own day is over (the hourly `close_open_trips` job, since 2026-10-26): the leaving time becomes the school's closing time - the end of the last period, the half-day bell on a half day - and the register's remarks say "Check-out not recorded - closed at school closing time." for the office to review and correct. Only the person's own check-ins and reader punches from the last 7 days; never a day the office marked, a check-in after the last bell, or a school with no bell schedule - those stay open, and until then the app's card says which day and to ask the office. |
| Office corrects the day afterwards | The register shows the correction; the card says the office updated the day; the web log still shows what the phone recorded. |
| Signed in as somebody with no staff record | The card says check-in is not set up for the account. |
| Super Admin / Group Admin / bus crew | Told which app or website to use. |

## On the web

- **Staff Attendance register:** a time the person checked in from the app
  reads **From the app** (phone icon) beside the times, until the office
  changes the day.
- **App check-ins** (below the register, same school / department / date):
  every check-in and check-out made from the app that day, in order - time,
  name, department, event, and the distance from school. Read from the audit
  trail (`GET staff-attendance/check-ins`), for whoever may mark the
  register; an HOD sees their own departments.

## Settings

Two settings on the Staff Attendance module (`school/modules.py`), on the
school's settings screen: **Staff check in and out from the app** (on by
default) and **Check-in distance from school (metres)** (100).

## Privacy

The coordinates are used for the one comparison and never stored. The audit
log (`staff_attendance.checked_in` / `checked_out`) keeps the time and how
far from school the phone was. The Teacher app asks for location only while
in use, at the tap; background location stays removed from its manifest.

## One app for the school's staff (2026-10-25)

The owner chose one app for everyone who works in the school, named just
**School365ai** (the Teacher app renamed; the Driver app stays separate for
the bus crew's passcode sign-in, background location and navigation).
- Teachers and HODs: Today, with periods, register and reports, check-in on
  top.
- Office staff, accountants, transport managers and school admins: their
  own Home - the school's date and the check-in card, or why there is none
  today (closed, on leave, marked in the office), and a line that leave,
  payslips and messages are on the website for now.
- Bus crew are sent to the Driver app; a Super Admin or Group Admin, who
  answer for many schools, to the website.
- An account with no staff record behind it is told so on the card rather
  than offered a retry that cannot work.

The Android application id is **`com.school365ai`** (chosen by the owner
2026-10-25, before the first Play upload, and permanent from it). The Driver
app's stays `com.school365ai.app`. The Gradle flavour and `main_teacher.dart`
keep their first names inside the build only. The web app is untouched by
the id: it never reads it.

## Not yet

- Leave, payslips and messages in the app (T4).
- A reminder if nobody has checked in by the first bell (needs push, T6).
