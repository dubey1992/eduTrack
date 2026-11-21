"""The classic printed fee receipt (docs/document-styles.md, decided
2026-11-17): the layout of a school's printed receipt book, for schools that
choose it under Module Settings -> Fee Management -> Fee receipt layout.

Black on white, no brand colour: the school's logo and name centred over its
address and phone, "Fee Receipt", the installment months, the receipt and the
student in two compact columns, a bordered Sl No. / Particulars / Amount
table of the month-wise fee lines, the money summary in two columns and then
the net, paid and dues lines, the paid amount in words, the remarks and the
accountant's signature.

**Every figure is one the receipt froze when it was recorded.** The summary
comes from `summary_*` (fees/receipt_summary.py) and the lines from each
allocation's `charge_amount`. A receipt recorded before those existed prints
what it always froze - each line's amount paid, the balance owed before it,
the amount paid and the balance after - and leaves out the rows it never
recorded rather than recalculating them. A cancelled receipt carries the
CANCELLED box, as on the standard layout.
"""

from __future__ import annotations

from decimal import Decimal

from .. import dates, money, pdf_design
from ..clock import DATE, TIME, SchoolClock
from ..enums import FeeDueKind, FeeReceiptStatus
from ..parent_names import parent_names
from ..receipts import e
from .receipt_summary import installment_label
from .resources import _class_names, enrollments_for, mode_label
from .words import amount_in_words

ZERO = Decimal("0.00")

CLASSIC_STYLES = """
@page {
    size: a4 portrait;
    margin: 1.2cm 1.5cm 1.4cm 1.5cm;
}
body { font-family: Helvetica, sans-serif; font-size: 10pt; color: #111111; }
table { width: 100%; border-collapse: collapse; }
td, th { vertical-align: top; }

.head .logo-cell { width: 80px; vertical-align: middle; }
.head .middle { text-align: center; vertical-align: middle; }
.head .pad-cell { width: 80px; }
.school { font-size: 19pt; font-weight: bold; letter-spacing: 0.5px; }
.address { font-size: 10pt; font-weight: bold; padding-top: 2px; }
.doc { font-size: 12.5pt; font-weight: bold; padding-top: 4px; }
.phone { font-size: 9.5pt; padding-top: 2px; }

.period { font-size: 10pt; font-weight: bold; padding: 10px 0 6px 0; }
.rule td { border-top: 1px solid #333333; font-size: 1pt; height: 2px; }

.info td { padding: 2px 0; font-size: 9.5pt; }
.info .k { width: 112px; font-weight: bold; }
.info .colon { width: 10px; font-weight: bold; }
.info .gap { width: 20px; }

.lines th { border: 1px solid #444444; padding: 6px 7px; font-size: 9.5pt; font-weight: bold; text-align: left; }
.lines td { border: 1px solid #444444; padding: 6px 7px; font-size: 9.5pt; }
.lines .amt { text-align: right; }

.sum td { padding: 3px 0; font-size: 10pt; font-weight: bold; }
.sum .v { text-align: right; }
.sum .gap { width: 40px; }

.final td { padding: 4px 0; font-size: 10.5pt; font-weight: bold; }
.final .v { text-align: right; }
.final .top { border-top: 1px solid #333333; }
.final .bottom { border-bottom: 1px solid #333333; }

.words td { border-top: 1px solid #777777; padding-top: 9px; font-size: 10pt; font-weight: bold; }
.remarks td { padding-top: 8px; font-size: 10pt; }

.sign .note { font-size: 8pt; color: #555555; vertical-align: bottom; }
.sign .line { width: 200px; text-align: center; border-top: 1px solid #555555; padding-top: 5px; font-size: 9.5pt; }
.sign .who { width: 200px; text-align: center; font-size: 8.5pt; color: #444444; vertical-align: bottom; }
.foot { font-size: 7.5pt; color: #666666; text-align: center; padding-top: 14px; }

.void td { border: 2px solid #b91c1c; color: #b91c1c; padding: 8px 12px; }
.void-word { font-size: 18pt; font-weight: bold; letter-spacing: 5px; }
.void-line { font-size: 9pt; }
"""


def amount(value) -> str:
    """1,750.00 - two places and the grouping the currency's locale uses,
    without a symbol: the column says what it is."""
    return f"{money.amount(value):,.2f}"


def spacer(height: int) -> str:
    return f'<table><tr><td style="height: {height}px; font-size: 1pt;">&nbsp;</td></tr></table>'


def particulars(due) -> str:
    """"SCHOOL FEE (DECEMBER 2025)" - the fee type and its installment."""
    return f"{due.fee_head.name} ({installment_label(due)})".upper()


