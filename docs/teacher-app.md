# The Teacher app (Android) — plan for review

*Written 2026-10-24. Nothing here is built. Four decisions are asked for at
the end; everything else is a recommendation that can be overruled.*

## The short version

**Most of what a teacher does already exists as web screens and as API,
and the way to ship a second Android app has just been proven once.** The
driver app (docs/driver-app.md) showed the shape: one Flutter codebase,
a second entry point (`lib/main_driver.dart`), a phone-first router, the
same repositories and notifiers the web uses, and screens rebuilt for a
thumb rather than a mouse where the web ones would not fold. The teacher
app is the same move for a different person, with one big difference:
**a teacher's day is scheduled.** The bus has one trip; the teacher has
seven periods, a register that closes, reports that are owed by the end
of the day, and a class test next week. So the home screen is not a list
of things the app can do - it is **today**, in order, with what is done
and what is owed.

| | |
|---|---|
| Reuse as-is | sign-in and sessions, the permission matrix and module switches, attendance register API, teaching reports, syllabus checklist, leave, timetable, assessments/marks, inbox, profile, holidays and working days |
| Extend | a "my day" view of the timetable, teaching-report submission keyed to a period, phone layouts for the register and marks entry |
| Genuinely new | the Today screen, push notifications, an offline register, the Android release of a second app |

## Who it is for, precisely

- **`TEACHER`** - signs in with email and password (Phase 1 auth: Sanctum-
  style tokens, 7-day idle / 30-day sessions, lockout, device sign-out
  from Profile). Their rights, from the matrix (`school/permissions.py`):
  students *view*, attendance *manage*, assessments *manage*, teaching
  reports *manage*, syllabus *manage*, leave *manage*, timetable *view*,
  academics *view*, transport *view*. Each is narrowed by policy to **their
  own classes, sections and subjects** - a teacher of 8A cannot touch 9A.
- **`HOD`** - a teacher with a department to look after: reviews teaching
  reports, marks the staff register, reads the department's syllabus and
  reports. **In scope as a second phase**, because an HOD teaches too and
  will not carry two apps.
- *Not this app:* `SCHOOL_ADMIN`, `STAFF`, `ACCOUNTANT`, `TRANSPORT_MANAGER`
  keep the web portal, which already works in a phone browser; the Super
  Admin has nothing to do on a phone.

## What exists today, precisely

Every row below is live on the web and on `/api/v1` with tests.

| A teacher's job | API | Web screen | Phone-ready? |
|---|---|---|---|
| Mark the class register | `GET attendance/register?class_section_id&date`, `POST attendance` | Student Attendance | the grid is a desktop table; the rule set (working day, one submission, holiday blocked) is all server-side |
| See the timetable | `GET timetable?teacher_id…` | Timetable (grid) | the grid; no "today for me" view |
| Submit a daily teaching report | `POST teaching-reports` (timetable entry + date + syllabus topic + notes), `GET teaching-reports/summary` | Teaching Reports | form is fine; the list is a table |
| Tick syllabus topics | `GET syllabus-topics`, `POST syllabus-progress` (toggle) | Syllabus checklist | a checklist - nearly phone-ready |
| Apply for leave, see its state | `POST leaves`, `GET leaves`, `GET leaves/summary` | Staff Leave | form and a table |
| Enter marks for a class test | assessments + marks endpoints (docs/assessments.md) | Class Tests | a wide grid: students × components |
| Look a student up | `GET students`, `GET students/{id}` | Students (view only) | list is a table; detail is cards |
| Read what the school sent | `GET inbox`, `unread-count`, `read`, `read-all` | the bell | already compact |
| Own payslips | payroll "My Payslips" | My Payslips | a list and a PDF |
| Profile, password, devices | `GET/PATCH me`, change-password, sessions | My Profile | reused as-is by the driver app already |

What does **not** exist, anywhere:

- **A "today" view.** The timetable API answers a grid for a teacher; nobody
  has asked it "what is period 3 right now, and did I report it?".
- **Push notifications.** `MessageChannel` has SMS, WhatsApp, email and
  in-app; there is no push adapter, no device token table, no Firebase
  project. The inbox is pull-only.
