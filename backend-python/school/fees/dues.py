"""What each student owes: step F2, "Dues" (docs/fees.md).

A due is one installment of one published fee on one student's account. They
are never typed: one reconcile, `FeeDueService.sync_student`, works out which
installments a student should be paying for a year and brings the ledger in
line with it. Every write that can change that answer - publishing a fee,
editing a published one, admitting, moving or deactivating a student, a
promotion, a bus route - calls it, inside the same transaction as the write.

What a student is expected to pay for a year:

- nothing, unless they are active (and did not leave that year);
- every installment of every published fee of their class that year (their
  StudentEnrollment, not the section they sit in today);
- every installment of the published Transport fee of the bus route they ride
  now, if they are enrolled that year;
- of those, only the ones due on or after the day they joined - their
  admission date, or the school-local day their record was created - and,
  for a class or route they moved to mid-year, on or after the day of the
  move (`class_since`, `route_since`).

And how the ledger follows:

- an expected installment with no due gets one; a cancelled due for it is
  revived (the unique key allows one row per student per installment);
- a due nothing was paid on, no longer expected and falling due *after*
  today, is cancelled with a reason. Anything due on or before today stays
  owed, whatever happened since;
- an unpaid due follows its installment's amount, date and label; a part-paid
  one never drops below what was paid; a paid one is never touched;
- every due still owed carries the discount its student's active concessions
  for the year give it (F4): each fixed amount, and each percentage of the
  due's amount, of a concession on its fee type or on every fee type, added
  up - never more than the amount less what has been paid. Worked out afresh
  on every run, so a new concession reaches the dues at once (and dues
  created later that year), and a revoked one gives the dues back. A paid,
  waived or cancelled due keeps the discount it had.

Late fines (F4, school/fees/fines.py) are dues of their own kind, with no
installment behind them: the reconcile never reads, prices, discounts or
cancels one.

Running it twice changes nothing the second time. "Today" is the school's
own date (docs/timezones.md).
"""

from __future__ import annotations

import datetime as dt
from collections import defaultdict
from dataclasses import dataclass, field
from decimal import ROUND_HALF_UP, Decimal

from django.db import transaction
from django.utils import timezone

from .. import audit
from ..clock import SchoolClock
from ..enums import (
    EnrollmentStatus,
    FeeConcessionKind,
    FeeDueCancelReason,
    FeeDueKind,
    FeeDueStatus,
    FeeStructureStatus,
    StudentStatus,
)
from ..models import (
    AcademicYear,
    FeeConcession,
    FeeInstallment,
    FeeStructure,
    Student,
    StudentEnrollment,
    StudentFeeDue,
    StudentTransportAssignment,
)

MODULE = "fees"
LABEL_MAX = 130

# A due that is still owed, in full or in part.
OPEN = (FeeDueStatus.PENDING, FeeDueStatus.PARTIAL)

CHANGED_FIELDS = [
    "amount", "due_date", "label", "status", "discount_amount", "cancelled_reason", "cancelled_at", "updated_at",
]

ZERO = Decimal("0.00")
CENT = Decimal("0.01")


@dataclass
class SyncResult:
    """What one or more reconciles changed. `charged` is the students who
    gained a due (new or revived)."""

    created: int = 0
    revived: int = 0
    cancelled: int = 0
    updated: int = 0
    charged: set = field(default_factory=set)

    def add(self, other: "SyncResult") -> "SyncResult":
        self.created += other.created
        self.revived += other.revived
        self.cancelled += other.cancelled
        self.updated += other.updated
        self.charged |= other.charged

        return self

    @property
    def changed(self) -> bool:
        return bool(self.created or self.revived or self.cancelled or self.updated)

    def counts(self) -> dict:
        return {"created": self.created, "revived": self.revived, "cancelled": self.cancelled, "updated": self.updated}

    def charged_summary(self) -> dict:
        """What a publish answers with: how many students were charged and
        how many dues that put on their accounts."""
        return {"students": len(self.charged), "dues_created": self.created + self.revived}


