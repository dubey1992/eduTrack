"""The PDF a family is handed for a fee payment (docs/fees.md, F3).

Wears the platform's shared PDF look (school/pdf_design.py), which this
receipt set: xhtml2pdf, tables and simple CSS only. Laid out as a printed A4
receipt: a blue header band with the school's logo and contact details, the
receipt and the student side by side, the installments paid, the total in figures and in
words, the balances as they stood at the receipt, a footer saying when it
was issued in the school's own timezone, and "Page X of Y" on every page.

Every optional detail - a logo, a registration number, a roll number, a
reference, a note - is printed only when it has a value; a receipt never
reads "None". A cancelled receipt carries a red CANCELLED box at the top with
the reason, who cancelled it and when, and keeps its figures below.

The balances are the ones frozen on the receipt when it was recorded
(`balance_before`; after = before - amount), so a reprint months later says
what the family was told on the day.
"""

from __future__ import annotations

from .. import dates, money, pdf_design
from ..clock import DATE_TIME, SchoolClock
from ..enums import FeeReceiptStatus
from ..pdf_design import STYLESHEET, fact, joined, logo_data_uri, school_band  # noqa: F401 - re-exported
from ..receipts import e
from .resources import mode_label, receipt_class
from .words import amount_in_words


def file_name(receipt) -> str:
    return f"{receipt.receipt_number}.pdf"


def render(receipt) -> bytes:
    """The rendered PDF, ready to download or attach to an email."""
    return pdf_design.render(document(receipt), file_name(receipt))


def installment_name(due) -> str:
    """The installment on its own - "April 2026" - because the fee type has a
    column of its own beside it. The due's label is "Tuition - April 2026",
    a snapshot; the installment's own name is preferred, and the label with
    its fee-type prefix taken off is the fallback."""
    installment = getattr(due, "fee_installment", None)
    if installment is not None and installment.label:
        return installment.label

    prefix = f"{due.fee_head.name} - "
    return due.label[len(prefix):] if due.label.startswith(prefix) else due.label


def header(school, receipt_number: str, title: str = "FEE RECEIPT") -> str:
    """The blue band (pdf_design.school_band) - kept under this name for the
    statement (statement_pdf.py)."""
    return school_band(school, title, receipt_number)


def stamp(receipt, clock: SchoolClock) -> str:
    if receipt.status != FeeReceiptStatus.CANCELLED:
        return ""

    lines = [f"Reason: {receipt.cancel_reason}" if receipt.cancel_reason else ""]
    by = receipt.cancelled_by.name if receipt.cancelled_by_id else None
    when = clock.format(receipt.cancelled_at, DATE_TIME)
    lines.append(joined(f"Cancelled by {by}" if by else None, f"on {when}" if when else None))
    lines.append("This receipt is void. The installments it paid are owed again.")
    body = '<div class="stamp-line">' + "<br/>".join(e(line) for line in lines if line) + "</div>"

    return f"""
    <table><tr><td style="height: 14px; font-size: 1pt;">&nbsp;</td></tr></table>
    <table class="stamp"><tr><td><div class="stamp-word">CANCELLED</div>{body}</td></tr></table>"""


