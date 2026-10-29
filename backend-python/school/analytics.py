"""Analytics: the school's figures week by week or month by month
(docs/analytics.md, A1).

A trend is the same figure a report already gives, asked for again for each
week or month in a range. So most measures here build no figure of their own:
each runs the report that owns it once per period, and the chart can never
disagree with the report a head teacher prints. A week of holidays has no
attendance rate in the report, so it has a gap in the chart, not a zero.

Four measures cannot be rebuilt for a past day - how many students and staff
a school had, and what it was owed - so `record_analytics_snapshots` writes
them down nightly, and those read the last snapshot inside each period. A
period from before the first snapshot has no value, never a guess.

Money is never added across currencies: a money point carries one amount per
currency.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass
from decimal import Decimal
from typing import Callable

from .enums import StudentStatus, UserRole, UserStatus
from .models import AnalyticsSchoolDay, AnalyticsSchoolFeeDay, School, StaffProfile, Student
from .reports import (
    ClassPerformanceReport,
    FeeCollectionReport,
    FeeOutstandingReport,
    StaffAttendanceReport,
    StudentAttendanceReport,
    SyllabusProgressReport,
    TeachingCoverageReport,
)
from .reports.fees import ZERO, cash
from .reports.range import ReportRange, rate_of
from .services import HolidayService, php_number

ADMINS = (UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN)

WEEK = "week"
MONTH = "month"
INTERVALS = (WEEK, MONTH)

# How many periods one request may ask for: two years of months, one of
# weeks. Each period runs a report, so this is what keeps a request quick.
MAX_PERIODS = {MONTH: 24, WEEK: 53}

# What a chart shows when nobody names a range: the last twelve periods,
# this one included.
DEFAULT_PERIODS = 12

PERCENT = "percent"
COUNT = "count"
MONEY = "money"


@dataclass(frozen=True)
class Measure:
    key: str
    label: str
    unit: str
    # Who may chart it: the same audience as the report it comes from. None
    # means the fees row of the permissions matrix decides, as for the fee
    # reports.
    roles: tuple | None
    # The value for one school over one period.
    value: Callable[[ReportRange, dict], object]
    # Narrowing a measure accepts; anything else in the request is ignored.
    filters: tuple[str, ...] = ()
    module: str | None = None
    # Recorded nightly rather than counted from history.
    snapshot: bool = False


def _student_attendance(period: ReportRange, filters: dict):
    totals = StudentAttendanceReport().build(period, filters)["totals"]

    # No register taken at all is a gap, as on the dashboard's trend: nobody
    # was absent, nobody was counted. The report says 0% with every day "not
    # marked" beside it; a chart has no room for that, and 0% alone reads as
    # an empty school.
    if totals["present"] + totals["absent"] + totals["leave"] == 0:
        return None

    return totals["attendance_rate"]


def _staff_attendance(period: ReportRange, filters: dict):
    """Worked out from the rows, the way each person's own rate is: a half
    day is half a day present. The report has no school-wide rate."""
    rows = StaffAttendanceReport().build(period, filters)["rows"]

    # As for students: no attendance taken at all is a gap, not 0%.
    if not any(row["present"] + row["half_day"] + row["absent"] + row["leave"] for row in rows):
        return None

    attended = sum(row["present"] + row["half_day"] / 2 for row in rows)

    return php_number(rate_of(attended, len(rows) * period.working_day_count()))


def _teaching_coverage(period: ReportRange, filters: dict):
    return TeachingCoverageReport().build(period, filters)["totals"]["coverage_rate"]


def _topics_completed(period: ReportRange, filters: dict):
    return SyllabusProgressReport().build(period, filters)["totals"]["completed_in_period"]


def _test_average(period: ReportRange, filters: dict):
    return ClassPerformanceReport().build(period, filters)["totals"]["average_percentage"]


def _fees_collected(period: ReportRange, filters: dict):
    collected = FeeCollectionReport().build(period, filters)["totals"]["collected"]

    return [{"currency_code": line["currency_code"], "amount": line["amount"]} for line in collected]


def _last_day(period: ReportRange):
    """The school's last snapshot inside the period, or None before the
    first one."""
    return (
        AnalyticsSchoolDay.objects.filter(
            school_id=period.school_id, snapshot_date__range=(period.start, period.end)
        )
        .order_by("-snapshot_date")
        .first()
    )


def _active_students(period: ReportRange, filters: dict):
    day = _last_day(period)

    return None if day is None else day.active_students


def _active_staff(period: ReportRange, filters: dict):
    day = _last_day(period)

    return None if day is None else day.active_staff


def _fee_snapshot(field: str):
    def value(period: ReportRange, filters: dict):
        last = (
            AnalyticsSchoolFeeDay.objects.filter(
                school_id=period.school_id, snapshot_date__range=(period.start, period.end)
            )
            .order_by("-snapshot_date")
            .values_list("snapshot_date", flat=True)
            .first()
        )

        if last is None:
            return None

        lines = AnalyticsSchoolFeeDay.objects.filter(school_id=period.school_id, snapshot_date=last)

        return [
            {"currency_code": line.currency_code, "amount": cash(getattr(line, field))}
            for line in lines.order_by("currency_code")
        ]

    return value


MEASURES = {
    measure.key: measure
    for measure in (
        Measure(
            "student_attendance_rate", "Student attendance", PERCENT, ADMINS, _student_attendance,
            filters=("class_section_id",),
        ),
        Measure(
            "staff_attendance_rate", "Staff attendance", PERCENT, (*ADMINS, UserRole.HOD, UserRole.ACCOUNTANT),
            _staff_attendance, filters=("department_id",),
        ),
        Measure("teaching_coverage_rate", "Teaching reports filed", PERCENT, (*ADMINS, UserRole.HOD), _teaching_coverage),
        Measure(
            "syllabus_topics_completed", "Syllabus topics completed", COUNT, (*ADMINS, UserRole.HOD),
            _topics_completed, filters=("class_section_id",),
        ),
        Measure(
            "test_average", "Average test score", PERCENT, (*ADMINS, UserRole.HOD), _test_average,
            filters=("class_section_id",),
        ),
        Measure("fees_collected", "Fees collected", MONEY, None, _fees_collected, module="fees"),
        Measure("active_students", "Students on roll", COUNT, ADMINS, _active_students, snapshot=True),
        Measure("active_staff", "Staff on roll", COUNT, ADMINS, _active_staff, snapshot=True),
        Measure(
            "fee_outstanding", "Fees outstanding", MONEY, None, _fee_snapshot("outstanding"), module="fees",
            snapshot=True,
        ),
        Measure(
            "fee_overdue", "Fees overdue", MONEY, None, _fee_snapshot("overdue"), module="fees", snapshot=True,
        ),
    )
}


# -- periods -------------------------------------------------------------------


def period_start(day: dt.date, interval: str) -> dt.date:
    """The Monday of the day's week, or the first of its month."""
    if interval == WEEK:
        return day - dt.timedelta(days=day.weekday())

    return day.replace(day=1)


