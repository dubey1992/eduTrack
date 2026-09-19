"""Salaries, a month's run, and payslips. See docs/payroll.md.

Views decide who may ask; this decides what happens, and writes every change
to the audit log in the same transaction as the change itself. The arithmetic
lives in calculator.py.
"""

from __future__ import annotations

import calendar
import datetime as dt
from decimal import Decimal

from django.db import transaction
from django.db.models import Count, Q, Sum
from django.utils import timezone

from .. import audit, modules, queue
from ..clock import SchoolClock
from ..enums import PayComponentType, PayrollRunStatus, PayslipLineSource, PayslipStatus, UserRole, UserStatus
from ..errors import PayrollRunEmpty, PayrollRunExists, PayrollRunLocked, PayrollRunNotFinalized, PayslipAlreadyPaid
from ..models import (
    PayrollRun,
    Payslip,
    PayslipLine,
    SalaryComponent,
    SalaryProfile,
    School,
    StaffAttendance,
    StaffProfile,
)
from ..scope import SchoolScope
from ..services import HolidayService
from . import calculator

MODULE = "payroll"
SEND_PAYSLIP = "payslip_email"


def period_label(year: int, month: int) -> str:
    return f"{calendar.month_name[month]} {year}"


def component_order(component) -> tuple:
    """Earnings before deductions, each in the order they were entered."""
    return (0 if component.type == PayComponentType.EARNING else 1, component.sort_order, component.id)


def month_bounds(year: int, month: int) -> tuple[dt.date, dt.date]:
    return dt.date(year, month, 1), dt.date(year, month, calendar.monthrange(year, month)[1])


# -- salaries -----------------------------------------------------------------


class SalaryService:
    @staticmethod
    def employees(actor, filters: dict):
        """The people a school pays: real employment records - never the
        placeholder profile a School Admin account carries - newest roster
        order, each with their salary if one is set."""
        staff = StaffProfile.objects.select_related("user", "department", "school", "salary")

        staff = SchoolScope.for_actor(actor).apply_to(staff, filters.get("school_id"))
        staff = staff.exclude(user__role=UserRole.SCHOOL_ADMIN)

        if filters.get("department_id"):
            staff = staff.filter(department_id=filters["department_id"])

        if filters.get("search"):
            search = filters["search"]
            staff = staff.filter(
                Q(user__first_name__icontains=search)
                | Q(user__last_name__icontains=search)
                | Q(employee_id__icontains=search)
            )

        if filters.get("salary") == "missing":
            staff = staff.filter(salary__isnull=True)
        elif filters.get("salary") == "set":
            staff = staff.filter(salary__isnull=False)

        return staff.order_by("employee_id", "id")

    @staticmethod
    def components_of(salary: SalaryProfile | None) -> list[SalaryComponent]:
        if salary is None:
            return []

        return sorted(salary.components.all(), key=component_order)

    @classmethod
    def save(cls, profile: StaffProfile, data: dict, actor, request=None) -> SalaryProfile:
        """Replaces the salary whole - basic and every component - because the
        screen edits it as one form, and a partial update is how a removed
        component quietly survives."""
        school = profile.school
        now = timezone.now()

        with transaction.atomic():
            salary = SalaryProfile.objects.select_for_update().filter(staff_profile=profile).first()
            before = cls.snapshot(salary)

            if salary is None:
                salary = SalaryProfile.objects.create(
                    school_id=profile.school_id,
                    staff_profile=profile,
                    basic_salary=data["basic_salary"],
                    currency_code=school.currency_code,
                    updated_by=actor,
                    created_at=now,
                    updated_at=now,
                )
            else:
                salary.basic_salary = data["basic_salary"]
                # Saving again adopts the school's currency, which is how a
                # salary set before a currency change is brought up to date.
                salary.currency_code = school.currency_code
                salary.updated_by = actor
                salary.updated_at = now
                salary.save()
                salary.components.all().delete()

            for index, component in enumerate(data["components"]):
                SalaryComponent.objects.create(
                    salary_profile=salary,
                    type=component["type"],
                    name=component["name"],
                    amount=component["amount"],
                    sort_order=index,
                    created_at=now,
                    updated_at=now,
                )

            audit.record(
                actor=actor, action="salary.saved", module=MODULE, entity_type="salary_profile",
                entity_id=salary.id, school_id=salary.school_id, old=before, new=cls.snapshot(salary),
                request=request,
            )

        return salary

    @classmethod
    def snapshot(cls, salary: SalaryProfile | None) -> dict | None:
        if salary is None:
            return None

        return {
            "staff_profile_id": salary.staff_profile_id,
            "basic_salary": salary.basic_salary,
            "currency_code": salary.currency_code,
            "components": [
                {"type": c.type, "name": c.name, "amount": c.amount} for c in cls.components_of(salary)
            ],
        }


