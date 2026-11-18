# Mobile apps review: what would set them apart

**Status (2026-11-18): review and phase plan (M0-M12) only - nothing here is built or approved.**

The three phone apps - Staff (teachers, HODs, office, accountants), Driver
(drivers and bus attendants) and Family (parents) - were read screen by screen
against what Indian school apps commonly offer (Teachmint, Entab CampusCare,
MyClassboard, Edunext, TrackSchoolBus and similar). Those rivals mostly sell
the same list: attendance, fees, homework, notices, GPS bus tracking, RFID or
QR boarding. Matching that list does not set School365ai apart. What can is:
**doing the daily jobs in fewer taps, never losing data on a bad signal,
telling the truth about every figure, and speaking the user's language** -
things the apps already lean towards and rivals rarely do well.

Each point says which app it is for: **[S]** Staff, **[D]** Driver,
**[F]** Family. **Effort**: S small (days), M medium (a week or two), L large.
**Kind**: *Fix* = something planned or promised that is missing or broken;
*Gap* = rivals have it and we do not; *Edge* = would make us different.

---

## 1. The daily job in fewer taps

The single biggest difference a teacher or driver feels.

| # | Improvement | App | Kind | Effort |
|---|---|---|---|---|
| 1.1 | **"Board everyone at this stop"** with tap-to-remove exceptions, instead of one tap per child (40 children = 40+ taps today) | D | Edge | S |
| 1.2 | **Undo snackbar** after every boarding/drop mark (the design promised it; only a superseding mark exists) | D | Fix | S |
| 1.3 | **Auto "Reached"** when the bus is within the stop's radius, with the button kept as override | D | Edge | M |
| 1.4 | **SOS and End trip in a fixed thumb bar**, not at the bottom of a long list (design said so) | D | Fix | S |
| 1.5 | **Register by exception**: open with everyone present, tap only absentees; search by name/roll; swipe left/right | S | Edge | S |
| 1.6 | **Teaching report in one tap**: "Same as yesterday", templates per subject, voice dictation, saved drafts | S | Edge | M |
| 1.7 | **Marks entry by voice or camera**: read a column of marks from a photo of the answer-sheet list (OCR), teacher confirms | S | Edge | L |
| 1.8 | **Shortcuts from Home** - Results card, "Report sick" on the attendance card, live map straight from the bus card | F | Fix | S |
| 1.9 | **Leave**: balance card (planned in T4, not built), cancel/withdraw, half-day | S | Fix | S |

## 2. Never lose work on a bad signal

Rivals assume signal; Indian school buses and staff rooms often do not have it.

| # | Improvement | App | Kind | Effort |
|---|---|---|---|---|
| 2.1 | **Offline queue for marks entry and teaching reports**, like the register already has | S | Edge | M |
| 2.2 | **Read-only cache for every Family screen** (fees, results, notices), not just Home - "showing what was true at 9:40" | F | Edge | M |
| 2.3 | **GPS points kept, not cleared**, when the server says the trip ended; refused batches logged, not discarded | D | Fix | S |
| 2.4 | **Start a trip with no signal** and sync when back (today it is refused) | D | Edge | M |
| 2.5 | **"Not sent" items can be retried or explained**, not only dismissed | D, S | Fix | S |
| 2.6 | **Today screen retries itself** when the connection returns (only a Retry button today) | S | Fix | S |

## 3. Speaking the user's language

No major rival does Hindi and regional languages well across all three apps; drivers and many parents need it most.

| # | Improvement | App | Kind | Effort |
|---|---|---|---|---|
| 3.1 | **Hindi first, then regional languages** (Marathi, Tamil, Telugu, Bengali...), chosen per user; all strings are hard-coded English today | D, F, S | Edge | L |
| 3.2 | **Spoken prompts for the driver** ("Next stop Green Park, 4 children") using text-to-speech | D | Edge | M |
| 3.3 | **Child photos** on the driver's list and the teacher's register - faster and safer than reading names | D, S | Gap | M |
| 3.4 | **Large-text and screen-reader pass**; dates in the user's local format rather than US order on phones | D, F, S | Fix | M |

