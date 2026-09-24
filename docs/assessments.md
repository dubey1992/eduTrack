# Class Tests & Assessments

**Status (2026-09-24): slices 1 to 4 built, the rest planned.** Terms, grade
scales, enrollment history and the class test itself are live, each with a
flow that runs in a browser. The marks sheet, publishing, the guardian
message, promotion and performance are still a plan. Decided with the user on
2026-09-21: the school year is divided into terms, marks are entered against
a maximum and turned into a grade by a scale the school configures, and
results reach guardians as a message and as a printable progress report.
Built on the Python backend and the Flutter app only, like everything since
Phase 19. Laravel stays the frozen reference, but its migrations still own
the schema, so the five tables below are Laravel migrations dated
`2026_10_01`. Promotion and the enrollment history it needs are a separate
document, [promotion.md](promotion.md); the two are built in that order
because a term belongs to an academic year and a result belongs to a term.

This is not an examination system. There is no exam scheduling, no hall
ticket, no seating plan, no board-exam register and no report card that
decides whether a child passes the year. It records the tests a teacher
actually sets, the marks they carry, and what those marks say about a child
over time.

```
FEATURE: Class Tests & Assessments, and student performance
OBJECTIVE: A teacher sets a test for one section and subject, enters marks
           for the class, and publishes the result. Marks become a grade
           through the school's scale, guardians are told, and the history
           feeds per-student and per-class performance reports.
DATABASE:  academic_terms, grade_scales, grade_bands, assessments,
           assessment_marks
API:       /api/v1/academic-terms, /api/v1/grade-scales,
           /api/v1/assessments (+ marks, publish, reopen),
           /api/v1/students/{id}/performance,
           /api/v1/reports/student-performance, /reports/class-performance
FLUTTER:   Terms and Grade scale under Academics, an Assessments screen with
           a marks sheet, a Performance tab on the student, two report kinds
```

## Why these tables and not fewer

Nothing in the product records a mark today. Attendance is the only
per-student fact, `syllabus_topics` is a flat list per subject, and
`daily_teaching_reports.topic_taught` is free text. So this is a green field,
and the shape below is chosen to match what already exists rather than to be
general.

**A term, because a result needs a period.** `academic_years` carries only
`is_current`; there is no term, semester or quarter anywhere in the product.
Without one, "Term 1 average" cannot be asked and a trend compares two
arbitrary date windows. A term is a named, dated slice of one academic year.

**A grade scale per school, because grades differ by school.** A school sets
its bands once (A1 is 91 to 100, and so on). A grade is never typed by a
teacher; it is derived from the percentage.

Built in slice 2 with one rule that needed deciding: **a percentage falls in
the highest band whose minimum it reaches.** A school writes 91 to 100 and
81 to 90, the way it says them out loud, and 90.5 is then an A2 rather than
nothing at all. The set still has to start at 0 and end at 100, and no two
bands may overlap, so every mark has exactly one grade.

**A grade frozen on the mark.** The band table can be edited later. A
published result must not change silently because somebody moved a boundary,
so the grade string is written onto the mark row at publish, the way a
finalized payslip stops being re-derived.

**No aggregate tables.** Every existing report computes from raw rows, and
there is no summary table in the product. Performance follows that rule:
averages are computed per request from `assessment_marks`.

## The tables

`academic_terms`

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | |
| `school_id` | FK schools | cascade, indexed |
| `academic_year_id` | FK academic_years | cascade, indexed |
| `name` | varchar(50) | "Term 1", "Final" |
| `sequence_number` | tinyint unsigned | order within the year |
| `start_date`, `end_date` | date | inside the year, no overlap with siblings |

Unique on `(academic_year_id, name)` and `(academic_year_id,
sequence_number)`.

`grade_scales`

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | |
| `school_id` | FK schools | cascade, indexed |
| `name` | varchar(50) | "Secondary", "Primary" |
| `is_default` | boolean | one per school, kept by the service |