def period_of(lines) -> str | None:
    """The installments a receipt covers: "DECEMBER 2025 - JANUARY 2026"
    when they run across months, the one name when there is one. Read off
    the school's own fee lines where there are any - a bus fee's
    installments are often named for the route rather than the month."""
    names: list[str] = []
    school_lines = [line for line in lines if not line.student_fee_due.fee_head.is_transport]

    for line in school_lines or lines:
        name = installment_label(line.student_fee_due)

        if name not in names:
            names.append(name)

    if not names:
        return None

    return (names[0] if len(names) == 1 else f"{names[0]} - {names[-1]}").upper()


def route_of(allocations) -> str | None:
    """The bus route the receipt paid for - the route of its transport fee,
    as it was charged, not wherever the student rides today."""
    for line in allocations:
        due = line.student_fee_due

        if not due.fee_head.is_transport or due.fee_structure_id is None:
            continue

        route = due.fee_structure.transport_route

        if route is not None:
            return route.name

    return None


def info_cell(key: str, value) -> str:
    shown = "" if value in (None, "") else e(value)
    return f'<td class="k">{e(key)}</td><td class="colon">:</td><td>{shown}</td>'


def info_rows(pairs: list[tuple[tuple[str, object] | None, tuple[str, object] | None]]) -> str:
    """Two columns of "Key : value", the receipt book's student block. A
    pair whose value is missing is left out; the column beside it keeps its
    place."""
    rows = []

    for left, right in pairs:
        cells = []

        for item in (left, right):
            cells.append(info_cell(*item) if item and item[1] not in (None, "") else '<td></td><td></td><td></td>')

        rows.append(f'<tr>{cells[0]}<td class="gap"></td>{cells[1]}</tr>')

    return "".join(rows)


def stamp(receipt, clock: SchoolClock) -> str:
    if receipt.status != FeeReceiptStatus.CANCELLED:
        return ""

    by = receipt.cancelled_by.name if receipt.cancelled_by_id else None
    when = clock.format(receipt.cancelled_at, DATE)
    lines = [
        f"Reason: {receipt.cancel_reason}" if receipt.cancel_reason else "",
        pdf_design.joined(f"Cancelled by {by}" if by else None, f"on {when}" if when else None),
        "This receipt is void. The installments it paid are owed again.",
    ]
    body = "<br/>".join(e(line) for line in lines if line)

    return f"""{spacer(8)}<table class="void"><tr><td><div class="void-word">CANCELLED</div>
        <div class="void-line">{body}</div></td></tr></table>"""


def header(school, title: str = "Fee Receipt") -> str:
    logo = pdf_design.stored_logo_data_uri(school) or pdf_design.logo_data_uri(school.logo_url)
    size = pdf_design.logo_size(logo) if logo else None
    logo_cell = (
        f'<img src="{logo}" width="{min(size[0], 70)}" height="{round(size[1] * min(size[0], 70) / size[0])}">'
        if size
        else ""
    )
    address = pdf_design.joined(school.address, school.city, school.state)

    return f"""
    <table class="head"><tr>
        <td class="logo-cell">{logo_cell}</td>
        <td class="middle">
            <div class="school">{e(school.name.upper())}</div>
            {f'<div class="address">{e(address.upper())}</div>' if address else ""}
            <div class="doc">{e(title)}</div>
            {f'<div class="phone">PH : {e(school.phone)}</div>' if school.phone else ""}
        </td>
        <td class="pad-cell"></td>
    </tr></table>"""