## 4. Trust and honesty - what the figures really mean

Already the product's character on the web; carry it into the apps.

| # | Improvement | App | Kind | Effort |
|---|---|---|---|---|
| 4.1 | **"Why am I seeing this?"** under every figure (attendance %, fees owed, grade) - one line saying how it was worked out | F | Edge | S |
| 4.2 | **Delivery receipts visible to parents and staff**: "Your absence note was read by Ms Rao at 9:12" (seen exists; extend to calls, notices) | F, S | Edge | S |
| 4.3 | **Trip proof for parents**: the actual time the child boarded/dropped and who marked it, already recorded - show it in a clean timeline with the stop map | F | Edge | S |
| 4.4 | **App lock** (fingerprint/face) for the Family and Staff apps - payslips, fees and children's data | F, S | Gap | S |
| 4.5 | **Privacy controls the parent can see**: which staff can see their number, when the bus shares location (only during their child's trip - already true, say so) | F | Edge | S |

## 5. Proactive, not reactive - the app tells you before you ask

| # | Improvement | App | Kind | Effort |
|---|---|---|---|---|
| 5.1 | **Reminders for staff**: register not marked by first period, reports owed at end of day, check-in missed (listed as "not yet") | S | Fix | M |
| 5.2 | **Push routing to the right screen**: a fee alert opens Fees, a bus alert opens the live map (Family push always opens Notices today) | F | Fix | S |
| 5.3 | **Turn on push for Family and Driver apps** - Family needs its Firebase app registered; the Driver app has the package but no use | F, D | Fix | S |
| 5.4 | **Early-warning for parents**: "Attendance is 72% this term, below the school's 75% line" - the backend's early-warning already exists | F | Edge | M |
| 5.5 | **Delay broadcast from the bus**: one tap "Running 15 min late" to every parent on the route | D | Gap | M |
| 5.6 | **Fee due nudges with the amount and a pay link**, three days before the date | F | Gap | S |

## 6. Phone-native touches rivals skip

| # | Improvement | App | Kind | Effort |
|---|---|---|---|---|
| 6.1 | **Home-screen widget**: "Bus 4 min away" / "Today: present" for parents; "2 reports owed" for teachers | F, S | Edge | M |
| 6.2 | **Keep screen awake and portrait lock** while a trip runs (design asked for both, not found) | D | Fix | S |
| 6.3 | **Add to calendar** for exam date sheets, PTMs and holidays (.ics) | F | Gap | S |
| 6.4 | **UPI intent** ("Pay with any UPI app") instead of copying the UPI ID, even before a gateway | F | Edge | S |
| 6.5 | **Deep links** from SMS/WhatsApp messages straight into the right app screen | F, S | Gap | M |
| 6.6 | **Camera in the Staff app** for profile photo (web-only today) and attaching a photo to a report | S | Fix | S |
| 6.7 | **Share payslip/receipt PDFs** through the share sheet, not only by email | S | Fix | S |

## 7. Role gaps inside the apps

| # | Improvement | App | Kind | Effort |
|---|---|---|---|---|
| 7.1 | **HOD approves leave** and marks the staff register from the phone (web-only today) | S | Fix | M |
| 7.2 | **Accountant home**: today's collection, recent receipts, students overdue - the office staff Home is only check-in | S | Fix | M |
| 7.3 | **Call requests for teachers** in the Staff app (they reach the web only) | S | Fix | S |
| 7.4 | **Student lookup** for teachers (planned in T4, no route) | S | Fix | M |
| 7.5 | **Week timetable**, not only today | S | Gap | S |
| 7.6 | **Fix stale copy**: office staff Home still says leave and payslips are "coming to this app next" - they are already there | S | Fix | S |

## 8. Learning and engagement for families

What rivals lead with; worth matching only where it fits the product.

| # | Improvement | App | Kind | Effort |
|---|---|---|---|---|
| 8.1 | **Homework** the teacher already writes in the teaching report, shown to the parent that evening | F | Gap | M |
| 8.2 | **Marks trend chart** per subject across tests and terms | F | Gap | S |
| 8.3 | **Notice attachments** (PDF, photo) | F | Gap | M |
| 8.4 | **PTM slot booking** with the class teacher | F | Gap | M |
| 8.5 | **Second guardian invite** by the parent, not only by the office | F | Gap | S |
| 8.6 | **Events and photo gallery** | F | Gap | L |

## 9. Release readiness (blocks everything above)

| # | Item | App |
|---|---|---|
| 9.1 | Family push: register `com.school365ai.family` in Firebase | F |
| 9.2 | Real-device test of trip GPS on Xiaomi/Oppo/Vivo/Samsung (D4.4 open) | D |
| 9.3 | Privacy policy legal review, Play listings and data-safety forms | D, F |
| 9.4 | Decide the crew role label and launcher name ("Driver App" shown to attendants) | D |
| 9.5 | Family app docs still say "plan only" at the top | F |

---

## Phase plan (2026-11-18)

Every point above, in the order it should be built. A phase is shipped,
tested on real phones and deployed before the next starts (CLAUDE.md rule 1).
**DB** marks a phase with database changes; **Decide** marks a question for
the product owner before that phase starts.

| Phase | Name | Items | Apps | Size | DB | Why here |
|---|---|---|---|---|---|---|
| M0 | Release groundwork | 9.1-9.5, 5.3 | F, D | S | - | Push and the real-phone GPS test unblock everything that notifies or tracks |
| M1 | Quick wins | 1.2, 1.4, 1.8, 1.9, 2.3, 2.5, 2.6, 6.2, 6.7, 7.6 | S, D, F | S | - | Small, low-risk fixes the design already promised; the apps feel finished |
| M2 | Fewer taps | 1.1, 1.5, 1.6 (templates, same-as-yesterday, drafts), 7.5 | D, S | S-M | - | The daily jobs - boarding a stop, the register, the teaching report - get fast |
| M3 | Notifications that land | 5.1, 5.2, 5.6, 6.5 | S, F | M | - | Needs M0's push; reminders and alerts open the right screen |
| M4 | Never lose work | 2.1, 2.2, 2.4 | S, F, D | M | - | Offline queues for marks and reports, cached Family screens, trips started with no signal |
| M5 | Role gaps | 7.1, 7.2, 7.3, 7.4, 6.6 | S | M | - | HOD, accountant and office staff get their jobs on the phone |
| M6 | Trust and safety | 4.1, 4.2, 4.3, 4.4, 4.5, 6.4 | F, S | S-M | - | App lock, honest figures, read receipts, boarding timeline, pay with any UPI app |
| M7 | Smart bus | 1.3, 3.2, 5.5 | D, F | M | Decide | Auto "Reached" at the stop, spoken prompts, one-tap delay message |
| M8 | Family learning | 8.1, 8.2, 8.5, 6.3, 5.4 | F | M | DB, Decide | Homework from the teaching report, marks trends, second guardian, calendar export, attendance warnings |
| M9 | Photos and attachments | 3.3, 8.3 | D, S, F | M | DB, Decide | Student photos (no photo field exists on students today), notice attachments |
| M10 | Widgets | 6.1 | F, S | M | - | Home-screen widgets once the data behind them (M3, M7) is settled |
| M11 | Languages and accessibility | 3.1, 3.4 | S, D, F | L | Decide | Hindi, then regional languages, plus a large-text and screen-reader pass - after the screens above exist, so each string is translated once |
| M12 | Bigger bets | 1.7, 8.4, 8.6 | S, F | L | DB, Decide | Marks from a photo (OCR), PTM booking, events and gallery - only if schools ask |

**M0 progress (2026-11-18, built on main, not deployed):**

- 9.4 naming decided and done: icon "School365ai Bus", Play name kept, "Bus crew" where text speaks to both crew (docs/driver-app.md).
- 5.3 Driver push wired: crew phones register as app `driver`; a tap opens My Trip; nothing is sent to crew until M7. Family push code was already in place.
- 9.1 Firebase: guide for the owner, docs/firebase-setup.md - push stays off until the project exists.
- 9.2 GPS test: a **Trip check** screen in the Bus app (the trip log: positions taken, longest gap, sent / waiting / refused, background time, battery exemption, shareable report) and the test plan, docs/phone-gps-test.md - the runs themselves are the owner's.
- 9.3 Play listings and data-safety answers drafted, docs/play-store-listings.md; legal review and the "to confirm" answers are the owner's.
- 9.5 Family doc status brought up to date.

**M1 progress (2026-11-18, built on main, not deployed):**

- Bus app sign-in (asked for by the owner): "Register this phone" now has *Already set up? Sign in with your passcode*, so a wrong tap on "register again" is no longer a dead end. A phone that was never set up still needs a setup code - the server checks the phone's own secret before the passcode, on purpose - and the message now says so.
- 1.2 A child's boarded / dropped / absent mark waits 5 seconds on the phone with an **Undo** snackbar (the server has no "unmark" and tells the family at once). Later marks wait behind it; an SOS never does.
- 1.4 **SOS and End trip** sit in a bar fixed at the foot of a running trip.
- 2.3 The server now takes positions recorded before a completed trip's end (answering `in_progress: false`); a cancelled trip, or a batch with nothing from before the end, is still `TRIP_NOT_IN_PROGRESS`, which older apps already handle. Points left on the phone after a trip are sent when sharing stops and when My Trip opens.
- 2.5 Bus: a turned-down mark can be **tried again** while the trip runs, and the card says what to do. Staff: a refused register says why on Today's card and what to do on the register.
- 2.6 Today asks again by itself every 15 seconds with no signal, and as soon as the app comes back to the front - no new package.
- 6.2 While a trip's sheet is open the screen stays on (FLAG_KEEP_SCREEN_ON through the app's own channel, beside FLAG_SECURE) and upright.
- 6.7 A payslip can be **shared** from the phone (the server already let an employee fetch their own finalized PDF). The Family app already shared receipts, statements and report cards.
- 7.6 Office staff Home names the Leave and Pay tabs and the bell, only those the school has on.
- 1.9 **Withdraw** a pending leave request (PATCH /leaves/{id}/withdraw: own, own school, pending only; status `withdrawn`, a plain string column, so no migration) and a **taken this year** card (GET /leaves/mine/taken: approved working days by type over the current academic year, the calendar year without one). Half-day leave already existed. A true *balance* is not built: the school sets no yearly allowance per leave type - see the decision below.
- 1.8 Family Home: **Report sick** on the attendance card (no mark yet, or absent), the bus card opens the **live map** while the child's trip runs, and a **Results** card where results are on.

