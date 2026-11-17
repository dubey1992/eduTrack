# The Family App: Parents and Students

**Status (2026-11-07): plan only.** CLAUDE.md lists the parent and student
apps as future work; the owner asked for this plan. Nothing is built until
the decisions at the end are answered and the plan is approved.

## 1. What it is, in one paragraph

One Android app, **School365ai Family**, for the people the school serves
rather than the people who work there. A parent signs in once and sees each
of their children: today at school, attendance, the bus, fees, results and
notices. An older student signs in to see their own timetable, tests and
notices. It shows what the school already records in School365ai. Nothing is
typed twice. Families get the alerts they get by SMS today, as free app
notifications instead.

## 2. Who it is for

| Person | What they want, in their words | How often |
|---|---|---|
| **Parent / guardian** | "Did my child reach school? Where is the bus? What do I owe, and is it paid? How did the test go? What did the school announce?" | Every school day, 2-3 short visits |
| **A parent of several children** | The same, for each child, without signing in again | Same |
| **Student (Class 6 and up)** | "What's my next period? When is the test? What marks did I get? Is tomorrow a holiday?" | Daily, short |
| **The school** (not a user, but the reason it exists) | Fewer phone calls to the office, fewer paid SMS, parents who trust the school | - |

**Who it is not for:** staff (they have the staff app), bus crew (Driver
app), and anyone the school has not linked to a student.

## 3. What already exists, and what is missing

| Need | Today in School365ai | Gap |
|---|---|---|
| A guardian's contact | One name, mobile and email on each student | No **guardian account**; no way to link one parent to several children or two parents to one child |
| Sign-in | Staff: email + password. Crew: mobile + passcode | No PARENT or STUDENT role, no family sign-in |
| Attendance | Daily register per class, absence alerts | Nothing for families to look at - only the alert |
| Bus | Routes, stops, trips, boarding events, live GPS during a trip | No family view, no time-to-my-stop |
| Fees | Dues, instalments, receipts (PDF), statements, reminders | No family view; payment is at the counter only |
| Results | Tests, marks, published results, progress report PDFs | No family view |
| Notices | Announcements (to parents), notices, inbox for users | Parents get them by SMS/WhatsApp/email only |
| Push notifications | Device tokens, push to staff phones | Not for families |
| Leave / absence notes | Staff leave only | **New:** a parent telling the school their child will be away |
| Homework | Assignments are a test type | No homework module (out of scope here) |

## 4. Decisions shaping the plan (recommended answers, for the owner to confirm)

| # | Question | Recommendation | Why |
|---|---|---|---|
| D1 | How do families sign in? | **Mobile number + a one-time code**, with a **school-issued passcode** as the fallback until codes can be sent reliably | Parents rarely have work emails. India SMS needs DLT registration first, so a passcode the school prints (as the bus crew have) works from day one |
| D2 | One app or two? | **One app** for parents and students, which opens the right home for each | One store listing, one codebase, one name for the school to share |
| D3 | Which students get a login? | **Class 6 and up, switched on per school**, only with the guardian's consent | Young children don't have phones; consent is the law for minors' data (DPDP Act 2023) |
| D4 | Online fee payment? | **Not in the first release**: show dues, receipts and how to pay at school. A payment gateway is a separate, later decision | A gateway brings settlement, refunds, reconciliation and compliance; the counter flow already works |
| D5 | Can parents message teachers? | **No open chat.** Structured requests only: an absence note, "please call me", replies to notices | Open chat floods teachers and can't be moderated; structured requests land in the right place |
| D6 | Do parents see "at risk" labels? | **No labels.** Parents see attendance and marks plainly; the school talks to them | A label in an app, without a conversation, does harm |
| D7 | Languages | **English first, Hindi in Phase 6**, built ready for more | Most parents read English or Hindi; adding languages later is cheap if planned now |
| D8 | iPhone? | **Android first**; iPhone once the Android app has settled | Most Indian parents use Android; the Apple account and review are a separate step |
| D9 | Live bus map | **Only during the child's trip**, with the time to *their* stop | Privacy for the crew, and it is the one question parents actually ask |

## 5. Look and feel

**Principles**

