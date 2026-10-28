"""The PDF a family is handed for a fee payment (docs/fees.md, F3).

The same engine as the Super Admin's payment receipt (school/receipts.py):
xhtml2pdf, because shared hosting has no cairo - so tables and simple CSS
only, no flexbox, no rotation. Laid out as a printed A4 receipt: a blue
header band with the school's logo and contact details, the receipt and the
student side by side, the installments paid, the total in figures and in
words, the balances as they stood at the receipt, and a footer saying when it
was issued in the school's own timezone.

Every optional detail - a logo, a registration number, a roll number, a
reference, a note - is printed only when it has a value; a receipt never
reads "None". A cancelled receipt carries a red CANCELLED box at the top with
the reason, who cancelled it and when, and keeps its figures below.

The balances are the ones frozen on the receipt when it was recorded
(`balance_before`; after = before - amount), so a reprint months later says
what the family was told on the day.
"""

from __future__ import annotations

import base64
import io
import logging
import urllib.request

from xhtml2pdf import pisa

from .. import dates, money
from ..clock import DATE_TIME, SchoolClock
from ..enums import FeeReceiptStatus
from ..receipts import e
from .resources import mode_label, receipt_class
from .words import amount_in_words

logger = logging.getLogger(__name__)

BRAND = "#2563EB"
LOGO_TIMEOUT_SECONDS = 3
LOGO_MAX_BYTES = 2 * 1024 * 1024
LOGO_TYPES = ("image/png", "image/jpeg", "image/jpg", "image/gif")

STYLESHEET = f"""
@page {{ size: a4 portrait; margin: 1.5cm 1.6cm 1.5cm 1.6cm; }}
body {{ font-family: Helvetica, sans-serif; font-size: 10pt; color: #1f2937; }}
table {{ width: 100%; border-collapse: collapse; }}
td, th {{ vertical-align: top; }}

.band td {{ background-color: {BRAND}; color: #ffffff; }}
.band .logo {{ width: 70px; padding: 14px 0 14px 16px; vertical-align: middle; }}
.band .school {{ padding: 14px 16px; vertical-align: middle; }}
.band .title {{ width: 230px; padding: 14px 16px; text-align: right; vertical-align: middle; }}
.school-name {{ font-size: 17pt; font-weight: bold; }}
.school-line {{ font-size: 8.5pt; color: #dbeafe; line-height: 1.5; padding-top: 4px; }}
.doc-title {{ font-size: 14pt; font-weight: bold; }}
.doc-number {{ font-size: 10.5pt; padding-top: 4px; }}

.stamp td {{ border: 3px solid #b91c1c; background-color: #fef2f2; color: #b91c1c; padding: 10px 14px; }}
.stamp-word {{ font-size: 26pt; font-weight: bold; letter-spacing: 6px; }}
.stamp-line {{ font-size: 9.5pt; line-height: 1.5; }}

.label {{ font-size: 7.5pt; color: #6b7280; text-transform: uppercase; letter-spacing: 1px; }}
.section-title {{ font-size: 8pt; font-weight: bold; color: #6b7280; letter-spacing: 1px;
    padding: 0 0 5px 0; border-bottom: 1px solid #e5e7eb; }}
.facts td {{ padding: 2px 0; font-size: 9.5pt; }}
.facts .key {{ width: 105px; color: #6b7280; }}
.facts .value {{ font-weight: bold; color: #111827; }}

.items th {{ background-color: #e0e7ff; color: #1e3a8a; font-size: 8.5pt; text-align: left;
    padding: 7px 8px; border-bottom: 1px solid #c7d2fe; }}
.items td {{ padding: 5px 8px; font-size: 9.5pt; border-bottom: 1px solid #e5e7eb; }}
.items .zebra td {{ background-color: #f8fafc; }}
.items .num {{ text-align: right; }}
.items .idx {{ width: 24px; color: #6b7280; }}

.totals td {{ background-color: #eff6ff; padding: 6px 14px; }}
.totals .big-label {{ font-size: 11pt; font-weight: bold; color: #1e3a8a; padding-top: 10px; vertical-align: middle; }}
.totals .big-value {{ font-size: 16pt; font-weight: bold; color: #1e3a8a; text-align: right; padding-top: 10px; }}
.totals .words {{ font-size: 9pt; font-style: italic; color: #1f2937; padding-top: 0; padding-bottom: 8px; }}

.balances td {{ padding: 4px 12px; font-size: 9.5pt; border-bottom: 1px solid #e5e7eb; }}
.balances .value {{ text-align: right; font-weight: bold; }}
.balances .after td {{ background-color: #fff7ed; color: #9a3412; font-weight: bold; }}
.balances .settled td {{ background-color: #ecfdf5; color: #065f46; font-weight: bold; }}

.note {{ font-size: 9.5pt; padding: 8px 12px; border-left: 3px solid {BRAND}; background-color: #f8fafc; }}
.footer td {{ font-size: 8pt; color: #6b7280; padding-top: 3px; text-align: center; }}
.rule {{ border-top: 1px solid #e5e7eb; }}
"""


