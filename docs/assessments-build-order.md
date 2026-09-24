# Assessments and promotion: the build order

**Status (2026-09-24): slices 1 to 5 done, 6 to 14 planned.** This is the slicing of
[assessments.md](assessments.md) and [promotion.md](promotion.md) into
fourteen slices. Each slice is a vertical one: a migration where it needs
one, the backend, the Flutter screen, the tests, and a demo in a browser
before the next slice starts. No slice leaves the product in a state where
a screen exists that the API refuses, or a table exists that nothing reads.

Two rules shape the order. **A slice is only done when it is integrated**,
so the cross-module checks belong to the slice that creates the risk, not
to a tidy-up at the end. And **the edge cases are listed before the code**,
because the list is what the tests are written from. Where a case is
already settled by an existing rule, the rule is named rather than
re-decided.

## What every slice carries

This list is not repeated per slice. It is the floor.

| Check | What it means here |
|---|---|
| Isolation | `school_id` from the actor, never the client. A DENY test per new endpoint, and a cross-branch test where a group admin is involved. |
| Module switch | Off means hidden in the app and `403 MODULE_DISABLED` from the API, checked before the matrix. |
| Matrix | Every new endpoint answers to a module key and a level, with an ALLOW and a DENY test per role that matters. |
| Audit | Every write records, or is named in `NOT_RECORDED` with a reason. |
| Validation | Backend first. Field-level messages in the app, server errors shown on the same field. |
| Dates | School dates from `SchoolClock`, instants in UTC, per [timezones.md](timezones.md). |
| Lists | Paged, filtered and sorted server-side, order ending in `id`. |
| App states | Loading, empty, error with retry, success. Custom dialogs, never the browser's. |
| Gate | `flutter analyze`, `dart format -l 120`, the Python suite, the Laravel suite on both databases, `check_models`, then the demo. |

Slices that add tables also move the two model counters in
`test_skeleton.py`, add the Django model as `managed = False`, and put the
Laravel migration in its own commit before the feature commit.

---

## Foundation

### Slice 1 — Terms · done 2026-09-21

**Landed:** `academic_terms`, five endpoints under `/api/v1/academic-terms`,
and a Terms dialog opened from each row of Academic Years - readable by
every role, editable by an administrator. Deleting a year with terms under
it is now refused with a reason, the way a year with classes already was.

**Shown working:** an administrator added Term 1, was refused a Term 2 that
overlapped it, moved its start to the day after Term 1 ends and had it
accepted. Run in a visible browser as
`integration_test/admin_academic_terms_flow_test.dart`.

**Tests:** 51 backend tests, 48 Flutter tests, 7 contract tests, and 6
sabotages - dropping the school filter, letting any school's year be named,
letting a term sit outside its year, letting terms overlap, letting two
share a name, and letting a year with terms be deleted. All six were caught,
by 1 to 5 tests each.

Edge cases: a term whose dates fall outside its year; two terms that
overlap by one day; two terms that touch exactly at a boundary, which is
allowed; the same name twice in a year; the same name in different years,
which is allowed; a term in a year that is not current; `end_date` before
`start_date`; a one-day term; deleting a term; deleting a year that has
terms, which the existing dependent-records refusal must now cover; a
group admin creating terms for a branch; a teacher refused the write.

### Slice 2 — Grade scales · done 2026-09-21

**Landed:** `grade_scales` and `grade_bands`, five endpoints under
`/api/v1/grade-scales`, and a Grade Scales screen in the Academics group.
Bands are sent and replaced as a set, the way salary components are. Every
role reads a scale, because a teacher entering marks needs to know what an
81 will be called; only an administrator writes one.

**The rule worth remembering:** a percentage falls in **the highest band
whose minimum it reaches**. That lets a school write its bands the way it
says them - 91 to 100, then 81 to 90 - and still have a grade for 90.5,
which would otherwise fall down the crack between them. The set must start
at 0 and end at 100, and no two bands may overlap.

**Shown working:** an administrator built a scale with one band starting at
33, was refused because 0 to 32 would have had no grade, added the band
underneath and saved. Run in a visible browser as
`integration_test/admin_grade_scales_flow_test.dart`.

