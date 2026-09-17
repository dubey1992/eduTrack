"""The window a report covers, and the working days inside it.

Port of App\\Support\\Reports\\ReportRange. Every percentage in a report is
"out of the days the school actually ran", so the denominator is computed
once, here, from the same holiday calendar that decides whether a register
may be taken at all.
"""

from __future__ import annotations

import datetime as dt

from ..clock import SchoolClock
from ..services import HolidayService, php_round_1


class ReportRange:
    def __init__(self, school_id: int, start: dt.date, end: dt.date, working_dates: list[dt.date]) -> None:
        self.school_id = school_id
        self.start = start
        self.end = end
        self.working_dates = working_dates

    @classmethod
    def from_filters(cls, school_id: int, filters: dict) -> "ReportRange":
        """An absent range means "this month so far" at the school - never to
        the end of a month that has not happened, which would report a
        percentage against days nobody has taught yet."""
        today = SchoolClock.for_school(school_id).now().date()

        start = filters.get("from") or today.replace(day=1)
        # Never past today at the school: days that have not happened are not
        # days anyone failed to mark.
        end = min(filters.get("to") or today, today)

        return cls(school_id, start, end, HolidayService.working_dates(school_id, start, end))

    def working_day_count(self) -> int:
        return len(self.working_dates)

    def rate(self, count: int) -> float | None:
        """A percentage of the working days in this range, to one decimal.

        None rather than zero when the range holds no working day at all - a
        week of holidays has no attendance rate, and "0%" would read as
        everybody being absent.
        """
        days = self.working_day_count()

        return None if days == 0 else php_round_1(count / days * 100)

    def to_dict(self) -> dict:
        return {
            "from": self.start.isoformat(),
            "to": self.end.isoformat(),
            "working_days": self.working_day_count(),
        }


def rate_of(part: int, whole: int) -> float | None:
    """`part` as a percentage of `whole` to one decimal, or None when there is
    no whole to measure against."""
    return None if whole == 0 else php_round_1(part / whole * 100)
