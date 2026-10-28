"""Taking money at the office: step F3, "Collection & receipts" (docs/fees.md).

A receipt is one payment from one student. Recording one, in one
transaction:

1. lock the student (the F2 reconcile locks the same row, so a payment and a
   reconcile of the same student take turns rather than overwrite each
   other), then the dues the payment touches;
2. work out what goes where - spread oldest first (due date, then id), or the
   amounts the office chose per installment - refusing anything that would
   overpay a due, pay one that is not owed, or (with part payments switched
   off) leave one half paid;
3. take the next number for the school and the academic year the receipt's
   date falls in, from the counter row locked with SELECT ... FOR UPDATE.
   The counter is read and bumped inside the payment's own transaction, so
   two clerks saving together get consecutive numbers, and a payment that
   fails rolls its number back with it - no gaps, no reuse. The unique key
   on (school, receipt number) is the last line of defence;
4. write the receipt, its allocations, the dues' new paid amounts and
   statuses, and the audit row.

Cancelling takes each allocation back off its due, recomputes the due's
status, keeps the receipt (number, allocations and all) stamped cancelled,
and runs the F2 reconcile over the years those dues belong to so the ledger
is what it would have been had the money never been taken.

A due's status after money moves on it: paid when nothing is left to pay,
partial while something has been paid, pending when nothing has. A due that
is `cancelled` or `waived` keeps that status - only its paid amount moves.
(The reconcile never cancels a due with money on it, so a cancelled due can
hold money only from a receipt that has itself been cancelled since; and a
waiver is a decision somebody made, F4's to undo, not arithmetic.)
"""

from __future__ import annotations

from decimal import Decimal

from django.db import IntegrityError, transaction
from django.db.models import DecimalField, F, OuterRef, Subquery, Sum, Value
from django.db.models.functions import Coalesce
from django.utils import timezone
from rest_framework import serializers

from .. import audit, modules, money, queue
from ..enums import FeeDueStatus, FeeReceiptStatus
from ..errors import FeeReceiptCancelled
from ..models import (
    AcademicYear,
    FeeReceipt,
    FeeReceiptAllocation,
    FeeReceiptSequence,
    Student,
    StudentFeeDue,
)
from .dues import OPEN, FeeDueService, today_for
from .ledger import balance_of
from .requests import plain

MODULE = "fees"
ZERO = Decimal("0.00")
MONEY = DecimalField(max_digits=14, decimal_places=2)

# The queued job that emails a receipt to the guardian (school/jobs.py).
EMAIL_JOB = "fee_receipt_email"


# -- small rules ----------------------------------------------------------------


def number_for(year: AcademicYear, n: int) -> str:
    """"RCPT-2026-27-00001": the year's name with every run of anything but
    letters and digits made a single hyphen, then the number."""
    token = "".join(char if char.isalnum() else " " for char in year.name).split()

    return f"RCPT-{'-'.join(token)}-{n:05d}"


def status_after(due: StudentFeeDue) -> str:
    """A due's status once its paid amount has moved. Cancelled and waived
    are decisions, not arithmetic, and stay as they are."""
    if due.status in (FeeDueStatus.CANCELLED, FeeDueStatus.WAIVED):
        return due.status

    if balance_of(due) <= 0:
        return FeeDueStatus.PAID

    if due.paid_amount > 0:
        return FeeDueStatus.PARTIAL

    return FeeDueStatus.PENDING


def outstanding(student_id: int, currency_code: str | None = None) -> Decimal:
    """What a student still owes, every year, pending and part-paid dues -
    in one currency when one is named."""
    dues = StudentFeeDue.objects.filter(student_id=student_id, status__in=OPEN)

    if currency_code is not None:
        dues = dues.filter(currency_code=currency_code)

    total = dues.aggregate(
        total=Sum(F("amount") - F("discount_amount") - F("paid_amount"), output_field=MONEY)
    )["total"]

    return money.amount(total)


