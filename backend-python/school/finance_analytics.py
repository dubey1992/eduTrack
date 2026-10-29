"""Finance analytics, A5 (docs/analytics.md, decided 2026-10-29).

A school's fee money month by month, and the four questions asked of it:

- **Collection by month** - what fell due, what came in, and how much of
  that month's dues has been paid so far.
- **Overdue by age** - 1-30, 31-60 and 61+ days past due, at the end of
  each month, from the nightly snapshot (the only way to know a past day's
  arrears, since a due keeps only what has been paid so far).
- **By class** - who is charged, who has paid, who owes, as at today.
- **The next three months** - what is scheduled to fall due. A fact from
  the fee plans, never a prediction.

And, for whoever may also read payroll, **fees against payroll**: money in
against the payroll the school finalized for each month.

The rules every fee report keeps hold here: cancelled and waived dues were
never money to collect, a cancelled receipt brought nothing in, a discount
comes off what is due, and money is never added across currencies - every
figure is one per currency.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from django.db.models import F, Q, Sum

from .analytics import MONTH, next_period, periods
from .clock import SchoolClock
from .enums import FeeDueStatus, FeeReceiptStatus, PayrollRunStatus
from .models import AnalyticsSchoolFeeDay, ClassSection, FeeReceipt, Payslip, StudentFeeDue
from .reports.fees import ZERO, cash

UPCOMING_MONTHS = 3

# Never money to collect.
NOT_OWED = (FeeDueStatus.CANCELLED, FeeDueStatus.WAIVED)
OPEN = (FeeDueStatus.PENDING, FeeDueStatus.PARTIAL)


def finance(school_id: int, start: dt.date, end: dt.date, include_payroll: bool) -> dict:
    today = SchoolClock.for_school(school_id).now().date()
    months = periods(start, min(end, today), MONTH)

    result = {
        "as_of": today.isoformat(),
        "months": [{"from": first.isoformat(), "to": last.isoformat()} for first, last in months],
        "collection": [_collection(school_id, first, last) for first, last in months],
        "overdue_by_age": [_ages(school_id, first, last) for first, last in months],
        "by_class": _by_class(school_id, today),
        "upcoming": _upcoming(school_id, today),
    }

    if include_payroll:
        result["fees_vs_payroll"] = [_fees_vs_payroll(school_id, first, last) for first, last in months]

    return result


def _dues(school_id: int):
    return StudentFeeDue.objects.filter(school_id=school_id).exclude(status__in=NOT_OWED)


def _by_currency(rows, *keys) -> list[dict]:
    """Grouped query rows as money, one line per currency, in currency order."""
    return [
        {"currency_code": row["currency_code"], **{key: cash(row[key]) for key in keys}}
        for row in sorted(rows, key=lambda row: row["currency_code"])
    ]


def _collection(school_id: int, first: dt.date, last: dt.date) -> dict:
    """What fell due in the month, what came in during it, and how much of the
    month's own dues has been paid by now. The last is 'so far': a due paid
    late still counts, so an old month's rate keeps rising as families pay."""
    due = (
        _dues(school_id)
        .filter(due_date__range=(first, last))
        .order_by()
        .values("currency_code")
        .annotate(due=Sum(F("amount") - F("discount_amount")), paid_so_far=Sum("paid_amount"))
    )
    collected = dict(
        FeeReceipt.objects.filter(school_id=school_id, receipt_date__range=(first, last))
        .exclude(status=FeeReceiptStatus.CANCELLED)
        .order_by()
        .values("currency_code")
        .annotate(total=Sum("amount"))
        .values_list("currency_code", "total")
    )
    lines = {row["currency_code"]: row for row in due}

    amounts = []
    for code in sorted(set(lines) | set(collected)):
        row = lines.get(code, {})
        owed = row.get("due") or ZERO
        paid = row.get("paid_so_far") or ZERO
        amounts.append({
            "currency_code": code,
            "due": cash(owed),
            "collected": cash(collected.get(code)),
            "paid_so_far": cash(paid),
            "rate": None if owed <= 0 else float(round(paid / owed * 100, 1)),
        })

    return {"from": first.isoformat(), "to": last.isoformat(), "amounts": amounts}


