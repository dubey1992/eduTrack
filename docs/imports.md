# Bulk upload

A school opening on the system already has its lists: a roll of students, a
staff register, a subject catalogue, a fleet. Typing them in one dialog at a
time is the slowest part of onboarding, so five of them can be uploaded as a
spreadsheet instead.

## What can be uploaded

| Type (path segment) | What it creates | Who may |
|---|---|---|
| `students` | Students | Super Admin, School Admin |
| `staff` | Teacher/HOD/Staff/Transport Manager accounts with a staff profile | Super Admin, School Admin |
| `subjects` | Subjects | Super Admin, School Admin |
| `vehicles` | Vehicles | Super Admin, School Admin, Transport Manager |
| `drivers` | Drivers | Super Admin, School Admin, Transport Manager |
| `assessments` | Class tests, as drafts | School Admin (not the Super Admin, who sets no tests) |

Class tests are the one type a teacher may create by hand and not in bulk,
and the reason is worth stating: a file crosses classes, and "is this your
class" is a per-row question the shared reader has no actor to ask. So bulk
creation belongs to the people whose answer is always yes within their
school. A teacher's own marks are a different matter - those upload against
one test, where the timetable answers exactly (see docs/assessments.md).

Permission is not defined separately for importing: each type asks the same
policy that decides who may add one of these by hand (`create` on `Student`,
`StaffProfile`, `Subject`, `Vehicle`, `Driver`). Importing a hundred records
is the same permission as creating one, and keeping it that way means there
is no second set of rules to fall out of step.

## The endpoints

```
GET  /api/v1/imports/{type}/template   -> the empty CSV, with one example row
POST /api/v1/imports/{type}            -> multipart: file, and school_id for a Super Admin
```

A Super Admin belongs to no school, so they name one; everybody else imports
into their own and a `school_id` in the request is ignored, exactly as it is
on every other write.

## Look before it lands

```
POST /api/v1/imports/{type}/preview   -> what the file would import
```

The same reading and the same checks as the upload itself, and then the rows
come back instead of being written. The dialog uses it as a step: choose a
file, check it, import it.

It exists because all-or-nothing is not the same as safe. A file that passes
lands unseen, and there is no undo for a hundred records made from the wrong
spreadsheet or from the right one with its columns shifted by a place. The
answer carries the first fifty rows and the total, which is what somebody
needs to recognise a file by - nobody checks two thousand rows, and the
count is what says how many there are.

A marks file has its own preview on its own test, `POST
/assessments/{id}/marks/preview`, for the same reason its upload does: the
permission is the teacher's (docs/assessments.md).

## All or nothing

A file either imports completely or not at all. Every row is validated
first; if any row fails, nothing is written and the response lists every row
that needs fixing:

```json
{
  "code": "BULK_IMPORT_FAILED",
  "message": "Nothing was imported. Fix the rows below and upload the file again.",
  "details": {
    "rows": [
      { "row": 7, "messages": ["There is no section \"Z\" in class \"Grade 5\"."] },
      { "row": 12, "messages": ["The admission_number \"ADM-014\" is also on row 9."] }
    ],
    "row_count": 0
  }
}
```

The alternative - import what parses, report the rest - leaves the school
reconciling a half-finished import, and makes re-uploading the corrected file
duplicate everything that already landed. `row` is the line number in the
spreadsheet with the heading row as line 1, so it points at the row the
person can go and fix.

Every bad row is reported at once, rather than stopping at the first: a file
with ten mistakes should take one upload to find them all.

## What the columns hold

Names, not ids. Nobody filling in a spreadsheet knows that a section is
number 37 or that the Science department is number 4, so a student row names
its class and section, and a staff or subject row names its department.
Matching ignores case and stray spaces.

A student's class and section are resolved in the school's **current
academic year** - the year students are being enrolled into. Class names
repeat from one year to the next, so without that anchor "Grade 5 / A" would
be ambiguous. A school with no current year is told so plainly.

Dates are US format, like everywhere else in the app: `09/14/2026`, and
`9/4/2026` also reads, because Excel drops the leading zeros. A date in the
other order is refused rather than guessed at - reading `14/09/2026` as a US
date would file the record under a month that does not exist.

Limits: 2,000 rows and 2 MB per file. CSV only - `.xlsx` is a zip archive of
XML and reading one would mean a new dependency; every spreadsheet program
saves CSV.

## Imported staff accounts

Nobody types a password into a spreadsheet: it would sit in the school
office's downloads folder in plain text for as long as the file survives.

So each imported account gets a generated one, returned **once** in the
import response - to whoever ran the import, on their screen - and the
account is flagged `must_change_password`. The router holds such an account
on `/change-password` and nothing else opens until it picks its own. Using
the emailed password-reset link clears the flag too; choosing a password is
choosing a password, however the account got there.

Changing a password revokes every other token for that account while leaving
the one in the caller's hand working - so if a temporary password reached the
wrong person, that is where it stops mattering.

An import can never create an admin account, whoever runs it: the roles it
accepts are HOD, TEACHER, STAFF and TRANSPORT_MANAGER, the same four the
"add an employee" form allows.

## On the screen

Each of the five list screens carries a **Bulk Upload** button beside its
Add button. The dialog is the three steps of the job: download the template,
choose a file, upload - and then either the list of rows to fix, or a summary
with the generated passwords for staff.

Bulk upload is a web feature today. Reading a file off an Android device
needs a storage permission and a picker the app does not carry, so the
button hides itself there rather than opening nothing (`core/utils/file_picker.dart`,
the mirror of the download side in `file_saver.dart`).

## Adding another type

Implement `App\Services\Imports\RowImporter` - it says what the columns are,
how a row is validated, what cross-column checks apply, and how one row
becomes a record - then add it to `ImportRegistry` with the model whose
`create` policy should gate it. Everything else (reading the file, checking
the headings, validating everything before writing anything, reporting what
was wrong) is already shared.