def document(receipt) -> str:
    """The classic receipt as HTML. `receipt` is loaded by
    FeeReceiptService.query()."""
    school = receipt.school
    student = receipt.student
    clock = SchoolClock.for_school(school)
    enrollment = enrollments_for([receipt]).get((receipt.student_id, receipt.academic_year_id))
    class_name, section_name = _class_names(enrollment)
    roll = (enrollment.roll_number if enrollment is not None else None) or student.roll_number
    parent_label, parent = parent_names(student).first_line()

    allocations = sorted(
        receipt.allocations.all(), key=lambda line: (line.student_fee_due.due_date, line.student_fee_due_id)
    )
    frozen = receipt.summary_net is not None
    # On a frozen receipt a late fine is a summary figure; on an older one
    # every line it paid is listed, as the standard receipt lists them.
    lines = [line for line in allocations if not frozen or line.student_fee_due.kind != FeeDueKind.LATE_FINE]

    issued_time = clock.format(receipt.created_at, TIME)
    when = pdf_design.joined(dates.us(receipt.receipt_date), issued_time, separator=" ")

    info = info_rows([
        (("Receipt No", receipt.receipt_number), ("Date", when)),
        (("Admission No", student.admission_number), ("Class", class_name)),
        (("Student Name", student.name.upper()), ("Sec", section_name)),
        ((parent_label, (parent or "").upper() or None), ("Roll", roll)),
        (("Session", receipt.academic_year.name), ("Route", (route_of(allocations) or "").upper() or None)),
    ])
    address = f'<tr>{info_cell("Address", (student.address or "").upper())}<td colspan="4"></td></tr>' if student.address else ""

    rows = "".join(
        f'<tr><td class="sl">{index}</td><td>{e(particulars(line.student_fee_due))}</td>'
        f'<td class="amt">{amount(line.charge_amount if frozen and line.charge_amount is not None else line.amount)}</td></tr>'
        for index, line in enumerate(lines, start=1)
    )

    credit = money.amount(receipt.credit_amount)
    paid = money.amount(receipt.amount)
    paid_against_dues = paid - credit

    if frozen:
        till = (receipt.summary_till or "").upper()
        left = [("Old Fee", receipt.summary_old_fee), ("Discount", receipt.summary_discount),
                ("Late Fee", receipt.summary_late_fee)]
        right = [("Total Amount", receipt.summary_total), ("Back Dues", receipt.summary_back_dues)]

        if money.amount(receipt.summary_paid_earlier) > 0:
            right.append(("Paid Earlier", receipt.summary_paid_earlier))

        net_label = f"Net Amount Till {till}" if till else "Net Amount"
        net = money.amount(receipt.summary_net)
    else:
        # Recorded before the summary existed: what it froze, and no more.
        left = []
        right = [("Total Amount", sum((money.amount(line.amount) for line in allocations), ZERO))]
        # Everything owed when it was taken, future installments included -
        # so it is not called "Net Amount Till", which it never measured.
        net_label = "Owed Before This Payment"
        net = money.amount(receipt.balance_before)

    dues = net - paid_against_dues

    def sum_rows(items) -> str:
        return "".join(f'<tr><td>{e(label)}</td><td class="v">{amount(value)}</td></tr>' for label, value in items)

    final = [(net_label, net), ("Paid Amount", paid)]

    if credit > 0:
        final.append(("Advance Held As Credit", credit))

    final.append(("Dues Amount", max(dues, ZERO)))
    final_rows = "".join(
        f'<tr><td class="{"top" if index == 0 else ""}{" bottom" if index == len(final) - 1 else ""}">{e(label)}</td>'
        f'<td class="v{" top" if index == 0 else ""}{" bottom" if index == len(final) - 1 else ""}">{amount(value)}</td></tr>'
        for index, (label, value) in enumerate(final)
    )

    remarks = pdf_design.joined(
        mode_label(receipt.payment_mode).upper(), receipt.reference, receipt.note, separator=" - "
    )
    received_by = receipt.received_by.name if receipt.received_by_id else None
    period = period_of(lines)

    body = f"""
    {header(school)}
    {f'<div class="period">Installment Month : {e(period)}</div>' if period else spacer(8)}
    <table class="rule"><tr><td>&nbsp;</td></tr></table>
    {stamp(receipt, clock)}
    {spacer(6)}
    <table class="info">{info}{address}</table>
    {spacer(10)}
    <table class="lines">
        <tr><th class="sl" width="12%">Sl&nbsp;No.</th><th width="65%">Particulars</th><th class="amt" width="23%">Amount</th></tr>
        {rows or '<tr><td class="sl">1</td><td>ADVANCE PAYMENT</td><td class="amt">' + amount(credit) + '</td></tr>'}
    </table>
    {spacer(14)}
    <table><tr>
        <td style="width: 48%"><table class="sum">{sum_rows(left)}</table></td>
        <td style="width: 4%"></td>
        <td style="width: 48%"><table class="sum">{sum_rows(right)}</table></td>
    </tr></table>
    {spacer(8)}
    <table class="final">{final_rows}</table>
    {spacer(12)}
    <table class="words"><tr><td>Paid In Words : {e(amount_in_words(paid, receipt.currency_code, local_scale=True))}</td></tr></table>
    <table class="remarks"><tr><td>Remarks : {e(remarks)}</td></tr></table>
    {spacer(60)}
    <table class="sign"><tr>
        <td class="note">Amounts in {e(receipt.currency_code)}. Computer-generated receipt.</td>
        <td class="who">{e(received_by) if received_by else ""}</td>
    </tr><tr>
        <td></td>
        <td class="line">Signature Of Accountant</td>
    </tr></table>
    <div class="foot">{e(school.name)} - Fee receipt {e(receipt.receipt_number)} - Powered by School365ai</div>"""

    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>{e(receipt.receipt_number)}</title>
<style>{CLASSIC_STYLES}</style></head>
<body>{body}</body></html>"""