# -- runs ---------------------------------------------------------------------


class PayrollRunService:
    @staticmethod
    def visible_to(actor, filters: dict):
        runs = PayrollRun.objects.select_related("school", "generated_by", "finalized_by")
        runs = SchoolScope.for_actor(actor).apply_to(runs, filters.get("school_id"))

        if filters.get("year"):
            runs = runs.filter(year=filters["year"])

        if filters.get("status"):
            runs = runs.filter(status=filters["status"])

        return runs.order_by("-year", "-month", "school__name", "id")

    @staticmethod
    def totals(run_ids) -> dict[int, dict]:
        """Headcount and money per run, in one query for a page of runs."""
        rows = (
            Payslip.objects.filter(payroll_run_id__in=list(run_ids))
            .values("payroll_run_id")
            .annotate(
                employees=Count("id"),
                paid=Count("id", filter=Q(status=PayslipStatus.PAID)),
                gross=Sum("gross_earnings"),
                deductions=Sum("total_deductions"),
                net=Sum("net_pay"),
            )
        )

        return {row["payroll_run_id"]: row for row in rows}

    @staticmethod
    def eligible(school: School):
        """Everybody this school pays this month, and everybody it cannot yet.

        Returns (payable, missing): payable profiles have a salary in the
        school's currency; missing ones are listed with the reason, so nobody
        is dropped from payroll without it being said.
        """
        staff = (
            StaffProfile.objects.select_related("user", "department")
            .filter(school_id=school.id, user__status=UserStatus.ACTIVE)
            .exclude(user__role=UserRole.SCHOOL_ADMIN)
            .order_by("employee_id", "id")
        )
        salaries = {
            salary.staff_profile_id: salary
            for salary in SalaryProfile.objects.filter(school_id=school.id).prefetch_related("components")
        }

        payable, missing = [], []

        for profile in staff:
            salary = salaries.get(profile.id)

            if salary is None:
                missing.append((profile, "No salary has been set."))
            elif salary.currency_code != school.currency_code:
                missing.append((
                    profile,
                    f"The salary is in {salary.currency_code} but the school now uses "
                    f"{school.currency_code}. Save the salary again.",
                ))
            else:
                payable.append((profile, salary))

        return payable, missing

    @classmethod
    def generate(cls, school: School, year: int, month: int, actor, request=None) -> PayrollRun:
        now = timezone.now()

        with transaction.atomic():
            if PayrollRun.objects.filter(school=school, year=year, month=month).exists():
                raise PayrollRunExists(f"A payroll run for {period_label(year, month)} already exists.")

            run = PayrollRun.objects.create(
                school=school,
                year=year,
                month=month,
                status=PayrollRunStatus.DRAFT,
                currency_code=school.currency_code,
                working_days=0,
                generated_by=actor,
                created_at=now,
                updated_at=now,
            )
            cls.compute(run)

            audit.record(
                actor=actor, action="payroll_run.generated", module=MODULE, entity_type="payroll_run",
                entity_id=run.id, school_id=school.id, new=cls.snapshot(run), request=request,
            )

        return run

    @classmethod
    def regenerate(cls, run: PayrollRun, actor, request=None) -> PayrollRun:
        with transaction.atomic():
            run = cls.lock(run)
            cls.assert_draft(run)
            before = cls.snapshot(run)

            cls.compute(run)

            audit.record(
                actor=actor, action="payroll_run.regenerated", module=MODULE, entity_type="payroll_run",
                entity_id=run.id, school_id=run.school_id, old=before, new=cls.snapshot(run), request=request,
            )

        return run

    @classmethod
    def compute(cls, run: PayrollRun) -> None:
        """(Re)builds every payslip on a draft from today's salaries and
        register. Adjustments already added to someone who is still paid are
        kept; everybody else's payslip is rebuilt from scratch."""
        school = run.school
        start, end = month_bounds(run.year, run.month)
        working_dates = HolidayService.working_dates(school.id, start, end)
        payable, _ = cls.eligible(school)
        payable_profiles = [profile for profile, _ in payable]
        now = timezone.now()

        run.working_days = len(working_dates)
        run.currency_code = school.currency_code
        run.updated_at = now
        run.save(update_fields=["working_days", "currency_code", "updated_at"])

        marks: dict[int, dict[dt.date, str]] = {}
        for row in StaffAttendance.objects.filter(
            school_id=school.id,
            staff_profile_id__in=[profile.id for profile in payable_profiles],
            attendance_date__range=(start, end),
        ).values("staff_profile_id", "attendance_date", "status"):
            marks.setdefault(row["staff_profile_id"], {})[row["attendance_date"]] = row["status"]

        existing = {slip.staff_profile_id: slip for slip in run.payslips.all()}
        keep = {profile.id for profile in payable_profiles}

        # Nobody is paid who is no longer eligible - deactivated, or their
        # salary removed - adjustments and all.
        for profile_id, slip in existing.items():
            if profile_id not in keep:
                slip.lines.all().delete()
                slip.delete()

        for profile, salary in payable:
            days = calculator.days(working_dates, marks.get(profile.id, {}), profile.joining_date)
            slip = existing.get(profile.id)

            snapshot = {
                "employee_name": profile.user.name,
                "employee_code": profile.employee_id,
                "designation": profile.designation,
                "department_name": profile.department.name if profile.department_id else None,
                "currency_code": school.currency_code,
                "working_days": Decimal(days.working),
                "paid_days": days.paid,
                "absent_days": days.absent,
                "half_days": days.half,
                "unmarked_days": days.unmarked,
                "updated_at": now,
            }

            if slip is None:
                slip = Payslip.objects.create(
                    payroll_run=run, school_id=school.id, staff_profile=profile, status=PayslipStatus.UNPAID,
                    gross_earnings=calculator.ZERO, total_deductions=calculator.ZERO, net_pay=calculator.ZERO,
                    shortfall=calculator.ZERO, created_at=now, **snapshot,
                )
            else:
                for field, value in snapshot.items():
                    setattr(slip, field, value)
                slip.save()
                slip.lines.exclude(source=PayslipLineSource.ADJUSTMENT).delete()

            lines = [(PayComponentType.EARNING, PayslipLineSource.BASIC, "Basic salary", salary.basic_salary)]
            lines += [
                (c.type, PayslipLineSource.COMPONENT, c.name, c.amount)
                for c in sorted(salary.components.all(), key=component_order)
            ]

            for order, (type_, source, name, full) in enumerate(lines):
                PayslipLine.objects.create(
                    payslip=slip, type=type_, source=source, name=name, full_amount=full,
                    amount=calculator.prorate(full, days.paid, days.working),
                    sort_order=order, created_at=now, updated_at=now,
                )

            PayslipService.refresh_totals(slip)

    @classmethod
    def delete(cls, run: PayrollRun, actor, request=None) -> None:
        with transaction.atomic():
            run = cls.lock(run)
            cls.assert_draft(run)
            before = cls.snapshot(run)

            PayslipLine.objects.filter(payslip__payroll_run=run).delete()
            run.payslips.all().delete()
            run_id, school_id = run.id, run.school_id
            run.delete()

            audit.record(
                actor=actor, action="payroll_run.deleted", module=MODULE, entity_type="payroll_run",
                entity_id=run_id, school_id=school_id, old=before, request=request,
            )

    @classmethod
    def finalize(cls, run: PayrollRun, actor, request=None) -> PayrollRun:
        with transaction.atomic():
            run = cls.lock(run)
            cls.assert_draft(run)

            if not run.payslips.exists():
                raise PayrollRunEmpty(
                    f"There are no payslips on the {period_label(run.year, run.month)} run to finalize. "
                    "Set salaries, then regenerate it."
                )

            before = cls.snapshot(run)
            now = timezone.now()
            run.status = PayrollRunStatus.FINALIZED
            run.finalized_by = actor
            run.finalized_at = now
            run.updated_at = now
            run.save(update_fields=["status", "finalized_by", "finalized_at", "updated_at"])

            # Each employee is sent their own payslip, unless the school has
            # switched that off (module settings). Queued in this same
            # transaction, so a finalize that rolls back queues nothing.
            if modules.setting(run.school_id, "payroll", "email_payslips_on_finalize"):
                for payslip_id in run.payslips.values_list("id", flat=True):
                    queue.push(SEND_PAYSLIP, {"payslip_id": payslip_id})

            audit.record(
                actor=actor, action="payroll_run.finalized", module=MODULE, entity_type="payroll_run",
                entity_id=run.id, school_id=run.school_id, old=before, new=cls.snapshot(run), request=request,
            )

        return run

    @classmethod
    def pay_all(cls, run: PayrollRun, data: dict, actor, request=None) -> int:
        """Marks every unpaid payslip on a finalized run paid, the same way."""
        with transaction.atomic():
            run = cls.lock(run)

            if run.status == PayrollRunStatus.DRAFT:
                raise PayrollRunNotFinalized("Finalize the run before recording payment.")

            unpaid = list(run.payslips.filter(status=PayslipStatus.UNPAID).order_by("id"))

            for slip in unpaid:
                PayslipService.mark_paid(slip, data, actor, request, run=run)

            cls.settle(run, actor, request)

        return len(unpaid)

    @classmethod
    def settle(cls, run: PayrollRun, actor, request) -> None:
        """A finalized run whose every payslip is paid is paid."""
        if run.status != PayrollRunStatus.FINALIZED or run.payslips.filter(status=PayslipStatus.UNPAID).exists():
            return

        before = cls.snapshot(run)
        now = timezone.now()
        run.status = PayrollRunStatus.PAID
        run.paid_at = now
        run.updated_at = now
        run.save(update_fields=["status", "paid_at", "updated_at"])

        audit.record(
            actor=actor, action="payroll_run.paid", module=MODULE, entity_type="payroll_run",
            entity_id=run.id, school_id=run.school_id, old=before, new=cls.snapshot(run), request=request,
        )

    @staticmethod
    def lock(run: PayrollRun) -> PayrollRun:
        """Re-reads the run under a row lock, so two people finalizing or
        paying at once cannot both succeed."""
        return PayrollRun.objects.select_for_update().select_related("school").get(pk=run.pk)

    @staticmethod
    def assert_draft(run: PayrollRun) -> None:
        if run.status != PayrollRunStatus.DRAFT:
            raise PayrollRunLocked(
                f"The {period_label(run.year, run.month)} run is {run.status} and can no longer be changed."
            )

    @classmethod
    def snapshot(cls, run: PayrollRun) -> dict:
        figures = cls.totals([run.id]).get(run.id, {})

        return {
            "year": run.year,
            "month": run.month,
            "status": run.status,
            "working_days": run.working_days,
            "employees": figures.get("employees", 0),
            "net_total": figures.get("net") or calculator.ZERO,
        }


