# Examinations and admit cards

**Built 2026-11-17**, from `school365ai_exam_admit_card_claude_prompt.md` and
`school365ai_exam_admit_card_prototype.html`. Until then the product had
class tests but no examination: nothing named "Half-Yearly 2026", with a
date sheet, to print an admit card from.

## Decisions (user, 2026-11-17)

| Question | Decision |
|---|---|
| Where does the date sheet come from? | A new **Examinations** screen. Each exam has its date sheet: one paper per subject per class, with a date and a start and end time. Class tests and marks stay as they were. |
| Who gets the card? | **School staff** print and download now. **Parents** download in the Family app, which arrives when that app goes live. **Students** wait for student sign-in (Family app F6). |
| Release | **Draft until published**, plus a **withhold** by name with a reason. Staff read the reason; a parent reads "contact the school". Optionally, per exam, a card is **held while fees are overdue**, and the school can **let a named student through**. |
| Changes after publishing | **Versioned republish.** Each publish freezes the exam and its date sheet as version N. A card always prints from a frozen version, and staff can reprint any earlier one. |

There is no student photo field, so the card shows a placeholder box. Seats,
rooms, QR codes and signature images are left out: the product has no
seating plan, no verification service and no signature store, and printing
them would be invention.

## Data (`2026_11_21_090000_create_examinations_tables`)

- **`examinations`**: school, year, optional term, name (unique per year), centre, reporting time, instructions (one per line), `card_style` (classic or mono), `block_on_fee_dues`, status (draft or published), `version`, `published_at`, `published_by`.
- **`examination_papers`**: exam, class (of the exam's year), subject (of the school), date, start and end time. Wall-clock time in the school's own timezone, never instants. There is one paper per subject per class.
- **`examination_versions`**: exam, version, the snapshot as JSON, who published it and when.
- **`examination_exceptions`**: exam, student, kind (withhold or allow), reason.

## Rules (`school/examinations/service.py`)

A card's state is worked out on the server for every reader, in this order:

1. **not_published**: the exam has never been published.
2. **no_papers**: the student's class that year (from the enrollment) sits no paper.
3. **withheld**: withheld by name.
4. **fee_hold**: the exam holds cards for fees, the student owes something past its due date, and no "allow" exception lets them through.
5. Otherwise **ready**.

The date sheet must meet these rules:

- the date falls inside the academic year;
- the paper ends after it starts;
- one paper per subject per class;
- a class never sits two papers at overlapping times (back to back is fine).

Errors are keyed `papers.N.field`.

**Publishing:**

- An empty sheet is refused, and so is a publish when nothing has changed since the last version.
- Each publish is locked against a second one running at the same time, and audited.
- A published exam cannot be deleted, because its cards are on record.

## API

| Method | Path | Who |
|---|---|---|
| GET/POST | `/examinations` | read: anyone with Class Tests view; create: School or Group Admin |
| GET/PATCH/DELETE | `/examinations/{id}` | read: same; change: admins (delete: drafts only) |
| PUT | `/examinations/{id}/papers` | admins |
| POST | `/examinations/{id}/publish` | admins |
| GET | `/examinations/{id}/candidates` | readers. Filters `school_class_id`, `class_section_id`, `q`, `state`. Includes `counts`. |
| PUT | `/examinations/{id}/exceptions` | admins. Body: `student_id`, `kind` (withhold, allow or none), `reason`. |
| GET | `/examinations/{id}/students/{sid}/card.pdf` | readers. `?version=n` reprints an earlier version; `?draft=1` previews (admins only). |
| GET | `/examinations/{id}/cards.pdf` | readers. One section or class, ready cards only, at most 80. Headers `X-Cards-Printed` and `X-Cards-Skipped`. |
| GET | `/family/children/{id}/admit-cards` | the child's parent |
| GET | `/family/children/{id}/admit-cards/{exam}/pdf` | the child's parent; ready cards only |

**Access:**

- A Super Admin reads and changes nothing.
- An exam, student or year from another school returns 404, or 422 for a form field.
- A family account is refused on staff URLs.

## The card (`school/examinations/card_pdf.py`)

The page follows the prototype, A4 portrait:

- the school's logo, name, address, phone and session;
- the "EXAMINATION ADMIT CARD" band, then the exam and term with "Version N - issued <date>";
- a student block: name, admission no, class and section that year, roll no, guardian (or a father or mother from Family-app links), centre, reporting time, and a photo box;
- the date sheet table, whose header repeats on page 2 when there are many papers;
- the instructions and the signature lines for the class teacher and the principal or exam controller.

`mono` prints black on white. Bulk printing starts each student on a new
sheet.

## Not done

- **Student download** waits for student sign-in (F6).
- **Parent download** goes live with the Family app.
- **Photos, seats and rooms**: no data exists for them.
- **A withdrawn or revoked state:** not asked for. Withholding a card covers it for one student.
