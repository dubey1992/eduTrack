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
| 4 | Student progress report | `school/progress_reports.py` | shared kit (phase 3) |
| 5-16 | The 12 reports (attendance, leave, teaching, syllabus, transport, payroll, performance, fees) | `school/reports/pdf.py` | shared kit (phase 4) |
| 17 | Payment receipt (school pays School365ai) | `school/receipts.py` | shared kit (phase 5) |

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
4. **No colspan in a table that sets its column widths, and no column with
   an empty heading.** xhtml2pdf gets every width wrong and squeezes the last
   column, or collapses the empty one. Put a totals line under the table as
   its own one-row table (`total_row`).
5. **xhtml2pdf ignores `text-transform`**: headings are uppercased in the
   text itself (`section`). Tiny nested tables (a 4px bar under a figure)
   crash it - colour the figure instead.

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
   Since 2026-10-28 also the bank, the account (masked: XXXXXX1234), the
   branch code and the tax ID - see "Additions" below.
3. **Progress report** - done 2026-10-28. The band (term and its dates),
   the student (name, admission and roll numbers, class, guardian, class
   teacher) beside the report (academic year, term, period, generated), the
   summary as tiles (average in red when below the weak mark, class average,
   change since last term, tests and missed), subjects with grades coloured
   (a failing grade in red), the topics inside each subject, every test with
   its frozen grade, the grade scale as a strip, attendance as tiles (or a
   sentence where the register was never taken), what the figures say and
   what to do next, and lines for the class teacher, principal and parent to
   sign. Since 2026-10-28 also the class teacher's remark for the term -
   see "Additions" below.
4. **The 12 reports** - done 2026-10-28, one template for all. Landscape;
   the school's band (logo, address) with the report's name, period and
   working days - a group report carries the group's label instead; what
   the sheet is (filters, branches, rows) beside when it was run and what
   it was compared with; the totals as headline tiles, each with the
   previous period's figure; every row, the heading repeated on each page
   and each column as wide as what it holds (xhtml2pdf otherwise makes them
   equal, and a receipt number runs into the next column); how the figures
   are worked out.
5. **The School365ai payment receipt** - done 2026-10-28. The issuer band
   is School365ai as the Super Admin describes it on the Company details
   screen (or just "School365ai" until then); billed-to beside the payment;
   the amount in words; agreed, received and balance; notes; a CANCELLED
   stamp.

## Additions (2026-10-28, "add all the necessary items")

- **Bank details on the payslip.** `salary_profiles` gains `bank_name`,
  `bank_account_number`, `bank_branch_code` (IFSC, sort code, routing
  number) and `tax_id` (PAN or equivalent), set on the Salaries dialog.
  The account number is encrypted at rest (school/crypto.py) and nothing
  the server sends - screen, payslip, audit row - carries more than its last
  four characters (school/payroll/bank.py). Left empty on the form, it is
  kept; the other three are saved as typed. Read live onto the payslip.
- **The class teacher's remark on the progress report.** `student_term_remarks`
  - one per student per term, up to 1,000 characters - written from the
  Performance dialog by the student's class teacher or a School / Group
  Admin who may manage class tests (`StudentPolicy.write_remark`);
  everyone who may read the performance reads it. `PUT
  students/{id}/remark`; clearing the text deletes it; audited.
- **Company details.** `company_profiles` (one row): legal and trading name,
  address, phone, email, website, tax number (GSTIN), registration number
  (CIN), logo. Super Admin only, `GET/PUT settings/company`, the Company
  Details screen. The issuer on the School365ai payment receipt.
- **Tidier addresses.** `joined` drops the commas and spaces a person typed
  at the ends of a part, so "77, IAS Colony," and "Patna" read "77, IAS
  Colony, Patna".
