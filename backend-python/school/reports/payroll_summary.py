"""What payroll cost over a range, per employee (Phase 20).

Read from the payslips of finalized runs, which are snapshots: a payslip
states what was paid under the salary and attendance of its month, so the
report never re-derives a figure from today's salaries.

Three rules worth knowing:

- **A run counts for every month it covers that overlaps the range.** Payroll
  is monthly, so "1-18 September" reports September's run.
- **Draft runs are left out.** A draft can still be regenerated or adjusted;
  the same figures an employee cannot see yet are not reported as spent.
- **Money is never added across currencies** (CLAUDE.md rule 5). An employee
  paid in two currencies over the range - a school whose currency changed -
  gets a line per currency, and the totals are a list, one entry per currency.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from django.db.models import Q

from ..enums import PayrollRunStatus, PayslipStatus
from ..models import Payslip
from .range import ReportRange

ZERO = Decimal("0.00")
MONEY = ("gross", "deductions", "net", "paid", "unpaid")


class PayrollSummaryReport:
    TITLE = "Payroll summary"
    PDF_NOTE = "From finalized payroll runs only; a draft can still change. Money is never added across currencies."
    # Compared with the previous period when one is asked for (comparison.py).
    COMPARED_ROWS = [("net", "Net pay")]

    @staticmethod
    def row_key(row: dict):
        return (row["staff_profile_id"], row["currency_code"])

    def build(self, report_range: ReportRange, filters: dict) -> dict:
        payslips = Payslip.objects.filter(
            school_id=report_range.school_id,
            payroll_run__status__in=(PayrollRunStatus.FINALIZED, PayrollRunStatus.PAID),
        ).select_related("payroll_run")

        # An empty Q() matches everything, so a range touching no month has to
        # say "none" outright.
        months = months_between(report_range.start, report_range.end)
        in_range = Q(pk__in=[])
        for year, month in months:
            in_range |= Q(payroll_run__year=year, payroll_run__month=month)
        payslips = payslips.filter(in_range)

        if filters.get("department_id"):
            payslips = payslips.filter(staff_profile__department_id=filters["department_id"])

        # Oldest first, so the name and department a line shows are the
        # employee's latest.
        payslips = list(payslips.order_by("payroll_run__year", "payroll_run__month", "id"))

        lines: dict[tuple, dict] = {}
        for slip in payslips:
            line = lines.setdefault((slip.staff_profile_id, slip.currency_code), {
                "staff_profile_id": slip.staff_profile_id,
                "currency_code": slip.currency_code,
                "payslips": 0,
                "paid_days": Decimal("0"),
                **{key: ZERO for key in MONEY},
            })
            line.update({
                "employee_id": slip.employee_code,
                "name": slip.employee_name,
                "department": slip.department_name,
                "designation": slip.designation,
            })
            line["payslips"] += 1
            line["paid_days"] += slip.paid_days
            line["gross"] += slip.gross_earnings
            line["deductions"] += slip.total_deductions
            line["net"] += slip.net_pay
            line["paid" if slip.status == PayslipStatus.PAID else "unpaid"] += slip.net_pay

        rows = [
            {
                "staff_profile_id": line["staff_profile_id"],
                "employee_id": line["employee_id"],
                "name": line["name"],
                "department": line["department"],
                "designation": line["designation"],
                "currency_code": line["currency_code"],
                "payslips": line["payslips"],
                "paid_days": float(line["paid_days"]),
                **{key: money(line[key]) for key in MONEY},
            }
            for line in sorted(lines.values(), key=lambda line: (line["name"].lower(), line["staff_profile_id"]))
        ]

        return {
            "range": report_range.to_dict(),
            "rows": rows,
            "totals": {
                "employees": len({row["staff_profile_id"] for row in rows}),
                "payslips": len(payslips),
                "months": sorted({f"{slip.payroll_run.year}-{slip.payroll_run.month:02d}" for slip in payslips}),
                "by_currency": by_currency(rows),
            },
        }

    def headings(self) -> list[str]:
        return [
            "Employee ID", "Name", "Department", "Designation", "Currency", "Payslips", "Paid days",
            "Gross", "Deductions", "Net pay", "Paid", "Unpaid",
        ]

    def csv_rows(self, report: dict) -> list[list]:
        return [
            [
                row["employee_id"], row["name"], row["department"], row["designation"], row["currency_code"],
                row["payslips"], row["paid_days"], row["gross"], row["deductions"], row["net"], row["paid"],
                row["unpaid"],
            ]
            for row in report["rows"]
        ]

    def combine_totals(self, branch_totals: list[dict]) -> dict:
        return {
            "branches": len(branch_totals),
            "employees": sum(totals["employees"] for totals in branch_totals),
            "payslips": sum(totals["payslips"] for totals in branch_totals),
            "months": sorted({month for totals in branch_totals for month in totals["months"]}),
            # Branches in one currency add up; branches in different ones
            # stay side by side.
            "by_currency": by_currency([entry for totals in branch_totals for entry in totals["by_currency"]]),
        }


def months_between(start: dt.date, end: dt.date) -> set[tuple[int, int]]:
    """Every (year, month) the range touches."""
    months = set()
    year, month = start.year, start.month

    while (year, month) <= (end.year, end.month):
        months.add((year, month))
        year, month = (year + 1, 1) if month == 12 else (year, month + 1)

    return months


def by_currency(entries: list[dict]) -> list[dict]:
    """Money summed per currency, in currency order."""
    sums: dict[str, dict[str, Decimal]] = {}

    for entry in entries:
        total = sums.setdefault(entry["currency_code"], {key: ZERO for key in MONEY})
        for key in MONEY:
            total[key] += Decimal(entry[key])

    return [
        {"currency_code": code, **{key: money(total[key]) for key in MONEY}}
        for code, total in sorted(sums.items())
    ]


def money(value: Decimal) -> str:
    """Money goes out as a string, exact, the way payroll's API sends it."""
    return f"{value:.2f}"