def label_for(head_name: str, installment_label: str) -> str:
    """"Tuition - April 2026", cut to the column's length."""
    return f"{head_name} - {installment_label}"[:LABEL_MAX]


def joined_on(student: Student, clock: SchoolClock) -> dt.date | None:
    """The day a student joined: their admission date, or the school-local
    day their record was created when nobody gave one."""
    if student.admission_date is not None:
        return student.admission_date

    if student.created_at is None:
        return None

    return student.created_at.astimezone(clock.now().tzinfo).date()


def latest(*days) -> dt.date | None:
    """The latest of the days given, ignoring the missing ones."""
    known = [day for day in days if day is not None]

    return max(known) if known else None


def due_from(installment: FeeInstallment, start: dt.date | None) -> bool:
    return start is None or installment.due_date >= start


def today_for(school_id: int) -> dt.date:
    return SchoolClock.for_school(school_id).now().date()


def discount_for(due: StudentFeeDue, concessions) -> Decimal:
    """What a student's active concessions take off one installment due: a
    fixed amount off each installment (decided 2026-10-28), a percentage of
    the due's amount, added up across concessions of its fee type or of every
    fee type - never more than the amount less what has been paid, so the
    balance never goes below zero."""
    total = ZERO

    for concession in concessions:
        if concession.fee_head_id is not None and concession.fee_head_id != due.fee_head_id:
            continue

        if concession.kind == FeeConcessionKind.PERCENT:
            total += (due.amount * concession.value / 100).quantize(CENT, rounding=ROUND_HALF_UP)
        else:
            total += concession.value

    return max(ZERO, min(total, due.amount - due.paid_amount))


class PublishedFees:
    """Every installment of every published fee of one academic year, read
    once and grouped by class and by route - so charging a whole class costs
    one query for the fees, not one per student or per installment."""

    def __init__(self, year: AcademicYear) -> None:
        self.year = year
        self.by_class: dict[int, list[FeeInstallment]] = defaultdict(list)
        self.by_route: dict[int, list[FeeInstallment]] = defaultdict(list)
        self.by_id: dict[int, FeeInstallment] = {}

        rows = (
            FeeInstallment.objects.filter(
                fee_structure__academic_year_id=year.id, fee_structure__status=FeeStructureStatus.PUBLISHED
            )
            .select_related("fee_structure__fee_head")
            .order_by("fee_structure_id", "sequence")
        )

        for row in rows:
            self.by_id[row.id] = row
            structure = row.fee_structure

            if structure.school_class_id is not None:
                self.by_class[structure.school_class_id].append(row)
            elif structure.transport_route_id is not None:
                self.by_route[structure.transport_route_id].append(row)