**Tests:** 41 backend tests, 21 Flutter tests, 7 contract tests, and 8
sabotages - all caught. Two findings the tests made rather than confirmed: a
duplicate name reached the unique index as a 500 until the form checked it,
and the list provider was auto-disposed, so a save from the dialog could
refresh a disposed notifier and show an internal error for a save that had
worked.

Edge cases: bands with a gap; bands that overlap; bands that do not reach
0 or 100; a single band covering everything; a band where min equals max;
percentages with two decimals at a boundary, 89.99 against 90.00; a
failing band that is not the lowest; two default scales for one school;
no default scale; deleting a scale, which is free until Slice 6 gives it
users; renaming a scale; another school's scale by id.

### Slice 3 — Enrollment history, read-only · done 2026-09-24

**Landed:** `student_enrollments`, the `backfill_enrollments` command,
`GET /students/{id}/enrollments`, and a Class history dialog on the students
list, open to every role that may see the student. Nothing decides anything
here; the row simply follows the student.

**Where it is written from:** admitting a student, moving one between
sections, and renumbering one all go through a single service, so the
history and `students.class_section_id` cannot disagree. Two shapes record
nothing, on purpose and without complaint: a student with no section, and a
school with no current year. The backfill picks both up once the fact
exists, and counts them as skipped so the number matches the sentence.

**Shown working:** an administrator admitted a student and opened their
history to find this year already recorded, with the class, the roll number
and "Studying". Run in a visible browser as
`integration_test/admin_student_history_flow_test.dart`.

**Tests:** 27 backend tests, 18 Flutter tests, 4 contract tests, 8
sabotages - all caught. Three findings the tests made: deleting an old
section would have stranded a year of somebody's history (the service now
clears the section and keeps the class), the backfill's skip count did not
match the sentence printed beside it, and the new History action widened the
students table enough to push the other actions out of view, so it became an
icon.

This slice moved earlier than the plan first said. It is read-only, so it
carries no risk, and it means promotion later is a smaller slice.

Edge cases: a student with no section; an inactive student; running the
backfill twice; running it on a school with no current year; a student
admitted after the backfill, who must still get a row; two branches of one
group; a student whose section is deleted afterwards; the unique
constraint on student and year; a student with no rows at all, which the
block must show as empty rather than blank.

---

## Assessments

### Slice 4 — The assessment record, draft only · done 2026-09-24

**Landed:** the `assessments` table, five endpoints under
`/api/v1/assessments`, the `assessments` module key with its matrix row and
its audit module, and a Class Tests screen with filters. No marks yet.

**The rule this slice decides:** a teacher reaches a section and subject
only when a timetable entry says they teach it. Being the section's class
teacher is *not* enough - the class teacher of 8A does not thereby teach 8A
mathematics, and a mark in a subject somebody does not teach is exactly the
loophole the rule exists to close. The plan's earlier sentence allowed the
class teacher; it was tightened here on purpose. An HOD reaches their own
department's subjects, an administrator their school, and the Super Admin
reads every school's tests and sets none of them.

**Its settings are not registered yet.** The module will have two - the pass
mark and the weak-subject threshold - and both are read by code that does
not exist (publishing, and the performance report). The registry's own rule
is that a setting nothing reads is a lie on a screen, so they arrive with
their readers.

**Shown working:** a teacher set a test for the class the timetable gives
them, was refused a date the term does not cover, and had the same test
accepted once the date moved inside it. Run in a visible browser as
`integration_test/teacher_sets_test_flow_test.dart`.

**Tests:** 58 backend tests, 19 Flutter tests, 6 contract tests, 14
sabotages - all caught. Three findings the tests made rather than confirmed:
a field-level failure short-circuited the cross-record checks, so a form
reported one problem at a time; a keyword argument named `required` shadowed
the message helper of the same name and turned it into a bool; and the
filter row overflowed its own header.

