# Class Promotion

**Status (2026-09-29): built, apart from the year-change checks.** The
history table, the backfill, the Class history dialog, the preview, the
three-step wizard, `promotion_batches`, the transactional run, the four
outcomes, the `graduated` student status, the audit entry and the batch
history are all live. What remains is slice 10: a pass that proves a change
of year survives across attendance, the timetable, transport, imports and
the reports. Decided with
the user on
2026-09-21: an administrator promotes a class into the next academic year in
one pass, deciding per student whether they move up, repeat the year,
graduate out of the school, or are left behind as transferred. Built on the
Python backend and the Flutter app only. Laravel still owns the schema, so
the two tables below are Laravel migrations dated `2026_10_01`. Read
[assessments.md](assessments.md) first: promotion is what lets a performance
history outlive a year.

```
FEATURE: Class Promotion
OBJECTIVE: Move a section's students into the next year's class in one
           reviewed, reversible-by-record batch, keeping every past year's
           class, section and roll number as a permanent record.
DATABASE:  student_enrollments, promotion_batches
API:       /api/v1/promotions (preview, run, history),
           /api/v1/students/{id}/enrollments
FLUTTER:   A promotion wizard under Academics, an enrollment history block
           on the student
```

## The problem, stated plainly

A student's class lives in exactly one column: `students.class_section_id`.
It is single-valued, and there is no enrollment table, no history table and
no year on the student. Promotion as the product stands today would mean
repointing that column at a section of the next year, and the moment it is
repointed **the fact that the child was ever in Grade 7 A is gone**. Last
year's attendance rows survive, because each snapshots its own
`class_section_id`, but nothing else does, and no report could ever say
"Grade 7, last year" again.

So promotion is not a screen over the existing schema. It needs a record of
who was in which class in which year, and everything else follows from that.

## Enrollment history

`student_enrollments` is one row per student per academic year.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | |
| `school_id` | FK schools | cascade, indexed |
| `student_id` | FK students | cascade, indexed |
| `academic_year_id` | FK academic_years | indexed |
| `school_class_id` | FK school_classes | the class, kept even if the section goes |
| `class_section_id` | FK class_sections null | nullable, as on the student |
| `roll_number` | varchar(20) null | as it was that year |
| `status` | varchar(16) | studying, promoted, retained, graduated, left |
| `created_at`, `updated_at` | timestamp | |

Unique on `(student_id, academic_year_id)`: a child is in one class per
year, and the constraint is what stops a double promotion rather than a
check in the service.

The two columns that say which batch moved a student - the batch and the row
it was promoted from - arrive with `promotion_batches` itself. Slice 3 wrote
no outcome, so it added no column that nothing reads.

**What writes a row today.** Admitting a student, moving one between
sections, and renumbering one, all through `StudentEnrollmentService`. Two
shapes record nothing rather than failing: a student with no section, and a
school with no current year. A section belonging to a year that is not the
current one is not where a student is *now*, so it records nothing either -
that shape is what a promotion will produce, and it belongs to the new year.

**A row is never blanked.** A student who loses their section keeps the row
saying which class they were in, and deleting a section clears the section
from past rows while leaving the class, which is the part worth keeping.

`promotion_batches` records the run itself.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | |
| `school_id` | FK schools | cascade, indexed |
| `from_academic_year_id`, `to_academic_year_id` | FK academic_years | |
| `from_class_section_id` | FK class_sections | the section promoted |
| `to_class_section_id` | FK class_sections null | null when every student graduated |
| `promoted_count`, `retained_count`, `graduated_count`, `left_count` | int | |
| `run_by` | FK users | |
| `run_at` | timestamp | |

**`students.class_section_id` stays exactly where it is**, as the pointer to
the current year. Every query in the product reads it: attendance, reports,
announcements, imports, transport, the policies. Moving all of that onto a
join would be a rewrite of working code for no gain, and the rule in
CLAUDE.md is not to. The enrollment row is the history; the column is the
present tense. One service writes both, in one transaction, and they cannot
disagree because nothing else is allowed to write either.

