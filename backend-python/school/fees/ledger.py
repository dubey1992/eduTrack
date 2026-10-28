"""Reading what students owe (docs/fees.md, F2): one student's fees statement
for a year, and the balances list - every student of a year with what they
were charged, what they paid and what they still owe.

Arithmetic, everywhere: balance = amount - discount - paid, per due, except
that a waived or cancelled due owes nothing (F4). A cancelled due is shown on
a statement (struck through) and counted nowhere. A waived one counts in what
was charged, and what was forgiven on it - amount - discount - paid, since a
waived due takes no more money - is the statement's `waived` total. A due is
overdue while something is still owed on it (pending or part-paid, with a
balance above zero - a discount can take one to nothing) and its date is
before the school's today.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from django.db.models import DecimalField, Exists, F, OuterRef, Q, Subquery, Sum, Value
from django.db.models.functions import Coalesce, Concat, Lower

from ..enums import FeeDueStatus, StudentStatus
from ..models import AcademicYear, FeeReceipt, Student, StudentEnrollment, StudentFeeDue
from .dues import OPEN

# A waived or cancelled due owes nothing.
SETTLED = (FeeDueStatus.WAIVED, FeeDueStatus.CANCELLED)

ZERO = Decimal("0.00")
MONEY = DecimalField(max_digits=14, decimal_places=2)


def balance_of(due: StudentFeeDue) -> Decimal:
    if due.status in SETTLED:
        return ZERO

    return due.amount - due.discount_amount - due.paid_amount


def forgiven(due: StudentFeeDue) -> Decimal:
    """What a waiver let go of: whatever was still owed on the due."""
    if due.status != FeeDueStatus.WAIVED:
        return ZERO

    return max(ZERO, due.amount - due.discount_amount - due.paid_amount)


def is_overdue(due: StudentFeeDue, today: dt.date) -> bool:
    return due.status in OPEN and due.due_date < today and balance_of(due) > 0


def owed(dues):
    """The dues of a queryset with something still to pay on them."""
    return dues.filter(status__in=OPEN, amount__gt=F("discount_amount") + F("paid_amount"))


# -- one student's statement ----------------------------------------------------


def default_year(student: Student) -> AcademicYear | None:
    """The year a statement opens on when nobody asks for one: the school's
    current year, else the latest year the student owes anything in, else
    the school's latest year."""
    years = AcademicYear.objects.filter(school_id=student.school_id)

    current = years.filter(is_current=True).order_by("-start_date", "-id").first()

    if current is not None:
        return current

    with_dues = years.filter(
        pk__in=StudentFeeDue.objects.filter(student_id=student.id).values("academic_year_id")
    ).order_by("-start_date", "-id").first()

    return with_dues or years.order_by("-start_date", "-id").first()


def statement(student: Student, year: AcademicYear, today: dt.date) -> dict:
    """Every due of one student in one year, oldest first, with totals."""
    dues = list(
        StudentFeeDue.objects.filter(student_id=student.id, academic_year_id=year.id)
        .select_related("fee_head")
        .order_by("due_date", Lower("fee_head__name"), "id")
    )
    enrollment = (
        StudentEnrollment.objects.filter(student_id=student.id, academic_year_id=year.id)
        .select_related("school_class", "class_section")
        .first()
    )

    counted = [due for due in dues if due.status != FeeDueStatus.CANCELLED]
    totals = {
        "charged": sum((due.amount for due in counted), ZERO),
        "discount": sum((due.discount_amount for due in counted), ZERO),
        "paid": sum((due.paid_amount for due in counted), ZERO),
        "balance": sum((balance_of(due) for due in counted), ZERO),
        "overdue": sum((balance_of(due) for due in counted if is_overdue(due, today)), ZERO),
        "waived": sum((forgiven(due) for due in counted), ZERO),
    }
    currency = next((due.currency_code for due in counted), None) or next(
        (due.currency_code for due in dues), None
    ) or student.school.currency_code

    # The receipts numbered in this year (their date falls in it), newest
    # first, cancelled ones included - F3.
    receipts = list(
        FeeReceipt.objects.filter(student_id=student.id, academic_year_id=year.id).order_by("-receipt_date", "-id")
    )

    # The discounts active for this year (F4), newest first.
    from .concessions import ConcessionService

    concessions = list(
        ConcessionService.query().filter(student_id=student.id, academic_year_id=year.id, revoked_at__isnull=True)
        .order_by("-created_at", "-id")
    )

    # F6: what credit paid on each due, and the credit the student holds.
    from .credit import balances as credit_balances, paid_from_credit

    from_credit = paid_from_credit(due.id for due in dues)

    for due in dues:
        due.paid_from_credit = from_credit.get(due.id, ZERO)

    return {"student": student, "enrollment": enrollment, "year": year, "dues": dues, "totals": totals,
            "currency_code": currency, "today": today, "receipts": receipts, "concessions": concessions,
            "credit": credit_balances(student.id)}


