"""What a parent sees of their child's fees in the Family app
(docs/parent-student-app.md, F3).

Read only: the app takes no payments (decision D4). It shows what the
office's own statement shows - built from the same ledger, so a parent and
the accounts clerk never see two different numbers - in a parent's words:

- each instalment with its due date and where it stands (paid, part paid,
  due, overdue, waived); a cancelled one is not the family's concern and is
  left out;
- every receipt of the year, a cancelled one marked so;
- the credit the child holds, if any;
- how to pay at this school, as the school wrote it in its Fees settings.
"""

from __future__ import annotations

from decimal import Decimal

from . import modules
from .enums import FeeDueStatus, FeeReceiptStatus
from .fees import ledger
from .fees.dues import today_for
from .models import FeeReceipt, Student

MODULE = "fees"

# A parent's words for where an instalment stands.
PAID = "paid"
PART_PAID = "part_paid"
DUE = "due"
OVERDUE = "overdue"
WAIVED = "waived"


def money(amount: Decimal) -> str:
    return f"{amount:.2f}"


def standing(due, today) -> str:
    """Where one instalment stands, as a parent reads it."""
    if due.status == FeeDueStatus.WAIVED:
        return WAIVED
    if due.status == FeeDueStatus.PAID or ledger.balance_of(due) <= 0:
        return PAID
    if ledger.is_overdue(due, today):
        return OVERDUE
    if due.status == FeeDueStatus.PARTIAL:
        return PART_PAID
    return DUE


def how_to_pay(school) -> dict:
    """The school's own words on paying: counter hours, bank and UPI, and
    the office's phone. Empty entries are None, so the app shows only what
    the school filled in."""
    settings = modules.settings_for(school.id, MODULE)

    return {
        "counter_hours": settings["pay_counter_hours"] or None,
        "bank_details": settings["pay_bank_details"] or None,
        "upi_id": settings["pay_upi_id"] or None,
        "office_phone": school.phone or None,
    }


def pay_by_upi(student: Student) -> dict:
    """What "Pay with any UPI app" fills in besides the school's UPI ID
    (docs/mobile-apps-review.md, 6.4): whom the money goes to, and a note
    that tells the office whose fees it is."""
    return {
        "payee_name": student.school.name,
        "payment_note": f"Fees - {student.name} ({student.admission_number})",
    }


def fees_of(student: Student) -> dict:
    """The child's fees for their current year, for the Fees tab."""
    today = today_for(student.school_id)
    year = ledger.default_year(student)

    if year is None:
        return {
            "academic_year": None, "currency_code": student.school.currency_code, "totals": None,
            "installments": [], "receipts": [], "credit": "0.00", "how_to_pay": how_to_pay(student.school),
            **pay_by_upi(student),
        }

    found = ledger.statement(student, year, today)
    currency = found["currency_code"]
    totals = found["totals"]

    return {
        "academic_year": {"id": year.id, "name": year.name},
        "currency_code": currency,
        "totals": {
            "charged": money(totals["charged"]),
            "discount": money(totals["discount"]),
            "paid": money(totals["paid"]),
            "balance": money(totals["balance"]),
            "overdue": money(totals["overdue"]),
        },
        "installments": [
            {
                "id": due.id,
                "label": due.label,
                "due_date": due.due_date.isoformat(),
                "amount": money(due.amount),
                "discount": money(due.discount_amount),
                "paid": money(due.paid_amount),
                "balance": money(ledger.balance_of(due)),
                "status": standing(due, today),
            }
            for due in found["dues"]
            if due.status != FeeDueStatus.CANCELLED
        ],
        "receipts": [
            {
                "id": receipt.id,
                "number": receipt.receipt_number,
                "date": receipt.receipt_date.isoformat(),
                "amount": money(receipt.amount),
                "currency_code": receipt.currency_code,
                "payment_mode": receipt.payment_mode,
                "cancelled": receipt.status == FeeReceiptStatus.CANCELLED,
            }
            for receipt in found["receipts"]
        ],
        "credit": money(found["credit"].get(currency, Decimal("0"))),
        "how_to_pay": how_to_pay(student.school),
        **pay_by_upi(student),
    }


def statement_of(student: Student) -> dict | None:
    """The year's statement, for its PDF; None when the child has no year."""
    year = ledger.default_year(student)

    if year is None:
        return None

    return ledger.statement(student, year, today_for(student.school_id))


def receipt_of(student: Student, receipt_id: int) -> FeeReceipt | None:
    """One of this child's receipts, loaded as the PDF needs it; None for
    any other receipt, so another family's is never confirmed to exist."""
    from .fees.receipts import FeeReceiptService

    if not FeeReceipt.objects.filter(pk=receipt_id, student_id=student.id).exists():
        return None

    return FeeReceiptService.load(receipt_id)