def outstanding_subquery() -> Coalesce:
    """The same, as a correlated subquery on a receipt's student - so a page
    of receipts costs one statement for it, not one per row."""
    total = (
        StudentFeeDue.objects.filter(student_id=OuterRef("student_id"), status__in=OPEN)
        .order_by()
        .values("student_id")
        .annotate(total=Sum(F("amount") - F("discount_amount") - F("paid_amount"), output_field=MONEY))
        .values("total")[:1]
    )

    return Coalesce(Subquery(total, output_field=MONEY), Value(ZERO), output_field=MONEY)


def refuse(field: str, message: str) -> None:
    raise serializers.ValidationError({field: [message]})


class FeeReceiptService:
    WITH = ("student", "academic_year", "received_by", "cancelled_by", "school")

    # -- reading ----------------------------------------------------------------

    @classmethod
    def query(cls):
        return (
            FeeReceipt.objects.select_related(*cls.WITH)
            .prefetch_related("allocations__student_fee_due__fee_head", "allocations__student_fee_due__fee_installment")
            .annotate(student_balance=outstanding_subquery())
        )

    @classmethod
    def load(cls, receipt_id: int) -> FeeReceipt:
        return cls.query().get(pk=receipt_id)

    # -- recording a payment ------------------------------------------------------

    @classmethod
    def create(cls, data: dict, actor, request=None) -> tuple[FeeReceipt, bool]:
        """Records a payment. Returns the receipt and whether an email to the
        guardian was queued."""
        student: Student = data["student"]
        year: AcademicYear = data["academic_year"]
        amount: Decimal = data["amount"]
        part_payments = modules.setting(student.school_id, MODULE, "allow_part_payment")

        with transaction.atomic():
            # The same row the reconcile locks: the two take turns.
            Student.objects.select_for_update().filter(pk=student.id).first()

            if data["allocations"] is None:
                plan = cls.spread(student, amount, part_payments)
            else:
                plan = cls.chosen(student, amount, data["allocations"], part_payments)

            currency = plan[0][0].currency_code
            # As at the receipt, in its currency - what the PDF prints for
            # ever after, however the account moves later.
            before = outstanding(student.id, currency)
            number = cls.next_number(student.school_id, year)
            now = timezone.now()

            receipt = FeeReceipt.objects.create(
                school_id=student.school_id,
                student_id=student.id,
                academic_year_id=year.id,
                receipt_number=number,
                receipt_date=data["receipt_date"],
                amount=amount,
                currency_code=currency,
                balance_before=before,
                payment_mode=data["payment_mode"],
                reference=data["reference"],
                note=data["note"],
                received_by_id=getattr(actor, "id", None),
                status=FeeReceiptStatus.VALID,
                created_at=now,
                updated_at=now,
            )

            FeeReceiptAllocation.objects.bulk_create([
                FeeReceiptAllocation(
                    fee_receipt_id=receipt.id, student_fee_due_id=due.id, amount=part, created_at=now, updated_at=now
                )
                for due, part in plan
            ])

            for due, part in plan:
                due.paid_amount = due.paid_amount + part
                due.status = status_after(due)
                due.updated_at = now

            StudentFeeDue.objects.bulk_update([due for due, _ in plan], ["paid_amount", "status", "updated_at"])

            audit.record(
                actor=actor, action="fee_receipt.created", module=MODULE, entity_type="fee_receipt",
                entity_id=receipt.id, school_id=student.school_id,
                new={
                    "receipt_number": number,
                    "amount": str(amount),
                    "currency_code": currency,
                    "payment_mode": data["payment_mode"],
                    "allocations": [{"due_id": due.id, "amount": str(part)} for due, part in plan],
                },
                request=request,
            )

            queued = False

            if data.get("email_to_guardian") and student.guardian_email:
                # Written in this transaction: queued if and only if the
                # payment is (school/queue.py).
                push_email(receipt.id)
                queued = True

        return receipt, queued

    @classmethod
    def payable(cls, student: Student, due_ids=None) -> list[StudentFeeDue]:
        """The student's dues, locked, oldest first: every one still owed,
        plus any named in `due_ids` whatever its status (so a paid or waived
        one can be named in the refusal rather than called unknown)."""
        rows = StudentFeeDue.objects.select_for_update().filter(student_id=student.id)

        if due_ids is None:
            rows = rows.filter(status__in=OPEN)
        else:
            rows = rows.filter(pk__in=due_ids)

        return list(rows.order_by("due_date", "id"))

    @classmethod
    def spread(cls, student: Student, amount: Decimal, part_payments: bool) -> list[tuple[StudentFeeDue, Decimal]]:
        """The amount over what the student owes, oldest first."""
        dues = [due for due in cls.payable(student) if balance_of(due) > 0]
        owed = sum((balance_of(due) for due in dues), ZERO)

        if not dues:
            refuse("amount", f"{student.name} owes nothing right now.")

        currencies = sorted({due.currency_code for due in dues})

        if len(currencies) > 1:
            # Never added together - CLAUDE.md rule 5.
            refuse(
                "allocations",
                f"{student.name} owes in more than one currency ({', '.join(currencies)}). "
                "Choose the installments to pay, one currency at a time.",
            )

        if amount > owed:
            refuse(
                "amount",
                f"This is more than {student.name} owes ({money.formatted(owed, currencies[0])}). "
                "Advance payments are not taken.",
            )

        plan: list[tuple[StudentFeeDue, Decimal]] = []
        left = amount

        for due in dues:
            if left <= 0:
                break

            part = min(left, balance_of(due))
            plan.append((due, part))
            left -= part

        if not part_payments and plan and plan[-1][1] < balance_of(plan[-1][0]):
            refuse("amount", PART_PAYMENTS_OFF)

        return plan

    @classmethod
    def chosen(cls, student: Student, amount: Decimal, allocations, part_payments: bool):
        """The amounts the office chose, installment by installment."""
        ids = [due_id for due_id, _ in allocations]
        found = {due.id: due for due in cls.payable(student, ids)}
        problems: list[str] = []
        plan: list[tuple[StudentFeeDue, Decimal]] = []
        seen: set[int] = set()
        partly = False

        for due_id, part in allocations:
            due = found.get(due_id)

            if due is None:
                problems.append("The selected installment is invalid.")
                continue

            if due_id in seen:
                problems.append(f'Installment "{due.label}" is listed more than once.')
                continue

            seen.add(due_id)

            if due.status not in OPEN:
                problems.append(NOT_PAYABLE.get(due.status, 'Installment "{label}" can\'t be paid.').format(
                    label=due.label
                ))
                continue

            balance = balance_of(due)

            if part > balance:
                problems.append(
                    f'Installment "{due.label}" has only {money.formatted(balance, due.currency_code)} left to pay.'
                )
                continue

            partly = partly or part < balance
            plan.append((due, part))

        if not problems and len({due.currency_code for due, _ in plan}) > 1:
            problems.append("Every installment on one receipt must be in the same currency.")

        if problems:
            raise serializers.ValidationError({"allocations": problems})

        total = sum((part for _, part in plan), ZERO)

        if total != amount:
            refuse(
                "allocations",
                f"The amounts against each installment add up to {plain(total)} but the payment is {plain(amount)}.",
            )

        if partly and not part_payments:
            refuse("allocations", PART_PAYMENTS_OFF)

        # Applied oldest first, as the receipt lists them.
        return sorted(plan, key=lambda pair: (pair[0].due_date, pair[0].id))

    @staticmethod
    def next_number(school_id: int, year: AcademicYear) -> str:
        """The next receipt number for a school's academic year, taken from
        the counter row locked for the rest of the transaction."""
        counter = FeeReceiptSequence.objects.select_for_update().filter(
            school_id=school_id, academic_year_id=year.id
        ).first()

        if counter is None:
            now = timezone.now()

            try:
                # Its own savepoint: if another payment created the row a
                # moment ago, the unique key refuses this insert and the
                # transaction carries on with theirs.
                with transaction.atomic():
                    FeeReceiptSequence.objects.create(
                        school_id=school_id, academic_year_id=year.id, last_number=0, created_at=now, updated_at=now
                    )
            except IntegrityError:
                pass

            counter = FeeReceiptSequence.objects.select_for_update().get(school_id=school_id, academic_year_id=year.id)

        counter.last_number += 1
        counter.updated_at = timezone.now()
        counter.save(update_fields=["last_number", "updated_at"])

        return number_for(year, counter.last_number)

    # -- cancelling ---------------------------------------------------------------

    @classmethod
    def cancel(cls, receipt: FeeReceipt, reason: str, actor, request=None) -> FeeReceipt:
        with transaction.atomic():
            receipt = FeeReceipt.objects.select_for_update().get(pk=receipt.pk)

            if receipt.status == FeeReceiptStatus.CANCELLED:
                raise FeeReceiptCancelled()

            Student.objects.select_for_update().filter(pk=receipt.student_id).first()

            allocations = list(FeeReceiptAllocation.objects.filter(fee_receipt_id=receipt.id))
            dues = {
                due.id: due
                for due in StudentFeeDue.objects.select_for_update()
                .filter(pk__in=[row.student_fee_due_id for row in allocations])
                .order_by("id")
            }
            now = timezone.now()

            for row in allocations:
                due = dues[row.student_fee_due_id]
                # Never below zero, whatever happened to the due since.
                due.paid_amount = max(ZERO, due.paid_amount - row.amount)
                due.status = status_after(due)
                due.updated_at = now

            if dues:
                StudentFeeDue.objects.bulk_update(list(dues.values()), ["paid_amount", "status", "updated_at"])

            before = {"status": receipt.status}
            receipt.status = FeeReceiptStatus.CANCELLED
            receipt.cancelled_at = now
            receipt.cancelled_by_id = getattr(actor, "id", None)
            receipt.cancel_reason = reason
            receipt.updated_at = now
            receipt.save(update_fields=["status", "cancelled_at", "cancelled_by", "cancel_reason", "updated_at"])

            audit.record(
                actor=actor, action="fee_receipt.cancelled", module=MODULE, entity_type="fee_receipt",
                entity_id=receipt.id, school_id=receipt.school_id, old=before,
                new={
                    "status": receipt.status,
                    "receipt_number": receipt.receipt_number,
                    "reason": reason,
                    "allocations": [
                        {"due_id": row.student_fee_due_id, "amount": str(row.amount)} for row in allocations
                    ],
                },
                request=request,
            )

            cls.reconcile_after_cancel(receipt, {due.academic_year_id for due in dues.values()}, actor, request)

        return receipt

    @staticmethod
    def reconcile_after_cancel(receipt: FeeReceipt, year_ids: set[int], actor, request) -> None:
        """A due that is unpaid again is the reconcile's once more: one no
        longer expected (the student moved class, say) and falling due after
        today is cancelled, exactly as F2 would have done had the money never
        been taken. Anything already due stays owed. Years that have ended
        are left alone, as F2 leaves them."""
        today = today_for(receipt.school_id)
        years = AcademicYear.objects.filter(pk__in=year_ids, end_date__gte=today).order_by("start_date")

        for year in years:
            result = FeeDueService.sync_many([receipt.student_id], year)
            FeeDueService.audit(
                result, entity_type="fee_receipt", entity_id=receipt.id, school_id=receipt.school_id, actor=actor,
                request=request,
            )

    # -- emailing -----------------------------------------------------------------

    @staticmethod
    def queue_email(receipt: FeeReceipt) -> None:
        if not receipt.student.guardian_email:
            refuse("guardian_email", "This student has no guardian email address.")

        push_email(receipt.id)


def push_email(receipt_id: int) -> None:
    # Imported here: school/jobs.py registers the handler, and reaches back
    # into this module when it runs.
    from .. import jobs  # noqa: F401

    queue.push(EMAIL_JOB, {"receipt_id": receipt_id})


PART_PAYMENTS_OFF = "Part payments are switched off for this school - pay each installment in full."

NOT_PAYABLE = {
    FeeDueStatus.PAID: 'Installment "{label}" is already paid.',
    FeeDueStatus.WAIVED: 'Installment "{label}" was waived and can\'t be paid.',
    FeeDueStatus.CANCELLED: 'Installment "{label}" was cancelled and can\'t be paid.',
}