def document(receipt) -> str:
    """The receipt as HTML - separate from render() so a test can read it.
    `receipt` is loaded by FeeReceiptService.query()."""
    school = receipt.school
    student = receipt.student
    currency = receipt.currency_code
    clock = SchoolClock.for_school(school)
    class_name, section_name = receipt_class(receipt)

    def cash(value) -> str:
        return e(money.formatted(money.amount(value), currency))

    mode = mode_label(receipt.payment_mode)
    paid_by = f"{mode} {receipt.reference}" if receipt.reference else mode

    receipt_facts = "".join([
        fact("Receipt no.", receipt.receipt_number),
        fact("Date", dates.us(receipt.receipt_date)),
        fact("Academic year", receipt.academic_year.name),
        fact("Paid by", paid_by),
        fact("Received by", receipt.received_by.name if receipt.received_by_id else None),
    ])
    student_facts = "".join([
        fact("Student", student.name),
        fact("Admission no.", student.admission_number),
        fact("Class", joined(class_name, section_name).replace(", ", " - ") or None),
        fact("Roll no.", student.roll_number),
        fact("Guardian", student.guardian_name),
        fact("Guardian mobile", student.guardian_mobile),
    ])

    allocations = sorted(
        receipt.allocations.all(), key=lambda line: (line.student_fee_due.due_date, line.student_fee_due_id)
    )
    rows = "".join(
        f'<tr class="{"zebra" if index % 2 == 0 else ""}"><td class="idx">{index}</td>'
        f"<td>{e(line.student_fee_due.fee_head.name)}</td><td>{e(installment_name(line.student_fee_due))}</td>"
        f"<td>{dates.us(line.student_fee_due.due_date)}</td>"
        f'<td class="num">{cash(line.amount)}</td></tr>'
        for index, line in enumerate(allocations, start=1)
    )

    # F6: the part of the payment held as credit for the student's next fees.
    credit = money.amount(receipt.credit_amount)

    if credit > 0:
        rows += (
            f'<tr class="{"zebra" if (len(allocations) + 1) % 2 == 0 else ""}"><td class="idx">'
            # One cell across fee type, installment and due date, so the
            # wording never squeezes the date column.
            f'{len(allocations) + 1}</td><td colspan="3">Held as credit for the next fees</td>'
            f'<td class="num">{cash(credit)}</td></tr>'
        )

    before = money.amount(receipt.balance_before)
    after = before - (money.amount(receipt.amount) - credit)
    after_class = "settled" if after <= 0 else "after"
    credit_line = (
        f'<tr><td>Held as credit for the next fees</td><td class="value">{cash(credit)}</td></tr>' if credit > 0 else ""
    )

    note = ""

    if receipt.note:
        note = f"""
    <table><tr><td style="height: 14px; font-size: 1pt;">&nbsp;</td></tr></table>
    <div class="label">Note</div>
    <div class="note">{e(receipt.note)}</div>"""

    issued = clock.format(receipt.created_at, DATE_TIME) or dates.us(receipt.receipt_date)

    body = f"""
    {header(school, receipt.receipt_number)}
    {stamp(receipt, clock)}

    <table><tr><td style="height: 18px; font-size: 1pt;">&nbsp;</td></tr></table>
    <table><tr>
        <td style="width: 48%">
            <div class="section-title">RECEIPT DETAILS</div>
            <table class="facts">{receipt_facts}</table>
        </td>
        <td style="width: 4%"></td>
        <td style="width: 48%">
            <div class="section-title">RECEIVED FROM</div>
            <table class="facts">{student_facts}</table>
        </td>
    </tr></table>

    <table><tr><td style="height: 16px; font-size: 1pt;">&nbsp;</td></tr></table>
    <div class="section-title">FEES PAID</div>
    <table><tr><td style="height: 6px; font-size: 1pt;">&nbsp;</td></tr></table>
    <table class="items">
        <tr><th class="idx">#</th><th>Fee type</th><th>Installment</th><th>Due date</th>
            <th class="num">Amount</th></tr>
        {rows}
    </table>

    <table><tr><td style="height: 14px; font-size: 1pt;">&nbsp;</td></tr></table>
    <table class="totals">
        <tr><td class="big-label">Total received</td><td class="big-value">{cash(receipt.amount)}</td></tr>
        <tr><td class="words" colspan="2">{e(amount_in_words(receipt.amount, currency))}</td></tr>
    </table>

    <table><tr><td style="height: 12px; font-size: 1pt;">&nbsp;</td></tr></table>
    <table class="balances">
        <tr><td>Owed before this payment</td><td class="value">{cash(before)}</td></tr>
        <tr><td>Paid now</td><td class="value">{cash(receipt.amount)}</td></tr>
        {credit_line}
        <tr class="{after_class}"><td>Still owed after this payment</td><td class="value">{cash(after)}</td></tr>
    </table>
    {note}

    <table><tr><td style="height: 26px; font-size: 1pt;">&nbsp;</td></tr></table>
    <table class="footer">
        <tr><td class="rule">This is a computer-generated receipt and needs no signature.</td></tr>
        <tr><td>Issued {e(issued)} ({e(school.timezone)})</td></tr>
        <tr><td>Powered by School365ai</td></tr>
    </table>"""

    return pdf_design.page(
        receipt.receipt_number, body, footer=f"{school.name} - Fee receipt {receipt.receipt_number}"
    )
