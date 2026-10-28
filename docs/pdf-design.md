# PDF design

Every PDF the platform prints shares one look, kept in
`backend-python/school/pdf_design.py`. Asked for on 2026-10-28: "advance
rendering is required in the PDF where all the information should be
displayed. A high level PDF should be designed." The fee receipt (Fees F3)
set the standard; the kit is that receipt's look taken out so every other
document can wear it.

## The PDFs (17, from 6 designs)

| # | PDF | Code | Design |
|---|---|---|---|
| 1 | Fee receipt | `school/fees/receipt_pdf.py` | shared kit (phase 1) |
| 2 | Fee statement | `school/fees/statement_pdf.py` | shared kit (phase 1) |
| 3 | Payslip | `school/payroll/payslips.py` | shared kit (phase 2) |
| 4 | Student progress report | `school/progress_reports.py` | old - phase 3 |
| 5-16 | The 12 reports (attendance, leave, teaching, syllabus, transport, payroll, performance, fees) | `school/reports/pdf.py` | old - phase 4 |
| 17 | Payment receipt (school pays School365ai) | `school/receipts.py` | old - phase 5 |

## What every document has

- **The blue band** - the issuer's logo (fetched and inlined; one that cannot
  be fetched is left out, never an error), name, address, phone, email and
  registration number, and on the right the document's title, number and a
  line under it. `school_band(school, title, number, subtitle)`.
- **Labelled facts side by side** - `facts`, `side_by_side`.
- **Section headings** that never end a page alone - `section`.
- **Striped tables** whose heading repeats on every page - `table`, with a
  totals line under it - `total_row`.
- **Headline figure tiles** - `tiles` - for reports and summaries.
- **The big figure and it in words** - `totals_panel`.
- **A stamp** for a void or draft document - `stamp`.
- **Signature lines** - `signatures`.
- **Closing lines** - computer-generated, issued at (in the school's own
  timezone), Powered by School365ai - `closing`.
- **A running footer** on every page: whose document it is, and "Page X of
  Y" - built into `page()`.
- Portrait A4 by default, **landscape** for wide tables - `page(landscape=True)`.

## Rules

1. **Never print an empty value.** A fact, a contact line or a logo with
   nothing in it is left out; no document reads "None".
2. **Escape everything a person typed** - names, notes, reasons.
3. **Never two style rules of the same specificity that can match one
   cell.** xhtml2pdf cannot rank them and silently prints the cell unstyled
   (found on the fee statement, whose total rows and table headings had
   quietly lost their styles). Narrow a shared rule with a more specific
   selector (`table.compact td`, `.items tr.void td`). Every document's tests
   assert `pdf_design.style_errors(html) == 0`.
4. **No colspan in a table that sets its column widths** - xhtml2pdf then
   gets every width wrong and squeezes the last column. Put a totals line
   under it as its own one-row table (`total_row`).

The engine is xhtml2pdf because shared hosting has no cairo or pango (which
rules out WeasyPrint): tables and simple CSS only - no flexbox, no grid, no
web fonts; spacing by spacer rows.

## Phases

1. **The shared kit**, worn by the fee receipt and statement - done 2026-10-28.
2. **Payslip** - done 2026-10-28. One A4 page: the band (number, pay
   period), a DRAFT stamp while the run can change, the employee (name, ID,
   designation, department, joining date, email, mobile) beside the pay
   period and payment (period dates, status, paid on, paid by, reference,
   currency), the month's attendance as five tiles, earnings beside
   deductions with "of X for the full month" under each pro-rated line,
   deductions beyond earnings said plainly, net pay in figures and in words.
   Bank account and tax ID are not on it: they need new staff fields, which
   the user has not yet approved.
3. Progress report.
4. The 12 reports.
5. The School365ai payment receipt.

Open decisions (asked 2026-10-28): bank account and tax ID on the payslip
(new staff fields); typed teacher remarks on the progress report (new field);
School365ai's legal name, address and tax number for its own receipt.
