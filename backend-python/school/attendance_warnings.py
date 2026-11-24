"""Attendance warnings to parents (docs/mobile-apps-review.md, M8, 5.4).

Decided 2026-11-24: when a child's attendance falls below the school's
early-warning line, the family is told once, in the Family app, with the
figure - and not again until it has come back up to the line and fallen
again.

The figure is the office's own: Early Warning's attendance over the last 30
school days, counted over the days the child was marked, and only once
there are enough of them (early_warning.py). A parent is never told
something the school's Early Warning list does not also say.

Each drop is a row in `attendance_warnings`, open until attendance is back
up; the job closes it then, without a message. Run from cron with the other
evening jobs: after 6 PM on the school's clock, so the day's register is in.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from django.utils import timezone

from . import early_warning, modules
from .clock import SchoolClock
from .enums import MessageEvent, SchoolStatus, StudentStatus
from .family_homework import DIGEST_AT
from .models import AttendanceWarning, School, Student


def open_warning_of(student: Student) -> AttendanceWarning | None:
    return AttendanceWarning.objects.filter(student_id=student.id, cleared_at__isnull=True).order_by("-id").first()


def warning_resource(warning: AttendanceWarning | None) -> dict | None:
    """What the Family app's attendance screen shows while a warning stands."""
    if warning is None:
        return None

    return {"rate": str(warning.rate), "line": warning.line, "days": early_warning.ATTENDANCE_DAYS}


def check(at: dt.datetime | None = None, school_id: int | None = None) -> int:
    """Warns the families whose child has just fallen below the line, and
    closes the warnings of children back above it. Returns how many families
    were warned. [at] is for tests."""
    schools = School.objects.filter(status=SchoolStatus.ACTIVE)
    if school_id is not None:
        schools = schools.filter(pk=school_id)

    warned = 0
    for school in schools:
        if not modules.is_enabled(school.id, "family_app"):
            continue

        clock = SchoolClock.for_school(school.id)
        now = at.astimezone(clock.now().tzinfo) if at is not None else clock.now()
        if now.time() < DIGEST_AT:
            continue

        warned += _check_school(school, now.date())

    return warned


def _check_school(school: School, today: dt.date) -> int:
    from .notifications import copy_to_family_app

    line = early_warning.Thresholds.for_school(school.id).attendance_below
    windows = early_warning.Windows.ending(school.id, today)
    students = {s.id: s for s in Student.objects.filter(school_id=school.id, status=StudentStatus.ACTIVE)}
    rates = early_warning.attendance_rates(school.id, list(students), windows.attendance)
    open_rows = {
        row.student_id: row
        for row in AttendanceWarning.objects.filter(school_id=school.id, cleared_at__isnull=True)
    }
    now = timezone.now()
    warned = 0

    for student_id, rate in rates.items():
        open_row = open_rows.get(student_id)

        if rate >= line:
            # Back up to the line: the next drop may be told again.
            if open_row is not None:
                open_row.cleared_at = now
                open_row.updated_at = now
                open_row.save(update_fields=["cleared_at", "updated_at"])
            continue

        if open_row is not None:
            continue

        student = students[student_id]
        AttendanceWarning.objects.create(
            school_id=school.id, student_id=student_id, rate=Decimal(str(rate)), line=line,
            warned_at=now, created_at=now, updated_at=now,
        )
        copy_to_family_app(
            MessageEvent.ATTENDANCE_BELOW_LINE,
            student,
            {
                "student_name": student.name,
                "rate": f"{rate:g}%",
                "line": f"{line}%",
                "days": str(early_warning.ATTENDANCE_DAYS),
                "school_name": school.name,
            },
            subject="Attendance below the school's line",
        )
        warned += 1

    return warned
