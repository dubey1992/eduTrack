"""Discounts and waivers: step F4 (docs/fees.md).

A **discount** (a concession) belongs to one student for one academic year:
a fixed amount or a percentage, off each installment of one fee type or of
every fee type, with a reason. Saving one does not touch the dues itself -
it runs the F2 reconcile for the student and the year, which works the
discount on every due still owed out afresh from the active concessions
(school/fees/dues.py). So a new discount reaches the dues at once and the
dues created later that year, and revoking one gives the dues back. Paid,
waived and cancelled dues keep what they had. Late fines are never
discounted.

A **waiver** forgives one due - an installment or a late fine - outright,
with a reason: its status becomes `waived` and it owes nothing more. A
part-paid due keeps what was paid; the rest is forgiven.

Both lock the student row first, as payments and the reconcile do, so the
three take turns on one student's account. Both are audited.
"""

from __future__ import annotations

from django.db import transaction
from django.db.models import Case, Count, IntegerField, OuterRef, Subquery, Value, When
from django.db.models.functions import Coalesce
from django.utils import timezone

from .. import audit
from ..enums import FeeDueKind, FeeDueStatus
from ..errors import FeeConcessionRevoked, FeeDueNotWaivable
from ..models import FeeConcession, Student, StudentFeeDue
from .dues import OPEN, FeeDueService
from .ledger import balance_of

MODULE = "fees"


def _count(dues) -> Coalesce:
    """How many of `dues` there are, as a correlated subquery."""
    counted = dues.order_by().values("student_id").annotate(n=Count("id")).values("n")[:1]

    return Coalesce(Subquery(counted, output_field=IntegerField()), Value(0))


def dues_affected():
    """The installment dues a concession is taking something off right now:
    the student's, in its year, of its fee type (any, when it has none), not
    cancelled, with a discount on them. 0 once it is revoked."""
    discounted = StudentFeeDue.objects.filter(
        student_id=OuterRef("student_id"), academic_year_id=OuterRef("academic_year_id"),
        kind=FeeDueKind.INSTALLMENT, discount_amount__gt=0,
    ).exclude(status=FeeDueStatus.CANCELLED)

    return Case(
        When(revoked_at__isnull=False, then=Value(0)),
        When(fee_head_id__isnull=True, then=_count(discounted)),
        default=_count(discounted.filter(fee_head_id=OuterRef("fee_head_id"))),
        output_field=IntegerField(),
    )


class ConcessionService:
    WITH = ("student", "academic_year", "fee_head", "created_by", "revoked_by", "school")

    @classmethod
    def query(cls):
        return FeeConcession.objects.select_related(*cls.WITH).annotate(dues_affected=dues_affected())

    @classmethod
    def load(cls, concession_id: int) -> FeeConcession:
        return cls.query().get(pk=concession_id)

    @classmethod
    def create(cls, data: dict, actor, request=None) -> FeeConcession:
        student: Student = data["student"]
        year = data["academic_year"]
        head = data["fee_head"]

        with transaction.atomic():
            Student.objects.select_for_update().filter(pk=student.id).first()
            now = timezone.now()

            concession = FeeConcession.objects.create(
                school_id=student.school_id,
                student_id=student.id,
                academic_year_id=year.id,
                fee_head_id=None if head is None else head.id,
                kind=data["kind"],
                value=data["value"],
                reason=data["reason"],
                created_by_id=getattr(actor, "id", None),
                created_at=now,
                updated_at=now,
            )

            result = FeeDueService.sync_many([student.id], year)

            audit.record(
                actor=actor, action="fee_concession.created", module=MODULE, entity_type="fee_concession",
                entity_id=concession.id, school_id=student.school_id,
                new={
                    "student_id": student.id,
                    "academic_year_id": year.id,
                    "fee_head_id": concession.fee_head_id,
                    "kind": concession.kind,
                    "value": str(concession.value),
                    "reason": concession.reason,
                    "dues_updated": result.updated,
                },
                request=request,
            )
            FeeDueService.audit(result, entity_type="fee_concession", entity_id=concession.id,
                                school_id=student.school_id, actor=actor, request=request)

        return concession

    @classmethod
    def revoke(cls, concession: FeeConcession, reason: str | None, actor, request=None) -> FeeConcession:
        with transaction.atomic():
            Student.objects.select_for_update().filter(pk=concession.student_id).first()
            concession = FeeConcession.objects.select_for_update().get(pk=concession.pk)

            if concession.revoked_at is not None:
                raise FeeConcessionRevoked()

            now = timezone.now()
            concession.revoked_at = now
            concession.revoked_by_id = getattr(actor, "id", None)
            concession.updated_at = now
            concession.save(update_fields=["revoked_at", "revoked_by", "updated_at"])

            result = FeeDueService.sync_many([concession.student_id], concession.academic_year)

            audit.record(
                actor=actor, action="fee_concession.revoked", module=MODULE, entity_type="fee_concession",
                entity_id=concession.id, school_id=concession.school_id,
                old={"revoked_at": None},
                new={
                    "revoked_at": now.isoformat(),
                    "reason": reason,
                    "kind": concession.kind,
                    "value": str(concession.value),
                    "dues_updated": result.updated,
                },
                request=request,
            )
            FeeDueService.audit(result, entity_type="fee_concession", entity_id=concession.id,
                                school_id=concession.school_id, actor=actor, request=request)

        return concession


class WaiverService:
    @staticmethod
    def waive(due: StudentFeeDue, reason: str, actor, request=None) -> StudentFeeDue:
        with transaction.atomic():
            Student.objects.select_for_update().filter(pk=due.student_id).first()
            due = StudentFeeDue.objects.select_for_update().get(pk=due.pk)

            if due.status not in OPEN or balance_of(due) <= 0:
                raise FeeDueNotWaivable()

            before = {"status": due.status, "balance": str(balance_of(due))}
            forgiven = balance_of(due)
            now = timezone.now()

            due.status = FeeDueStatus.WAIVED
            due.waived_at = now
            due.waived_by_id = getattr(actor, "id", None)
            due.waive_reason = reason
            due.updated_at = now
            due.save(update_fields=["status", "waived_at", "waived_by", "waive_reason", "updated_at"])

            audit.record(
                actor=actor, action="fee_due.waived", module=MODULE, entity_type="student_fee_due",
                entity_id=due.id, school_id=due.school_id, old=before,
                new={
                    "status": due.status,
                    "kind": due.kind,
                    "label": due.label,
                    "student_id": due.student_id,
                    "forgiven": str(forgiven),
                    "currency_code": due.currency_code,
                    "reason": reason,
                },
                request=request,
            )

        return due