class FeeDueService:
    # -- the reconcile --------------------------------------------------------

    @classmethod
    def sync_student(cls, student: Student, academic_year: AcademicYear) -> SyncResult:
        """Brings one student's dues for one year in line with what they are
        expected to pay. Idempotent; transactional."""
        return cls.sync_many([student.id], academic_year)

    @classmethod
    def sync_many(cls, student_ids, academic_year: AcademicYear, fees: PublishedFees | None = None) -> SyncResult:
        """The same reconcile for many students of one school and one year,
        with everything read in bulk: the published fees once, then the
        students, their enrollments, their bus routes and their dues in one
        query each, and the changes written back in two."""
        result = SyncResult()
        student_ids = sorted(set(student_ids))

        if not student_ids:
            return result

        with transaction.atomic():
            fees = fees or PublishedFees(academic_year)
            clock = SchoolClock.for_school(academic_year.school_id)
            today = clock.now().date()
            now = timezone.now()

            # Locked in id order: two reconciles of the same students wait
            # for each other instead of both inserting the same due.
            students = list(Student.objects.select_for_update().filter(pk__in=student_ids).order_by("id"))
            enrollments = {
                row.student_id: row
                for row in StudentEnrollment.objects.filter(academic_year_id=academic_year.id, student_id__in=student_ids)
            }
            assignments = {
                row.student_id: row
                for row in StudentTransportAssignment.objects.filter(student_id__in=student_ids)
            }
            dues: dict[int, list[StudentFeeDue]] = defaultdict(list)

            # Installments only: a late fine is not the reconcile's (F4).
            for due in StudentFeeDue.objects.filter(
                academic_year_id=academic_year.id, student_id__in=student_ids, kind=FeeDueKind.INSTALLMENT
            ).select_related("fee_structure"):
                dues[due.student_id].append(due)

            concessions: dict[int, list[FeeConcession]] = defaultdict(list)

            for concession in FeeConcession.objects.filter(
                academic_year_id=academic_year.id, student_id__in=student_ids, revoked_at__isnull=True
            ):
                concessions[concession.student_id].append(concession)

            # The installment behind a due that is no longer published (or
            # is in no fee the year has) - read once, for all of them.
            missing = {
                due.fee_installment_id
                for rows in dues.values()
                for due in rows
                if due.fee_installment_id not in fees.by_id and due.status != FeeDueStatus.CANCELLED
            }
            others = {
                row.id: row
                for row in FeeInstallment.objects.filter(pk__in=missing).select_related("fee_structure__fee_head")
            } if missing else {}

            creates: list[StudentFeeDue] = []
            changes: list[StudentFeeDue] = []

            for student in students:
                cls.reconcile(
                    student, academic_year, fees, others, enrollments.get(student.id), assignments.get(student.id),
                    dues.get(student.id, []), clock, today, now, creates, changes, result,
                    concessions.get(student.id, []),
                )

            if creates:
                StudentFeeDue.objects.bulk_create(creates, batch_size=500)

            if changes:
                StudentFeeDue.objects.bulk_update(changes, CHANGED_FIELDS, batch_size=500)

        return result

    @classmethod
    def reconcile(cls, student, year, fees, others, enrollment, assignment, dues, clock, today, now,
                  creates, changes, result, concessions=()) -> None:
        expected = cls.expected(student, fees, enrollment, assignment, clock)
        held = {due.fee_installment_id: due for due in dues}
        # Existing dues this run changed, each written (and counted) once.
        touched: dict[int, StudentFeeDue] = {}

        for installment in expected.values():
            due = held.get(installment.id)

            if due is None:
                new = cls.new_due(student, year, installment, now)
                new.discount_amount = discount_for(new, concessions)
                creates.append(new)
                result.created += 1
                result.charged.add(student.id)
            elif due.status == FeeDueStatus.CANCELLED:
                cls.revive(due, installment, now)
                touched[due.id] = due
                result.revived += 1
                result.charged.add(student.id)
            elif cls.follow(due, installment, now):
                touched[due.id] = due
                result.updated += 1

        for due in dues:
            if due.fee_installment_id in expected or due.status == FeeDueStatus.CANCELLED:
                continue

            installment = fees.by_id.get(due.fee_installment_id) or others.get(due.fee_installment_id)
            followed = installment is not None and cls.follow(due, installment, now)

            if cls.cancellable(due, today):
                due.status = FeeDueStatus.CANCELLED
                due.cancelled_reason = cls.reason(due, student, enrollment, assignment)
                due.cancelled_at = now
                due.updated_at = now
                touched[due.id] = due
                result.cancelled += 1
            elif followed:
                touched[due.id] = due
                result.updated += 1

        # The discounts last, on the amounts as they now stand (F4).
        for due in dues:
            if cls.discount(due, concessions, now) and due.id not in touched:
                touched[due.id] = due
                result.updated += 1

        changes.extend(touched.values())

    @staticmethod
    def discount(due: StudentFeeDue, concessions, now) -> bool:
        """Brings a due's discount in line with the active concessions. Only
        a due still owed follows them; a paid one keeps its discount (only
        ever trimmed to what its amount less its payments leaves room for,
        should its fee have been cut), and a waived or cancelled one is left
        as it is. True when something changed."""
        if due.status in OPEN:
            wanted = discount_for(due, concessions)
        elif due.status == FeeDueStatus.PAID:
            wanted = max(ZERO, min(due.discount_amount, due.amount - due.paid_amount))
        else:
            return False

        if wanted == due.discount_amount:
            return False

        due.discount_amount = wanted
        due.updated_at = now

        return True

    @staticmethod
    def expected(student, fees: PublishedFees, enrollment, assignment, clock) -> dict[int, FeeInstallment]:
        """installment id -> installment, for everything this student should
        be paying in the year."""
        if student.status != StudentStatus.ACTIVE or enrollment is None:
            return {}

        if enrollment.status == EnrollmentStatus.LEFT:
            return {}

        joined = joined_on(student, clock)
        # A student who moved class or route mid-year pays the new one only
        # from the day of the move - never two for the same month (decided
        # 2026-10-28, docs/fees.md).
        class_from = latest(joined, enrollment.class_since)
        expected = {
            row.id: row for row in fees.by_class.get(enrollment.school_class_id, []) if due_from(row, class_from)
        }

        if assignment is not None:
            route_from = latest(joined, assignment.route_since)
            expected.update({
                row.id: row for row in fees.by_route.get(assignment.route_id, []) if due_from(row, route_from)
            })

        return expected

    @staticmethod
    def cancellable(due: StudentFeeDue, today: dt.date) -> bool:
        """Only an untouched due falling due after today. One already due
        stays owed; one with money against it is somebody's to sort out by
        hand, never the reconcile's."""
        return due.status == FeeDueStatus.PENDING and due.paid_amount == 0 and due.due_date > today

    @staticmethod
    def reason(due: StudentFeeDue, student, enrollment, assignment) -> str:
        if student.status != StudentStatus.ACTIVE or (
            enrollment is not None and enrollment.status == EnrollmentStatus.LEFT
        ):
            return FeeDueCancelReason.LEFT

        structure = due.fee_structure

        if structure.status != FeeStructureStatus.PUBLISHED:
            return FeeDueCancelReason.FEE_CHANGED

        if enrollment is None:
            return FeeDueCancelReason.CLASS_CHANGED

        if structure.school_class_id is not None and structure.school_class_id != enrollment.school_class_id:
            return FeeDueCancelReason.CLASS_CHANGED

        if structure.transport_route_id is not None and (
            assignment is None or assignment.route_id != structure.transport_route_id
        ):
            return FeeDueCancelReason.ROUTE_CHANGED

        # Still the student's fee, but the installment no longer applies to
        # them - its date moved before the day they joined, or the day they
        # joined moved after it.
        return FeeDueCancelReason.FEE_CHANGED

    @staticmethod
    def new_due(student, year, installment: FeeInstallment, now) -> StudentFeeDue:
        structure = installment.fee_structure

        return StudentFeeDue(
            school_id=student.school_id,
            student_id=student.id,
            academic_year_id=year.id,
            fee_structure_id=structure.id,
            fee_installment_id=installment.id,
            fee_head_id=structure.fee_head_id,
            label=label_for(structure.fee_head.name, installment.label),
            due_date=installment.due_date,
            amount=installment.amount,
            discount_amount=0,
            paid_amount=0,
            # The fee's currency, never the client's - CLAUDE.md rule 5.
            currency_code=structure.currency_code,
            status=FeeDueStatus.PENDING,
            created_at=now,
            updated_at=now,
        )

    @staticmethod
    def revive(due: StudentFeeDue, installment: FeeInstallment, now) -> None:
        due.status = FeeDueStatus.PENDING
        due.amount = installment.amount
        due.due_date = installment.due_date
        due.label = label_for(installment.fee_structure.fee_head.name, installment.label)
        due.cancelled_reason = None
        due.cancelled_at = None
        due.updated_at = now

    @staticmethod
    def follow(due: StudentFeeDue, installment: FeeInstallment, now) -> bool:
        """An unpaid due follows its installment; a part-paid one follows its
        amount but never below what was paid; anything else stays as it is.
        True when something changed."""
        if due.status == FeeDueStatus.PENDING:
            label = label_for(installment.fee_structure.fee_head.name, installment.label)
            wanted = (installment.amount, installment.due_date, label)

            if (due.amount, due.due_date, due.label) == wanted:
                return False

            due.amount, due.due_date, due.label = wanted
            due.updated_at = now

            return True

        if due.status == FeeDueStatus.PARTIAL:
            amount = max(installment.amount, due.paid_amount)

            if due.amount == amount:
                return False

            due.amount = amount
            # Cut to what was already paid (F3): nothing is left to pay. A
            # discount that covers the rest is not a payment - the due stays
            # part-paid, so revoking the discount gives it back (F4).
            if due.amount - due.paid_amount <= 0:
                due.status = FeeDueStatus.PAID
            due.updated_at = now

            return True

        return False

    # -- who a change touches -------------------------------------------------

    @classmethod
    def students_of(cls, structure: FeeStructure) -> set[int]:
        """Everybody a fee can reach: those enrolled in its class that year,
        or riding its route and enrolled that year - and anybody it already
        charges, who may since have moved but still owes its overdue lines."""
        enrolled = StudentEnrollment.objects.filter(academic_year_id=structure.academic_year_id)

        if structure.school_class_id is not None:
            ids = set(enrolled.filter(school_class_id=structure.school_class_id).values_list("student_id", flat=True))
        else:
            riders = StudentTransportAssignment.objects.filter(route_id=structure.transport_route_id)
            ids = set(enrolled.filter(student_id__in=riders.values("student_id")).values_list("student_id", flat=True))

        ids |= set(
            StudentFeeDue.objects.filter(fee_structure_id=structure.id)
            .exclude(status=FeeDueStatus.CANCELLED)
            .values_list("student_id", flat=True)
        )

        return ids

    @classmethod
    def sync_structures(cls, structures, year: AcademicYear) -> SyncResult:
        """After publishing or editing fees of one year: everybody they can
        reach, each reconciled once."""
        ids: set[int] = set()

        for structure in structures:
            ids |= cls.students_of(structure)

        return cls.sync_many(ids, year)

    @classmethod
    def live_years_of(cls, student: Student) -> list[AcademicYear]:
        """The years a change to a student can still matter in: those they
        are enrolled in or owe something in, that have not ended."""
        today = today_for(student.school_id)
        year_ids = set(
            StudentEnrollment.objects.filter(student_id=student.id).values_list("academic_year_id", flat=True)
        ) | set(StudentFeeDue.objects.filter(student_id=student.id).values_list("academic_year_id", flat=True))

        return list(AcademicYear.objects.filter(pk__in=year_ids, end_date__gte=today).order_by("start_date"))

    @classmethod
    def sync_student_everywhere(cls, student: Student) -> SyncResult:
        """After the student themselves changed - admitted, moved class,
        deactivated, given an admission date."""
        result = SyncResult()

        for year in cls.live_years_of(student):
            result.add(cls.sync_many([student.id], year))

        return result

    @classmethod
    def route_years(cls, school_id: int, route_ids) -> list[AcademicYear]:
        """The years a bus route change matters in: those with a published
        fee for one of the routes, that have not ended."""
        route_ids = [route_id for route_id in route_ids if route_id is not None]

        if not route_ids:
            return []

        with_fees = FeeStructure.objects.filter(
            transport_route_id__in=route_ids, status=FeeStructureStatus.PUBLISHED
        ).values("academic_year_id")

        return list(
            AcademicYear.objects.filter(
                school_id=school_id, pk__in=with_fees, end_date__gte=today_for(school_id)
            ).order_by("start_date")
        )

    @classmethod
    def sync_route_change(cls, student: Student, route_ids) -> SyncResult:
        result = SyncResult()

        for year in cls.route_years(student.school_id, route_ids):
            result.add(cls.sync_many([student.id], year))

        return result

    # -- the audit trail ------------------------------------------------------

    @staticmethod
    def audit(result: SyncResult, *, entity_type: str, entity_id: int | None, school_id: int,
              actor=audit.CURRENT, request=None) -> None:
        """One row per action that changed somebody's dues. A reconcile that
        changed nothing says nothing."""
        if not result.changed:
            return

        audit.record(
            actor=actor, action="fee_dues.synced", module=MODULE, entity_type=entity_type, entity_id=entity_id,
            school_id=school_id, new=result.counts(), request=request,
        )
