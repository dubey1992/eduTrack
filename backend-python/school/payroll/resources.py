"""The JSON payroll's screens read.

Money goes out as strings with two decimals, as payments do - a client that
parsed it as a double would put a rounding error into somebody's pay. Day
counts are numbers, and can be halves.
"""

from __future__ import annotations

from ..enums import PayslipLineSource, PayslipStatus
from ..resources import timestamp
from .calculator import ZERO
from .service import SalaryService, period_label


def cash(value) -> str:
    return f"{(value if value is not None else ZERO):.2f}"


def days(value) -> float:
    return float(value)


def employee_salary_resource(profile) -> dict:
    """A row of the salary screen: who, and what they are paid if it is set."""
    salary = getattr(profile, "salary", None) if _has_salary(profile) else None
    user = profile.user

    return {
        "staff_profile_id": profile.id,
        "user_id": profile.user_id,
        "employee_id": profile.employee_id,
        "name": user.name,
        "role": user.role,
        "status": user.status,
        "designation": profile.designation,
        "department_name": profile.department.name if profile.department_id else None,
        "joining_date": profile.joining_date.isoformat() if profile.joining_date else None,
        "school_id": profile.school_id,
        "school_name": profile.school.name,
        "school_currency_code": profile.school.currency_code,
        "salary": None if salary is None else salary_resource(salary),
    }


def salary_resource(salary) -> dict:
    components = SalaryService.components_of(salary)
    earnings = sum((c.amount for c in components if c.type == "earning"), ZERO)
    deductions = sum((c.amount for c in components if c.type == "deduction"), ZERO)
    gross = salary.basic_salary + earnings

    return {
        "id": salary.id,
        "basic_salary": cash(salary.basic_salary),
        "currency_code": salary.currency_code,
        "components": [
            {"id": c.id, "type": c.type, "name": c.name, "amount": cash(c.amount)} for c in components
        ],
        "total_earnings": cash(earnings),
        "total_deductions": cash(deductions),
        "gross_monthly": cash(gross),
        "net_monthly": cash(gross - deductions),
        "updated_by_name": salary.updated_by.name if salary.updated_by_id else None,
        "updated_at": timestamp(salary.updated_at),
    }


def run_resource(run, figures: dict | None, missing=None) -> dict:
    figures = figures or {}
    employees = figures.get("employees", 0)
    paid = figures.get("paid", 0)

    body = {
        "id": run.id,
        "school_id": run.school_id,
        "school_name": run.school.name,
        "year": run.year,
        "month": run.month,
        "period_label": period_label(run.year, run.month),
        "status": run.status,
        "currency_code": run.currency_code,
        "working_days": run.working_days,
        "employees": employees,
        "paid_count": paid,
        "unpaid_count": employees - paid,
        "gross_total": cash(figures.get("gross")),
        "deductions_total": cash(figures.get("deductions")),
        "net_total": cash(figures.get("net")),
        "generated_by_name": run.generated_by.name if run.generated_by_id else None,
        "finalized_by_name": run.finalized_by.name if run.finalized_by_id else None,
        "finalized_at": timestamp(run.finalized_at),
        "paid_at": timestamp(run.paid_at),
        "created_at": timestamp(run.created_at),
        "updated_at": timestamp(run.updated_at),
    }

    if missing is not None:
        body["missing_salaries"] = [
            {
                "staff_profile_id": profile.id,
                "employee_id": profile.employee_id,
                "name": profile.user.name,
                "reason": reason,
            }
            for profile, reason in missing
        ]

    return body


def payslip_resource(slip, with_lines: bool = False) -> dict:
    run = slip.payroll_run

    body = {
        "id": slip.id,
        "payroll_run_id": slip.payroll_run_id,
        "year": run.year,
        "month": run.month,
        "period_label": period_label(run.year, run.month),
        "run_status": run.status,
        "school_id": slip.school_id,
        "school_name": slip.school.name,
        "staff_profile_id": slip.staff_profile_id,
        "employee_name": slip.employee_name,
        "employee_code": slip.employee_code,
        "designation": slip.designation,
        "department_name": slip.department_name,
        "currency_code": slip.currency_code,
        "working_days": days(slip.working_days),
        "paid_days": days(slip.paid_days),
        "absent_days": days(slip.absent_days),
        "half_days": slip.half_days,
        "unmarked_days": slip.unmarked_days,
        "gross_earnings": cash(slip.gross_earnings),
        "total_deductions": cash(slip.total_deductions),
        "net_pay": cash(slip.net_pay),
        "shortfall": cash(slip.shortfall),
        "status": slip.status,
        "is_paid": slip.status == PayslipStatus.PAID,
        "paid_on": slip.paid_on.isoformat() if slip.paid_on else None,
        "payment_mode": slip.payment_mode,
        "payment_reference": slip.payment_reference,
        "emailed_at": timestamp(slip.emailed_at),
    }

    if with_lines:
        body["lines"] = [
            {
                "id": line.id,
                "type": line.type,
                "source": line.source,
                "name": line.name,
                "full_amount": None if line.full_amount is None else cash(line.full_amount),
                "amount": cash(line.amount),
                "note": line.note,
                "created_by_name": line.created_by.name if line.created_by_id else None,
                "is_adjustment": line.source == PayslipLineSource.ADJUSTMENT,
            }
            for line in slip.lines.select_related("created_by").order_by("sort_order", "id")
        ]

    return body


def _has_salary(profile) -> bool:
    try:
        return profile.salary is not None
    except Exception:  # noqa: BLE001 - Django raises RelatedObjectDoesNotExist for a missing reverse one-to-one
        return False
