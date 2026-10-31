"""One public page per part of the product (docs/seo.md, S3).

Each is a built-in Website Page (docs/site-pages.md): live from the first
deploy, listed in the Super Admin's Website Pages editor, and rewritten
there like any other page. The public site gives these a little more than a
plain page - an invitation to ask for a demo, and links to the other parts -
and the homepage links to every one that is live.

Written for how a school searches ("school attendance software", "school
bus tracking app"), and only about what the product really does today: a
page that promises a parent app or online fee payment would be read by
search engines and school leaders alike, and neither exists yet.

The format is the Website Pages one: `##` headings, `-` bullets, `**bold**`
and `[links](/address)`. The first paragraph is the search snippet, so it
says plainly what the page is about.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ModulePage:
    slug: str
    title: str
    # One line for the card that links here, on the homepage and beside
    # the other module pages.
    blurb: str
    body: str


ATTENDANCE = """School365ai's attendance software gives every class a daily register that a teacher marks in under a minute, on the web or on a phone, and tells guardians straight away when their child is absent.

## A register for every class, every day

- **One register per class per day.** The class teacher marks each student Present, Absent or On leave. A second tap can never overwrite marks already submitted; a correction is a deliberate edit.
- **Only the classes they teach.** A teacher reaches their own classes; the school's admins reach every class.
- **Marked on the phone, even without signal.** In the School365ai staff app the register is saved on the phone and sent as soon as there is a connection.
- **Holidays and weekends are closed.** Each school sets its own working week and holiday calendar, and a register cannot be taken on a day the school did not run.
- **A sensible window for late marking.** The school decides how many days back a missed register may still be filled in.

## Guardians know the same morning

When the school switches it on, guardians get a message the moment the register is submitted - by SMS, WhatsApp or email. The school chooses whether to send for absences only or for every mark, and can reword the message itself.

## Reports that count only real school days

- **Student attendance report** for any class and period, in PDF or CSV, with the previous period beside it.
- **Chronic absentees** filtered out in one click.
- **Early warning** flags students whose attendance or test average is low or falling, against limits the school sets, and shows the figures behind each flag.

Every percentage counts only the days the school was open, so a holiday never makes a class look worse than it was.

Staff attendance has its own page: [Staff attendance and check-in](/staff-attendance-software)."""


STAFF_ATTENDANCE = """School365ai keeps a daily staff register - present, absent, on leave or half day, with check-in and check-out times - filled in by the office, by staff checking in from their phones at school, or from fingerprint readers.

## Check in from the phone, at school

- **Only at school.** A member of staff checks in and out from the School365ai app, and the phone's location must be within the school's radius - 100 metres by default, set by the school.
- **No faked locations.** A mock location, a vague fix, a holiday or a day of approved leave is refused.
- **Location only when they tap.** Nothing follows anybody around; the phone is asked once, at the moment of checking in or out.
- **A forgotten check-out** is filled in with the school's closing time and flagged for the office to look at.

## Fingerprint readers

Where a school uses fingerprint readers, punches can be sent straight to School365ai, or uploaded as a CSV file from the reader. A punch marks a day Present, but never marks anyone Absent and never overrides a status the office set by hand. Readers are added per school on request; talk to us about your reader before you rely on it.

## Late, leave and the register together

- **Late arrivals** are worked out from check-in time against the school's first period, and shown on the register and in the report.
- **Approved leave** is written onto the register automatically, so nobody is marked absent while on leave. See [Staff payroll and leave](/school-payroll-software).
- **Staff attendance report** in PDF or CSV for any period."""


FEES = """School365ai's fee management software sets up a school's fees once, charges every student the right amount on the right dates, and records each payment with a numbered receipt - in the school's own currency.

## Set up once, charged automatically

- **Fee heads per class and year.** Tuition, admission, activity, whatever the school calls them, each with an amount for each class.
- **Monthly, quarterly, termly, yearly or one-time,** every instalment with its own due date.
- **Bus fees from the route.** A student's transport fee follows the route they ride, and moving class, changing route or leaving re-works their future dues.
- **Discounts and waivers** per student, as an amount or a percentage, always with a reason.

## Collecting and receipts

