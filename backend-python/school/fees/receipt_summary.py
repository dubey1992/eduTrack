"""The classic printed receipt's money summary (docs/document-styles.md,
decided 2026-11-17), worked out once - when the payment is taken - and frozen
on the receipt.

A school's printed receipt book reads like this:

    Old Fee     Total Amount
    Discount    Back Dues
    Late Fee
    Net Amount Till <month>
    Paid Amount
    Dues Amount

Mapped onto this product's ledger (fees/ledger.py: owed on a due = amount -
discount - paid; waived and cancelled dues owe nothing):

- **The lines** are the installments this payment touches. Each shows its
  full charge (`charge_amount`); **Total Amount** is their sum.
- **Discount** is the discount on those lines; **Late Fee** the late fines
  among them (a fine is a line of its own in the ledger, F4, but a printed
  receipt carries it in the summary, not as a fee line).
- **Paid Earlier** is what had already been paid on those lines by earlier
  receipts. Printed books have no such row; it is printed only when it is not
  zero, so a part-paid installment finished today adds up.
- **Back Dues** is what was still owed on the same year's earlier
  installments that this payment did not touch, falling due up to the month
  the payment runs to.
- **Old Fee** is the same for earlier academic years.
- **Net Amount Till <month>** = Total - Discount + Late Fee - Paid Earlier +
  Back Dues + Old Fee: everything owed up to that month, before this payment.
- **Dues Amount** = Net - Paid (what goes to credit, F6, is not paid
  against it). Installments falling due after the month are not counted
  anywhere - a receipt for December says nothing about March.

Pure: it is handed dues and returns figures, so the rules are tested without
a database.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass
from decimal import Decimal

from ..enums import FeeDueKind, FeeDueStatus

ZERO = Decimal("0.00")
SETTLED = (FeeDueStatus.WAIVED, FeeDueStatus.CANCELLED)


@dataclass(frozen=True)
class Summary:
    total: Decimal
    discount: Decimal
    late_fee: Decimal
    paid_earlier: Decimal
    back_dues: Decimal
    old_fee: Decimal
    net: Decimal
    till: str | None

    def dues_after(self, paid_against_dues: Decimal) -> Decimal:
        return self.net - paid_against_dues


def owed(due) -> Decimal:
    if due.status in SETTLED:
        return ZERO

    return max(ZERO, due.amount - due.discount_amount - due.paid_amount)


def is_transport(due) -> bool:
    head = getattr(due, "fee_head", None)
    return bool(getattr(head, "is_transport", False))


def installment_label(due) -> str:
    """"January 2026": the installment's own name, else the due's label
    with its fee type taken off."""
    installment = getattr(due, "fee_installment", None)

    if installment is not None and installment.label:
        return installment.label

    prefix = f"{due.fee_head.name} - "

    return due.label[len(prefix):] if due.label.startswith(prefix) else due.label


def summarize(paid_dues: list, other_open_dues: list, *, year_id: int, receipt_date: dt.date) -> Summary:
    """The summary, from the dues as they stand **before** the payment is
    applied.

    `paid_dues` are the dues this payment touches; `other_open_dues` every
    other due of the student in the receipt's currency that may still owe
    something. `year_id` is the receipt's academic year: dues of any other
    year are Old Fee.
    """
    lines = [due for due in paid_dues if due.kind != FeeDueKind.LATE_FINE]
    fines = [due for due in paid_dues if due.kind == FeeDueKind.LATE_FINE]

    total = sum((due.amount for due in lines), ZERO)
    late_fee = sum((due.amount for due in fines), ZERO)
    discount = sum((due.discount_amount for due in paid_dues), ZERO)
    paid_earlier = sum((due.paid_amount for due in paid_dues), ZERO)

    # The month the receipt runs to: the latest installment it pays. A
    # payment that pays only fines runs to the latest fine; one that pays
    # nothing (all credit) runs to its own date.
    # On the same date, a school fee names the month rather than a bus fee,
    # whose installments are often named for the route.
    last = max(lines or fines, key=lambda due: (due.due_date, not is_transport(due), due.id), default=None)
    till_date = last.due_date if last is not None else receipt_date
    till = installment_label(last) if last is not None else None

    touched = {due.id for due in paid_dues}
    back_dues = ZERO
    old_fee = ZERO

    for due in other_open_dues:
        if due.id in touched or due.due_date > till_date:
            continue

        if due.academic_year_id == year_id:
            back_dues += owed(due)
        else:
            old_fee += owed(due)

    net = total - discount + late_fee - paid_earlier + back_dues + old_fee

    return Summary(
        total=total, discount=discount, late_fee=late_fee, paid_earlier=paid_earlier,
        back_dues=back_dues, old_fee=old_fee, net=net, till=till,
    )
