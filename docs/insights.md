# Weak areas, recommendations, and one entry instead of two

**Status (2026-10-01): slices 1, 2 and 3 built; 4 and 5 planned.** Decided with the user on 2026-10-01. This
continues [assessments.md](assessments.md) rather than replacing it: terms,
grade scales, marks, publishing, the two performance reports and the
progress report are all built and live. What follows is the part of
"performance enhancement" that was specified and never built, plus the one
place in the product where somebody still types the same thing twice.

Built on the Python backend and the Flutter app, like everything since
Phase 19. Laravel stays the frozen reference and its migrations still own
the schema, so slice 3's column is a Laravel migration.

```
FEATURE: Weak areas by topic, recommendations, and the report that ticks
         the syllabus
OBJECTIVE: Say which topics inside a weak subject are weak, suggest one
         thing to do about it, let a guardian be sent the term's picture,
         and stop a teacher entering the same topic twice.
DATABASE: daily_teaching_reports.syllabus_topic_id (slice 3) - nothing else
API:      /students/{id}/performance (topics, recommendations),
          /students/{id}/progress-report/send, /teaching-reports
FLUTTER:  Performance dialog (topics, recommendations, Send to guardian),
          Submit Report dialog (topic picker)
```

## What was already there

Worth stating, because three of the four asks turned out to be mostly
built and the fourth was hiding somewhere else entirely:

- **Class tests, assignments and quizzes** all exist - `AssessmentType`
  carries `class_test`, `unit_test`, `assignment`, `quiz` and `practical`.
  Marks, grades from the school's own scale, publishing, the frozen grade,
  the history, the bulk upload and both reports are live.
- **Attendance is already automatic end to end.** Submitting a register
  writes the rows, queues the guardian alerts the school has switched on,
  and every dashboard and report computes from those rows. There is no
  stored summary anywhere in the product, which is exactly why nothing has
  to be entered twice to keep one up to date. Approving leave writes the
  staff register for the same reason.

## The four gaps

**1. A topic nobody reads.** `assessments.syllabus_topic_id` has been
written since the assessments work and is read by nothing - not
`performance.py`, not `insights.py`, not either report, not the progress
report. assessments.md promises "where assessments name a
`syllabus_topic_id`, the topics inside them". It was never built.

**2. Findings, not recommendations.** Every insight states what the
numbers say and stops. "Mathematics is at 34%, below the school's 40%
mark" tells a teacher something they can check and nothing they can do.

**3. A guardian never sees the term.** They get an SMS per published
result. The progress report is a staff download. The queued
PDF-by-email path already exists and is proven twice - payment receipts
and payslips both do `message.attach(name, bytes, "application/pdf")`.

**4. The same topic, typed twice.** `daily_teaching_reports.topic_taught`
is free text with no link to `syllabus_topics`, and filing a report does
not touch `syllabus_topic_progress`. A teacher writes "Newton's laws" in
the daily report and then ticks Newton's laws complete on the Syllabus
screen. This is the duplicate entry the automation ask is really about.

## The decisions

Taken with the user on 2026-10-01.

**Recommendations suggest one next step, drawn from figures already on the
page.** Not a model, not pedagogy the product cannot stand behind: the
same rules shape as `insights.py`, where every sentence carries the
numbers it came from. A weak topic earns "revise it before the next test";
missed tests earn "arrange a re-sit". A teacher can see why it was said
and disagree with it.

**Filing a daily report marks its topic covered.** One entry instead of
two. The teacher picks the topic from the subject's syllabus rather than
typing it, and the Syllabus screen shows it complete, reversible there as
it always was. `topic_taught` stays - a report may name something that is
not a syllabus topic at all, and a year of existing reports have only the
text.

**A guardian is sent the report when staff choose.** A "Send to guardian"
action beside the download. Nothing goes out automatically at term end:
this is a document about a child, and somebody should have looked at it.
It respects the school's channel switches and is logged like every other
message - including the rule that a switched-off channel is not logged at
all.

## The slices

Each ends green, demoed in a browser, and committed.

### Slice 1 - The topic a test was about

Read `syllabus_topic_id`. Per-topic averages inside each subject, on the
performance payload, the dialog and the progress report. A test that names
no topic is simply not counted towards one - most are, and a subject whose
tests name none has no topic breakdown rather than an empty table.

Edge cases: a subject with one topic; a topic with one test; a test naming
a topic of another subject; a topic every student missed; a topic whose
title is long; the same topic across two terms.

### Slice 2 - What to do next

Recommendation rules beside the existing insight rules, in the same pure
module, each tied to a figure the page already shows. No recommendation
from fewer than two published results, for the reason the insights have
that floor already.

Edge cases: nothing weak; everything weak; a weak subject with no topic
data; a recommendation that would repeat an insight word for word.

**Built, with one rule the plan got wrong.** The first draft only looked
at chapters once the *subject* was weak, which hid the exact case slice 1
exists for: a subject at 70% with a chapter at 30%. A live demo caught it.
A weak chapter now counts on its own, as a finding (`weak_topic`) and as a
next step, and the subject is only sent for practice when it is weak as a
whole - naming the chapter is the better advice, and a page that said both
would be telling somebody the same thing twice.

### Slice 3 - One entry: the report ticks the syllabus

A Laravel migration adds `syllabus_topic_id` to `daily_teaching_reports`.
The Submit Report dialog offers the period's subject's topics; filing with
one marks it covered for that section. HOD coverage and the syllabus
report follow without anybody entering anything twice.

Edge cases: a report with no topic; a topic already complete; two reports
naming the same topic; a report edited to a different topic; a topic
belonging to another subject; a section that has already covered it.

### Slice 4 - The term's picture, to the guardian

A queued job emailing the progress report, the same shape as the receipt
and payslip jobs. Offered beside the download.

Edge cases: a student with no guardian email; the email channel switched
off; a term with nothing published; a send that fails; who may send whose.

### Slice 5 - The automation sweep

A pass over every write path looking for anything else entered twice, and
regression tests pinning the chains that must stay automatic:
attendance to alerts, leave to the staff register, publishing to the
guardian alert, and the daily report to the syllabus.
