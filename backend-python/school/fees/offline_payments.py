"""Fees taken at the counter while the internet was down (docs/offline-web.md, O4).

A trusted computer takes cash or a cheque against the dues it kept, gives
the family a provisional receipt (P-<computer>-<n>) and sends the payment
when the line is back. Here it becomes:

- the real receipt, straight away, when the dues it was taken for are still
  owed and the day's books are open - the same FeeReceiptService.create a
  payment at the counter goes through, so nothing about a receipt differs;
- otherwise a payment "to settle", with what was found, for an Accountant or
  School Admin to keep on the student's account (a receipt now, paying what
  is owed and holding the rest as credit) or to record as handed back.

Sending the same payment twice records it once: the computer's client_id is
unique per school. Nothing here is ever deleted.
"""

from __future__ import annotations

from django.db import IntegrityError, transaction
from django.utils import timezone
from rest_framework import serializers

from .. import audit
from ..clock import SchoolClock
from ..enums import OfflineFeePaymentStatus, UserRole
from ..errors import ApiError, OfflinePaymentSettled
from ..models import OfflineFeePayment, Student
from . import lock
from .receipts import FeeReceiptService
from .requests import NOTE_MAX, year_covering

MODULE = "fees"

# Who settles a payment that could not become a receipt (decided 2026-11-28).
SETTLERS = (UserRole.SCHOOL_ADMIN, UserRole.GROUP_ADMIN, UserRole.ACCOUNTANT)


def receipt_note(note: str | None, provisional_number: str, taken_on) -> str:
    """The receipt's note: the counter's own, then where the money came from."""
    origin = f"Taken offline on {taken_on.isoformat()} as {provisional_number}."

    if not note:
        return origin

    return f"{note[: NOTE_MAX - len(origin) - 1]} {origin}"


def problem_text(failure: Exception) -> str:
    """Why a payment could not become a receipt, in the words a person reads."""
    if isinstance(failure, ApiError):
        return failure.message[:1000]

    detail = getattr(failure, "detail", None)
    messages: list[str] = []

    if isinstance(detail, dict):
        for value in detail.values():
            messages.extend(str(message) for message in (value if isinstance(value, list) else [value]))
    elif isinstance(detail, list):
        messages.extend(str(message) for message in detail)
    else:
        messages.append(str(failure))

    return " ".join(messages)[:1000]