- **Any offline tolerance outside the bus.** Every web screen assumes
  signal.
- **A second Android release**: name, id, icon, listing, signing.

## Decisions this plan rests on *(asked for below)*

1. **One app or two?** Recommendation: **two APKs from one codebase.** The
   driver app carries location, foreground service and microphone
   permissions and a Play listing written for drivers; a teacher app with
   those permissions in its manifest would be refused by cautious schools
   and reviewed harder by Play. Separate `applicationId`s
   (`com.school365ai.app` is taken by the driver; `com.school365ai.teacher`
   is proposed), separate icons, one repository, shared everything else -
   exactly how `main.dart` / `main_driver.dart` already relate. The cost is
   a second listing and a second signing key entry, once.
2. **Push now, or inbox first?** Recommendation: **ship Phase T1-T4 on
   the pull-only inbox, add push as its own phase (T6).** Push needs a
   Firebase project owned by the business, `google-services.json` kept out
   of git, a device-token table, a `PUSH` channel with the switched-off rule
   from docs/communication.md, and a background handler on the phone. It is
   a week of its own and should not gate the register.
3. **Offline register: yes or later?** Recommendation: **yes, in T2, using
   the pattern the bus already proved** - marks saved on the phone with an
   idempotent id and the time they happened, sent oldest-first, a "Not sent"
   card when the server refuses. Classrooms lose signal too, and a register
   that is lost when the Wi-Fi drops is the complaint every teacher app
   gets first. The server already refuses a second submission and a
   non-working day, so nothing new is needed on its side beyond honouring
   `client_id` on `POST attendance` the way `trips/{id}/sync` does.
4. **HOD in this app?** Recommendation: **yes, as T7**, gated by role at
   sign-in like the driver app gates crew: an HOD sees the teacher screens
   plus a *Department* tab (reports to review, the staff register). Not
   before the teacher half is in a teacher's hands.

## Architecture - what is shared and what is not

```
lib/
  main.dart            web portal          (exists)
  main_driver.dart     crew app            (exists)
  main_teacher.dart    teacher app         (new, ~50 lines like main_driver)
  core/routing/
    app_router.dart    web                 (exists)
    driver_router.dart crew                (exists)
    teacher_router.dart                    (new: sign-in, Today, Register,
                                            Reports, Syllabus, Leave, Tests,
                                            Students, Inbox, Profile)
  features/<module>/
    data/              repositories + API  (reused unchanged)
    application/       notifiers           (reused; a few new ones: today,
                                            offline register queue)
    presentation/      web screens         (reused where they fold:
                                            syllabus checklist, leave form,
                                            inbox, profile, student detail)
    presentation/phone/                    (new, only where the web one is a
                                            table or a grid: register, marks,
                                            timetable, report list)
```

Rules carried over from the driver app, because they held:

- **No API call or rule in a widget.** Presentation → notifier → repository
  → API. The teacher app adds notifiers, not endpoints.
- **Everything the server already refuses, the app does not offer** - a
  register for a holiday, a second submission, a section that is not
  theirs. The UI mirrors the policy; the policy stays the authority.
- **One column.** A tablet gets a readable 640-px column, not a second
  layout (`driver_router` pins this with a test at 1600×2560).
- **Role gate at the door.** Anyone who is not `TEACHER` or `HOD` is told
  in one sentence that this app is for teachers and offered the portal -
  the same screen the crew app shows an administrator.
- **Platform things behind an interface with a web stub and a fake:**
  push, the offline store, anything that touches a plugin. Tests never
  reach the phone.

## The phases

Each slice ends with: backend tests where anything server-side changed,
widget tests for every state (loading / empty / error / success, ALLOW and
DENY), a run on the emulator, and a line in this document.

