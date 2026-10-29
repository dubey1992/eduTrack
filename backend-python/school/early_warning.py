"""Student early warning (docs/analytics.md, A3): which students' attendance
or test results are low, or falling, and why.

Decided 2026-10-29. Four signals, each a sentence with the numbers it was
drawn from, so nothing on the screen is a verdict somebody has to trust:

- **low attendance**: under the school's line (75% unless it set its own)
  over the last 30 working days;
- **falling attendance**: down by the school's drop (10 points unless set)
  on the 30 working days before;
- **low test average**: under the school's pass mark, over the published
  results of the last 90 days;
- **falling test average**: down by the drop on the 90 days before.

One signal is "at risk", two or more "high risk".

Attendance is counted over the days a student was actually marked, not
over every working day: a register nobody took says nothing about the
child, and counting it would flag a whole class whose teacher forgot. For
the same reason a signal needs enough to go on - ten marked days, two
results - or it says nothing at all. One test is not a trend.

The test average is the Student Performance report's own, so a flag can
always be checked against the report the school prints.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field

from django.db.models import Count

from . import modules
from .clock import SchoolClock
from .enums import AttendanceStatus, StudentStatus
from .models import Attendance, Student
from .reports import StudentPerformanceReport
from .reports.range import ReportRange
from .services import HolidayService, php_number, php_round_1

ATTENDANCE_DAYS = 30
MARKS_DAYS = 90

# Fewer marked days than this and there is no attendance rate worth a flag.
ENOUGH_MARKED_DAYS = 10

# Fewer published results than this and there is no average worth a flag.
ENOUGH_RESULTS = 2

# Far enough back to find sixty working days through a long holiday.
LOOK_BACK_DAYS = 200

LOW_ATTENDANCE = "low_attendance"
FALLING_ATTENDANCE = "falling_attendance"
LOW_MARKS = "low_marks"
FALLING_MARKS = "falling_marks"

HIGH = "high"
AT_RISK = "at_risk"


@dataclass(frozen=True)
class Thresholds:
    attendance_below: int
    drop_points: int
    pass_mark: int

    @classmethod
    def for_school(cls, school_id: int) -> "Thresholds":
        return cls(
            attendance_below=int(modules.setting(school_id, "reports", "early_warning_attendance_below")),
            drop_points=int(modules.setting(school_id, "reports", "early_warning_drop_points")),
            pass_mark=int(modules.setting(school_id, "assessments", "pass_percentage")),
        )

    def to_dict(self) -> dict:
        return {
            "attendance_below": self.attendance_below,
            "drop_points": self.drop_points,
            "pass_mark": self.pass_mark,
        }


@dataclass(frozen=True)
class Scope:
    """Whose students, and which signals.

    `full` is the students every signal is shown for - None meaning the
    whole school (an admin), otherwise a class teacher's own classes.
    `department_ids` is a head of department's subjects: for students
    outside `full`, only the test signals, and only from those subjects.
    """

    full_section_ids: list[int] | None
    department_ids: list[int] = field(default_factory=list)

    @property
    def is_empty(self) -> bool:
        return self.full_section_ids == [] and not self.department_ids


@dataclass(frozen=True)
class Windows:
    attendance: list[dt.date]
    attendance_before: list[dt.date]
    marks: tuple[dt.date, dt.date]
    marks_before: tuple[dt.date, dt.date]

    @classmethod
    def ending(cls, school_id: int, today: dt.date) -> "Windows":
        dates = HolidayService.working_dates(school_id, today - dt.timedelta(days=LOOK_BACK_DAYS), today)
        marks_from = today - dt.timedelta(days=MARKS_DAYS - 1)

        return cls(
            attendance=dates[-ATTENDANCE_DAYS:],
            attendance_before=dates[-2 * ATTENDANCE_DAYS:-ATTENDANCE_DAYS],
            marks=(marks_from, today),
            marks_before=(marks_from - dt.timedelta(days=MARKS_DAYS), marks_from - dt.timedelta(days=1)),
        )

    def to_dict(self) -> dict:
        def span(dates):
            return None if not dates else {"from": dates[0].isoformat(), "to": dates[-1].isoformat()}

        return {
            "attendance": span(self.attendance),
            "attendance_before": span(self.attendance_before),
            "marks": {"from": self.marks[0].isoformat(), "to": self.marks[1].isoformat()},
            "marks_before": {"from": self.marks_before[0].isoformat(), "to": self.marks_before[1].isoformat()},
        }


def flagged(school_id: int, scope: Scope, class_section_id: int | None = None) -> dict:
    """Every flagged student in [scope] at the school, today, with the
    windows and lines they were judged by. Highest risk first."""
    today = SchoolClock.for_school(school_id).now().date()
    thresholds = Thresholds.for_school(school_id)
    windows = Windows.ending(school_id, today)
    summary = {"as_of": today.isoformat(), "thresholds": thresholds.to_dict(), "windows": windows.to_dict()}

    # A teacher with no class and no department: nobody to look at.
    if scope.is_empty:
        return {**summary, "rows": []}

    students = Student.objects.filter(school_id=school_id, status=StudentStatus.ACTIVE).select_related(
        "class_section__school_class"
    )
    if class_section_id:
        students = students.filter(class_section_id=class_section_id)

    students = {student.id: student for student in students}
    full = {
        student_id for student_id, student in students.items()
        if scope.full_section_ids is None or student.class_section_id in scope.full_section_ids
    }

    signals: dict[int, list[dict]] = {}

    if full and modules.is_enabled(school_id, "attendance"):
        for student_id, found in _attendance_signals(school_id, sorted(full), windows, thresholds).items():
            signals.setdefault(student_id, []).extend(found)

    if modules.is_enabled(school_id, "assessments"):
        if full:
            marks = _marks_signals(school_id, {}, windows, thresholds)
            for student_id in full & marks.keys():
                signals.setdefault(student_id, []).extend(marks[student_id])

        others = set(students) - full
        if others and scope.department_ids:
            marks = _marks_signals(school_id, {"department_ids": scope.department_ids}, windows, thresholds)
            for student_id in others & marks.keys():
                signals.setdefault(student_id, []).extend(marks[student_id])

    rows = [
        _row(students[student_id], found)
        for student_id, found in signals.items()
        if found and student_id in students
    ]
    rows.sort(key=lambda row: (row["level"] != HIGH, -len(row["signals"]), row["class_section"] or "", row["name"]))

    return {**summary, "rows": rows}


def _row(student, found: list[dict]) -> dict:
    section = student.class_section

    return {
        "student_id": student.id,
        "admission_number": student.admission_number,
        "name": student.name,
        "class_section_id": student.class_section_id,
        "class_section": None if section is None else f"{section.school_class.name} {section.name}",
        "level": HIGH if len(found) >= 2 else AT_RISK,
        "signals": found,
    }


def _attendance_signals(school_id: int, student_ids: list[int], windows: Windows, thresholds: Thresholds) -> dict:
    now = _attendance_rates(school_id, student_ids, windows.attendance)
    before = _attendance_rates(school_id, student_ids, windows.attendance_before)
    found: dict[int, list[dict]] = {}

    for student_id, rate in now.items():
        if rate < thresholds.attendance_below:
            found.setdefault(student_id, []).append(_signal(
                LOW_ATTENDANCE, rate, None,
                f"Attendance {_pct(rate)} over the last {ATTENDANCE_DAYS} school days, "
                f"below {thresholds.attendance_below}%.",
            ))

        earlier = before.get(student_id)
        if earlier is not None and earlier - rate >= thresholds.drop_points:
            found.setdefault(student_id, []).append(_signal(
                FALLING_ATTENDANCE, rate, earlier,
                f"Attendance down {_pct(earlier - rate, sign=False)} points, from {_pct(earlier)} to {_pct(rate)}.",
            ))

    return found


def _attendance_rates(school_id: int, student_ids: list[int], dates: list[dt.date]) -> dict[int, float]:
    """Present out of the days each student was marked - only for those
    marked often enough to say anything."""
    if not dates:
        return {}

    counts: dict[int, dict[str, int]] = {}
    grouped = (
        Attendance.objects.filter(school_id=school_id, student_id__in=student_ids, attendance_date__in=dates)
        .values("student_id", "status")
        .annotate(total=Count("id"))
        .order_by()
    )
    for line in grouped:
        counts.setdefault(line["student_id"], {})[line["status"]] = line["total"]

    rates = {}
    for student_id, by_status in counts.items():
        marked = sum(by_status.values())
        if marked >= ENOUGH_MARKED_DAYS:
            rates[student_id] = php_round_1(by_status.get(AttendanceStatus.PRESENT, 0) / marked * 100)

    return rates


def _marks_signals(school_id: int, filters: dict, windows: Windows, thresholds: Thresholds) -> dict:
    now = _averages(school_id, filters, windows.marks)
    before = _averages(school_id, filters, windows.marks_before)
    found: dict[int, list[dict]] = {}

    for student_id, average in now.items():
        if average < thresholds.pass_mark:
            found.setdefault(student_id, []).append(_signal(
                LOW_MARKS, average, None,
                f"Test average {_pct(average)} over the last {MARKS_DAYS} days, "
                f"below the {thresholds.pass_mark}% pass mark.",
            ))

        earlier = before.get(student_id)
        if earlier is not None and earlier - average >= thresholds.drop_points:
            found.setdefault(student_id, []).append(_signal(
                FALLING_MARKS, average, earlier,
                f"Test average down {_pct(earlier - average, sign=False)} points, "
                f"from {_pct(earlier)} to {_pct(average)}.",
            ))

    return found


def _averages(school_id: int, filters: dict, span: tuple[dt.date, dt.date]) -> dict[int, float]:
    """Each student's average over the span, as the Student Performance
    report gives it - for those with enough results to say anything."""
    report = StudentPerformanceReport().build(ReportRange(school_id, span[0], span[1], []), filters)

    return {
        row["student_id"]: float(row["average_percentage"])
        for row in report["rows"]
        if row["average_percentage"] is not None and row["assessments"] - row["absent"] >= ENOUGH_RESULTS
    }


def _signal(code: str, value: float, previous: float | None, message: str) -> dict:
    return {
        "code": code,
        "value": php_number(value),
        "previous": php_number(previous),
        "message": message,
    }


def _pct(value: float, sign: bool = True) -> str:
    text = f"{php_round_1(value):g}"

    return f"{text}%" if sign else text