**M2 progress (2026-11-18, built on main, not deployed):**

- 1.1 Bus: **Board all n here** under each stop on a pickup (Drop all on a drop), and **all at school** at the run's school end. A sheet lists everyone ticked; untick the few who are not there. One Undo takes the lot back inside the 5-second window.
- 1.5 Staff: the register **opens with everyone present** - except a child whose parent sent a note for the day, left for the teacher, and Submit waits for them. The confirm dialog still says the counts. Search by name or roll number; swipe a row right for present, left for absent.
- 1.6 Staff: the teaching report has **Same as <date>** (the teacher's own last report for this class and subject - GET /teaching-reports now takes `class_section_id` and `subject_id`), **templates** per subject (at most ten, newest first) and a **draft** saved as the teacher types. Templates and drafts stay on the phone and go on sign-out. Voice dictation was not part of M2.
- 7.5 Staff: **My week**, one tap from Today - the teacher's own periods for each day, opening on today (the existing GET /timetable?teacher_id=).

**M3 progress (2026-11-18, built on main, not deployed). Decided by the owner: staff reminders off for schools already live, times from the day's periods, links in push and WhatsApp only:**

- 5.1 **Staff reminders** - register not taken (once the first period has ended), not checked in (30 minutes into the first period, where staff check in from the app), reports still owed (once the last period has ended). `send_staff_reminders`, cron every 15 minutes (docs/deployment.md). Three switches in Settings -> Modules (Student Attendance, Staff Attendance, Teaching Reports): **off for every school already live**, on for schools created from now. Inbox and push only, never SMS; once a person a day; nothing on closed days, holidays or leave. A tap opens Today.
- 5.2 Family push opens the screen it is about: fees -> Fees, bus -> Bus, results -> Results, attendance -> Attendance, anything else -> Notices.
- 5.6 Fee reminders already went three days before the due date with the amount (F5); with 5.2 their push opens Fees.
- 6.5 **Links**: a WhatsApp template may now use a `link` value - `https://school365ai.com/f/<screen>` for parents (the web app for staff). It never reaches SMS or a school's own wording. The website writes `/f/` (a page for phones without the app) and `/.well-known/assetlinks.json`; the Family app opens those links on the named screen. **Owner steps:** (1) the Family app's SHA-256 signing fingerprints from Play Console into `FAMILY_APP_LINK_FINGERPRINTS` on the server, (2) a WhatsApp template with a link variable approved in Meta/Twilio, then `link` added to its parameters in Platform messaging.

**M4 progress (2026-11-18, built on main, not deployed):**

- 2.1 Staff: a **teaching report** filed with no signal, and a class test's **marks** saved with none, wait on the phone in one outbox (like the register) and go when signal returns - retried after 5/15/30/60 s, on sign-in and when the app comes back to the front. A report the server already has counts as done; another refusal is kept with its reason and the words go back into the period's draft. The newest marks for a test replace older ones, and Publish waits until they are in. Today's card says *Saved, not sent* or *Not sent*.
- 2.2 Family: **Fees, Bus, Attendance, Results, Notices, Timetable, Syllabus and Admit cards** keep their last answer on the phone and, with no signal, show it with *No connection. Showing what was true at 9:40 AM.* - as Home did. Signing out now forgets every copy, Home's included (Home's was kept before). A refusal is never covered by an old copy; the live bus map never uses one.
- 2.4 Bus: **Start works with no signal**. My routes now carries each route's roster (its stops and children); the phone opens the trip from it under a stand-in id, and marks, positions and End collect there. When signal returns the start goes first - `POST /transport/trips` now takes `started_at`, today only, at most 12 hours old - and everything moves onto the real trip. If the other crew member started it meanwhile, this phone joins that trip; any other refusal moves its marks to *Not sent* with the reason. A phone that never saved the roster (an app or server older than this) still needs signal to start.