### Phase T0 — The second app exists *(built 2026-10-24)*
*Decision 1 came back "2 apks", and this phase is its shape.*
- `lib/main_teacher.dart` and `core/routing/teacher_router.dart`, on the
  pattern of the driver's: no '/', no dashboard, no office. Routes:
  splash, `/login` (the web's sign-in screen, which already folds to a
  phone, with the bus crew's link switched off), `/forgot-password`,
  `/today`, `/profile`, maintenance, and `/not-teacher` for an
  administrator or bus crew who installed the wrong app. `TEACHER` and
  `HOD` get in; the HOD's Department tab waits for T7.
- `TeacherFrame`: who is signed in, the way out, a bottom bar with **Today
  · Me**. Two tabs, not the three the plan drew: Classes has nothing behind
  it until T2 and a tab with nothing behind it is decoration. One 640-px
  column on a tablet, pinned by a test.
- **Today** is in place with the greeting and the date; the periods and
  what each owes are T1's.
- **Android: product flavours**, `driver` and `teacher`, in one Gradle
  project - the one Android mechanism that gives each app its own id
  (`com.school365ai.app`, `com.school365ai.teacher`), name, icon and
  manifest while every line of Dart and every plugin stays shared. The
  teacher manifest is subtraction: it removes location, the foreground
  service and its notification permission, and the microphone, plus the
  plugin manifests' own copies, so Play and a cautious school see an app
  that asks for nothing a teacher does not need. The icon is an open book
  on green (`scripts/teacher_icon.py` draws it at every density; the
  driver's is blue so the two tell apart on a launcher). **Every build now
  names its flavour** - `--flavor driver` / `--flavor teacher` - because
  Gradle refuses to guess once flavours exist; CI builds both and prints
  each package name, which is the proof the flavours did their one job.
- Tests: `teacher_router_test.dart` - the screens it carries and the ones
  it does not, the splash held for its beat, signed-out → sign-in without
  the crew's link, teacher and HOD → Today, admin / crew / staff told and
  signed out, the tablet column, the API-down screen.

### Phase T1 — Today *(built 2026-10-25)*
**As built.** `GET timetable/today` (backend-python/school/today.py) answers
for the caller only - a `teacher_id` in the query is ignored, and a role
without the timetable (the bus crew) gets 403. One call returns:
the school's date and wall clock (`now`, `HH:mm`) on its own timezone;
`school_day` - open or not, `full`/`half`, the holiday if any; `periods` -
today's entries of today's shape, earliest first, each `done` / `current` /
`upcoming` with its report filed or not (and the report's id); `registers` -
the classes the caller is **class teacher** of this year, submitted or not;
`leave` - approved leave covering today and this week's; `owed` - reports
for periods that have started, registers not yet in.

Two corrections to the plan below, both from what the server enforces:
- **The register is not per period.** Only a section's class teacher may
  mark it (`ClassSectionPolicy._reaches`), once a day. So it is its own card,
  not a badge on every period the teacher happens to teach in that class.
- **The two actions wait for T2 and T3.** The phone register is T2 and the
  report form T3; until then Today shows the states only. A button that
  opened nothing would be a promise the app cannot keep.

Nothing is owed on a closed day or while on approved leave; the day is
still shown on leave. The screen pulls to refresh, keeps the old day on
screen while the new one loads, and has no automatic retry (its own Retry
button instead). Tests: `test_today_api.py` (19: order, current, owed only
once started, filed report, another day's report, the school's clock across
midnight UTC, last year's grid, register owed/submitted/none, holiday,
closed weekday, half-day bells, leave today/this week/pending, HOD, the
ignored `teacher_id`, DENY for a driver, 401), `today_screen_test.dart`
(14 states incl. dark mode, retry, pull to refresh) and `teacher_day_test.dart`
(the JSON as the server writes it). Run on the tablet emulator against the
local API with its clock pinned to a Monday morning.

*The plan, as written before building:*
- **New API, one endpoint:** `GET timetable/today` (or `my-day`) answering
  for the signed-in teacher: the school's date on its own clock, whether
  it is a working day (holidays.md), each period in order with class,
  section, subject, room, start/end, and - joined here so the phone makes
  one call - whether the **register** for that section is submitted today
  and whether a **teaching report** exists for that period. Scoped to the
  caller; a `teacher_id` parameter is not accepted.
- The screen: the date; a closed-day card on a holiday; otherwise the
  periods as a vertical list with the current one marked, each carrying
  two small states (*Register ✓ / owed*, *Report ✓ / owed*) and the two
  actions. Under the list, the day's owed count, and the week's leave if
  any is approved.
- Tests: backend ALLOW (own day) / DENY (another teacher's), holiday,
  non-working day, a period with and without report; widget states.

### T1.1 — The app's own look *(built 2026-10-25)*
The owner asked for a phone app, not the portal on a phone: its own splash
and landing like the driver app's, no web sign-in page, and a proper brand.
- **Brand** (`core/theme/teacher_brand.dart`): classroom teal `#0F766E` to
  `#115E59`, bookmark amber `#F59E0B` as the one warm note, mint containers;
  `AppTheme.teacherLight()` / `teacherDark()` are the portal's theme with that
  primary (bright teal `#2DD4BF` in dark mode). Status colours are unchanged.
- **Mark** (`core/widgets/teacher_mark.dart`): an open book with an amber
  ribbon, painted, so it is sharp at every size and can open. The launcher
  icon is the same drawing (`scripts/teacher_icon.py`, drawn at 8x and scaled
  down for smooth edges), with a **monochrome layer** for Android 13 themed
  icons and a rounded legacy icon.
- **Cold start is one colour.** The teacher flavour's launch window and
  Android 12's system splash are teal (`res/values-v31`, `drawable/
  launch_background.xml`), so the system splash hands straight to the Flutter
  splash: the book opens, the name and "Your school day, in your pocket."
  follow, with the old six-second "try again".
- **Signed out**, the app's own screens: `/welcome` (what it does, in four
  true lines, and how an account is made), `/login` (email and password with
  the keyboard's email key, autofill, remember-my-email, failures in a banner
  that stays), `/forgot-password` (the same answer whether or not the address
  has an account), and `/change-password`, which a teacher with an imported
  temporary password is now held on, as on the portal - the T0 router let
  them straight through.
- Today's period cards put their badges under the class line: at phone width
  a third column had left "Mathematics" breaking mid-word.
- Tests: `teacher_auth_screens_test.dart` (19, through the real router:
  splash, slow splash, welcome, small phone, empty and malformed forms,
  server refusal, Today after sign-in, remembered email, busy button, a
  non-teacher, reset sent and refused, the temporary-password hold and its
  sign-out, dark mode) and `teacher_mark_test.dart`.

### Staff check-in, and one app for all staff *(built 2026-10-25)*
Asked by the owner before the register: staff check in and out from the
phone within 100 m of the school's pin, which marks them present
(docs/staff-check-in.md). Then, on their word, the app became **School365ai**
for every member of a school's staff - teachers on Today, everybody else on
a check-in Home - with the bus crew kept on the Driver app.

### T4, part 1 — My leave *(built 2026-10-25)*
A **Leave** tab between Today and Me, for every role the app serves, hidden
when the school switched leave off. "My leave" lists the person's own
requests, newest first, with their status and the reviewer's remarks, 20 at a
time; **Apply for leave** opens a full screen (type, dates, reason). A half
day is one date - the To field goes. The form checks what it can see; the
server's notice, overlap and closed-day rules come back as its own sentence
on the form. A School Admin's own request approves itself, and the message
says so. The list asks `GET leaves?mine=1` - new on the server, the caller's
own requests whatever else their role sees. Tests: `MyOwnLeave` in
`test_leave_api.py`, `my_leave_test.dart` (10).

### T4, part 2 — My pay *(built 2026-10-25)*
A **Pay** tab (Today · Leave · Pay · Me), shown where the school runs
payroll - every employee reads their own payslips, whatever their role's
matrix says about the office's payroll screen. One card a month, newest
first: net pay in the school's currency and whether it has been paid. A
payslip opens on its own screen: net pay, paid on / by, the days (paid,
absent, half, unmarked - zeros left out), every earning and deduction with
totals, and any shortfall from unpaid days. **Email me the PDF** - new on the
server, `POST payroll/my-payslips/{id}/email`: the caller's own finalized
payslip only (anybody else's, or a draft, is a 404); refused with `NO_EMAIL`
for an account with no real address, and `EMAILED_RECENTLY` while one is
still in the queue or was sent in the last two minutes, so two taps never
become two emails. The phone needs no PDF viewer and no storage permission:
the inbox keeps the file. Tests: `EmailMeMyPayslip` (9) in
`test_payroll_api.py`, `my_pay_test.dart` (11).

### T4, part 3 — Messages *(built 2026-10-25)*
A **bell** in the top bar with the unread count - not a fifth tab, which a
phone's bottom bar has no room for - opens **Messages**: what the school
sent this person in the app (announcements, leave decisions, alerts), newest
first, unread ones marked, **All / Unread**, **Mark all read**, older pages.
Opening one shows it whole in a sheet and marks it read in place; the count
is read again on the way back. No server change: the inbox endpoints were
already pinned to the signed-in person. Pull-only until push (T6). Tests:
`my_inbox_test.dart` (13).

T4 is complete: leave, pay and messages are in the app.

### Phase T2 — The register, offline-tolerant *(built 2026-10-25)*

**As built.** The register card on Today opens `/register/<section>` with
the date and class name from Today, so the school's date is used, not the
phone's. The screen shows a tally (Present / Absent / Leave / Not marked),
**All present** (fills only students not yet marked), a large Present /
Absent / Leave row per student, and **Submit**. Submit stays shut until
everyone is marked, then asks with the counts. A day already taken shows
its marks with **Correct**.

- **Saved first, sent after.** Submit saves the register on the phone
  (`register.waiting`), then sends it. With no signal it is retried after
  5, 15, 30, then every 60 seconds, on app resume, and on sign-in. It is
  read back from the phone after the app is closed. Only the teacher who
  took a register sends it, so a shared phone never sends one teacher's
  register under another's sign-in. Sign-out drops the in-memory copy only.
- **Opening without signal.** Each class list is kept on the phone when
  opened (names and roll numbers, never marks), so a class opened once with
  signal can be taken without it. A class never opened says to open it once
  with signal.
- **Refusals.** Anything the server refuses other than a lost connection
  moves the register to "Not sent" with the server's own message, and it is
  not retried. Taking the register again replaces it.
- **Corrections need signal.** Parents may already have been told, so a
  correction is never left waiting on a phone.
- **No `client_id` column, no migration.** The server recognises a resend
  instead: the day's rows were all marked by the same person, with exactly
  the same marks. It answers 201 with `resent: true` and sends no second
  absence message or audit entry. Anything else is still
  `ATTENDANCE_ALREADY_SUBMITTED` (409). This covers the one case that
  matters, an answer lost after the server saved the register.
- **Today card:** Taken, Saved not sent, Not sent, or Not taken.
- **Tests:** backend `TheAppSendingItAgain` (5). Flutter: queue (11), sheet
  (14), screen (12), Today card (3), and the router opening the register
  and coming back.

**The plan, as written before building:**
- Phone register: one section, one date (today by default; back-dates only
  as far as the server allows), the class as a list of large rows - name,
  roll number, **Present / Absent / Leave** as big buttons like the bus's
  Boarded / Dropped / Absent (those three are the student statuses the
  server knows - there is no "late" for a child; that is a staff-register
  idea, docs/biometric.md) - a running tally in the header, and one
  **Submit** with a confirm ("27 present, 3 absent. Submit?").
- **Offline:** the submission is saved on the phone first with a
  `client_id` and the time it happened, sent when signal returns, and the
  Today card reads *Register: saved on this phone, not yet sent* until it
  lands. Server: `POST attendance` honours `client_id` (a resend is
  harmless) - a migration on the Laravel side for the column, a small
  change in `AttendanceService`. The refusal cases (already submitted,
  not a working day, not your section) come back as the codes they are
  today and go to a "Not sent" card, as on the bus.
- Tests: queue unit tests (reuse `trip_mark_queue` patterns), ALLOW/DENY
  on the server for `client_id` replays, widget tests for the tally and
  the confirm, the Not-sent card.

### Phase T3 — Teaching reports and the syllabus
- From a period on Today: **Report this period** - the form the web has
  (what was taught, the syllabus topic, remarks), prefilled with the
  period, submitted once; the server already refuses a second report for
  the same period and date.
- Reports list for the teacher: their own, by date, with the HOD's review
  state. A phone list, not the table.
- **Syllabus**: the existing checklist screen fits a phone already; wrap it
  in the frame, keyed to the teacher's subjects.
- Tests: form validation, duplicate refusal surfaced plainly, list states.

### Phase T4 — Leave, students, payslips, inbox, profile
- **Leave**: apply (dates, type, reason) and the list with status - the web
  form folds to one column; the summary card (balance) on top.
- **Students**: the teacher's own sections as a list, a student's detail
  as the card stack the web already has (view only, as the matrix says).
- **Payslips** and **Profile**: reused as they are (the driver app reuses
  Profile today; the crew-mobile lock does not apply - a teacher may edit
  their number).
- **Inbox**: the bell and the list, pull-to-refresh, unread badge from
  `inbox/unread-count`.
- Tests: mostly widget states; ALLOW/DENY already covered server-side.

### Phase T5 — Class tests and marks
- Marks entry on a phone is the hard screen: students × components. One
  component at a time, students as a list, a numeric keypad field per row
  with next-field focus, running count of entered / missing, save per
  component, the pass-mark and max-mark rules from docs/assessments.md
  surfaced inline. Read-only once published, as on the web.
- Tests: validation (over max, non-numeric), partial save, locked state.

### Phase T6 — Push notifications *(decision 2)*
- Backend: `device_tokens` (user, platform, token, app, last seen; Laravel
  migration), a `PUSH` adapter behind `NotificationService` with FCM, the
  switched-off rule (a muted alert is not sent **and not logged**,
  docs/communication.md), and the events that should push: a report
  reviewed, a leave decided, an announcement, a message. Credentials in
  `backend/.env`, never in git.
- App: `firebase_messaging` behind an interface with a web stub; token
  registered at sign-in, removed at sign-out; tapping a notification opens
  the thing it is about.
- Tests: adapter unit tests with a fake sender, the muted rule, token
  lifecycle; widget test that a tap routes.

### Phase T7 — HOD *(decision 4)*
- Same app, one more tab for `HOD`: **Department** - teaching reports
  awaiting review (approve / return with a note), the department's staff
  register for today, the syllabus coverage the web shows. All existing
  endpoints.
- Tests: role gate (a teacher never sees the tab), review ALLOW/DENY.

### Phase T8 — Release
- Second listing: name ("School365ai Teacher" proposed), icon, screenshots,
  the privacy policy (`/privacy` already covers the driver app; the teacher
  app collects less - no location, no microphone - so it needs a section,
  not a new page), signing with the upload key, SHA-1s where keys need them
  (none until Maps or Firebase), internal testing track first.

## Order and size

T0 → T1 → T2 → T3 → T4 → T5, then T6 / T7 in either order, T8 last. T1 and
T2 are the app; a teacher who has those two would use it on Monday. The
rough weight: T0 small; T1 medium (the one new endpoint plus the screen);
T2 medium-large (offline is where the care goes); T3 small; T4 small-
medium (mostly reuse); T5 medium (the grid); T6 medium (a new channel end
to end); T7 small-medium; T8 small but gated on the business (listing,
keystore, policy text).

## Risks, named

- **Two apps on one signing key.** The upload keystore that does not exist
  yet (docs/driver-app.md, D6) is now needed for two listings. Make it
  before either reaches Play.
- **Statuses drift.** The register offers exactly the statuses the server
  accepts (present / absent / leave today). If the school side ever gains
  one, the phone must learn it from the API, not from a hard-coded list.
- **Back-dated registers.** The web allows what the server allows; the
  phone must not quietly widen it. The date picker's range comes from the
  API's refusal, not from the app.
- **Push without a business Firebase project** is a demo, not a feature.
  T6 waits for the account.
- **Session length on a shared staff-room phone.** 30 days is right for a
  driver's own phone; a teacher app on a shared tablet needs the existing
  device sign-out to be easy to find. Profile already has it.

## What I need from you

1. **One app or two** (recommend two APKs, one codebase).
2. **Push in a later phase** (recommend yes - T6) and, when the time comes,
   a Firebase project owned by the business.
3. **Offline register in T2** (recommend yes).
4. **HOD inside the teacher app** (recommend yes - T7).

Answer those and T0 can start the same day; T0 and T1 together give a
screen to show.
