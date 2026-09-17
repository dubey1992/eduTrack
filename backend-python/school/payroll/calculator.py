"""The arithmetic of a payslip, and nothing else.

Pure functions over plain values, so the rules in docs/payroll.md can be
tested exactly without a database. Every figure is a Decimal: this is money
somebody is paid, and a float would put a stray paisa into it.

The rules, as decided on 2026-09-17:

- Over the month's working days (weekdays that are not the school's
  holidays), a day counts as **paid** when the employee was present, on leave,
  or **not marked at all**; half when marked a half day; not at all when
  marked absent, or when it falls before they joined.
- **Everything is pro-rated** by paid days / working days - basic, earnings
  and deductions - rounded to 2 places, halves up. A month with no working day
  pays in full.
- **Adjustments** are one-off lines and are never pro-rated.
- **Net pay** never goes below zero; the shortfall is kept.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal

from ..enums import PayComponentType, StaffAttendanceStatus

ZERO = Decimal("0.00")
CENT = Decimal("0.01")
HALF = Decimal("0.5")
ONE = Decimal("1")


@dataclass(frozen=True)
class Days:
    working: int
    paid: Decimal
    absent: Decimal
    half: int
    unmarked: int
    before_joining: int


def days(working_dates: list[dt.date], marks: dict[dt.date, str], joining_date: dt.date | None) -> Days:
    """How many of the month's working days this employee is paid for.

    `marks` is the staff register for the month: date -> status. A working day
    missing from it was never marked, and is paid.
    """
    paid = Decimal("0")
    absent = Decimal("0")
    half = 0
    unmarked = 0
    before_joining = 0

    for date in working_dates:
        if joining_date is not None and date < joining_date:
            before_joining += 1
            continue

        status = marks.get(date)

        if status is None:
            unmarked += 1
            paid += ONE
        elif status == StaffAttendanceStatus.ABSENT:
            absent += ONE
        elif status == StaffAttendanceStatus.HALF_DAY:
            half += 1
            paid += HALF
        else:
            # Present, or on leave - approved leave is written onto the
            # register as `leave`, and approved leave is paid.
            paid += ONE

    return Days(len(working_dates), paid, absent, half, unmarked, before_joining)


def prorate(amount: Decimal, paid_days: Decimal, working_days: int) -> Decimal:
    """`amount x paid / working`, to the cent, halves up.

    A month with no working day at all - every weekday a holiday - pays in
    full: nobody failed to turn up for days that did not exist.
    """
    if working_days == 0:
        return money(amount)

    return money(Decimal(amount) * paid_days / Decimal(working_days))


def money(value) -> Decimal:
    return Decimal(value).quantize(CENT, rounding=ROUND_HALF_UP)


@dataclass(frozen=True)
class Totals:
    gross_earnings: Decimal
    total_deductions: Decimal
    net_pay: Decimal
    shortfall: Decimal


def totals(lines) -> Totals:
    """The payslip's figures from its lines - (type, amount) pairs.

    Net pay stops at zero. Deductions beyond what was earned are not a debt the
    payslip invents; the shortfall is recorded so somebody can deal with it.
    """
    gross = sum((money(amount) for type_, amount in lines if type_ == PayComponentType.EARNING), ZERO)
    deductions = sum((money(amount) for type_, amount in lines if type_ == PayComponentType.DEDUCTION), ZERO)
    net = gross - deductions

    return Totals(gross, deductions, max(net, ZERO), max(-net, ZERO))
