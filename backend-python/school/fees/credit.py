"""A student's fee credit: step F6, "Credit balance" (docs/fees.md).

Credit is money a student paid that nothing is owed against yet. It is kept,
never refused or lost, and used for the student's next fees. Every movement
is a row of `student_fee_credits` with a signed amount, so a student's credit
in a currency is the sum of their rows in it, and the rows are its history.

Where it comes from:

- **released** - an installment paid ahead (falling due after today) that
  stopped applying: a route or class change, leaving, a fee cut. The F2
  reconcile cancels it and its paid amount moves here (school/fees/dues.py);
- **overpaid** - a receipt for more than the student owed (F3): the rest;
- **returned** - credit taken back off an installment it had paid, when a
  cancelled receipt needs it (below).

Where it goes:

- **applied** - paying the student's open dues, oldest first, in the same
  currency, automatically: whenever the reconcile runs and whenever credit
  is added. Every installment of a published fee is charged when it is
  published, so this pays ahead too. No receipt and no number: no money came
  in, and receipt numbers stay gapless;
- **refunded** - money handed back to the family, recorded by the office;
- **reversed** - a cancelled receipt taking back what it put here.

Cancelling a receipt takes back all of its money: what is still on the
installments it paid, and the rest - its overpaid part, and whatever was
released from those installments since - from the credit. When the credit no
longer holds enough, because it went on to pay other installments, those
installments give it back (newest first) and are owed again. Only money that
was refunded cannot come back, and then the receipt cannot be cancelled.

Every write here happens with the student's row locked, as the reconcile and
payments do, so the three take turns.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from django.db import transaction
from django.db.models import Sum
from django.utils import timezone
from rest_framework import serializers

from .. import audit, money
from ..enums import FeeCreditKind, FeeDueStatus
from ..errors import FeeReceiptCreditRefunded
from ..models import FeeReceipt, Student, StudentFeeCredit, StudentFeeDue
from .dues import OPEN, today_for
from .ledger import balance_of

MODULE = "fees"
ZERO = Decimal("0.00")


def balances(student_id: int) -> dict[str, Decimal]:
    """currency -> the student's credit in it, the currencies holding any."""
    rows = (
        StudentFeeCredit.objects.filter(student_id=student_id)
        .values("currency_code")
        .annotate(total=Sum("amount"))
        .order_by("currency_code")
    )

    return {row["currency_code"]: money.amount(row["total"]) for row in rows if row["total"]}


def balance(student_id: int, currency_code: str) -> Decimal:
    return balances(student_id).get(currency_code, ZERO)


def students_with_credit(student_ids) -> set[int]:
    """Those of the students holding credit in any currency - one query."""
    rows = (
        StudentFeeCredit.objects.filter(student_id__in=list(student_ids))
        .values("student_id", "currency_code")
        .annotate(total=Sum("amount"))
    )

    return {row["student_id"] for row in rows if row["total"] and row["total"] > 0}


def paid_from_credit(due_ids) -> dict[int, Decimal]:
    """due id -> what credit paid on it and still does: applied less
    returned, never more than the due holds now (it may have been released
    since)."""
    rows = (
        StudentFeeCredit.objects.filter(
            student_fee_due_id__in=list(due_ids), kind__in=(FeeCreditKind.APPLIED, FeeCreditKind.RETURNED)
        )
        .values("student_fee_due_id")
        .annotate(total=Sum("amount"))
    )

    return {row["student_fee_due_id"]: -money.amount(row["total"]) for row in rows}


def entry(due_or_student, kind: str, amount: Decimal, today: dt.date, now, **fields) -> StudentFeeCredit:
    """One credit row, about a due (when given one) or just a student."""
    is_due = isinstance(due_or_student, StudentFeeDue)

    return StudentFeeCredit(
        school_id=due_or_student.school_id,
        student_id=due_or_student.student_id if is_due else due_or_student.id,
        currency_code=due_or_student.currency_code if is_due else fields.pop("currency_code"),
        kind=kind,
        amount=amount,
        student_fee_due_id=due_or_student.id if is_due else None,
        entry_date=today,
        created_at=now,
        updated_at=now,
        **fields,
    )


def status_after(due: StudentFeeDue) -> str:
    """A due's status once its paid amount has moved (the receipts' rule)."""
    from .receipts import status_after as rule

    return rule(due)