def next_period(start: dt.date, interval: str) -> dt.date:
    if interval == WEEK:
        return start + dt.timedelta(days=7)

    return (start.replace(day=28) + dt.timedelta(days=4)).replace(day=1)


def default_from(today: dt.date, interval: str) -> dt.date:
    """The start of the period eleven before today's, so a chart with no
    range shows twelve."""
    start = period_start(today, interval)

    for _ in range(DEFAULT_PERIODS - 1):
        start = period_start(start - dt.timedelta(days=1), interval)

    return start


def periods(start: dt.date, end: dt.date, interval: str) -> list[tuple[dt.date, dt.date]]:
    """Whole weeks or months covering start..end, the first and last cut
    to the range - a chart from the 10th starts on the 10th, it does not
    quietly count the days before it."""
    spans = []
    current = period_start(start, interval)

    while current <= end:
        following = next_period(current, interval)
        spans.append((max(current, start), min(following - dt.timedelta(days=1), end)))
        current = following

    return spans


def period_count(start: dt.date, end: dt.date, interval: str) -> int:
    return len(periods(start, end, interval))


# -- the series ----------------------------------------------------------------


def series(school_id: int, measure: Measure, interval: str, start: dt.date, end: dt.date, filters: dict) -> dict:
    """One school's measure for every period in the range."""
    points = []

    for period_from, period_to in periods(start, end, interval):
        period = ReportRange(
            school_id, period_from, period_to, HolidayService.working_dates(school_id, period_from, period_to)
        )
        point = {
            "from": period_from.isoformat(),
            "to": period_to.isoformat(),
            "working_days": period.working_day_count(),
        }

        value = measure.value(period, filters)

        if measure.unit == MONEY:
            point["amounts"] = value
        else:
            point["value"] = value

        points.append(point)

    return {
        "measure": measure.key,
        "label": measure.label,
        "unit": measure.unit,
        "interval": interval,
        "from": start.isoformat(),
        "to": end.isoformat(),
        "points": points,
    }


# -- snapshots -----------------------------------------------------------------


def record_snapshot(school_id: int, day: dt.date, now: dt.datetime) -> None:
    """Writes the school's roll and what it is owed for [day], replacing what
    an earlier run wrote for the same day.

    Owed is counted exactly as the outstanding-fees report counts it on that
    day - due on or before it, discounts taken off, waived and cancelled dues
    left out - so a chart point always matches the report run that day.
    """
    students = Student.objects.filter(school_id=school_id, status=StudentStatus.ACTIVE).count()
    staff = StaffProfile.objects.filter(school_id=school_id, user__status=UserStatus.ACTIVE).count()

    AnalyticsSchoolDay.objects.update_or_create(
        school_id=school_id,
        snapshot_date=day,
        defaults={"active_students": students, "active_staff": staff, "updated_at": now},
        create_defaults={"active_students": students, "active_staff": staff, "created_at": now, "updated_at": now},
    )

    owed = FeeOutstandingReport().build(ReportRange(school_id, day, day, []), {})["totals"]["by_currency"]

    # Owing nothing is a figure, not a gap: nought in the school's own
    # currency, so the chart reads 0 rather than "no data yet".
    if not owed:
        currency = School.objects.filter(pk=school_id).values_list("currency_code", flat=True).first()
        owed = [{"currency_code": currency, "balance": "0.00", "overdue_0_30": "0.00", "overdue_31_60": "0.00",
                 "overdue_61_plus": "0.00"}]

    currencies = []

    for line in owed:
        overdue = sum(
            (Decimal(line[key]) for key in ("overdue_0_30", "overdue_31_60", "overdue_61_plus")), ZERO
        )
        values = {"outstanding": Decimal(line["balance"]), "overdue": overdue}
        currencies.append(line["currency_code"])

        AnalyticsSchoolFeeDay.objects.update_or_create(
            school_id=school_id,
            snapshot_date=day,
            currency_code=line["currency_code"],
            defaults={**values, "updated_at": now},
            create_defaults={**values, "created_at": now, "updated_at": now},
        )

    # A currency nothing is owed in any more since an earlier run today.
    AnalyticsSchoolFeeDay.objects.filter(school_id=school_id, snapshot_date=day).exclude(
        currency_code__in=currencies
    ).delete()
