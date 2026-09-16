"""The PDF receipt for a payment.

Port of PaymentReceiptService and resources/views/receipts/payment.blade.php.

Rendered by `xhtml2pdf`, which is pure Python - shared hosting has no cairo or
pango, so WeasyPrint is not an option (docs/python-migration.md, M0). Like
dompdf on the Laravel side it understands only simple CSS, which is why the
layout is tables and there is no flexbox. The stylesheet came across unchanged
so the document a school files looks the same after the cutover as before it.

The receipt states what was agreed, what has been received and what is still
owed, so a part-payment produces an honest document rather than one that reads
as though the account is settled.
"""

from __future__ import annotations

import html
import io

from xhtml2pdf import pisa

from . import money
from .clock import SchoolClock
from .enums import PaymentMode, PaymentStatus, PaymentType

BADGES = {
    PaymentStatus.PAID: "paid",
    PaymentStatus.PARTIAL: "part",
    PaymentStatus.PENDING: "pending",
    PaymentStatus.CANCELLED: "cancelled",
}

STYLESHEET = """
body { font-family: Helvetica, sans-serif; font-size: 12px; color: #1f2430; margin: 0; }
.sheet { padding: 36px 40px; }
.head { border-bottom: 2px solid #1f2430; padding-bottom: 14px; }
.brand { font-size: 20px; font-weight: bold; }
.muted { color: #6b7280; }
.right { text-align: right; }
h1 { font-size: 16px; margin: 22px 0 10px; }
table { width: 100%; border-collapse: collapse; }
.meta td { padding: 4px 0; vertical-align: top; }
.meta .key { color: #6b7280; width: 130px; }
.amounts { margin-top: 8px; border: 1px solid #d7dbe3; }
.amounts td { padding: 9px 12px; border-bottom: 1px solid #eceef2; }
.amounts .label { color: #4b5563; }
.amounts .value { text-align: right; font-weight: bold; }
.due td { background: #fdecec; color: #8a1c1c; }
.settled td { background: #eaf7ee; color: #155e2e; }
.badge { padding: 4px 10px; font-weight: bold; font-size: 11px; }
.badge-paid { background: #eaf7ee; color: #155e2e; }
.badge-part { background: #fff4e5; color: #8a5300; }
.badge-pending { background: #fdecec; color: #8a1c1c; }
.badge-cancelled { background: #eceef2; color: #4b5563; }
.note { margin-top: 26px; padding-top: 12px; border-top: 1px solid #eceef2; font-size: 11px; }
"""


def receipt_number(payment) -> str:
    """"RCPT-000042" - stable for a payment, so a school re-sent the same
    receipt files it over the one it already has rather than beside it."""
    return f"RCPT-{payment.id:06d}"


def file_name(payment) -> str:
    return receipt_number(payment) + ".pdf"


def render(payment) -> bytes:
    """The rendered PDF, ready to download or attach to an email."""
    source = document(payment)
    out = io.BytesIO()

    result = pisa.CreatePDF(source, dest=out, encoding="utf-8")

    if result.err:
        raise RuntimeError(f"Could not render {file_name(payment)}")

    return out.getvalue()


def document(payment) -> str:
    """The receipt as HTML. Separate from render() so a test can read it."""
    total = money.amount(payment.amount)
    paid = money.amount(payment.paid_amount)
    owed = money.remaining(total, paid, payment.status)

    settled = payment.status == PaymentStatus.PAID
    cancelled = payment.status == PaymentStatus.CANCELLED

    def cash(value) -> str:
        return e(money.formatted(value, payment.currency_code))

    school = payment.school
    # Dates on the receipt are read at the school, not on the server.
    issued_on = SchoolClock.for_school(school).now().strftime("%m/%d/%Y")

    rows = [
        row("School", e(school.name) if school else "-"),
    ]

    if school and school.address:
        rows.append(
            row("Address", e(f"{school.address}, {school.city}, {school.country}"))
        )

    rows.append(row("Email", e(school.email) if school else "-"))

    payment_rows = [
        row("For", e(label(PaymentType, payment.payment_type))),
        row("Date", payment.payment_date.strftime("%m/%d/%Y")),
        row("Method", e(label(PaymentMode, payment.payment_mode))),
    ]

    if payment.reference_number:
        payment_rows.append(row("Reference", e(payment.reference_number)))

    badge = BADGES.get(payment.status, "cancelled")
    payment_rows.append(
        row(
            "Status",
            f'<span class="badge badge-{badge}">{e(label(PaymentStatus, payment.status))}</span>',
        )
    )

    balance_label = "Cancelled" if cancelled else ("Balance" if settled else "Balance due")
    balance_class = "settled" if settled or cancelled else "due"

    # Escaped in every branch, so the template can drop it in without having
    # to know which branch produced it.
    if cancelled:
        note = e("This payment has been cancelled. Nothing is owed against it.")
    elif settled:
        note = e("Paid in full. Thank you.")
    else:
        note = f"{cash(owed)} remains outstanding on this payment."

    recorded_by = payment.created_by.name if payment.created_by_id else "the platform team"

    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>{e(receipt_number(payment))}</title>
<style>{STYLESHEET}</style>
</head>
<body>
<div class="sheet">
    <table class="head">
        <tr>
            <td>
                <div class="brand">School365ai</div>
                <div class="muted">Payment receipt</div>
            </td>
            <td class="right">
                <div><strong>{e(receipt_number(payment))}</strong></div>
                <div class="muted">Issued {issued_on}</div>
            </td>
        </tr>
    </table>

    <h1>Billed to</h1>
    <table class="meta">{"".join(rows)}</table>

    <h1>Payment</h1>
    <table class="meta">{"".join(payment_rows)}</table>

    <table class="amounts">
        <tr><td class="label">Amount</td><td class="value">{cash(total)}</td></tr>
        <tr><td class="label">Amount received</td><td class="value">{cash(paid)}</td></tr>
        <tr class="{balance_class}">
            <td class="label">{balance_label}</td>
            <td class="value">{cash(owed)}</td>
        </tr>
    </table>

    {notes_block(payment)}

    <div class="note muted">
        {note}
        <br>
        Recorded by {e(recorded_by)}.
        This receipt is issued electronically and is valid without a signature.
    </div>
</div>
</body>
</html>"""


def notes_block(payment) -> str:
    if not payment.notes:
        return ""

    return f"<h1>Notes</h1>\n    <div>{e(payment.notes)}</div>"


def row(key: str, value: str) -> str:
    return f'<tr><td class="key">{key}</td><td>{value}</td></tr>'


def label(choices, value: str) -> str:
    """The human name for a stored value - "Partially Paid" for "partial"."""
    return dict(choices.choices).get(value, value)


def e(value) -> str:
    """Escapes a value for HTML.

    A school's name and a payment's notes are typed by people, and an
    ampersand or an angle bracket in either would otherwise break the
    document - or, worse, be rendered as markup.
    """
    return html.escape(str(value or ""))