- **Every way money arrives at the counter:** cash, bank transfer, UPI, cheque, card or online transfer, recorded by the office.
- **Part payments** are allowed and pay the oldest dues first.
- **Numbered PDF receipts** with no gaps, per school and year, ready to print or email to the guardian. A wrong receipt is cancelled with a reason, never deleted.
- **Credit balance.** Money paid ahead or overpaid is held as credit, pays the next dues, and can be refunded.

## Reminders and fines

- **Automatic reminders** by SMS, WhatsApp or email, a set number of days before a due date and when it becomes overdue - one message per family per day, even with several children at the school.
- **A late fine** after a grace period, added automatically overnight.

## Knowing where the money stands

Fee collection, outstanding and discount reports in PDF or CSV, a fee statement for any student, and dashboard figures for what has been collected, what is outstanding and what is overdue - each currency on its own, never added together.

School365ai records the money a school receives; families do not pay online through it."""


TRANSPORT = """School365ai's school bus software plans routes on a map, runs every pickup and drop from the driver's phone, and tells guardians when their child boards the bus and when they are dropped off.

## Routes, stops and riders

- **Vehicles, drivers and bus attendants,** with licence details for drivers.
- **Stops picked on the map** once and reused across routes, with road paths worked out when a route is saved.
- **Every student assigned** to a route and the stop they use.

## The trip, run from the phone

The bus crew use the **School365ai Driver** app:

- **Start the pickup or drop** and mark each child boarded, dropped or absent - with a voice search to find a child quickly on a full bus.
- **Directions to the next stop** inside the app, or handed to Google Maps.
- **Call a parent** from the trip sheet; the call is noted on the trip.
- **SOS** - held for two seconds, it alerts the school's transport managers and admins with the crew member's number.
- **No signal, no problem.** Marks are kept on the phone and sent when the bus is back in coverage.

## The office sees every bus

While a trip runs, the driver's phone shares the bus's position. Transport managers and admins see each bus on a live map, when it was last seen, and an estimate for the next stop. Trips left open are closed overnight and the office is told. Positions are deleted after 30 days.

## Guardians are told

When the school switches it on, guardians get an SMS, WhatsApp message or email when their child boards, when they are dropped off, and when they did not board.

## Reports

A transport usage report in PDF or CSV, and route-by-route analytics: trips run, riders, and stops where the bus is often late."""


TIMETABLE = """School365ai builds each class's weekly timetable, shows every teacher their day, and turns each lesson taught into a teaching report that ticks off the syllabus - so heads of department see what was taught, not just what was planned.

## The timetable

- **Bell periods** set once for the school, on its own working days.
- **A weekly timetable per class section,** built entry by entry.
- **No double-booking.** A teacher cannot be put in two classes in the same period, and a class cannot have two lessons in one slot.
- **Today's timetable** on every teacher's phone and dashboard, with the current period marked.

## Daily teaching reports

- **One report per period taught,** filed from the web or the School365ai app.
- **The syllabus ticks itself.** Choosing the topic taught marks it covered - one entry, not two.
- **Holidays are closed,** and the school can set how long teachers have to file.

## Syllabus tracking

Topics per subject and class, with progress for every section and a syllabus progress report, so a school can see in October which classes are behind.

## Heads of department

- **Review or return** each teaching report with a note; the teacher is told in the app.
- **A monthly department report** and a teaching coverage report: periods scheduled against periods actually reported.
- **A department view** in the app: who is in today and each teacher's month."""


PAYROLL = """School365ai runs a school's monthly payroll from each employee's salary profile and attendance, produces PDF payslips, and handles staff leave from application to approval.

## Payroll

- **A salary profile per employee:** monthly basic pay plus the school's own earnings and deductions, and bank details kept encrypted.
- **One run a month,** from draft to finalised to paid, with adjustments on any single payslip before it is final.
- **Pro-rated from attendance.** Half days, unpaid absences and a mid-month joining date are taken into account.
- **PDF payslips,** emailed to staff and readable in the School365ai app.
- **An Accountant role** for whoever keeps the books, and a payroll summary report.

Payroll works in each school's own currency. Country-specific tax and statutory deductions are not calculated; they are entered as deductions where a school needs them.

## Leave

- **Staff apply from the app or the web** - casual, medical, earned or half-day leave.
- **Approved or rejected** by an admin, or by the head of department for their own department, and the applicant is told.
- **Written onto the register** once approved, so the day counts as leave in attendance and payroll alike.
- **Minimum notice** if the school wants one, and a leave usage report."""