Unique on `(school_id, name)`.

`grade_bands`

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | |
| `grade_scale_id` | FK grade_scales | cascade, indexed |
| `label` | varchar(10) | "A1", "Pass" |
| `min_percentage`, `max_percentage` | decimal(5,2) | 0 to 100, contiguous |
| `is_failing` | boolean | a band that counts as not passed |

`assessments`

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | |
| `school_id` | FK schools | snapshot, indexed |
| `academic_year_id` | FK academic_years | snapshot, indexed |
| `academic_term_id` | FK academic_terms | indexed |
| `class_section_id` | FK class_sections | indexed |
| `subject_id` | FK subjects | indexed |
| `syllabus_topic_id` | FK syllabus_topics null | what it tested |
| `type` | varchar(20) | class_test, assignment, quiz, practical, unit_test |
| `title` | varchar(150) | "Fractions - unit test" |
| `max_marks` | decimal(6,2) | greater than zero |
| `pass_marks` | decimal(6,2) null | falls back to the module's pass percentage |
| `weightage` | decimal(5,2) null | share of the term for that subject |
| `assessment_date` | date | inside the term, a school date |
| `grade_scale_id` | FK grade_scales null | null means no grade is shown |
| `status` | varchar(16) | draft, published |
| `created_by`, `published_by` | FK users | |
| `published_at` | timestamp null | |

Indexed on `status` and `assessment_date`. `school_id` and
`academic_year_id` are snapshotted the way `attendances` does it, and neither
is ever taken from the client.

`assessment_marks`

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | |
| `school_id` | FK schools | snapshot, indexed |
| `assessment_id` | FK assessments | cascade |
| `student_id` | FK students | indexed |
| `marks_obtained` | decimal(6,2) null | null when absent |
| `is_absent` | boolean | |
| `grade` | varchar(10) null | frozen at publish |
| `remarks` | varchar(255) null | |
| `entered_by` | FK users | |

Unique on `(assessment_id, student_id)`. That constraint is named
explicitly, the way `syllabus_progress_topic_section_unique` is, so it stays
inside MySQL's 64-character limit.

Five tables here, two more in promotion. The schema goes from 54 tables to
61, and the model count asserted in `test_skeleton.py` from 48 to 55. Both
counters move in the same commit as the models that justify them.

## Who may do what

A new module key, `assessments`, joins the fifteen in `modules.py` and the
matrix in `permissions.py`. Its default row, in the matrix's column order:

| School Admin | HOD | Teacher | Staff | Transport | Accountant | Bus Attendant |
|---|---|---|---|---|---|---|
| manage | manage | manage | none | none | none | none |

The matrix says a teacher may manage assessments at all. It does not say
*which* ones. That is the policy's job: a teacher reaches a section and
subject only when a `timetable_entries` row says they teach it.

**Being the class teacher is not enough**, and that is a deliberate
tightening of how this was first written. The class teacher of 8A does not
thereby teach 8A mathematics, and a mark in a subject somebody does not
teach is the loophole the rule exists to close. An HOD reaches the subjects of their own department. A School
Admin reaches their school. The Super Admin reads any school and changes
none of it, exactly as in payroll.

Terms and grade scales are school configuration rather than teaching, so
they sit under the existing `academics` module and only an administrator may
write them.

Two module settings, both read by a service, because a setting nothing reads
would be a lie on a screen. Neither is registered yet: they arrive with the
code that reads them, publishing and the performance report.

| Setting | Default | What reads it |
|---|---|---|
| `pass_percentage` | 33 | pass or fail when an assessment sets no `pass_marks` |
| `weak_below_percentage` | 40 | the subject average the performance report flags |

## The rules

**A draft is private, a published result is not.** Marks may be entered,
corrected and left half-finished while the assessment is a draft. Nothing is
sent, and no performance figure counts a draft.

