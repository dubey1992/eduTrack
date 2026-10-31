# School onboarding

How a new school goes from an empty account to taking attendance, with as
few decisions as possible for the people setting it up. Asked for by the
user on 2026-10-31; their answers are recorded below.

## What was missing

- A new School Admin landed on an empty dashboard with nothing saying where
  to start, though the order matters (a year before classes, departments
  before subjects, classes before students).
- Classes were added one at a time, each with a level typed by hand from 0
  to 12, and there was room for only one pre-primary year, so Nursery, LKG
  and UKG could not be ordered.
- The Students page was one list sorted by first name. Roll numbers were
  free text: never given automatically, never checked for duplicates, and
  not used for ordering.
- Welcome emails: a School Admin created with a password got no email at
  all; one created without got a bare "Set your password" email that did
  not name their school or say what to do next; the school's own address
  got nothing.

## Decided (2026-10-31)

| Question | Answer |
|---|---|
| Class names in Quick setup | Nursery, LKG, UKG, Class 1 ... Class 12 (Playgroup offered too) |
| Wizard steps | Six: academic year, departments, classes & sections, subjects, staff, students; then optional extras |
| Finished or hidden wizard | Remembered for the whole school |
| Welcome emails | The School Admin always; the school's own address too when it differs |
| Students page | A class-and-section list in class order; pick one to see its students by roll number; "All students" for searching |
| Blank roll number | The next free number in the section (file order in a bulk upload) |
| Duplicate roll number in a section | Refused, naming the student who has it |
| Renumber a section | Yes: "Renumber A-Z", confirmed and audited |

## The slices

| | Slice | What it does |
|---|---|---|
| O1 | Classes in one step | Levels from names (`school/class_levels.py`); Quick setup creates the standard classes and their sections at once; pre-primary levels -3 to 0 |
| O2 | Students by class, roll numbers | Students page by class and section in class order; roll-number ordering; next free number; duplicates refused; Renumber A-Z |
| O3 | Welcome emails | A real welcome to the School Admin; a note to the school |
| O4 | Setup wizard | Six steps, done from real data; first-sign-in opening; dashboard progress card; remembered per school |

## Class levels

Playgroup -3, Nursery -2, LKG -1, UKG 0, Class 1 to Class 12 are 1 to 12.
Schools that already use 0 for their first year keep their order. Promotion
already moves a class "one level up", so it works across the pre-primary
years unchanged. A class's level is worked out from its name - "LKG", "KG2",
"Class 7", "Grade 7", "Std VII", "7th" - and asked for only when the name says
nothing.

## O1 - built 2026-10-31

- `school/class_levels.py` (and its mirror `frontend/lib/features/classes/data/class_levels.dart`):
  the standard classes, the default ticks (Nursery to Class 10), and `infer()`.
- Migration `2026_11_10_090000_allow_pre_primary_class_levels`: `school_classes.level`
  and the subject class range become signed, so -3 to 0 fit.
- `POST /api/v1/classes`: `level` is optional; left out, it comes from the name, and a
  name that says nothing is refused asking for the year. Levels run -3 to 12, for
  subjects too.
- `GET /api/v1/classes/quick-setup` lists the standard classes with which are ticked;
  `POST` takes `academic_year_id`, `classes` (standard names) and `sections` (1 to 6,
  named A, B ...). One transaction; a class the year already has is skipped and named
  in `skipped`, so running it twice adds nothing twice. Each class and section is
  audited. School Admins only (`SchoolClassPolicy.create`); the year must be the
  caller's school's.
- Flutter: a "Quick setup" button on Classes & Sections; the Add/Edit Class dialogs pick
  the year by name ("Year": Playgroup ... Class 12), filled in from the class name as it
  is typed; the subject dialogs pick "From class" / "To class" by name, and the subject
  list shows "Nursery - Class 10" instead of "-2-10".

## O2 - built 2026-10-31

Rules (`school/roll_numbers.py`):

- **Only active students hold a roll number.** A child who left keeps theirs on record,
  but the number is free for the next admission.
- **Blank means the next free number**: one past the highest plain number held in the
  section (a gap is never filled, so a register already written down does not reorder).
  This applies to the Add Student form, to clearing the number when editing, to moving a
  student to another section without giving a number, and to blank cells in a bulk
  upload (in file order, numbered past any number typed elsewhere in the file for that
  section). The section row is locked while the number is worked out.
- **Duplicates in a section are refused**, naming who has the number ("Roll number 5 is
  already Asha Verma's in this section"). "07" and "7" are the same number. Checked in the
  app, not by a database constraint, because older data may hold duplicates. A bulk upload
  also refuses the same number twice in one section of the file.
- **One section lists by roll number**: numbers by length then value (9 before 10),
  students without a number last, by name. "All students" stays in name order.

API:

- `GET /api/v1/students/classes` - the current year's classes in class order, each with
  its sections and their count of active students. A teacher gets only the sections they
  are class teacher of; another school's classes never appear.
- `POST /api/v1/sections/{id}/renumber` - numbers the section's active students 1, 2, 3 ...
  by first then last name. Needs the students write permission for that school; a teacher
  only for their own section. Each changed number is an audited student update.

Flutter: the Students page shows the class list beside the table when there are at
least 1500px for it, and a "Class" dropdown above the list otherwise (and on phones),
with "All students" first. A chosen section shows "Class 5 - A · in roll number order"
and, for those who manage students, "Renumber A-Z" behind a confirmation. The table has
a Roll column; the admission number moved under the name to keep the actions on screen.
The roll number field says "Blank: the next free number in the section".

Known limit: reactivating a student whose number was given to someone else meanwhile is
not refused; Renumber A-Z sorts it out.

## O3 - built 2026-10-31

`school/welcome_emails.py` writes the two emails; `school/jobs.py` sends them from the queue.

- **School Admin welcome** (`school_admin_welcome` job) - queued by `UserService.create` for
  every SCHOOL_ADMIN, from Add School or from Users. Subject "Welcome to School365ai -
  {school} is ready". It names the school, the sign-in email and page, the way in, the six
  first steps in wizard order, the help centre and the support address. With no password
  chosen, the button is "Set your password" (the usual one-hour reset link). With a password
  chosen, the button is "Sign in", and the password is never in the email. A Sub Admin is told
  they are one. Other roles keep the plain "Set your password" email when no password was
  chosen. Bus crew still get nothing.
- **School note** (`school_welcome` job) - queued by `SchoolService.create` for every new
  school, to the school's own email: "{school} is set up on School365ai", naming the School
  Admin (or saying one will be added). Not sent when the school's address is the admin's,
  since their welcome already reached it. It never carries the admin's link.
- The set-password link is issued in one place, `jobs.issue_reset_link`, for both the
  welcome and Forgot password. A welcome whose link is refused (one went out less than a
  minute ago) is not sent half-done.
