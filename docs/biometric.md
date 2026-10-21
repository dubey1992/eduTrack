# Biometric attendance — built, B4 pending a real device

A customer requirement, decided 2026-10-20. Staff punch in and out on a
fingerprint device; those punches become the check-in and check-out times on
the staff register.

## The three decisions

**Staff only.** `staff_attendances` already has `check_in`, `check_out` and a
half-day status — the columns a device would fill are the ones that exist.
Students are deliberately out: a class register is submitted by a teacher and
the guardian alerts go out from it, so a device that also marked students
would need a rule for what wins when the two disagree, and that rule is a
product decision nobody has needed yet.

**Devices push; a CSV upload is the fallback.** Shared hosting has no
persistent process and the devices sit behind the school's NAT with no public
address, so the server can never pull from them — that option is not slow, it
is impossible here. Devices POST to us on their own schedule, and any school
whose devices cannot reach the internet exports a CSV from the device software
and uploads it. The import machinery already exists
(`school/imports/reader.py`), so the fallback is cheap and it is what keeps
this working at a school with a locked-down network.

**A punch records a time, never a status.** The device fills `check_in` and
`check_out`; present, absent, half day and leave stay a person's call. A flat
battery, a device offline for a morning, or somebody who forgot to punch out
must never silently mark a colleague absent, because an absence reaches
payroll. The screen shows the device's times beside the status so a mismatch
is visible rather than resolved by guessing.

## What a punch actually is

A device reports a user id it knows and a wall-clock time in the school's own
day, and nothing else of use. Three consequences:

- **The user id is the device's, not ours.** It has to be mapped to a staff
  profile, and an unmapped id is a punch nobody can attribute - which must be
  visible, not dropped, or the first anybody knows is a missing register.
- **The time has no zone.** It is wall-clock at the school, so the school's
  own timezone turns it into an instant (`SchoolClock`, docs/timezones.md). A
  server that assumed its own zone would move every punch for any school far
  enough east or west.
- **Devices resend.** A device that did not get a clean answer sends the same
  batch again, so the same punch arrives twice and must land once.

## Schema

- **`biometric_devices`** — `school_id`, `serial_number` (unique across the
  platform, because the serial is how an unauthenticated device says who it
  is), `name`, `location`, `status`, `last_seen_at`. A serial maps to exactly
  one school; that mapping is the whole of the device's identity, which is why
  the next section is about its limits.
- **`staff_profiles.biometric_user_id`** — nullable, unique per school. One
  column rather than a table: a member of staff enrolled on four devices has
  the same id on all four, which is how the devices are set up.
- **`biometric_punches`** — `school_id`, `device_id` (null for an upload),
  `biometric_user_id`, `staff_profile_id` (null when nobody has mapped it),
  `punched_at` (UTC), `local_date`, `source`, and the raw line. Unique on
  (`source`, `device_id`, `biometric_user_id`, `punched_at`) so a resend lands
  once.

Raw punches are kept rather than folded straight into the register: an admin
asking why check-in says 09:02 needs to see the punch, an unmapped id needs
somewhere to sit until somebody fixes it, and idempotency needs a record of
what has already been seen.

## How the times reach the register

The earliest punch of a local day is the check-in and the latest is the
check-out. Where a `staff_attendances` row already exists for that day, its
times are filled in; where none does, **no row is created** - creating one
would mean choosing a status, which is exactly what these punches do not do.
The marking screen pre-fills the times from the punches instead, so the person
setting the status sees what the device saw.

A punch arriving after the register was saved updates the check-out. Times are
the device's business and the status is the human's, in both directions.

## What the device's identity is worth

A serial number is not a credential. It is sent in the clear by a box on a
school's LAN, and anybody who learns it can post punches for that school.
What limits the damage:

- **A punch can only ever write a time**, never a status, never a day's
  presence, and never anything payroll reads directly.
- **Devices are registered before they are trusted.** An unknown serial is
  recorded and refused, not silently accepted.
- A shared secret in the query string where the firmware allows one, rate
  limiting per serial, and every batch logged with what was accepted and what
  was refused.

This is stated plainly because the alternative - pretending the serial
authenticates anybody - is how this kind of endpoint becomes the weak point of
an otherwise careful system.

## The slices

**B1 - devices and who is on them. Built 2026-10-20.** The
`biometric_devices` table, `staff_profiles.biometric_user_id`, a Biometric
Devices screen under Staff Attendance, and a Biometric ID field on the
employee form. Nothing reads a punch yet.

Three things worth keeping:

- **"Never heard from" is said, not left blank.** A device registered this
  morning and silent is somebody's next job; one that spoke and then stopped
  is a fault. A blank in that column would read as neither, so the screen
  names the first case in its own words.
- **Removing a device says what it does not do.** It leaves the register of
  devices; the device itself is untouched and simply stops being recognised.
  Somebody about to press that button should know which of those they are
  doing.
- **The device list is cleared on sign-out.** `auth_notifier_reset_test`
  caught it: without that, one school's hardware stays on screen for whoever
  signs in next on the same browser.