**Publishing freezes the grade and tells the guardian.** On publish, each
mark's grade is written from the scale's bands, the assessment is locked,
and a `RESULT_PUBLISHED` message goes to each guardian through the existing
messaging module with the tokens `{student_name}`, `{guardian_name}`,
`{school_name}`, `{subject_name}`, `{assessment_title}`, `{marks_obtained}`,
`{max_marks}`, `{percentage}`, `{grade}` and `{date}`. The rule that a
switched-off alert is not recorded at all still holds, and a school with
communication switched off sends and logs nothing.

**A published result can be corrected, but visibly.** A School Admin or the
HOD may reopen an assessment. It returns to draft, the frozen grades are
cleared, and the reopen is audited with who and when. Republishing does
**not** message guardians a second time, because a correction to one child's
mark must not text the whole class again.

**Absent is not zero.** An absent student has no marks and is left out of
every average and every pass rate. A class of thirty with two absentees is
averaged over twenty-eight. This matches the reports rule that a rate with
no denominator is nothing rather than zero.

**Marks are bounded.** Between zero and `max_marks`, to two decimals. Once
any mark exists, `max_marks` may not be changed, because every stored
percentage would change with it. Delete the assessment, or reopen it and
re-enter.

**Dates belong to the school.** `assessment_date` is a school date from
`SchoolClock`, and it must fall inside its term. Publishing stamps an
instant in UTC. That is the rule in [timezones.md](timezones.md), not a new
one.

**Nothing may orphan a result.** A term cannot be re-dated so that its
assessments fall outside it; a subject or section with assessments cannot be
deleted; a grade scale in use cannot be deleted. Each refusal has its own
error code rather than a generic conflict.

## The API

| Endpoint | What it does |
|---|---|
| `GET/POST /academic-terms` | list for a year, create |
| `GET/PATCH/DELETE /academic-terms/{id}` | one term |
| `GET/POST /grade-scales` | list, create with its bands inline |
| `GET/PATCH/DELETE /grade-scales/{id}` | one scale, bands replaced as a set |
| `GET/POST /assessments` | list by term, section, subject, type, status; create |
| `GET/PATCH/DELETE /assessments/{id}` | one assessment, deletable while draft |
| `GET /assessments/{id}/marks` | the roster with whatever marks exist |
| `PUT /assessments/{id}/marks` | save the whole sheet in one write |
| `POST /assessments/{id}/publish` | freeze grades, lock, notify |
| `POST /assessments/{id}/reopen` | back to draft, audited |
| `GET /students/{id}/performance` | subject averages, trend, insights |
| `GET /students/{id}/progress-report` | the same thing as a PDF |
| `GET /reports/student-performance` | a class's students, with CSV and PDF |
| `GET /reports/class-performance` | subjects across a class, with CSV and PDF |

Lists page through `LaravelPagination` with the usual envelope, filter
server-side, and carry a fixed order ending in `id` so a page boundary
cannot repeat a row. The marks sheet is saved in one `PUT` rather than a
request per child, because a class of forty entered on a phone in a
staffroom cannot afford forty round trips, and because a half-saved sheet is
worse than an unsaved one.

New error codes: `ASSESSMENT_PUBLISHED` (409, editing a published sheet),
`ASSESSMENT_NOT_PUBLISHED` (409, reopening a draft), `MARKS_OUT_OF_RANGE`
(422), `MAX_MARKS_LOCKED` (422), `GRADE_SCALE_IN_USE` (409) and
`NOT_YOUR_CLASS` (403, a teacher reaching a section they do not teach).

A term outside its year, a term overlapping a sibling, and a gap in a grade
scale's bands are **validation errors, not codes of their own**. They are
properties of the form somebody just filled in, so they arrive as a 422
naming the field, and the app marks up the field rather than showing a
banner. Built that way in slice 1 and kept for the rest.

## Performance, and what counts as an insight