ASSESSMENTS = """School365ai records class tests and marks against the school's own grade scale, publishes results to guardians, and prints a progress report for each student - term by term.

## Tests and marks

- **Academic terms and grade scales** set by the school.
- **Class tests, unit tests, assignments, quizzes and practicals,** each for one section and subject.
- **Marks entered on a sheet** - on the web or in the School365ai app - or imported from a CSV file.
- **Publishing fixes each grade** and, when the school switches it on, tells guardians by SMS, WhatsApp or email. Results can be reopened for a correction.

## Seeing how students are doing

- **Performance by term,** compared with the term before, for each student and each class.
- **Weak topics** picked out from the marks, with a suggested next step for each.
- **Early warning** for students whose test average is low or falling, beside their attendance.
- **Student and class performance reports** in PDF or CSV.

## Progress reports

A printable progress report for each student: every test with its grade, the class teacher's remark and signature lines - emailed to the guardian when the school chooses to send it.

## Moving up a year

A promotion wizard moves a whole class on at the end of the year: promote, retain, graduate or mark as left, student by student, in one batch. Every year's class stays in the student's history.

School365ai handles class tests and progress through the year; it does not schedule examinations or issue hall tickets."""


COMMUNICATION = """School365ai keeps a school in touch with guardians and staff by SMS, WhatsApp, email, the in-app inbox and push notifications - from one-off announcements to automatic alerts when something happens.

## Automatic alerts

Seventeen kinds of event can send a message on their own: attendance, a child boarding or leaving the school bus, leave decisions, published results, progress reports, fee reminders, a bus SOS and more. The school switches each one on or off, picks the channels, and rewords the message with placeholders such as the student's name and the date.

## Announcements and notices

- **Announcements** to everyone, teachers, parents, a class or a department, on any mix of channels, with an end date.
- **Messages and emergency alerts** to one student's family, one member of staff, a class, a department, all parents, all staff or everyone.
- **A preview before sending** shows how many people each channel will reach.

## Every message accounted for

A message log shows each message as queued, sent, failed or skipped - with the reason - and failed messages can be sent again.

## No accounts to set up

School365ai sends SMS and WhatsApp for every school through its own account, so a school does not need its own messaging provider. Each school still decides which channels it uses."""


REPORTS = """School365ai gives every role a dashboard of its own and twelve ready-made school reports in PDF and CSV - each compared with the period before - plus analytics that show how the school's figures move over the year.

## Twelve reports, two formats

Student attendance, staff attendance, teaching coverage, transport usage, payroll summary, leave usage, syllabus progress, student performance, class performance, fee collection, fee outstanding and fee discounts. Each downloads as a polished PDF or a CSV that opens in any spreadsheet, and most show the previous period beside this one.

## A dashboard for each role

School admins, heads of department, teachers, transport managers, accountants and staff each open to the figures that matter to them, with a row of trends at the top.

## Analytics

- **Trends** week by week or month by month: attendance, fees collected, students on roll and more.
- **Early warning** for students whose attendance or results are low or falling.
- **Subjects and classes** term by term.
- **Fees** month by month: collected against what fell due, in each currency.
- **Transport** route by route: trips run, riders, and stops where the bus runs late.

## For school groups

A school with several branches sees reports and a dashboard across the whole group, as well as branch by branch."""


RECORDS = """School365ai keeps a school's students, guardians, staff, classes and academic years in one place - with bulk import from spreadsheets, support for school groups with several branches, and a record of every change.

## Students and staff

- **Student records:** admission and roll number, class and section, address, the guardian's name, mobile and email, and status.
- **A class history** for every student, year by year.
- **Staff records** with their own sign-in.
- **Academic years, departments, subjects, classes and sections,** set up by the school.

## Bulk import

Students, staff, subjects, vehicles, drivers, class tests and marks can be imported from CSV files: download the template, fill it in, and see a preview before anything is saved. Every problem is listed at once, and nothing is saved until the whole file is right.

## School groups

A group of schools runs each branch as a school of its own, with its own currency and timezone if it needs them, while a group admin sees across all branches - reports, dashboard and a map of the schools.

## The right access for each role

Ten roles, from school admin and head of department to teacher, accountant, transport manager and bus crew. Every request is checked on the server against the person's school, department and classes, so a teacher sees their own classes and nobody sees another school's data. Each part of the product can be switched on or off for each school.

## A record of every change

An audit log shows who changed what and when, with the values before and after. Sign-in sessions can be reviewed and ended, and accounts lock after repeated failed sign-ins."""