**B2 - the punch log, by upload. Built 2026-10-21.** `biometric_punches`, a
CSV upload, and a screen showing what arrived - matched to a person, or
sitting unmatched with the id nobody has mapped. Still changes no register.

The log is the other half of the Biometric Devices screen rather than a nav
entry of its own: a log of punches with no sight of the readers that made
them is not a screen anybody opens, and a Devices | Punch log toggle matches
the List | Map pattern the schools page already uses.

Four things worth keeping:

- **An unattributed punch says so on the row.** "Nobody mapped to 88", not a
  blank. A blank reads as an absence of information; this is information,
  and it is somebody's next job.
- **The count comes from the server, not the page.** Twenty rows cannot tell
  "none on this page" from "none at all", so the list endpoint sends
  `unmatched_total` under the same filters and the screen says it above the
  table.
- **The upload dialog promises that a repeat is safe before anybody
  presses it.** That is the question somebody asks themselves while
  hesitating over a file they may already have sent, and the answer is three
  numbers afterwards: new, already in, and the lines that could not be read -
  every one of them, so the file can be fixed once.
- **One bad line does not refuse the file.** A month of attendance is worth
  having without the row somebody fat-fingered. This is deliberately unlike
  the bulk importer, which is all-or-nothing because a half-imported student
  roll is worse than none.

The punch log is cleared on sign-out for the same reason the device list is:
one school's staff movements, with names on them.

**The upload asks which school when the answer is ambiguous.** A file of
punches has no school in it. An admin over a group of branches, or a Super
Admin, has to say which one - the server will not guess, and before this it
answered a guess with "You are not authorized to perform this action", which
is both wrong and useless. It is the same `SchoolPicker` the device form
uses, prefilled from whatever the screen is filtered to, and the Upload
button stays disabled until it is answered. An admin of a single school is
never asked: the server files it under theirs whatever the request says.

**B3 - punches reach the register. Built 2026-10-21.** Earliest and latest of
a local day fill check-in and check-out; the marking screen pre-fills from
them; the status stays a human's. After this slice the feature is genuinely
useful with no device integration at all.

Four rules do the work, and each exists because the one sentence above would
otherwise let a device do something it must not:

- **A punch never creates a row.** Creating one means choosing a status, and
  a fingerprint reader cannot know whether somebody was late, on duty
  elsewhere, or simply there. A day nobody has marked stays unmarked - the
  times wait on the marking screen instead.
- **A punch never clears a time.** A day with no punches is left exactly as
  it was, typed times included. The cost is that a corrected enrolment
  leaves somebody else's times behind for a human to fix; the alternative -
  silently blanking a time somebody entered - is worse.
- **One punch is an arrival, not a day.** It fills the check-in and leaves
  the check-out alone, because a check-out equal to the check-in reads as a
  day of no work at all.
- **The clock is the school's.** The register is read at the school; a punch
  stored as an instant is converted back through the school's timezone
  (docs/timezones.md), which is what a half-hour offset catches.

The screen says `From the device` beside times it did not get from the
register, so whoever sets the status knows they did not type them - and can
change them, because the times are a starting point and the status is the
decision. Once the day is saved the times are the register's own and the
marker goes away. The upload dialog says how many days reached the register,
including when the answer is none: that almost always means nobody is
enrolled on those device IDs yet, which is better learned at the upload than
from an empty register a week later.

Filling is audited as `staff_attendance.times_from_device`, one entry per
day rather than per row: a month's upload is one action by one person.

**B5 - the punch marks the day. Built 2026-10-21.** Asked for after B3 went
in ("if a user puts his finger on the device, what should the action be?"),
and built before B4 because it needs no device integration at all: a file
uploaded this morning marks this morning's register.

A punch on a working day marks the person **Present**, with their times, on
a day nobody has marked. The decisions that shape it:

- **A punch is evidence of presence; no punch is evidence of nothing.** The
  absence of a punch is equally consistent with a broken reader, a failed
  scan and a file nobody uploaded, so nothing is ever marked Absent. A dead
  reader must not mark a school absent.
- **A status a human set is never changed**, in either direction. Once
  somebody has decided a day, the devices only keep the times current.
- **Only a working day, and only inside the school's own marking window.**
  A holiday, a weekend or a closed day keeps the punch and nothing else, and
  an upload of old history cannot rewrite months that humans are no longer
  allowed to touch either (`max_backdate_days`, docs/settings.md).
- **Nobody's name goes on it.** `marked_by` is left empty, and the screen
  says "Marked from the device" rather than implying somebody decided it.
  The audit entry (`staff_attendance.marked_by_device`) carries who uploaded.

**Lateness is derived, never a status.** It is `check_in` against the first
period of the school's timetable - the rule StaffReportService already counts
by, reused rather than reinvented, so the screen and the report can never
disagree. It is deliberately not a status value: four places count
`status == PRESENT`, one of them the day credit payroll reads, so adding
`LATE` to the enum would quietly stop a teacher who arrived at 09:05 from
counting as present. A school with no timetable has nobody late, which is
the same answer the report gives rather than a guess at a start time.