class CreditService:
    # -- using it -------------------------------------------------------------

    @classmethod
    def apply(cls, student_ids, actor=None) -> dict[int, Decimal]:
        """Pays each student's open dues from their credit, oldest first, one
        currency at a time. Run inside the caller's transaction with the
        students' rows locked. Returns student id -> how much credit it used
        (only those it used any for)."""
        used: dict[int, Decimal] = {}
        holders = sorted(students_with_credit(student_ids))

        if not holders:
            return used

        with transaction.atomic():
            for student_id in holders:
                spent = cls.apply_one(student_id)

                if spent:
                    used[student_id] = spent

        return used

    @classmethod
    def apply_one(cls, student_id: int) -> Decimal:
        held = {currency: amount for currency, amount in balances(student_id).items() if amount > 0}

        if not held:
            return ZERO

        dues = [
            due
            for due in StudentFeeDue.objects.select_for_update()
            .filter(student_id=student_id, status__in=OPEN, currency_code__in=list(held))
            .order_by("due_date", "id")
            if balance_of(due) > 0
        ]

        if not dues:
            return ZERO

        now = timezone.now()
        today = today_for(dues[0].school_id)
        rows: list[StudentFeeCredit] = []
        changed: list[StudentFeeDue] = []
        spent = ZERO

        for due in dues:
            left = held[due.currency_code]

            if left <= 0:
                continue

            part = min(left, balance_of(due))
            held[due.currency_code] = left - part
            due.paid_amount = due.paid_amount + part
            due.status = status_after(due)
            due.updated_at = now
            changed.append(due)
            rows.append(entry(due, FeeCreditKind.APPLIED, -part, today, now))
            spent += part

        StudentFeeDue.objects.bulk_update(changed, ["paid_amount", "status", "updated_at"])
        StudentFeeCredit.objects.bulk_create(rows)

        return spent

    # -- taking it back for a cancelled receipt -------------------------------

    @classmethod
    def take_back(cls, receipt: FeeReceipt, needed: Decimal, now) -> dict:
        """Takes `needed` - the part of a cancelled receipt's money no longer
        on the installments it paid - off the student's credit, first freeing
        credit from installments it paid (newest first) when it holds too
        little. Refuses when even that is not enough: the money was refunded.
        Returns what it did, for the audit row."""
        if needed <= 0:
            return {}

        currency = receipt.currency_code
        today = today_for(receipt.school_id)
        short = needed - balance(receipt.student_id, currency)
        returned: list[dict] = []

        if short > 0:
            short, returned = cls.free(receipt, short, today, now)

        if short > 0:
            raise FeeReceiptCreditRefunded(money.formatted(short, currency))

        StudentFeeCredit.objects.create(
            school_id=receipt.school_id, student_id=receipt.student_id, currency_code=currency,
            kind=FeeCreditKind.REVERSED, amount=-needed, fee_receipt_id=receipt.id, entry_date=today,
            created_at=now, updated_at=now,
        )

        return {"credit_reversed": str(needed), "credit_returned_from": returned}

    @classmethod
    def free(cls, receipt: FeeReceipt, short: Decimal, today, now) -> tuple[Decimal, list[dict]]:
        """Takes credit back off the installments it paid, newest payment
        first, until `short` is covered or nothing is left to take."""
        applied = (
            StudentFeeCredit.objects.filter(
                student_id=receipt.student_id, currency_code=receipt.currency_code,
                kind__in=(FeeCreditKind.APPLIED, FeeCreditKind.RETURNED),
            )
            .values("student_fee_due_id")
            .annotate(total=Sum("amount"))
        )
        on_due = {row["student_fee_due_id"]: -row["total"] for row in applied if row["total"] and row["total"] < 0}
        dues = (
            StudentFeeDue.objects.select_for_update()
            .filter(pk__in=list(on_due), status__in=(FeeDueStatus.PAID, FeeDueStatus.PARTIAL), paid_amount__gt=0)
            .order_by("-due_date", "-id")
        )
        changed: list[StudentFeeDue] = []
        rows: list[StudentFeeCredit] = []
        returned: list[dict] = []

        for due in dues:
            if short <= 0:
                break

            give = min(short, due.paid_amount, on_due[due.id])
            due.paid_amount = due.paid_amount - give
            due.status = status_after(due)
            due.updated_at = now
            changed.append(due)
            rows.append(entry(due, FeeCreditKind.RETURNED, give, today, now))
            returned.append({"due_id": due.id, "amount": str(give)})
            short -= give

        if changed:
            StudentFeeDue.objects.bulk_update(changed, ["paid_amount", "status", "updated_at"])
            StudentFeeCredit.objects.bulk_create(rows)

        return short, returned

    # -- refunds ----------------------------------------------------------------

    @classmethod
    def refund(cls, student: Student, data: dict, actor, request=None) -> StudentFeeCredit:
        """Records money handed back to the family out of their credit."""
        currency = data["currency_code"]
        amount: Decimal = data["amount"]

        with transaction.atomic():
            Student.objects.select_for_update().filter(pk=student.id).first()
            held = balance(student.id, currency)

            if held <= 0:
                raise serializers.ValidationError({
                    "amount": [f"{student.name} has no credit in {currency} to refund."]
                })

            if amount > held:
                raise serializers.ValidationError({
                    "amount": [f"{student.name} has only {money.formatted(held, currency)} in credit."]
                })

            now = timezone.now()
            row = StudentFeeCredit.objects.create(
                school_id=student.school_id, student_id=student.id, currency_code=currency,
                kind=FeeCreditKind.REFUNDED, amount=-amount, entry_date=data["refund_date"],
                payment_mode=data["payment_mode"], reference=data["reference"], note=data["reason"],
                created_by_id=getattr(actor, "id", None), created_at=now, updated_at=now,
            )

            audit.record(
                actor=actor, action="fee_credit.refunded", module=MODULE, entity_type="student_fee_credit",
                entity_id=row.id, school_id=student.school_id,
                old={"credit": str(held)},
                new={
                    "student_id": student.id,
                    "amount": str(amount),
                    "currency_code": currency,
                    "credit": str(held - amount),
                    "payment_mode": data["payment_mode"],
                    "reason": data["reason"],
                },
                request=request,
            )

        return row

    # -- reading ----------------------------------------------------------------

    @staticmethod
    def history(student_id: int):
        return (
            StudentFeeCredit.objects.filter(student_id=student_id)
            .select_related("student_fee_due", "fee_receipt", "created_by")
            .order_by("-entry_date", "-id")
        )