def file_name(receipt) -> str:
    return f"{receipt.receipt_number}.pdf"


def render(receipt) -> bytes:
    """The rendered PDF, ready to download or attach to an email."""
    out = io.BytesIO()
    result = pisa.CreatePDF(document(receipt), dest=out, encoding="utf-8")

    if result.err:
        raise RuntimeError(f"Could not render {file_name(receipt)}")

    return out.getvalue()


def logo_data_uri(url: str | None) -> str | None:
    """The school's logo, fetched and inlined - or None, so that a logo that
    is missing, slow, too big or not an image costs the receipt its logo and
    nothing else. Logged, never raised."""
    if not url or not url.lower().startswith(("http://", "https://")):
        return None

    try:
        request = urllib.request.Request(url, headers={"User-Agent": "School365ai receipts"})

        with urllib.request.urlopen(request, timeout=LOGO_TIMEOUT_SECONDS) as response:  # noqa: S310 - http(s) only
            kind = (response.headers.get_content_type() or "").lower()
            body = response.read(LOGO_MAX_BYTES + 1)
    except Exception as error:  # noqa: BLE001 - any failure means "no logo", by design
        logger.warning("Fee receipt: could not fetch the school logo %s (%s)", url, error)
        return None

    if kind not in LOGO_TYPES or len(body) > LOGO_MAX_BYTES or not body:
        logger.warning("Fee receipt: the school logo %s is not a usable image (%s, %s bytes)", url, kind, len(body))
        return None

    return f"data:{kind};base64,{base64.b64encode(body).decode('ascii')}"


def joined(*parts) -> str:
    """The parts that have a value, comma-separated."""
    return ", ".join(str(part).strip() for part in parts if part and str(part).strip())


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


def fact(key: str, value) -> str:
    """One labelled line, or nothing at all when there is no value."""
    if value is None or str(value).strip() == "":
        return ""

    return f'<tr><td class="key">{e(key)}</td><td class="value">{e(value)}</td></tr>'


def header(school, receipt_number: str, title: str = "FEE RECEIPT") -> str:
    """The blue band: logo, school and its contact lines, and on the right
    the document's title and number - shared by the receipt and the
    statement (statement_pdf.py)."""
    logo = logo_data_uri(school.logo_url)
    logo_cell = f'<td class="logo"><img src="{logo}" width="60" height="60"></td>' if logo else ""

    lines = [
        joined(school.address, school.city, school.state, school.postal_code, school.country),
        joined(f"Phone {school.phone}" if school.phone else None, school.email),
        f"Reg. no. {school.registration_number}" if school.registration_number else "",
    ]
    shown = "<br/>".join(e(line) for line in lines if line)
    contact = f'<div class="school-line">{shown}</div>' if shown else ""

    return f"""
    <table class="band"><tr>
        {logo_cell}
        <td class="school"><div class="school-name">{e(school.name)}</div>{contact}</td>
        <td class="title"><div class="doc-title">{e(title)}</div>
            <div class="doc-number">{e(receipt_number)}</div></td>
    </tr></table>"""


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

    before = money.amount(receipt.balance_before)
    after = before - money.amount(receipt.amount)
    after_class = "settled" if after <= 0 else "after"

    note = ""

    if receipt.note:
        note = f"""
    <table><tr><td style="height: 14px; font-size: 1pt;">&nbsp;</td></tr></table>
    <div class="label">Note</div>
    <div class="note">{e(receipt.note)}</div>"""

    issued = clock.format(receipt.created_at, DATE_TIME) or dates.us(receipt.receipt_date)

    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>{e(receipt.receipt_number)}</title>
<style>{STYLESHEET}</style>
</head>
<body>
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
        <tr class="{after_class}"><td>Still owed after this payment</td><td class="value">{cash(after)}</td></tr>
    </table>
    {note}

    <table><tr><td style="height: 26px; font-size: 1pt;">&nbsp;</td></tr></table>
    <table class="footer">
        <tr><td class="rule">This is a computer-generated receipt and needs no signature.</td></tr>
        <tr><td>Issued {e(issued)} ({e(school.timezone)})</td></tr>
        <tr><td>Powered by School365ai</td></tr>
    </table>
</body>
</html>"""