# -- payslips -----------------------------------------------------------------


class PayslipService:
    @staticmethod
    def refresh_totals(slip: Payslip) -> None:
        figures = calculator.totals(slip.lines.values_list("type", "amount"))
        slip.gross_earnings = figures.gross_earnings
        slip.total_deductions = figures.total_deductions
        slip.net_pay = figures.net_pay
        slip.shortfall = figures.shortfall
        slip.updated_at = timezone.now()
        slip.save(update_fields=["gross_earnings", "total_deductions", "net_pay", "shortfall", "updated_at"])

    @classmethod
    def add_adjustment(cls, slip: Payslip, data: dict, actor, request=None) -> PayslipLine:
        with transaction.atomic():
            run = PayrollRunService.lock(slip.payroll_run)
            PayrollRunService.assert_draft(run)
            now = timezone.now()
            last = slip.lines.order_by("-sort_order").values_list("sort_order", flat=True).first() or 0

            line = PayslipLine.objects.create(
                payslip=slip, type=data["type"], source=PayslipLineSource.ADJUSTMENT, name=data["name"],
                full_amount=None, amount=data["amount"], note=data["note"], sort_order=max(last + 1, 100),
                created_by=actor, created_at=now, updated_at=now,
            )
            cls.refresh_totals(slip)

            audit.record(
                actor=actor, action="payslip.adjustment_added", module=MODULE, entity_type="payslip",
                entity_id=slip.id, school_id=slip.school_id, new=cls.line_snapshot(line), request=request,
            )

        return line

    @classmethod
    def remove_adjustment(cls, slip: Payslip, line: PayslipLine, actor, request=None) -> None:
        with transaction.atomic():
            run = PayrollRunService.lock(slip.payroll_run)
            PayrollRunService.assert_draft(run)
            before = cls.line_snapshot(line)
            line.delete()
            cls.refresh_totals(slip)

            audit.record(
                actor=actor, action="payslip.adjustment_removed", module=MODULE, entity_type="payslip",
                entity_id=slip.id, school_id=slip.school_id, old=before, request=request,
            )

    @classmethod
    def pay(cls, slip: Payslip, data: dict, actor, request=None) -> Payslip:
        with transaction.atomic():
            run = PayrollRunService.lock(slip.payroll_run)

            if run.status == PayrollRunStatus.DRAFT:
                raise PayrollRunNotFinalized("Finalize the run before recording payment.")

            slip = Payslip.objects.select_for_update().get(pk=slip.pk)
            cls.mark_paid(slip, data, actor, request, run=run)
            PayrollRunService.settle(run, actor, request)

        return slip

    @staticmethod
    def mark_paid(slip: Payslip, data: dict, actor, request, run: PayrollRun) -> None:
        if slip.status == PayslipStatus.PAID:
            raise PayslipAlreadyPaid(f"{slip.employee_name}'s payslip has already been paid.")

        now = timezone.now()
        slip.status = PayslipStatus.PAID
        slip.paid_on = data["paid_on"]
        slip.payment_mode = data["payment_mode"]
        slip.payment_reference = data.get("payment_reference")
        slip.updated_at = now
        slip.save(update_fields=["status", "paid_on", "payment_mode", "payment_reference", "updated_at"])

        audit.record(
            actor=actor, action="payslip.paid", module=MODULE, entity_type="payslip", entity_id=slip.id,
            school_id=slip.school_id,
            new={"paid_on": slip.paid_on, "payment_mode": slip.payment_mode, "payment_reference": slip.payment_reference},
            request=request,
        )

    @staticmethod
    def send(slip: Payslip) -> None:
        queue.push(SEND_PAYSLIP, {"payslip_id": slip.id})

    @staticmethod
    def mine(actor):
        """An employee's own payslips - never a draft, which can still change."""
        return (
            Payslip.objects.select_related("payroll_run", "school")
            .filter(staff_profile__user_id=actor.id)
            .exclude(payroll_run__status=PayrollRunStatus.DRAFT)
            .order_by("-payroll_run__year", "-payroll_run__month", "-id")
        )

    @staticmethod
    def line_snapshot(line: PayslipLine) -> dict:
        return {"type": line.type, "name": line.name, "amount": line.amount, "note": line.note}


def school_today(school_id: int) -> dt.date:
    return SchoolClock.for_school(school_id).now().date()
