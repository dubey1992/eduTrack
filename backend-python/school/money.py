"""What a payment is worth, and what is still owed on it.

Every figure here is a `Decimal`, never a float. The column is
`decimal(12,2)`, the numbers are money, and a float would put a
half-a-hundredth-of-a-rupee error into a ledger that somebody eventually
reconciles by hand. Laravel's version works in floats and gets away with it
because the values are small; that is luck rather than design, and it is not
worth copying.

There is no currency conversion anywhere, here or elsewhere. Each payment
carries the currency its school used at the time (CLAUDE.md rule 5), and
totals are grouped by currency rather than blended.
"""

from __future__ import annotations

from decimal import Decimal

from .enums import PaymentStatus

ZERO = Decimal("0.00")


def amount(value) -> Decimal:
    """Reads a figure from a request or a column as money."""
    if value is None:
        return ZERO

    return Decimal(str(value)).quantize(Decimal("0.01"))


def status_for(total: Decimal, paid: Decimal, requested: str | None = None) -> str:
    """The standing of a payment, derived from its figures.

    Derived rather than taken at face value, so a payment can never read
    "Paid" with a balance outstanding. Cancelled is the exception: it is a
    decision somebody made, not an arithmetic result.
    """
    if requested == PaymentStatus.CANCELLED:
        return PaymentStatus.CANCELLED

    if paid <= ZERO:
        return PaymentStatus.PENDING

    if paid >= total:
        return PaymentStatus.PAID

    return PaymentStatus.PARTIAL


def paid_amount_for(data: dict, total: Decimal, fallback: Decimal = ZERO) -> Decimal:
    """What was actually received.

    When the client sends no figure, the status it asked for says what it
    meant: "Paid" means all of it, "Pending" means none of it yet. That keeps
    the plain "just mark it paid" path working without forcing every caller to
    restate the amount twice.

    Never more than the agreed amount, so lowering the amount on an existing
    payment cannot leave more paid than is owed.
    """
    if data.get("paid_amount") is not None:
        return min(amount(data["paid_amount"]), total)

    requested = data.get("status")

    if requested == PaymentStatus.PAID:
        return total

    if requested in (PaymentStatus.PENDING, PaymentStatus.CANCELLED):
        return ZERO

    return min(fallback, total)


def remaining(total: Decimal, paid: Decimal, status: str) -> Decimal:
    """What is still owed. Nothing is owed on a cancelled payment."""
    if status == PaymentStatus.CANCELLED:
        return ZERO

    return max(ZERO, total - paid)


def formatted(value: Decimal, currency_code: str) -> str:
    """"INR 4,500.00" - the form a receipt prints.

    The code, not a symbol. Schools operate in different countries and a bare
    currency glyph is ambiguous between several of them.
    """
    return f"{currency_code} {value:,.2f}"