**The existing students need their first row.** A one-time management
command, `backfill_enrollments`, writes a `studying` enrollment in the
current academic year for every active student who has a section. It is
idempotent, reports what it did, and runs before the first promotion. This
is a Python command rather than a migration, because it is data, and
migrations here create tables.

## The four outcomes

| Outcome | What happens | Student status |
|---|---|---|
| Promoted | old row becomes `promoted`, a new `studying` row in the target class, `students.class_section_id` repointed | unchanged |
| Retained | old row becomes `retained`, a new `studying` row in the **same class** of the new year | unchanged |
| Graduated | old row becomes `graduated`, no new row, the section pointer is cleared | `graduated` |
| Left out | old row becomes `left`, no new row, nothing is repointed | unchanged |

`graduated` is a new value on the student status enum, which today holds
only `active` and `inactive`. It is contract the Flutter app compares
against, so it is added deliberately, and the students list gains it as a
filter. A graduated student keeps every record and can no longer be marked
present, assigned to a bus, or promoted again.

"Left out" is for the child who has already transferred away. They are
`inactive` today, they are skipped by default, and the year closes for them
honestly rather than pretending they finished it.

## How a promotion runs

**Preview first, always.** `GET /promotions/preview` takes the source
section (`class_section_id`), the target year (`to_academic_year_id`) and
optionally the target section (`to_class_section_id`), and answers with the
roster, each student's default outcome, and anything that would refuse. The
screen shows it as a list the administrator edits per student. Nothing has
been written.

Leaving the target section out is the ordinary case: the backend suggests the
class one level up in the target year and, inside it, the section of the same
name where there is one, and says `is_suggested` so the screen can mark it.
A source class with nothing above it is not an error - it is the graduating
case, and every student defaults to graduated.

A student who already has a row in the target year comes back `is_blocked`
with the reason rather than being dropped from the list: a roster that
quietly omits a child is how a child gets left behind. A section with nobody
in it answers 200 with `can_run: false` and `cannot_run_reason:
NOTHING_TO_PROMOTE`, because an empty list is something to show, not an
error to raise.

Where the assessments module is on and the source year has published
results, each row also carries the final term's average and the year's
attendance, and `suggested_outcome: "retain"` where the average is under the
school's pass percentage. The default is untouched by it.

The default outcome is **promote**, for everyone active. Where the
assessments module is on and the year has published results, the preview
also carries each student's final-term average and attendance, and marks a
suggestion to retain where the average is below the pass mark. It is a
suggestion on a screen. It never changes the default, and nothing is ever
promoted or retained automatically. A decision that affects a child's year
belongs to a person.

**The run is one transaction.** `POST /promotions` takes the batch: source,
target, and an explicit outcome per student. All of it commits or none of it
does. The batch row, every enrollment row and every repointed student go
together.

The roster is locked for the length of the run (`select_for_update`), so two
administrators cannot promote the same children twice, and the refusals are
checked most-specific first: a student already in the target year is
`ALREADY_ENROLLED` before the emptied section can report
`NOTHING_TO_PROMOTE`. Running the same batch twice therefore says what
actually happened rather than "there is nobody here".

A student the batch does not name is left alone rather than defaulted:
leaving somebody out of a run is a decision too. A student whose year was
never recorded - admitted before the history table existed, missed by the
backfill - has it written as part of the run, so a promotion never leaves a
hole where a year should be.

Each row the run touches carries `promotion_batch_id`, and each new row also
carries `promoted_from_enrollment_id`. Together they answer "what did this
run do" and "where did this child come from" without either needing a guess,
which is what `GET /promotions/{id}` reads.

It is refused, each with its own error code, when:

