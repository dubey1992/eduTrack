# Offline mode for the web app - plan (2026-11-28)

**Status: plan only, nothing built or approved.** Schools asked to keep using
the web app when the school's internet goes down. This page says what can
be made to work offline, what cannot, and what each step costs.

## Where we start

- **The web app does not open at all without internet.** Nothing of it is
  kept on the computer: every visit downloads the app, then asks the server
  for every screen.
- **The phone apps already survive a lost signal.** The Staff app saves a
  register or a teaching report on the phone and sends it when the signal
  is back (M4); the Driver app keeps trip marks; the Family app shows the
  last copy of each screen with "as of 9:40 AM". That code is reused below.
- **The server is the one source of truth.** Receipt numbers, fee dues,
  payroll, report cards, messages and PDFs are worked out on the server.
  Two computers offline at the same time cannot see each other's work
  until both are back online - that is the real limit of any offline mode.
- **Sessions end after 7 days unused** (Phase 21). Offline work longer
  than that needs a fresh sign-in before it can be sent.

## What can work - four steps, each useful on its own

### O1. The app opens without internet (small)

After one visit online, the computer keeps a copy of the app itself (a
service worker caches the app's files). With no connection the app still
opens, signs the person in from their saved session, and shows a clear
**"Offline - showing what this computer last saw"** bar. Anything that needs
the server says so instead of spinning.

- Sign-in for the **first** time on a computer, and password resets, still
  need internet.
- A new version of the app is picked up the next time the computer is
  online.

### O2. Read the important screens offline (medium)

The computer keeps the last copy of the screens a school office uses all
day, each marked with when it was fetched:

- today's timetable and each teacher's day
- class lists: names, roll numbers, admission numbers, guardian name and phone
- student and staff records (the list and each person's details)
- each student's fee dues and receipts
- the day's registers already taken
- notices and the inbox

Stored in the browser's own database (IndexedDB), because the browser's
small key-value storage holds only a few MB. Records are refreshed in the
background while online, so the copy is never more than minutes old when
the line drops.

**Privacy on shared office computers:** class lists and records name
children. Copies are kept only on a computer marked **"This is a school
computer I trust"** at sign-in (default off), are wiped on sign out, and
the school can switch offline copies off entirely in its settings.

### O3. Do the daily work offline, send it later (medium)

Work that only one person writes, and that the server can check when it
arrives, is saved on the computer and sent when the line is back:

- **student attendance registers** - the same queue as the Staff app
- **staff attendance** marked in the office
- **teaching reports** and **marks** on a marks sheet (as drafts, saved later)
- **leave applications**
- **notices and messages** written offline - they go out when the
  connection returns, never before (the server sends SMS and WhatsApp)

A **"Waiting to send (3)"** counter shows what has not reached the school
yet. If the server turns something down when it arrives - a register
somebody else already submitted, a holiday - it is listed with the reason,
never silently dropped, exactly as the Staff app does today.

### O4. Collect fees offline (large - needs a decision)

The most-asked case: the fee counter keeps taking cash when the line is
down. Receipt numbers are given out in order by the server, so an offline
counter cannot know the next one. The safe way:

- An offline payment gets a **provisional receipt** - "P-<counter>-<n>",
  printed with a line saying the final receipt follows.
- When the counter is back online the payment is sent, the server checks it
  against the dues as they are then, and gives it its real receipt number.
- If two counters took money for the same fee while both were offline, the
  second one is flagged for the accountant to settle (refund or credit);
  nothing is merged on its own.
- Only cash and cheque offline; UPI and bank transfer are confirmed later
  anyway.

## What will not work offline

- **Sending SMS, WhatsApp and email** - they are queued and go out when the
  line is back.
- **Anything another person changed meanwhile** - an offline computer sees
  only its own copy.
- **Setting up the school** - classes, timetables, fee plans, users and
  permissions stay online-only: two people changing them offline would
  conflict.
- **Payroll runs, imports, report cards, progress reports and every PDF or
  CSV report** - worked out on the server from everybody's data.
- **The live bus map** and the school bus alerts.
- **A first sign-in, a password reset, the Super Admin's screens.**

## Not recommended: a server inside the school

A small computer in each school running its own copy of School365ai would
make everything work offline, but it means hardware to buy and maintain in
every school, two databases to keep in step, and the hosting rules
(CLAUDE.md: cPanel only, no extra servers) rule it out. The steps above
keep one server and one truth.

## Order and size

| Step | What the school gets | Size | Database change |
|---|---|---|---|
| O1 | The app opens with no internet; a clear offline bar | S | - |
| O2 | The main screens readable offline, "as of" time on each | M | - (a "trusted computer" switch per school setting) |
| O3 | Registers, staff attendance, reports, marks, leave, notices done offline and sent later | M | - |
| O4 | Fee counter keeps collecting, provisional receipts | L | Yes - provisional payments and how they were settled |

O1 + O3 together cover what most schools mean by "the internet went down
this morning": the registers get taken and nothing is lost. O2 makes the
office useful while it waits. O4 is worth doing only if fee counters are
where the outages hurt.

## Decisions needed

- **D1** - Which steps, in which order? (O1 + O3 first recommended.)
- **D2** - Offline copies of records on office computers: only on a computer
  marked trusted, wiped on sign out, school can switch off - agreed?
- **D3** - Fees offline (O4): build it, and if so, cash and cheque only?
- **D4** - How old may an offline copy get before the app refuses to show
  it as current - one school day, or as long as the session lasts (7 days)?