**Decisions needed before their phase:**

- **M7** - does an auto "Reached" also send the parents' "bus at stop" alert, or only the manual one? What delay choices does the driver get (10 / 15 / 30 minutes, or free text)?
- **M8** - should every period's homework go to parents, or only what the teacher marks "send to parents"? Does a second guardian get the same rights as the first (fees, absence notes)?
- **M9** - who uploads student photos (office, class teacher, or the parent), and are they shown to bus crew? Which notice attachments are allowed (PDF and images only?) and how large?
- **M11** - which languages after Hindi, and in what order? Does each user choose, or does the school set it?
- **M12** - only on a school's request.

- **Leave balance (1.9, left out of M1)** - a balance needs a yearly allowance per leave type (e.g. 12 casual, 10 medical), set per school and perhaps per role, and a rule for a new joiner mid-year and for unused days. That is a new table and a decision. Until then the card shows what was taken.

Nothing else in M1-M6 changes the database or needs a decision.

## Recommended first slice - the clearest difference for least effort (M1 + M2)

1.1 board-all, 1.2 undo, 1.4 thumb bar, 1.5 register by exception, 1.8 Home
shortcuts, 2.3 keep GPS points, 4.4 app lock, 5.2 push routing, 6.2 keep
awake, 6.4 UPI intent, 7.6 stale copy - all small, and together they change
how the apps feel day to day. Hindi (3.1) is the biggest single
differentiator but is large; it is worth starting early because every new
screen added later makes it larger.