| Refusal | Why |
|---|---|
| `SAME_ACADEMIC_YEAR` | source and target year are the same (422, and the preview refuses it too) |
| `TARGET_YEAR_NOT_FOUND` | the target year does not exist for this school (404 - another school's year is not a year this one may be told about) |
| `TARGET_SECTION_MISMATCH` | the target section is not in the target year, or another school (422, and the refusal that stops children being moved into somebody else's class by changing an id) |
| `ALREADY_ENROLLED` | a student already has a row in the target year |
| `ROSTER_CHANGED` | a student in the request is no longer in the source section |
| `NOTHING_TO_PROMOTE` | the source section is empty, or the batch names nobody |
| `RETAIN_CLASS_MISSING` | the class a retained child would repeat does not exist in the target year, or the class being promoted has nothing above it. Added with the run: a child held back needs somewhere to be held back *in*, and refusing by name beats a foreign key error or a quiet promotion |

`ROSTER_CHANGED` is the one that matters in practice. Two administrators on
two screens, one admits a child while the other is reviewing, and the run
must refuse rather than quietly promote a stale list.

**Idempotence.** Running the same batch twice fails on the unique
constraint, not on a check that could race. The second run reports
`ALREADY_ENROLLED` naming the students.

**No undo, on purpose, for now.** The batch row makes an undo possible
later, and the audit entry makes the change legible today. An undo that has
to reason about marks entered and attendance taken in the new year after the
promotion is a feature of its own, and a half-correct one would be worse
than none. Correcting a wrong promotion today means moving those students by
hand, which is the existing, audited edit path.

## Who may do it

Promotion sits under the existing `academics` module, so no sixteenth row is
added to the permissions matrix. Within it, only a School Admin or a Group
Admin for that school may preview or run a batch. An HOD, a teacher and
everyone else are refused, even though `academics` grants them view, because
the policy narrows it, the way payroll refuses the Super Admin a write. The
Super Admin reads any school's promotion history and runs none of it.

Every branch is its own school row, so a group admin promotes each branch
separately, and `SchoolScope` keeps the target year and section inside the
same school as the source.

## The API

| Endpoint | What it does |
|---|---|
| `GET /promotions/preview` | the roster, defaults, suggestions, refusals |
| `POST /promotions` | run one batch |
| `GET /promotions` | past batches, paged and filtered by year |
| `GET /promotions/{id}` | one batch with its student outcomes |
| `GET /students/{id}/enrollments` | that child's year-by-year history |

## Flutter

One wizard, held as state inside the Academics area rather than as its own
route, the way the payroll screen opens a run in place. Three steps: choose
the source section and the target year and class; review the list and set
outcomes, with a search box and bulk actions for "promote all" and "retain
none"; confirm a summary that spells out the counts before anything is
written. The confirm step is the app's own dialog, never the browser's.

On the student, an Enrollment history block: a row per year with class,
section, roll number and outcome. It appears for every role that may view
the student, because a teacher asking "what did this child do last year"
should not need an administrator.

## Audit

The module key is the existing `academic`. One entry per run,
`promotion.completed`, carrying the source and target, the counts and the
student ids by outcome. One entry per student would put forty rows in the
log for one intended action and bury everything else; the enrollment rows
themselves carry who ran the batch and when, so nothing is lost. A
`graduated` status change is part of the same entry.

## Testing

- The unique constraint: promote the same student twice, promote into a year
  they already have a row in.
- Each of the four outcomes, and a batch mixing all four.
- `ROSTER_CHANGED`: preview, admit a student, then run.
- Transaction integrity: force a failure on the last student of the batch
  and assert that no enrollment row, no batch row and no repointed student
  survives.
- School isolation: a target section in another school, a source section in
  another school, a group admin reaching a sister branch, an outsider
  refused with a 403.
- Role denial: an HOD, a teacher and an accountant each refused a preview
  and a run.
- The backfill command: run it twice, and on a school with a student who has
  no section.
- A graduated student: refused attendance, refused a transport assignment,
  refused a second promotion, and still readable in every past report.
- A sabotage pass: drop the unique constraint's guard, let the target
  section come from the client, skip the old row's status update. Each must
  turn tests red.
- Contract tests, plus the endpoints in `PYTHON_ONLY_ENDPOINTS`.
- A Flutter integration flow: an administrator promotes a section end to
  end, and the student's history shows both years.

## Order of work

Slices 8 and 9 - the preview, the wizard and the run - are built.
Promotion is slices 8 to 10 of
[assessments-build-order.md](assessments-build-order.md): the preview, the
run, and then a slice that does nothing but prove a change of year is
survivable across attendance, the timetable, transport, imports and the
reports. Enrollment history is slice 3, and lands before any of the
assessment work rather than beside promotion, because it is read-only and
makes the promotion slice smaller.
