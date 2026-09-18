# Dashboard and reports

Phase 18: the landing screen every role sees, and the four reports behind it.
Phase 20 (Python only): three more reports, a chronic-absentee filter, the
previous-period comparison and PDF export - see
[Advanced reporting](#advanced-reporting-phase-20) below.

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

CSV (`?format=csv`) and, since Phase 20, PDF (`?format=pdf`).

The file is fetched through the authenticated client and handed to the browser
as a blob — a token has no business in a link. `lib/core/utils/file_saver.dart`
picks the implementation by platform.

**Downloading is a web feature today.** On Android the stub throws with a
message the user can read, rather than a button that appears to work and does
nothing. Wiring it up needs a storage permission and a path, which the app does
not ask for yet.

The CSV opens with a byte order mark, without which Excel reads it as the
system codepage and mangles any non-ASCII name.

## Advanced reporting (Phase 20)

Decided 2026-09-18, built on the Python backend only - Laravel was frozen
before it, and answers none of this. Everything is opt-in, so a request
without the new parameters gets exactly the report Laravel gives, and the
contract suite still passes against both.

### Three more reports

| Report | Endpoint | Who |
|---|---|---|
| Payroll summary | `/reports/payroll-summary` | Accountant, School/Group Admin, Super Admin |
| Leave usage | `/reports/leave-usage` | Super/Group/School Admin, HOD (own departments only) |
| Syllabus progress by class | `/reports/syllabus-progress` | Super/Group/School Admin, HOD (own departments only) |

- **Payroll summary** reads the payslips of *finalized* runs only - a draft
  can still change. A run counts for every month it covers that the range
  touches, so "1-18 September" reports September's run. One line per
  employee **per currency**, and the totals are a `by_currency` list: money is
  never added across currencies (CLAUDE.md rule 5).
- **Leave usage** counts approved leave in *working days inside the range* -
  a request over a weekend or a holiday takes no leave for those days, and a
  half-day leave is half a day. Beside it: pending requests (and their days),
  rejected requests, and working days marked absent - absence with no leave
  behind it.
- **Syllabus progress** is one line per class section and subject, for the
  current academic year, for subjects whose class levels include the class
  and which have a syllabus. Completion is progress through the year and is
  not bounded by the range; **completed in period** is, measured in the
  school's own days (a topic finished at 11 pm counts on that date at the
  school, not in UTC).

### Chronic absentees

`/reports/student-attendance?below=75` lists only the students whose rate is
under 75%. The totals still describe the whole class, plus `below` and
`students_below`. A student with no rate (a range with no working day) is not
under anything. `below` must be more than 0 and at most 100.

### The previous period

`?compare=1` on any report adds:

- `comparison.range` and `comparison.totals` - the same number of calendar
  days ending the day before the range starts (7-11 September is compared with
  2-6 September), with that period's own working days, built by the same
  report.
- `previous` on each row - that row's earlier value of the figures the report
  compares, or `null` for a row that did not exist then.

| Report | Compared per row |
|---|---|
| Student attendance | attendance rate |
| Staff attendance | attendance rate |
| Teaching coverage | coverage rate |
| Transport usage | days run, riders boarded |
| Payroll summary | net pay |
| Leave usage | leave days, absent days |
| Syllabus progress | completed in period |

The previous period ignores `below`: a student who has just slipped under the
threshold still has last month's rate to be read against. A group's previous
totals are recombined from each branch's raw counts, never averaged. In a CSV
or PDF the earlier figures are extra columns headed "(previous period)".

### PDF

`?format=pdf` on any report: landscape A4 with the school (or "All N
branches"), the period and working days, the totals (and the previous period
beside them when compared), then the same rows as the CSV. Rendered with
xhtml2pdf like receipts and payslips (`school/reports/pdf.py`).

## Adding a report

On the Python backend (`backend-python/school/reports/`):

1. Add a class with `TITLE`, `COMPARED_ROWS`, `row_key()`, `build()`,
   `headings()`, `csv_rows()` and `combine_totals()`. Take the denominator from
   `ReportRange`; never count weekends or holidays yourself.
2. Add a view in `school/views/reports.py` naming the roles allowed, and its
   route in `config/urls.py`. New endpoints are Python-only: list them in
   `PYTHON_ONLY_ENDPOINTS` in `contract/endpoints.py`.
3. Add the enum case and its columns to `lib/features/reports/data/models/report.dart`,
   and the role in `_kindsFor` on the reports screen.
4. Test it at a range containing a holiday, and at a range containing no
   working day at all — those two are where report bugs live.