def _ages(school_id: int, first: dt.date, last: dt.date) -> dict:
    """The month's last snapshot that recorded ages - None before the first."""
    rows = AnalyticsSchoolFeeDay.objects.filter(
        school_id=school_id, snapshot_date__range=(first, last), ages_recorded=True
    )
    day = rows.order_by("-snapshot_date").values_list("snapshot_date", flat=True).first()

    if day is None:
        return {"from": first.isoformat(), "to": last.isoformat(), "as_of": None, "amounts": None}

    return {
        "from": first.isoformat(),
        "to": last.isoformat(),
        "as_of": day.isoformat(),
        "amounts": [
            {
                "currency_code": row.currency_code,
                "overdue_0_30": cash(row.overdue_0_30),
                "overdue_31_60": cash(row.overdue_31_60),
                "overdue_61_plus": cash(row.overdue_61_plus),
            }
            for row in rows.filter(snapshot_date=day).order_by("currency_code")
        ],
    }


def _by_class(school_id: int, today: dt.date) -> list[dict]:
    """Every class's dues that have fallen due by today: charged (after
    discounts), paid, still owed, and the part of it past its date. By each
    student's class now - the class a family is chased through."""
    owing = F("amount") - F("discount_amount") - F("paid_amount")
    rows = (
        _dues(school_id)
        .filter(due_date__lte=today)
        .order_by()
        .values("student__class_section_id", "currency_code")
        .annotate(
            charged=Sum(F("amount") - F("discount_amount")),
            paid=Sum("paid_amount"),
            outstanding=Sum(owing, filter=Q(status__in=OPEN)),
            overdue=Sum(owing, filter=Q(status__in=OPEN, due_date__lt=today)),
        )
    )

    sections = {
        section.id: f"{section.school_class.name} {section.name}"
        for section in ClassSection.objects.filter(
            id__in={row["student__class_section_id"] for row in rows}
        ).select_related("school_class")
    }

    lines = []
    for row in rows:
        charged = row["charged"] or ZERO
        paid = row["paid"] or ZERO
        lines.append({
            "class_section_id": row["student__class_section_id"],
            "class_section": sections.get(row["student__class_section_id"]) or "No class",
            "currency_code": row["currency_code"],
            "charged": cash(charged),
            "paid": cash(paid),
            "outstanding": cash(max(row["outstanding"] or ZERO, ZERO)),
            "overdue": cash(max(row["overdue"] or ZERO, ZERO)),
            "rate": None if charged <= 0 else float(round(paid / charged * 100, 1)),
        })

    # Most owed first: the class to look at.
    return sorted(lines, key=lambda line: (line["currency_code"], -Decimal(line["outstanding"]), line["class_section"]))


def _upcoming(school_id: int, today: dt.date) -> list[dict]:
    """What is scheduled to fall due in each of the next three months and is
    not yet paid - from the fee plans as they stand, not a forecast."""
    months = []
    first = next_period(today.replace(day=1), MONTH)

    for _ in range(UPCOMING_MONTHS):
        following = next_period(first, MONTH)
        last = following - dt.timedelta(days=1)
        rows = (
            StudentFeeDue.objects.filter(school_id=school_id, status__in=OPEN, due_date__range=(first, last))
            .order_by()
            .values("currency_code")
            .annotate(due=Sum(F("amount") - F("discount_amount") - F("paid_amount")))
        )
        months.append({"from": first.isoformat(), "to": last.isoformat(), "amounts": _by_currency(rows, "due")})
        first = following

    return months


def _fees_vs_payroll(school_id: int, first: dt.date, last: dt.date) -> dict:
    """Fees that came in during the month against the payroll the school
    finalized for it - net pay, the money that leaves."""
    fees = dict(
        FeeReceipt.objects.filter(school_id=school_id, receipt_date__range=(first, last))
        .exclude(status=FeeReceiptStatus.CANCELLED)
        .order_by()
        .values("currency_code")
        .annotate(total=Sum("amount"))
        .values_list("currency_code", "total")
    )
    payroll = dict(
        Payslip.objects.filter(
            payroll_run__school_id=school_id,
            payroll_run__year=first.year,
            payroll_run__month=first.month,
            payroll_run__status__in=(PayrollRunStatus.FINALIZED, PayrollRunStatus.PAID),
        )
        .order_by()
        .values("currency_code")
        .annotate(total=Sum("net_pay"))
        .values_list("currency_code", "total")
    )

    return {
        "from": first.isoformat(),
        "to": last.isoformat(),
        "amounts": [
            {"currency_code": code, "fees_in": cash(fees.get(code)), "payroll_out": cash(payroll.get(code))}
            for code in sorted(set(fees) | set(payroll))
        ],
    }