# -- the balances list ----------------------------------------------------------


def _sum(dues, expression) -> Coalesce:
    """A per-student total over `dues`, as a correlated subquery - one SQL
    statement for the whole page, however many students are on it."""
    total = dues.order_by().values("student_id").annotate(total=Sum(expression, output_field=MONEY)).values("total")[:1]

    return Coalesce(Subquery(total, output_field=MONEY), Value(ZERO), output_field=MONEY)


def balances(year: AcademicYear, filters: dict, today: dt.date):
    """The students of a year - enrolled in it, and either active or owing
    something - each annotated with charged, paid, balance, overdue, the next
    date something falls due and the currency. Ordered as a register is:
    class, section, roll number, name."""
    counted = StudentFeeDue.objects.filter(
        student_id=OuterRef("student_id"), academic_year_id=year.id
    ).exclude(status=FeeDueStatus.CANCELLED)
    # Waived and cancelled dues owe nothing; nor does a due a discount took
    # to zero (F4).
    still_owed = owed(counted)
    owing = F("amount") - F("discount_amount") - F("paid_amount")

    rows = (
        StudentEnrollment.objects.filter(academic_year_id=year.id)
        .select_related("student", "school_class", "class_section")
        .filter(Q(student__status=StudentStatus.ACTIVE) | Exists(counted))
        .annotate(
            charged=_sum(counted, F("amount")),
            paid=_sum(counted, F("paid_amount")),
            balance=_sum(still_owed, owing),
            overdue=_sum(still_owed.filter(due_date__lt=today), owing),
            next_due_date=Subquery(
                still_owed.filter(due_date__gte=today).order_by("due_date").values("due_date")[:1]
            ),
            currency=Coalesce(
                Subquery(counted.order_by("id").values("currency_code")[:1]), Value(year.school.currency_code)
            ),
        )
    )

    if filters.get("school_class_id") is not None:
        rows = rows.filter(school_class_id=filters["school_class_id"])

    if filters.get("class_section_id") is not None:
        rows = rows.filter(class_section_id=filters["class_section_id"])

    search = filters.get("search")

    if search:
        # icontains, so PostgreSQL matches without regard to case as MySQL did.
        rows = rows.annotate(
            full_name=Concat("student__first_name", Value(" "), "student__last_name")
        ).filter(
            Q(full_name__icontains=search)
            | Q(student__first_name__icontains=search)
            | Q(student__last_name__icontains=search)
            | Q(student__admission_number__icontains=search)
        )

    if filters.get("owing"):
        rows = rows.filter(balance__gt=0)

    if filters.get("overdue"):
        rows = rows.filter(overdue__gt=0)

    return rows.order_by(
        "school_class__level", "school_class__name", "class_section__name", "roll_number",
        "student__first_name", "student__last_name", "id",
    )