Performance is computed, never stored. Two report classes join the seven in
`school/reports/`, using the existing `ReportRange`, the group roll-up and
the PDF machinery, so a branch group gets the same combined view it gets
today.

A student's page answers four questions:

1. **Where do they stand?** Average percentage per subject this term, with
   the grade, against the class average for the same assessments.
2. **Are they improving?** The same figures for the previous term, and the
   difference between them.
3. **What is weak?** Subjects below `weak_below_percentage`, and, where
   assessments name a `syllabus_topic_id`, the topics inside them.
4. **Is anything else going on?** Attendance for the same period, out of the
   school's working days, from the existing holiday-aware denominator.

The recommendations are rules, not a model, and they live in one small pure
module with its own unit tests. Each produces a code, a sentence and the
numbers it was drawn from, so a teacher can see why it was said:

| Code | When | Sentence |
|---|---|---|
| `weak_subject` | subject average below the threshold | "Mathematics is at 34%, below the school's 40% mark." |
| `slipping` | down 10 points or more on the previous term | "Science has fallen 14 points since Term 1." |
| `improving` | up 10 points or more | "English is up 12 points since Term 1." |
| `missed_tests` | absent for a third or more of the term's tests | "Absent for 3 of 8 tests this term." |
| `attendance_may_explain` | a weak subject and attendance under 75% | "Attendance is 68% this term." |

No insight is produced from fewer than two published assessments. One test
is not a trend, and a confident sentence drawn from a single mark is worse
than silence.

## Audit

The module key `assessments` joins `audit.MODULES`. Recorded:
`assessment.created`, `assessment.updated`, `assessment.deleted`,
`marks.saved` (the sheet, with what changed), `assessment.published`,
`assessment.reopened`, `grade_scale.saved` and `grade_scale.deleted`.
Reading a report changes nothing and is not recorded.

Terms are school configuration and record under the existing `academic`
module, with the names the audit writer derives from the model:
`academic_term.created`, `academic_term.updated` and
`academic_term.deleted`.

## Testing

The usual shape, with the places a bug would actually hide named on purpose:

- ALLOW and DENY for every rule, the DENY half first: a teacher of 8A
  refused 9A's marks sheet, an HOD another department's subject, a school
  another school's assessment, an accountant the module entirely.
- Boundaries: a mark of exactly `max_marks`, of zero, one over, a negative
  and a non-number. A grade band at exactly 90 and at 90.01.
- Absent: an average with one absentee, with every student absent, and a
  class where nobody has a mark yet.
- Terms: an assessment on the term's first day and last day, one a day
  outside, and an edit that would strand it.
- Publishing: publishing twice, editing after publish, reopening and
  republishing, and that republishing sends no second message.
- Communication off, and a guardian with no mobile number: the first records
  nothing at all, the second records a skipped message with a reason.
- Trend arithmetic where there is no previous term.
- A sabotage pass: drop the timetable check, drop the scope filter, count
  absentees as zero, stop freezing the grade. Each must turn tests red, and
  the counts are written back into this document.
- Contract tests beside `contract/test_academic.py`, with every endpoint
  added to `PYTHON_ONLY_ENDPOINTS`.
- Flutter: notifier tests, dialog tests for every validation message, widget
  tests for the marks sheet itself, and one integration flow of a teacher
  signing in, opening a test, entering marks and publishing.

## Order of work

The work is sliced into fourteen shippable pieces in
[assessments-build-order.md](assessments-build-order.md), which is the
single home for the sequence and for the edge cases each slice is tested
against. In outline, slices 1 to 3 are the foundation of terms, grade
scales and enrollment history; 4 to 7 are the assessment, the marks sheet,
publishing and the guardian message; 8 to 10 are promotion and the checks
that a change of year survives; 11 to 14 are performance, insights, the two
reports and the progress report.

Each slice is committed and shown working in a browser before the next
begins, and each one that adds a table starts with its Laravel migration in
its own commit.