- **Today first.** The home screen answers the morning's questions without a tap: is my child in school, where is the bus, is anything due.
- **One child at a time, switched in one tap.** Each child has a colour and their photo or initial; the colour carries through every screen so a parent never confuses two children.
- **Plain words.** "Present", "Absent", "On the bus", "Paid", "Due on 10 Dec". No codes, no system words.
- **The same colours mean the same things everywhere**, matching the staff dashboard: green = good (attendance 90%+), amber = watch (75-89%), red = act (below 75%); blue for information.
- **Calm, not noisy.** No red badge for something that is fine. A notification only for what a parent would want to be interrupted for.
- **Built for one hand, a cheap phone and a weak signal.** Large touch targets, small app, the last-seen data shown when offline with a clear "updated 8:42 am" line.

**The visual system**

- School365ai blue (#2563EB) as the brand, navy (#0F172A) for headers, a soft off-white ground, Poppins for type - the same family as the website and staff app.
- Rounded cards, generous spacing, one main action per screen.
- Light and dark themes from the start.
- Icons from one set, always with a word beside them on the main screens.

**Navigation**

- Parent: a bottom bar with **Home · Attendance · Bus · Fees · More** (More holds Results, Notices, Calendar, Leave notes, Profile).
- Student: **Home · Timetable · Tests · Notices · More**.
- A child switcher at the top of every parent screen.

**Every screen has all five states designed:** loading (shaped placeholders,
not a spinner), success, empty ("No notices this week"), error with a retry,
and offline (last data, with when it was fetched).

## 6. Validation and safety rules (the main ones)

| Where | Rule | What the person sees |
|---|---|---|
| Mobile number | Country code required, digits only, the school's country by default | "Enter your mobile number with the country code, e.g. +91 98765 43210" |
| Mobile not on file | The number must match a guardian on at least one student | "This number isn't registered with a school. Please ask the school office to add it." - never reveals which school or child |
| One-time code | 6 digits, 5 minutes, 5 tries, then a 15-minute wait; resend after 30 s | Countdown on the resend button; the field shakes and says how many tries remain |
| Passcode | 6 digits, set by the school, changed on first sign-in | Same lockout rules as staff |
| Absence note | From today up to 30 days ahead; not on holidays; a reason is required (10-500 characters); an optional photo of a note (JPG/PNG, under 5 MB, re-encoded on the server) | Field-level messages; a note already sent for those days is shown, not duplicated |
| Profile | Email format; a second mobile only with its own code | Inline, as the field is left |
| Student login | Only if the school has switched it on and the guardian has consented | "Ask your parent to turn on your account in their app" |

**Server rules that never rely on the app:**

- A family account sees only the students linked to it, inside their own school.
- Every family API has an ALLOW and a DENY test, including a guardian trying another child's ID.
- No phone number, email or other child is ever shown across families.
- Family sign-ins and changes go to the audit log.
- Sessions last 30 days on a phone and can be signed out from the school's side.

## 7. The phases

Each phase ships on its own and is tested, demoed live and deployed before
the next one starts.

### Phase F0: Foundations (no app yet)

- **Guardian accounts.** A `guardians` table linked to students many-to-many: relationship (mother, father, guardian), primary contact, mobile, email, consent recorded with date. The existing guardian columns are read once to create the first links; nothing is removed.
- **PARENT and STUDENT roles**, with a scope rule of "linked students only".
- **Family sign-in:** mobile + code (when sending is approved) and school-issued passcode, lockout, sessions, device sign-out.
- **School side:** a Guardians tab on each student (add a second guardian, resend a passcode), a switch per school for the family app and for student logins, and a printable letter for parents with how to download and sign in.
- **Push for families:** the existing alerts (absence, boarding, fee reminder, results, announcements) can go to the app first, and to SMS only when the app isn't installed. This cuts the school's SMS cost.
- **Tests:** isolation ALLOW/DENY, sign-in lockout, guardian-linking rules.

**As built (2026-11-07).** Sign-in works the way the bus crew's does. The office notes the guardian's consent, then either prints a sign-in letter or reads out a code. The code is 8 digits, works for 7 days on one phone, and issuing a new one cancels the old one. On the phone, the parent enters their mobile number and the code, then chooses a 6-digit passcode. The app keeps a secret tied to that phone. Five wrong passcodes lock the account for 15 minutes, and a session ends after 30 days unused. Sign-in by a code sent to the mobile comes later, once sending is approved.

A family account works only on `/api/v1/family/...` and on the public pages (privacy, terms). Every staff URL refuses it with `FAMILY_APP_ONLY`, and family accounts never appear in staff lists or counts. The switch is the module "Family App", which is off unless the platform grants it. Mobile numbers already on student records became guardians: one guardian per school and number, so siblings share theirs. Still to do in F0: push for families, and the switch for student logins (it waits for F6).

### Phase F1: The parent app's core (read only)

- Sign-in, child switcher, **Home "Today"**: attendance today, bus status, the next fee due, the latest notice, today's timetable at a glance.
- **Attendance:** a month calendar coloured by day, the term's percentage with the colour bands, and the reason for any absence.
- **Notices:** announcements and messages from the school, newest first, unread marked.
- **School calendar:** holidays and closed days.
- **Notifications** with per-type switches (absence, bus, fees, results, notices).
- Profile, sign-out, help and a "Contact the school" card (call / WhatsApp the office).

**As built (2026-11-07).** The app is its own build: flavour `family`, `com.school365ai.family`, `lib/main_family.dart`. It asks only for the internet and notifications. It has a bottom bar (Home, Attendance, Bus, Fees, More) and a child switcher that gives each child a colour.

- **Home** shows:
  - attendance today, in plain words;
  - the bus trip;
  - the next fee due;
  - the latest message;
  - today's classes.

  With no signal, it keeps showing the last copy and says when that copy is from.
- **Attendance** shows the month as a calendar coloured by day, the month's and the year's rate in the 90/75 bands, and the teacher's note on every absence.
- **Bus** and **Fees** show today's facts. The map comes in F4, the statement in F3.
- **More** holds Notices, the school calendar, the notification switches, Contact the school (call, WhatsApp, email the office) and sign-out.

Decisions taken while building:

- **The parent's rate is out of the days the register was marked.** A working day the school never marked doesn't count against the child, and the app says how many such days there were. The staff reports keep the Phase 18 rule (working days).
- **The school's messages reach the app as well as the phone.** A guardian with the app gets an in-app copy of each message the school sends them (school/family_inbox.py), addressed to them by name. Their own switches decide which kinds arrive; an emergency always does. A whole-school notice arrives once, however many children they have at the school. SMS and WhatsApp go out exactly as before. "The app instead of SMS" is still to come.
- **Push** reuses the staff app's Firebase code through `family/devices`. It needs `com.school365ai.family` added to the business's Firebase project. Until then the app has no push, and notices still arrive inside it.

### Phase F2: Academics

- **Results:** each published test with the mark, the grade and the class average (if the school allows), term by term.
- **Progress reports:** the PDF, downloaded and shareable.
- **Timetable** for the week, with today's lessons.
- **Syllabus progress** per subject, in plain words: "Science: 14 of 22 topics covered".

### Phase F3: Fees

- **What is due:** each instalment with its due date and status (paid, part paid, due, overdue).
- **Receipts:** every payment with its numbered PDF receipt, downloadable.
- **Statement** for the year.
- **How to pay:** the school's counter hours, bank and UPI details as the school enters them.
- Reminders arrive as notifications, before the due date and when overdue, as the school sets.

**As built (2026-11-17).** The Fees tab reads the same ledger as the office's statement (`school/family_fees.py`), so a parent and the accounts clerk never see different numbers.

- It shows:
  - what is left to pay this year and how much of it is overdue;
  - charged, discount, paid and any credit held;
  - each instalment as paid, part paid, due, overdue or waived (a cancelled one is left out);
  - every receipt (a cancelled one marked), each opening as its PDF;
  - the year's statement as a PDF.
- **How to pay** is the school's own words: three new Fees settings (fee counter hours, bank details, UPI ID) that the School Admin fills in under Module Settings, plus the office phone. The UPI ID must look like one (`name@bank`).
- Module settings gained a "text" type (length-capped, optionally several lines, optionally a pattern) for this.
- Both the Family App and the Fees module must be on; a receipt or a child that isn't the caller's own is a 404.
- Reminders already reach the app: fee reminders go through the guardian notifications, which copy into the Family app since F1.
- API: `GET family/children/{id}/fees`, `.../fees/statement.pdf`, `.../receipts/{receipt_id}/pdf`.

### Phase F4: The bus

- **Live map during the child's trip** only: the bus, the route, the child's stop, and the time to the stop.
- **The trip, as it happens:** "Boarded at Baner stop, 7:41 am" - "Reached school, 8:02 am", and the same on the way home.
- The route, the stop, the vehicle number, and the attendant's and transport office's numbers (as the school allows).
- A notification when the bus is near the stop (the distance set by the school).

**As built (2026-11-17).** `school/family_bus.py`.

- **The Bus tab** shows:
  - the route, the child's stop with its pick-up and drop times, and the vehicle and its number;
  - today's trips as the child's own moments, each with its time:
    - to school: the bus set off, reached their stop, they boarded, reached school;
    - home: the bus left school, they boarded, reached their stop, they got off;
    - "Did not board", a cancelled trip, or a child not on the list are said plainly;
  - who to call: the school office always. The bus attendant's own mobile appears only when the school switches on the Transport setting "Show parents the bus attendant's mobile" (off by default).
- **Following the bus**:
  - It is only for the child's own running trip, and only until they get off or are marked absent (D9). At any other time the API answers `BUS_NOT_LIVE`, and the app says the bus isn't on the road for them now.
  - The map shows the bus, the route's road and their stop, refreshed every 15 seconds. Underneath, in words: "On its way to Sakal Nagar · about 4 minutes · 350 m away · 1 stop before yours".
  - The time appears only once their stop is the next one (from the stored road legs).
  - It warns when the last position is a few minutes old.
  - Without a map key, the words are still there.
- **"The bus is near your stop"** is a new alert, `transport.near_stop`:
  - It reaches the Family app only, never by SMS or WhatsApp.
  - It is sent once per child per trip, when a position the crew's phone uploads comes within the school's distance of the stop. The distance is the Transport setting `near_stop_alert_m`: default 500 m, and 0 turns it off.
  - It is for a child still waiting at a stop the bus hasn't reached: on a pickup, one not yet boarded; on a drop, one on board.
  - It follows the parent's Bus switch.
  - Like every alert, the school can reword it.
- **Maps** for a family account come from `family/maps-config`; the staff endpoint stays closed to them.
- API: `GET family/children/{id}/bus`, `.../bus/live`, `family/maps-config`. Transport must be on, and another child is a 404.

### Phase F5: Talking to the school

- **Absence notes:** a parent tells the school their child will be away (dates, reason, an optional photo of a doctor's note). The class teacher sees it on the register; the parent sees it acknowledged.
- **"Please call me"** to the class teacher or office, with a reason, handled in the staff app.
- **Replies to notices** that ask for one (consent slips, event RSVPs), counted for the school.

### Phase F6: The student app, Hindi, polish

- **Student sign-in** (Class 6+, with consent): today's timetable, upcoming tests and assignments, their own results, notices and the calendar. No fees, no bus map for students unless the school allows.
- **Hindi** throughout, chosen on first launch.
- **Accessibility pass:** large-text layouts, screen-reader labels, contrast checked.
- **Play Store release:** listing, screenshots, privacy policy page, data-safety form.

### Later, only if approved

- Online fee payment through a gateway (D4).
- iPhone app (D8).
- Homework module, events and photo gallery.

## 8. How each phase is checked

- **Backend:** unit tests for the rules, API tests for every endpoint, ALLOW/DENY for school and guardian isolation.
- **App:** unit tests for repositories and view models; widget tests for every state of every screen and every form's validation; integration flows - *parent signs in → switches child → sees today*, *parent sends an absence note → teacher sees it*, *parent opens a receipt*.
- **Live demo** on a real phone against a demo school before each deploy.
- **Measured:** cold start under 3 s on a budget phone, app size under 30 MB, the home screen usable offline.

## 9. What the owner needs to decide now

1. **D1** sign-in method (code, passcode, or both).
2. **D2** one app for parents and students.
3. **D3** student logins: which classes, on by default or off.
4. **D4** online fee payment: later, as recommended?
5. **D5** structured requests instead of chat.
6. **D6** no risk labels for parents.
7. **D7 / D8** English then Hindi, Android then iPhone.
8. The app's name: "School365ai Family" or another.
