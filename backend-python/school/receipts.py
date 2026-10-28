"""The receipt a school gets for paying School365ai (Super Admin payments).

Wears the platform's shared PDF look (school/pdf_design.py, docs/pdf-design.md,
phase 5). The issuer in the blue band is School365ai as a business - legal or
trading name, address, contacts, tax and company registration numbers, logo -
from the Company details the Super Admin keeps (CompanyProfile); until those
are saved the band says "School365ai" and nothing more. Then the school billed
beside the payment, the amount in figures and in words, what was agreed,
received and is still owed, any notes, a CANCELLED stamp for a cancelled
payment, and when it was issued in the school's own timezone.

The receipt states what was agreed, what has been received and what is still
owed, so a part-payment produces an honest document rather than one that reads
as though the account is settled.
"""

from __future__ import annotations

from . import dates, money, pdf_design
from .clock import DATE_TIME, SchoolClock
from .enums import PaymentMode, PaymentStatus, PaymentType
# The escape lives with the shared PDF look; imported here too because the
# documents written before it (fee receipts, payslips) import it from here.
from .pdf_design import e  # noqa: F401

def receipt_number(payment) -> str:
    """"RCPT-000042" - stable for a payment, so a school re-sent the same
    receipt files it over the one it already has rather than beside it."""
    return f"RCPT-{payment.id:06d}"


def file_name(payment) -> str:
    return receipt_number(payment) + ".pdf"


def render(payment) -> bytes:
    """The rendered PDF, ready to download or attach to an email."""
    return pdf_design.render(document(payment), file_name(payment))


def issuer_band(receipt_no: str, issued_on: str) -> str:
    """School365ai's band: the business as the Super Admin has described it,
    or just the name until they have."""
    from .services import CompanyProfileService

    company = CompanyProfileService.current()

    if company is None:
        return pdf_design.band("School365ai", [], "PAYMENT RECEIPT", receipt_no, f"Issued {issued_on}")

    name = company.trading_name or company.legal_name
    lines = [
        company.legal_name if company.trading_name and company.legal_name != company.trading_name else "",
        pdf_design.joined(company.address, company.city, company.state, company.postal_code, company.country),
        pdf_design.joined(f"Phone {company.phone}" if company.phone else None, company.email, company.website),
        pdf_design.joined(
            f"Tax no. {company.tax_number}" if company.tax_number else None,
            f"Reg. no. {company.registration_number}" if company.registration_number else None,
            separator="  |  ",
        ),
    ]

    return pdf_design.band(
        name, [line for line in lines if line], "PAYMENT RECEIPT", receipt_no, f"Issued {issued_on}",
        logo_url=company.logo_url,
    )


def document(payment) -> str:
    """The receipt as HTML. Separate from render() so a test can read it."""
    from .fees.words import amount_in_words

    total = money.amount(payment.amount)
    paid = money.amount(payment.paid_amount)
    owed = money.remaining(total, paid, payment.status)

    settled = payment.status == PaymentStatus.PAID
    cancelled = payment.status == PaymentStatus.CANCELLED

    def cash(value) -> str:
        return money.formatted(value, payment.currency_code)

    school = payment.school
    clock = SchoolClock.for_school(school)
    # Dates on the receipt are read at the school, not on the server.
    issued_on = dates.us(clock.now())
    number = receipt_number(payment)
    kind = label(PaymentType, payment.payment_type)

    billed = pdf_design.facts([
        ("School", school.name if school else "-"),
        ("Address", pdf_design.joined(school.address, school.city, school.state, school.postal_code, school.country)
         if school else None),
        ("Phone", school.phone if school else None),
        ("Email", school.email if school else None),
        ("Reg. no.", school.registration_number if school else None),
    ])
    details = pdf_design.facts([
        ("Receipt no.", number),
        ("For", kind),
        ("Date", dates.us(payment.payment_date)),
        ("Method", label(PaymentMode, payment.payment_mode)),
        ("Reference", payment.reference_number),
        ("Status", label(PaymentStatus, payment.status)),
        ("Recorded by", payment.created_by.name if payment.created_by_id else "the platform team"),
    ])

    stamp = ""
    if cancelled:
        stamp = pdf_design.stamp("CANCELLED", ["This payment has been cancelled. Nothing is owed against it."])

    items = pdf_design.table(
        [("#", "6%", False), ("Description", "64%", False), ("Amount", "30%", True)],
        [["1", e(f"{kind} - {school.name}" if school else kind), e(cash(total))]],
    )

    try:
        words = amount_in_words(paid, payment.currency_code)
    except ValueError:
        words = None

    balance_label = "Cancelled" if cancelled else ("Balance" if settled else "Balance due")
    balance_class = "settled" if settled or cancelled else "after"
    balances = f"""
    <table class="balances">
        <tr><td>Amount</td><td class="value">{e(cash(total))}</td></tr>
        <tr><td>Amount received</td><td class="value">{e(cash(paid))}</td></tr>
        <tr class="{balance_class}"><td>{balance_label}</td><td class="value">{e(cash(owed))}</td></tr>
    </table>"""

    if cancelled:
        note = "This payment has been cancelled. Nothing is owed against it."
    elif settled:
        note = "Paid in full. Thank you."
    else:
        note = f"{cash(owed)} remains outstanding on this payment."

    issued_at = clock.format(clock.now(), DATE_TIME)
    closing = [
        note,
        "This receipt is issued electronically and is valid without a signature.",
        f"Issued {issued_at} ({school.timezone})" if school and issued_at else "",
        "Thank you for choosing School365ai.",
    ]

    body = f"""
    {issuer_band(number, issued_on)}
    {stamp}
    {pdf_design.spacer(16)}
    {pdf_design.side_by_side(billed, details, "Billed to", "Payment")}

    {pdf_design.section("Details")}
    {items}

    {pdf_design.spacer(12)}
    {pdf_design.totals_panel("Amount received", cash(paid), words)}
    {pdf_design.spacer(10)}
    {balances}
    {notes_block(payment)}
    {pdf_design.closing([line for line in closing if line])}
"""

    return pdf_design.page(
        number, body, footer=f"School365ai - Payment receipt {number} - {school.name if school else ''}",
    )


def notes_block(payment) -> str:
    if not payment.notes:
        return ""

    return f'{pdf_design.section("Notes")}<div class="note">{e(payment.notes)}</div>'


def label(choices, value: str) -> str:
    """The human name for a stored value - "Partially Paid" for "partial"."""
    return dict(choices.choices).get(value, value)