Edge cases: a teacher creating for a section they do not teach; a teacher
who is the class teacher but does not teach the subject; an HOD outside
their department; an HOD inside it; a subject whose level range excludes
the class; a date outside the term; a date inside the term but in a
different year; `max_marks` of zero, negative, or absurd; `pass_marks`
above `max_marks`; weightage over 100 for one subject and term; a
`syllabus_topic_id` belonging to a different subject; another school's
section, subject, term or grade scale by id; the module switched off;
deleting a draft; the list filtered by every filter at once and by none.

### Slice 5 — The marks sheet, draft · done 2026-09-24

**Landed:** `assessment_marks`, `GET` and `PUT /assessments/{id}/marks`, and
a Marks dialog opened from the Class Tests screen. The whole class is on
screen and the whole class saves in one write.

**Three rules the sheet keeps:** absent is not zero, so an absentee has no
mark at all; a blank is not zero either, so clearing a box removes the mark
rather than storing one; and a mark belonging to somebody who has since left
the class stays, because the sheet writes the students it was sent and never
deletes a row it was not asked about.

**Also landed:** the test's total is locked once anybody has been marked. A
percentage already entered is a share of the old total, so re-scaling would
silently change every one of them.

**Shown working:** a teacher set a test, opened its sheet, was refused a
mark of 99 out of 20 on that student's own row, corrected it, marked a third
child absent and saved the class in one write. Reopened, the sheet read back
what the server had. Run in a visible browser as
`integration_test/teacher_marks_sheet_flow_test.dart`.

**Bulk upload, added the same day at the user's request:** a file of tests
through the shared importer, and a file of marks against one test with the
roster already on the template. 31 more backend tests, 11 more Flutter
tests, 2 more contract tests and 12 more sabotages, all caught - two of them
only after the tests were tightened, because a class from another school and
a Super Admin's upload were each being refused by a second rule rather than
the one under test.

**Tests:** 44 backend tests, 19 Flutter tests, 5 contract tests, 12
sabotages - all caught, after one survivor was pinned with a direct service
test rather than deleted. Two findings: the row's refusal was clipped to
"The marks ..." inside a 110-pixel box, so it now reads in full underneath
the row; and on the web build a programmatic keystroke into a field that
does not hold focus is dropped, which is how a corrected mark silently kept
its old value in the browser flow.

Edge cases: a mark above the maximum, below zero, with three decimals,
blank, or not a number; absent with a mark attached; absent with a mark
left over from before; a student id that is not in the section; the same
student twice in one payload; an empty payload; a sheet saved while
another teacher saves it, which the row lock must serialise; a student
admitted between loading the sheet and saving it; a student who left
between them; a section of one, and a section of sixty; saving a sheet
with nothing filled in; every validation error reported at once rather
than the first.

### Slice 6 — Publish, freeze, reopen

**Lands:** publish, the grade written from the bands, the lock, reopen for
a School Admin or HOD, and the audit entries. No message yet. **Demo:**
publish, fail to edit, reopen, edit, republish.

Edge cases: publishing twice; publishing a sheet where a student has
neither a mark nor an absence, which is refused; publishing with no grade
scale, which leaves the grade empty rather than failing; a percentage
landing exactly on a band boundary; a percentage of zero and of 100; a
band table edited after publish, which must not change a frozen grade;
editing, deleting, or re-saving marks on a published assessment; reopening
a draft; reopening clearing the grades; a grade scale delete refused once
it is in use; who may reopen and who may not.

### Slice 7 — Telling the guardian

**Lands:** the `RESULT_PUBLISHED` event, its default template and tokens,
the queued fan-out, and the school's template override. **Demo:** publish
with messaging on and watch the messages appear, then switch
communication off and watch nothing be recorded.

Edge cases: communication switched off, which records nothing at all, not
even a skip; the event switched off in the school's communication
settings, same rule; a guardian with no mobile number, which is a skipped
message with a reason; a guardian email but no mobile; republishing after
a reopen, which sends nothing; a token the template does not supply, which
renders blank and never leaks braces; the date in the message being the
school's date; a class of sixty queued rather than sent inline; a
messaging failure that must not roll back the publish.

---

## Promotion

### Slice 8 — Preview

**Lands:** the preview endpoint and the first two steps of the wizard.
Read-only. **Demo:** preview a section into next year and edit outcomes on
screen without writing anything.

