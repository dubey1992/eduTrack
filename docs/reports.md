# Dashboard and reports

Phase 18. The landing screen every role sees, and the four reports behind it.

## The one rule that matters

**Every rate is out of the days the school actually ran.**

That denominator comes from the same holiday calendar that decides whether a
register may be taken at all, so a report can never contradict the screen that
refused the mark. Three consequences worth knowing:

- A holiday inside the range shrinks the denominator. Four days present out of
  four working days is 100%, not 80% — nobody is penalised for a day the school
  was shut.
- A mark left on a day that *later* became a holiday stops counting. The record
  survives; it just is not a working day any more.
- A range containing no working day has **no** rate, not 0%. Zero would read as
  everybody having been absent.

`ReportRange` owns all of this. A report that needs a denominator asks it.

## The dashboard

`GET /dashboard` (optionally `?school_id=` for a Super Admin).

Every role gets the same shape — `cards`, `attendance_trend`, `attention` — so
the client renders one layout instead of six. What goes in them is decided per
role in `DashboardService`, where the authorization rules already live, rather
than by the client asking for whatever it likes.

| Role | Sees |
|---|---|
| Super Admin (no school) | Schools, user accounts, money collected by currency, payments owing |
| Super Admin (a school) / School Admin | Students, staff, attendance today, trips today, trend, what needs attention |
| HOD | Their departments, their teachers, reports awaiting review |
| Teacher | Periods today, reports filed, registers still to mark |
| Transport Manager | Active routes, trips running, trips completed |
| Staff | Leave requests pending, unread messages |

Two states are easy to misread and are handled explicitly:

- **No register yet today** is `null`, shown as a dash — not 0%.
- **A closed day** gets a banner naming the holiday, so "nothing marked" reads
  as expected rather than as a lapse. It is only shown when a single school is
  in scope; across every school there are no one set of opening hours.

## The reports

All four take `from`, `to` (defaulting to this month so far at the school) and
answer `?format=csv` with the same figures.

| Report | Endpoint | Who |
|---|---|---|
| Student attendance | `/reports/student-attendance` | Super Admin, School Admin |
| Staff attendance & leave | `/reports/staff-attendance` | + HOD (own departments only) |
| Teaching & syllabus coverage | `/reports/teaching-coverage` | + HOD (own departments only) |
| Transport usage | `/reports/transport-usage` | Super Admin, School Admin, Transport Manager |

A school user's report is always their own school's — `school_id` is read only
for a Super Admin, who belongs to no school and must name one.

### What a few columns mean

- **Not marked** — working days with no mark at all. Kept separate from
  "absent": nobody said the student was away, only that no register was taken.
- **Periods scheduled** is computed from the timetable and the calendar, not
  stored: a Monday period is scheduled once per working Monday in the range.
  That is what keeps the figure honest when a holiday removes a day.
- **Syllabus completion** is not bounded by the range. A syllabus is cumulative
  progress through a year, so "35% covered" means 35% of the course.
- **Days run** (transport) are the distinct working days on which the route
  set off - a trip in progress or completed. A cancelled trip never ran, and a
  trip on a weekend or holiday is not a working day run, so days run never
  exceed working days. Decided 2026-09-17; before that it was the most days any
  one trip status ran on, which undercounted a route whose trips finished on
  some days and not others.
- **Days not run** (transport) is working days less days run, so a route is
  never marked as having missed a holiday.
- A **half day** counts as half a day present, which is the figure payroll will
  want in Phase 19.

## Export

CSV only for now; PDF layouts belong with Phase 20's advanced reporting.

The file is fetched through the authenticated client and handed to the browser
as a blob — a token has no business in a link. `lib/core/utils/file_saver.dart`
picks the implementation by platform.

**Downloading is a web feature today.** On Android the stub throws with a
message the user can read, rather than a button that appears to work and does
nothing. Wiring it up needs a storage permission and a path, which the app does
not ask for yet.

The CSV opens with a byte order mark, without which Excel reads it as the
system codepage and mangles any non-ASCII name.

## Adding a report

1. Add a service under `app/Services/Reports/` with `build()`, `headings()` and
   `csvRows()`. Take the denominator from `ReportRange`; never count weekends
   or holidays yourself.
2. Add a method to `ReportController` and name the roles allowed.
3. Add the enum case and its columns to `lib/features/reports/data/models/report.dart`.
4. Test it at a range containing a holiday, and at a range containing no
   working day at all — those two are where report bugs live.