APPS = """School365ai has two Android apps: **School365ai** for teachers, heads of department and office staff, and **School365ai Driver** for the drivers and bus attendants who run each trip. Admins work in the web app.

## School365ai, for school staff

For teachers, heads of department, office staff, accountants, transport managers and school admins.

- **Today** - the day's periods, with the current one marked.
- **The class register,** which works without signal and sends itself when the phone is back online.
- **Teaching reports** that tick off the syllabus, and syllabus progress.
- **Class tests and marks.**
- **Check in and out** at school by location - the home screen for staff who do not teach.
- **Leave** - apply and follow its progress.
- **Payslips,** with the PDF emailed on request.
- **Inbox** for announcements and alerts.
- **For heads of department:** reports to review or return, who is in today, and each teacher's month.

## School365ai Driver, for the bus crew

Drivers and bus attendants sign in with their mobile number and a passcode, on a phone the school has registered.

- **My Trip** - start the pickup or drop and mark each child boarded, dropped off or absent, with voice search to find a child quickly.
- **Navigate** to the next stop, in the app or through Google Maps.
- **Call a parent** from the trip sheet.
- **SOS** to the school's transport managers and admins.
- **Shares the bus's position** with the school while a trip runs, and works without signal.

Both apps run on Android 7 and newer. There is no iPhone app yet. Read more about [school bus tracking](/school-bus-tracking-software) and [attendance](/school-attendance-software)."""

# In the order the homepage shows them: what a school asks about first.
MODULES: tuple[ModulePage, ...] = (
    ModulePage(
        "school-attendance-software", "School Attendance Software",
        "Daily class registers on web and phone, with absence alerts to guardians.", ATTENDANCE,
    ),
    ModulePage(
        "school-fee-management-software", "School Fee Management Software",
        "Fee plans, numbered receipts, reminders, late fines and credit, in your currency.", FEES,
    ),
    ModulePage(
        "school-bus-tracking-software", "School Bus Tracking and Transport",
        "Routes on a map, trips run from the driver's phone, and boarding alerts.", TRANSPORT,
    ),
    ModulePage(
        "staff-attendance-software", "Staff Attendance and Check-in",
        "Check in at school from the phone, fingerprint readers, late and leave.", STAFF_ATTENDANCE,
    ),
    ModulePage(
        "school-timetable-software", "Timetable, Teaching Reports and Syllabus Tracking",
        "Clash-free timetables, daily teaching reports and syllabus progress.", TIMETABLE,
    ),
    ModulePage(
        "student-progress-reports", "Class Tests, Grades and Progress Reports",
        "Marks, grade scales, published results, progress reports and promotion.", ASSESSMENTS,
    ),
    ModulePage(
        "school-payroll-software", "Staff Payroll and Leave",
        "Monthly payroll from attendance, PDF payslips, and leave from apply to approve.", PAYROLL,
    ),
    ModulePage(
        "school-communication-software", "Parent and Staff Communication",
        "SMS, WhatsApp, email, inbox and push: alerts, announcements and notices.", COMMUNICATION,
    ),
    ModulePage(
        "school-reports-and-analytics", "School Reports and Analytics",
        "Twelve reports in PDF and CSV, role dashboards and trends over the year.", REPORTS,
    ),
    ModulePage(
        "student-information-system", "Student and Staff Records",
        "Students, guardians, staff and classes, with CSV import and school groups.", RECORDS,
    ),
    ModulePage(
        "school-staff-and-driver-apps", "The School365ai Staff and Driver Apps",
        "Two Android apps: one for school staff, one for the bus crew.", APPS,
    ),
)