Edge cases: source and target the same year; a target year that does not
exist; a target section in another year or another school; an empty
section; a student who already has a row in the target year; inactive
students defaulting to left out; a graduated student not appearing at all;
a section whose class has no next class, which is the graduating case; the
retain suggestion when assessments are off, or on with no published
results; a group admin previewing a branch; an HOD and a teacher refused.

### Slice 9 — The run

**Lands:** `promotion_batches`, the transactional run, the four outcomes,
the `graduated` student status, the audit entry, and the batch history.
**Demo:** promote a section, retain one child, graduate another, then show
both years in the student's history.

Edge cases: running the same batch twice; two administrators running at
once; a student admitted between preview and run, which is
`ROSTER_CHANGED`; a student removed between them; a forced failure on the
last student, after which no batch row, no enrollment and no repointed
student may survive; a retained student landing in the same class of the
new year; a graduated student with the section pointer cleared; an
outcome for a student who is not in the section; an empty outcome list;
the audit entry naming the counts and the students.

### Slice 10 — Living with a new year

**Lands:** no new tables. The cross-module checks that a year change
breaks, and whatever fixes they turn up. **Demo:** in the new year, take
attendance, open the timetable, run a report for last year, and show last
year's marks still attached to last year's class.

This slice exists because this is where an integration bug would actually
appear, and finding it here is cheaper than finding it in a school.

Edge cases: attendance for a graduated student, refused; a transport
assignment for one, refused; promoting one twice, refused; last year's
attendance report still naming last year's class; last year's marks
unchanged; the students list filtered by the new status; the bulk import
of students into the new year; a teacher's timetable across the change;
announcements and messages aimed at a class that has moved on; the
dashboard counting the current year only.

---

## Performance

### Slice 11 — A student's numbers

**Lands:** the per-student performance endpoint and the Performance tab:
subject averages for the term, the class average beside them, the previous
term, and attendance for the same period. No insights yet. **Demo:** a
student with two terms of marks, next to one with none.

Edge cases: no published assessments; exactly one; drafts, which must be
excluded; every mark absent; a subject with one assessment and one
absentee; a student who changed section mid-term; a student promoted
between the two terms, which is where the enrollment history earns its
place; a term with no previous term; attendance over a range with no
working day, which is nothing rather than zero; a weightage that does not
add to 100; division by zero anywhere.

### Slice 12 — Insights

**Lands:** the rules module, its unit tests, and the insight list on the
tab. **Demo:** a slipping subject, an improving one, and a student too new
to say anything about.

Edge cases: fewer than two published assessments, which produces nothing;
a change of exactly ten points, the boundary; a subject exactly on the
weak threshold; attendance exactly at 75%; a student weak in every subject
and in none; absent for exactly a third of the tests; two rules firing on
one subject; the sentences carrying the numbers they were drawn from.

### Slice 13 — The two reports

**Lands:** the student-performance and class-performance report classes,
their CSV and PDF, the group roll-up, and the figures on the dashboard.
**Demo:** both reports on screen, downloaded as CSV and as PDF, and once
across a branch group.

Edge cases: a range holding a holiday; a range holding no working day; an
empty class; a class where nothing is published; a group where one branch
has no data; the CSV's formula-injection guard on a student name starting
with a symbol; the PDF's rows matching the CSV's exactly; the previous
period column against a period that did not exist; a report for a year
that is not current.

### Slice 14 — The progress report

**Lands:** the per-student progress report PDF. **Demo:** generate one for
a real student and print it.

Edge cases: a student with no marks; with one subject; with fifteen; a
very long name or school name; a school with no logo; a term with no
assessments; the grade shown being the frozen one; the school's timezone
on the footer date; the file name; who may download whose.

---

## What this ordering protects

- Nothing can publish a result before a grade scale exists, so there is no
  window where a grade has to be invented.
- Nothing can promote before enrollment history exists, so there is no
  window where a promotion loses a year.
- Performance is last, so it is written against real published data rather
  than against fixtures that flatter it.
- Slice 10 sits between the two halves on purpose. Every later slice
  depends on a year change being survivable, and that is proven before
  they are built rather than after.