class OfflineFeePaymentService:
    WITH = ("student", "taken_by", "settled_by", "fee_receipt")

    @classmethod
    def query(cls):
        return OfflineFeePayment.objects.select_related(*cls.WITH)

    @classmethod
    def record(cls, data: dict, actor, request=None) -> tuple[OfflineFeePayment, bool]:
        """Records a payment sent from the counter. Returns it and whether it
        is new - False when this computer had sent it before."""
        student: Student = data["student"]
        found = cls.query().filter(school_id=student.school_id, client_id=data["client_id"]).first()

        if found is not None:
            return found, False

        allocations = data["allocations"]
        now = timezone.now()

        try:
            with transaction.atomic():
                payment = OfflineFeePayment.objects.create(
                    school_id=student.school_id,
                    student_id=student.id,
                    client_id=data["client_id"],
                    provisional_number=data["provisional_number"],
                    receipt_date=data["receipt_date"],
                    amount=data["amount"],
                    currency_code=student.school.currency_code,
                    payment_mode=data["payment_mode"],
                    reference=data["reference"],
                    note=data["note"],
                    allocations=(
                        None
                        if allocations is None
                        else [{"due_id": due_id, "amount": str(part)} for due_id, part in allocations]
                    ),
                    taken_by_id=getattr(actor, "id", None),
                    taken_at=data["taken_at"],
                    status=OfflineFeePaymentStatus.TO_SETTLE,
                    created_at=now,
                    updated_at=now,
                )

                try:
                    # A savepoint: a receipt refused part way leaves nothing behind.
                    with transaction.atomic():
                        receipt, _ = FeeReceiptService.create(
                            {
                                **data,
                                "note": receipt_note(data["note"], data["provisional_number"], data["receipt_date"]),
                                "email_to_guardian": False,
                            },
                            actor,
                            request,
                        )
                except (serializers.ValidationError, ApiError) as failure:
                    payment.problem = problem_text(failure)
                else:
                    payment.status = OfflineFeePaymentStatus.RECEIPTED
                    payment.fee_receipt_id = receipt.id
                    payment.currency_code = receipt.currency_code

                payment.save(update_fields=["status", "problem", "fee_receipt_id", "currency_code"])

                audit.record(
                    actor=actor,
                    action="offline_fee_payment.received",
                    module=MODULE,
                    entity_type="offline_fee_payment",
                    entity_id=payment.id,
                    school_id=student.school_id,
                    new={
                        "provisional_number": payment.provisional_number,
                        "student_id": student.id,
                        "amount": str(payment.amount),
                        "currency_code": payment.currency_code,
                        "payment_mode": payment.payment_mode,
                        "status": payment.status,
                        "fee_receipt_id": payment.fee_receipt_id,
                    },
                    request=request,
                )
        except IntegrityError:
            # The same payment, sent twice at once: the other request won.
            return cls.query().get(school_id=student.school_id, client_id=data["client_id"]), False

        return cls.query().get(pk=payment.id), True

    @classmethod
    def settle(cls, payment: OfflineFeePayment, data: dict, actor, request=None) -> OfflineFeePayment:
        """Keeps the money on the student's account, or records it handed back."""
        with transaction.atomic():
            payment = OfflineFeePayment.objects.select_for_update().get(pk=payment.pk)

            if payment.status != OfflineFeePaymentStatus.TO_SETTLE:
                raise OfflinePaymentSettled("This payment has already been settled.")

            if data["action"] == "credit":
                student = Student.objects.select_related("school").get(pk=payment.student_id)
                payment.fee_receipt_id = cls.receipt_now(payment, student, data["reason"], actor, request).id
                payment.status = OfflineFeePaymentStatus.CREDITED
            else:
                payment.status = OfflineFeePaymentStatus.REFUNDED
                payment.refund_mode = data["refund_mode"]
                payment.refund_reference = data["reference"]

            now = timezone.now()
            payment.settle_note = data["reason"]
            payment.settled_by_id = getattr(actor, "id", None)
            payment.settled_at = now
            payment.updated_at = now
            payment.save()

            audit.record(
                actor=actor,
                action=f"offline_fee_payment.{payment.status}",
                module=MODULE,
                entity_type="offline_fee_payment",
                entity_id=payment.id,
                school_id=payment.school_id,
                old={"status": OfflineFeePaymentStatus.TO_SETTLE.value},
                new={
                    "status": payment.status,
                    "fee_receipt_id": payment.fee_receipt_id,
                    "refund_mode": payment.refund_mode,
                    "reason": payment.settle_note,
                },
                request=request,
            )

        return cls.query().get(pk=payment.id)

    @staticmethod
    def receipt_now(payment: OfflineFeePayment, student: Student, reason: str | None, actor, request):
        """The real receipt for a payment being kept: spread over whatever is
        owed now, oldest first, the rest held as credit. Dated the day it was
        taken when those books are open, otherwise today."""
        day = payment.receipt_date
        locked = lock.locked_until(student.school_id)

        if locked is not None and day <= locked:
            day = SchoolClock.for_school(student.school_id).now().date()

        year = year_covering(student.school_id, day)

        if year is None:
            raise serializers.ValidationError({
                "action": ["No academic year covers this date. Add one under Academic Years first."]
            })

        receipt, _ = FeeReceiptService.create(
            {
                "student": student,
                "academic_year": year,
                "receipt_date": day,
                "amount": payment.amount,
                "payment_mode": payment.payment_mode,
                "reference": payment.reference,
                "note": receipt_note(reason or payment.note, payment.provisional_number, payment.receipt_date),
                "allocations": None,
                "email_to_guardian": False,
            },
            actor,
            request,
        )

        return receipt


def offline_fee_payment_resource(payment: OfflineFeePayment) -> dict:
    student = payment.student
    receipt = payment.fee_receipt

    return {
        "id": payment.id,
        "client_id": payment.client_id,
        "provisional_number": payment.provisional_number,
        "status": payment.status,
        "problem": payment.problem,
        "student": {"id": student.id, "name": student.name, "admission_number": student.admission_number},
        "receipt_date": payment.receipt_date.isoformat(),
        "amount": str(payment.amount),
        "currency_code": payment.currency_code,
        "payment_mode": payment.payment_mode,
        "reference": payment.reference,
        "note": payment.note,
        "allocations": payment.allocations,
        "taken_by": payment.taken_by.name if payment.taken_by else None,
        "taken_at": payment.taken_at.isoformat() if payment.taken_at else None,
        "receipt": None if receipt is None else {"id": receipt.id, "receipt_number": receipt.receipt_number},
        "settled_by": payment.settled_by.name if payment.settled_by else None,
        "settled_at": payment.settled_at.isoformat() if payment.settled_at else None,
        "settle_note": payment.settle_note,
        "refund_mode": payment.refund_mode,
        "refund_reference": payment.refund_reference,
    }
