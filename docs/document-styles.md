# Document styles

Decided 2026-11-17, from a customer's printed receipt book and report card
(N.N.M. Public School). The reference layouts are in the prototype
`school365ai_reports_prototype.html` the user supplied.

A school chooses how its printed documents look. **Standard** stays the
default, so no school's documents change until it chooses otherwise.

| Document | Setting | Values |
|---|---|---|
| Fee receipt | Module Settings → Fee Management → **Fee receipt layout** (`fees.receipt_style`) | `standard`, `classic` |
| Report card | Module Settings → Class Tests → **Report card layout** (`assessments.report_card_style`) | `standard`, `classic` |

The choice is applied wherever the document is made: the download in the
web app, the Family app's copy and the copy emailed to the guardian. Every
one of them goes through `fees/receipt_pdf.render()` or
`progress_reports.render()`.

## Classic printed fee receipt (`fees/receipt_classic.py`)

The page is black on white with no brand colour. Printed documents keep the
customer's printed look; the Warm Editorial colours are for the app.

- **Header.** Centred: the school's logo, its name in capitals, its address, "Fee Receipt" and its phone number. The months the receipt covers sit under it ("Installment Month : APRIL - JULY"), read off the school's own fee lines, because a bus fee's installments are often named for the route.
- **Student block.** Two columns:
  - Receipt No and Date, with the time it was recorded in the school's timezone. Dates are written in the app's one order (see the date-format rule).
  - Admission No, Class and Sec as they were in the receipt's year.
  - Student Name and Roll, the roll number also as it was in that year.
  - Father's Name: only where a Family-app parent link says father; then mother; else the guardian name on the student record (`school/parent_names.py`).
  - Session.
  - Route: the route of the transport fee the receipt paid, not wherever the student rides today.
  - Address.
- **Fee lines.** Sl No. / Particulars / Amount. Each line reads "TUITION (APRIL)" and shows the line's full charge.
- **Summary.**
  - Left column: Old Fee, Discount, Late Fee.
  - Right column: Total Amount, Back Dues, and Paid Earlier when it is not zero.
  - Then: Net Amount Till <month>, Paid Amount, Advance Held As Credit when there is one, and Dues Amount.
- **Below the summary.**
  - Paid In Words, on the Indian scale (lakh, crore) for rupees.
  - Remarks: the payment mode, the reference and the note.
  - The name of whoever received the payment, over "Signature Of Accountant".

### The summary is frozen at the payment

The rows of a printed receipt book cannot be worked out later without
recalculating history. A concession given next month changes a due's
discount, and a reconcile changes what is owed. So each figure is worked out
once, when the payment is taken (`fees/receipt_summary.py`), and stored on
the receipt in `fee_receipts.summary_*`. Each fee line's full charge is
stored as `fee_receipt_allocations.charge_amount`.

| Row | Meaning |
|---|---|
| Total Amount | The full charge of the installments this payment touches |
| Discount | The discount on those installments |
| Late Fee | The late fines among them. A fine is a summary figure, not a fee line. |
| Paid Earlier | What earlier receipts had already paid on those installments |
| Back Dues | Still owed on the same year's earlier installments that this payment did not touch |
| Old Fee | The same, for earlier academic years |
| Net Amount Till <month> | Total − Discount + Late Fee − Paid Earlier + Back Dues + Old Fee |
| Paid Amount | The receipt's amount |
| Dues Amount | Net minus what was paid against dues; the part held as credit is not counted |

- Installments falling due after the receipt's last month are counted nowhere.
- Waived and cancelled installments owe nothing.

**Receipts recorded before 2026-11-17** have no frozen summary. They print
what they did freeze, and nothing is recalculated:

- each line's amount paid;
- the total;
- "Owed Before This Payment", which covered every unpaid fee, future ones included;
- the amount paid;
- what was left owing.

## Grading systems (decided 2026-11-17)

Schools grade in different ways, so each grade scale has a **type**
(`grade_scales.kind`, `GradeScaleKind`). Every scale made before this date
is a percentage scale.

| Type | Bands carry | The classic card prints |
|---|---|---|
| `percentage`: marks and percentage | % ranges, optional meaning | each test's marks, totals, percentage, grade |
| `gpa`: grade points | % ranges, **grade points** (required, never fewer for a better band), optional meaning | the above plus each subject's points and the GPA (mean of the subjects' points) out of the scale's top points; "Equivalent percentage" only when the school sets `gpa_multiplier` |
| `grades`: grades only | % ranges, optional meaning | each subject's grade per term, and the final grade. No marks or percentages. |

- Divisions (First, Second, Third) are a percentage scale whose bands are the divisions.
- The Grade Scales screen offers five presets: nine-point with grade points (CBSE style, × 9.5), four-point GPA, A to F percentage, Divisions, and descriptive grades for young classes. A preset only fills the form; everything stays editable.

**The result line** is set per school (`assessments.result_rule`):

- **Passed every subject** (the default): each subject reaches the pass mark (`pass_percentage`, the same line promotion uses). On a grades-only scale there is no percentage, so the rule is that no subject's grade is a failing band.
- **Passed overall**: the year's total does.
- **Don't print a result.**

The words are the school's own (`result_pass_word`, `result_fail_word`;
QUALIFIED and NOT QUALIFIED by default).

**The rank** prints only when the school switches on `print_rank`. It is the
place within the student's section that year, by the year's percentage (or
GPA on a grade-point scale). Equal scores share a place and the next one is
skipped (1, 2, 2, 4). A grades-only card has no score to rank by, so it
prints no rank.

## Classic printed report card (`report_card.py`, `report_card_classic.py`)

The figures come from `report_card.py`, which is pure apart from `load()`.
The layout is `report_card_classic.py`.

- **Raw marks added up.** A subject's term total is the sum of its tests' marks out of the sum of their maximums, as a printed marksheet adds them. This is the classic card's rule only: the screens and the standard progress report keep their average of percentages, and no stored mark or grade changes.
- **Only published results count.**
- **Absent is not zero.** A missed test prints "AB" and leaves both the marks and the maximum.
- **Tests are columns by their title** ("F.A.-I", "Notebook", "S.A.-I"), in the order they were first held. A column's maximum is in its heading when every subject's test has the same one; otherwise each cell reads "19/20".
- **Terms.** The card shows the year's terms up to the one asked for, so a card printed after Term 1 shows Term 1 only. With more than two terms, or a very wide table, the page turns landscape.
- **Other content.**
  - Attendance: the register over the printed terms, up to today, out of working days.
  - The class teacher's remark for the term.
  - The school's "A word to parents" (`report_card_note`) and instructions (`report_card_instructions`).
  - The grading key: grade, % range, points, meaning.
  - Signature lines.
- **People.** Father's and mother's names come only from Family-app parent links (`school/parent_names.py`); otherwise the guardian name. There is no student photo field, so the card has a placeholder box.

## Not done

- **The fee statement PDF** (`fees/statement_pdf.py`) keeps the standard look. A classic style for it is possible the same way, if a school asks.
- **The Student Fees screen and the student search** already show payment history with View Receipt, dues by month and fee type, and the statement download. They were left as they are.
