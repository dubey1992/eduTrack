"""Suggested installments for a fee: what the Fee Setup form fills in when the
Accountant picks a frequency (docs/fees.md, "What is charged").

Suggestions only - nothing here is saved. The Accountant adjusts the dates
and amounts, and the structure's own validation (requests.py) decides what
may be stored. Pure functions over dates and Decimals, so the arithmetic is
tested without a database.
"""

from __future__ import annotations

import calendar
import datetime as dt
from dataclasses import dataclass
from decimal import ROUND_DOWN, Decimal

from ..enums import FeeFrequency

CENT = Decimal("0.01")


@dataclass(frozen=True)
class Term:
    name: str
    start_date: dt.date


class NoTerms(Exception):
    """A per-term plan for a year with no terms set up."""


def split(amount: Decimal, count: int) -> list[Decimal]:
    """`amount` in `count` parts, even to the cent, the remainder on the last:
    1000.00 in 3 is 333.33, 333.33, 333.34."""
    base = (amount / count).quantize(CENT, rounding=ROUND_DOWN)

    return [base] * (count - 1) + [amount - base * (count - 1)]


def on_day(year: int, month: int, day: int, start: dt.date, end: dt.date) -> dt.date:
    """`day` of the month, or its last day when the month is shorter - the
    31st in February is the 28th, or the 29th in a leap year - kept inside
    the academic year."""
    due = dt.date(year, month, min(day, calendar.monthrange(year, month)[1]))

    return min(max(due, start), end)


def months_between(start: dt.date, end: dt.date) -> list[tuple[int, int]]:
    """Every calendar month from `start`'s to `end`'s, inclusive."""
    months = []
    year, month = start.year, start.month

    while (year, month) <= (end.year, end.month):
        months.append((year, month))
        year, month = (year + 1, 1) if month == 12 else (year, month + 1)

    return months


def add_months(year: int, month: int, count: int) -> tuple[int, int]:
    index = year * 12 + (month - 1) + count

    return index // 12, index % 12 + 1


def dates_for(frequency: str, start: dt.date, end: dt.date, due_day: int, terms: list[Term]) -> list[tuple[str, dt.date]]:
    """(label, due date) for each installment the frequency offers."""
    if frequency == FeeFrequency.MONTHLY:
        return [
            (f"{calendar.month_name[month]} {year}", on_day(year, month, due_day, start, end))
            for year, month in months_between(start, end)
        ]

    if frequency == FeeFrequency.QUARTERLY:
        quarters = [add_months(start.year, start.month, 3 * index) for index in range(4)]

        return [
            (f"Quarter {index + 1}", on_day(year, month, due_day, start, end))
            for index, (year, month) in enumerate(quarters)
        ]

    if frequency == FeeFrequency.TERM:
        if not terms:
            raise NoTerms()

        return [(term.name, min(max(term.start_date, start), end)) for term in terms]

    if frequency == FeeFrequency.YEARLY:
        return [("Annual", start)]

    return [("One-time", start)]


def suggest(frequency: str, amount: Decimal, start: dt.date, end: dt.date, due_day: int = 10,
            terms: list[Term] | None = None) -> list[dict]:
    """The installments a frequency offers, with the amount split across
    them. Raises NoTerms for a per-term plan in a year without terms."""
    dates = dates_for(frequency, start, end, due_day, terms or [])
    amounts = split(amount, len(dates))

    return [
        {"label": label, "due_date": due, "amount": part}
        for (label, due), part in zip(dates, amounts)
    ]


def count_for(frequency: str, start: dt.date, end: dt.date, terms: list[Term] | None = None) -> int:
    """How many installments a frequency offers - without the dates."""
    if frequency == FeeFrequency.MONTHLY:
        return len(months_between(start, end))

    if frequency == FeeFrequency.QUARTERLY:
        return 4

    if frequency == FeeFrequency.TERM:
        return len(terms or [])

    return 1
