"""A teacher's day, in the order they live it (docs/teacher-app.md, T1).

The Teacher app opens on this. One call answers what the timetable grid,
the register and the teaching reports would otherwise take three to say:
which periods are mine today, which one is now, and what I still owe.

Two things are owed, and they are owed differently:

- **A teaching report** is owed per period, by whoever taught it, once the
  period has started. A period later in the day is not owed yet.
- **A register** is owed per class, once a day, by its class teacher - the
  only teacher the server lets mark it. So it is listed on its own, not on
  every period that teacher happens to teach in that class.

Nothing is owed on a day the school is closed, by its week or by a holiday,
or while the teacher is on approved leave.

Always the caller's own day. There is no teacher parameter to change.
"""

from __future__ import annotations

import datetime as dt

from . import week
from .clock import SchoolClock
from .enums import LeaveStatus
from .models import Attendance, ClassSection, DailyTeachingReport, School, StaffLeave, User
from .services import HolidayService, TimetableService, holiday_summary

DONE = "done"
CURRENT = "current"
UPCOMING = "upcoming"


def section_label(section: ClassSection) -> str:
    return f"{section.school_class.name} {section.name}".strip()


def period_state(start: dt.time, end: dt.time, now: dt.time) -> str:
    if now >= end:
        return DONE

    if now >= start:
        return CURRENT

    return UPCOMING


def day_for(teacher: User, at: dt.datetime | None = None) -> dict:
    """The day as the teacher's school sees it. `at` is for tests; the app
    always asks about now."""
    clock = SchoolClock.for_user(teacher)
    now = at.astimezone(clock.now().tzinfo) if at is not None else clock.now()
    today = now.date()

    school = School.objects.filter(pk=teacher.school_id).first()
    shape = week.WorkingWeek(school.working_days if school else None).shape_on(today)
    holiday = HolidayService.holiday_on(teacher.school_id, today) if teacher.school_id else None
    is_open = shape is not None and holiday is None

    leave = leave_for(teacher, today)
    on_leave = leave["today"] is not None

    periods = periods_for(teacher, today, shape, now.time()) if is_open else []
    registers = registers_for(teacher, today) if is_open else []

    owes = is_open and not on_leave

    return {
        "date": today.isoformat(),
        "weekday": week.DAYS[today.weekday()],
        "now": now.strftime("%H:%M"),
        "school_day": {
            "is_open": is_open,
            "shape": shape,
            "holiday": holiday_summary(holiday) if holiday is not None else None,
        },
        "periods": periods,
        "registers": registers,
        "leave": leave,
        "owed": {
            "reports": sum(1 for p in periods if p["state"] != UPCOMING and not p["report"]["filed"]) if owes else 0,
            "registers": sum(1 for r in registers if not r["submitted"]) if owes else 0,
        },
    }


def periods_for(teacher: User, today: dt.date, shape: str, now: dt.time) -> list[dict]:
    """The teacher's periods today, earliest first.

    A half day rings its own, shorter bells, so only the periods of today's
    shape count - a full day's sixth period does not exist on a half day.
    """
    entries = (
        TimetableService.for_teacher(teacher)
        .filter(day_of_week=week.DAYS[today.weekday()], period__day_shape=shape)
        .order_by("period__start_time", "period__period_number")
    )
    entries = list(entries)

    reports = {
        report.timetable_entry_id: report.id
        for report in DailyTeachingReport.objects.filter(
            teacher_id=teacher.id, report_date=today, timetable_entry_id__in=[entry.id for entry in entries]
        )
    }

    return [
        {
            "timetable_entry_id": entry.id,
            "period_id": entry.period_id,
            "period_number": entry.period.period_number,
            "start_time": entry.period.start_time.strftime("%H:%M"),
            "end_time": entry.period.end_time.strftime("%H:%M"),
            "state": period_state(entry.period.start_time, entry.period.end_time, now),
            "class_section_id": entry.class_section_id,
            "class_section": section_label(entry.class_section),
            "subject_id": entry.subject_id,
            "subject": entry.subject.name,
            "report": {"filed": entry.id in reports, "id": reports.get(entry.id)},
        }
        for entry in entries
    ]


def registers_for(teacher: User, today: dt.date) -> list[dict]:
    """The classes this teacher is class teacher of this year, and whether
    each one's register is in for today."""
    year_id = TimetableService.current_year_id(teacher.school_id)

    if year_id is None:
        return []

    sections = list(
        ClassSection.objects.select_related("school_class")
        .filter(class_teacher_id=teacher.id, school_class__academic_year_id=year_id)
        .order_by("school_class__name", "name")
    )
    submitted = set(
        Attendance.objects.filter(
            class_section_id__in=[section.id for section in sections], attendance_date=today
        ).values_list("class_section_id", flat=True)
    )

    return [
        {
            "class_section_id": section.id,
            "class_section": section_label(section),
            "submitted": section.id in submitted,
        }
        for section in sections
    ]


def leave_for(teacher: User, today: dt.date) -> dict:
    """The teacher's approved leave this week, Monday to Sunday, and the
    one that covers today if any."""
    monday = today - dt.timedelta(days=today.weekday())
    sunday = monday + dt.timedelta(days=6)

    leaves = list(
        StaffLeave.objects.filter(
            staff_profile__user_id=teacher.id,
            status=LeaveStatus.APPROVED,
            start_date__lte=sunday,
            end_date__gte=monday,
        ).order_by("start_date")
    )

    def summary(leave: StaffLeave) -> dict:
        return {
            "id": leave.id,
            "leave_type": leave.leave_type,
            "start_date": leave.start_date.isoformat(),
            "end_date": leave.end_date.isoformat(),
        }

    covering = next((leave for leave in leaves if leave.start_date <= today <= leave.end_date), None)

    return {
        "today": summary(covering) if covering is not None else None,
        "this_week": [summary(leave) for leave in leaves],
    }
