"""Late fines: step F4 (docs/fees.md).

Every installment still owed `late_fine_grace_days` days after it fell due
gets **one** fine - a due of its own (`kind` `late_fine`) for the school's
`late_fine_amount`, pointing at the installment due it is for. Once, never
again and never compounding: the unique key on `fine_for_due_id` is the
database's word on it, and the job never even tries a second. Paying the
installment later leaves its fine owed; waiving the fine forgives it.

"Overdue" is judged on the school's own date (docs/timezones.md): an
installment due on the 10th with 7 days' grace is fined from the 18th,
school-local - `due_date + grace < today`.

Fined only:

- in a school with the fees module on and `late_fine_amount` above 0;
- installments (a fine is never fined) still pending or part-paid with
  something left to pay on them - a discount can take one to nothing;
- of a student who is active, and has not left in that installment's year
  (the reconcile's notion of a student still being charged, F2).

Run hourly by `manage.py apply_late_fines`, because schools keep their own
timezones; a run that finds nothing new to fine does nothing.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass
from decimal import Decimal

from django.db import transaction
from django.db.models import Exists, F, OuterRef
from django.utils import timezone

from .. import audit, modules
from ..clock import SchoolClock
from ..enums import EnrollmentStatus, FeeDueKind, FeeDueStatus, StudentStatus
from ..models import ModuleSetting, StudentEnrollment, Student, StudentFeeDue
from .dues import LABEL_MAX, OPEN

MODULE = "fees"
BATCH = 500


@dataclass
class FineRun:
    """What one school's run did, or why it did nothing."""

    school_id: int
    fines: int = 0
    students: int = 0
    amount: Decimal = Decimal("0.00")
    skipped: str | None = None


def fine_label(installment_label: str) -> str:
    """"Late fine - Tuition - April", cut to the column's length."""
    return f"Late fine - {installment_label}"[:LABEL_MAX]


def schools_with_fines() -> list[int]:
    """Every school that could be fined today: fees granted and kept on.
    The module is off unless granted, so only a school with a saved fees row
    can have it on."""
    ids = ModuleSetting.objects.filter(module=MODULE).values_list("school_id", flat=True).order_by("school_id")

    return [school_id for school_id in ids if modules.is_enabled(school_id, MODULE)]


def unfined(school_id: int, today: dt.date, grace_days: int):
    """The installment dues of a school that have earned their fine and do
    not have it yet."""
    cutoff = today - dt.timedelta(days=grace_days)
    left = StudentEnrollment.objects.filter(
        student_id=OuterRef("student_id"), academic_year_id=OuterRef("academic_year_id"),
        status=EnrollmentStatus.LEFT,
    )
    fined = StudentFeeDue.objects.filter(fine_for_due_id=OuterRef("pk"))

    return (
        StudentFeeDue.objects.filter(
            school_id=school_id,
            kind=FeeDueKind.INSTALLMENT,
            status__in=OPEN,
            # due_date + grace < today
            due_date__lt=cutoff,
            amount__gt=F("discount_amount") + F("paid_amount"),
            student__status=StudentStatus.ACTIVE,
        )
        .exclude(Exists(left))
        .exclude(Exists(fined))
    )


class LateFineService:
    @classmethod
    def apply(cls, school_id: int) -> FineRun:
        """Fines one school's overdue installments, once each."""
        run = FineRun(school_id=school_id)

        if not modules.is_enabled(school_id, MODULE):
            run.skipped = "fees module off"
            return run

        settings = modules.settings_for(school_id, MODULE)
        amount = Decimal(int(settings["late_fine_amount"])).quantize(Decimal("0.01"))
        grace = int(settings["late_fine_grace_days"])

        if amount <= 0:
            run.skipped = "late fine amount is 0"
            return run

        run.amount = amount
        today = SchoolClock.for_school(school_id).now().date()
        student_ids = sorted(set(unfined(school_id, today, grace).values_list("student_id", flat=True)))
        fined_students: set[int] = set()

        for start in range(0, len(student_ids), BATCH):
            batch = student_ids[start:start + BATCH]

            with transaction.atomic():
                # The rows payments and the reconcile lock: a payment and a
                # fine on one student take turns, and two runs that overlap
                # wait for each other instead of both fining one installment.
                list(Student.objects.select_for_update().filter(pk__in=batch).order_by("id").values_list("id"))
                now = timezone.now()
                fines = [
                    StudentFeeDue(
                        school_id=due.school_id,
                        student_id=due.student_id,
                        academic_year_id=due.academic_year_id,
                        fee_structure_id=None,
                        fee_installment_id=None,
                        fee_head_id=due.fee_head_id,
                        kind=FeeDueKind.LATE_FINE,
                        fine_for_due_id=due.id,
                        label=fine_label(due.label),
                        # The school-local day the fine was added.
                        due_date=today,
                        amount=amount,
                        discount_amount=0,
                        paid_amount=0,
                        # The installment's currency, never anybody's choice.
                        currency_code=due.currency_code,
                        status=FeeDueStatus.PENDING,
                        created_at=now,
                        updated_at=now,
                    )
                    for due in unfined(school_id, today, grace).filter(student_id__in=batch).order_by("id")
                ]

                if fines:
                    StudentFeeDue.objects.bulk_create(fines, batch_size=500)

                run.fines += len(fines)
                fined_students |= {fine.student_id for fine in fines}

        run.students = len(fined_students)

        if run.fines:
            # One row per school per run that fined anybody.
            audit.record(
                actor=None, action="fee_late_fines.applied", module=MODULE, entity_type="school",
                entity_id=school_id, school_id=school_id,
                new={"fines": run.fines, "students": run.students, "amount_each": str(amount),
                     "grace_days": grace, "date": today.isoformat()},
            )

        return run