The consequence worth knowing: after this, the staff register fills itself
for everyone who punched, and the people who need a human are the ones who
did not. A day nobody reviews now reads as marked rather than as blank -
which is the point, but it is why the empty `marked_by` and the label on the
screen matter.

**B4 - the live push endpoint. Built 2026-10-21, against an assumed
dialect.** The device posts its own punches, so the CSV upload stops being
the only way in. Three URLs at the domain root - `/iclock/cdata`,
`/iclock/getrequest`, `/iclock/devicecmd` - answering plain text.

**The dialect is an assumption until a real device is in front of us.** It
is written against the common ZKTeco push protocol, which is what the boxes
schools buy tend to speak, and written liberally: tabs or commas, seconds
optional, unknown tables acknowledged and dropped, an unreadable line
skipped rather than failing the batch. Every punch keeps its raw line, so
if the real firmware differs the evidence for fixing it is already in the
database. **Confirm the make, the model, and whether the box can do HTTPS
before pointing a school at this.**

Two exceptions to house rules, both deliberate:

- **The URL is not ours.** The firmware appends its own path to whatever
  address somebody types into the box, so these sit outside `/api/v1/`.
- **The response is not the envelope.** Plain text, because that is what
  the firmware reads; a JSON error would be answered with a parse failure
  and a retry loop by a box nobody can see the screen of.

**A serial number is not a credential**, and the code says so where it is
used. It is printed on the box and sent in the clear. What limits the
damage, in order of how much work each does:

- **A punch can only ever write a time.** Never a status, never a day's
  presence, never anything payroll reads directly. Even a successful
  forgery moves somebody's check-in - which is why B5's "a human's status
  is never overruled" is a security property and not only a usability one.
- **An unknown serial is refused and audited.** A device somebody installed
  and forgot to register looks exactly like somebody guessing serials, and
  both are worth seeing.
- **A shared secret where the firmware can send one** (`push_key`, set on
  the device form). Write-only: never read back through the API and never
  in the audit trail, because the people who may *look* at this register
  are a wider set than the people who should be able to post into it. Null
  means none required, which is the only workable answer for older boxes.
- **A rate limit per serial**, not per address: a school's devices sit
  behind one address, and a per-address limit tight enough to matter would
  throttle the school rather than the problem.

A refusal never says which of "no such device" and "wrong key" it was.

**This product never sends a device a command.** `/iclock/getrequest`
always answers `OK` and nothing else. It does not enrol fingers, set the
clock or open a door, and every one of those would be a way for a
compromised server to reach into a school. The endpoint exists only because
the firmware treats a 404 as a fault.

**The device's clock drifts** and nobody notices until a month of punches
is an hour out. `last_seen_at` - updated on every contact, not just a
punch - and the raw line are what make that diagnosable.

### What B4 still risks

- **The URL is not ours to choose.** This firmware appends its own path
  (`/iclock/cdata`), so the endpoint has to live at the domain root rather
  than under `/api/v1/`. That is a routing exception and should be a
  deliberate one.
- **Older devices cannot do TLS.** A box that will only POST over plain HTTP
  cannot talk to an HTTPS-only host, and weakening the host for it is not on
  the table. The CSV fallback is the answer for those schools, which is why it
  is built first rather than last.
- **The device's clock drifts** and nobody notices until a month of punches is
  an hour out. `last_seen_at` and the raw line are what make that diagnosable.

## Out of scope, deliberately

- **Students.** See the first decision.
- **Deriving a status from hours.** See the third.
- **Pushing commands back to devices** (enrol a finger, set the clock
  remotely). The protocol allows it; nobody has asked for it, and it turns a
  read-only integration into one that can break a school's hardware.

---

# The schools page — built 2026-10-21

Two smaller requirements from the same conversation, written here because
neither warrants a document of its own.

## Search, filter, and what comes first

The schools list has no search and no filter today: it pages everything,
ordered by name. On a platform with 150 schools that is a list somebody
scrolls rather than a list somebody uses.

**Search** is server-side, like every other list in the product (CLAUDE.md
§12), across name, registration number, email and city — the four things
somebody actually knows about a school they are looking for. **Filter** is by
status.

**The order changes, and that is worth saying out loud.** Today it is name
A–Z; the requirement is active and latest first, so it becomes status (active
before inactive) then newest first. Anybody who knew where a school sat in the
list will find it somewhere else. Inactive schools are sorted below rather
than hidden — a list that silently omits them is how somebody concludes a
school was deleted.

One thing to keep honest: `GET schools/locations`, which draws the map, shares
the same scoping. If the list is filtered and the map is not, the two disagree
about what exists. The filters apply to both.

## A school of its own page

"View" on a school opens `/schools/:id` rather than a dialog: its details, its
branches, and a map centred on it.

The map is the read-only one, not the picker — this is a page for looking at a
school, and moving the pin belongs on the edit form where the change is saved.
A school nobody has placed shows the "not placed" state with a way to go and
place it, rather than an empty frame or a pin at (0, 0) off the coast of
Africa.

Who may open it is who may already see the school: the same `SchoolScope` the
list uses, checked server-side, so changing the id in the URL reaches nothing
new.
