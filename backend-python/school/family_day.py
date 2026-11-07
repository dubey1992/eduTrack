"""What the Family app shows a parent about one child (docs/parent-student-app.md, F1).

Read only. Every function takes a child the caller has already been checked
against (FamilyAuthService.child_of), so nothing here decides who may see
what - and nothing here reaches past that one child.

- `today_for`      - the home screen: in school or not, the bus, the next
                     fee due, today's periods.
- `month_for`      - the attendance calendar for one month, with the
                     month's and the year's percentage.
- `calendar_for`   - the school's holidays and the days of the week it is
                     closed, for one month.

Dates are the school's, from SchoolClock: a parent in another timezone
still sees the school's today.
"""

from __future__ import annotations

import calendar
import datetime as dt

from . import week
from .clock import SchoolClock
from .enums import AttendanceStatus
from .fees.ledger import balance_of, is_overdue, owed
from .models import (
    AcademicYear,
    Attendance,
    Holiday,
    School,
    SchoolBreak,
    Student,
    StudentFeeDue,
    StudentTransportAssignment,
    TransportTrip,
    TransportTripRider,
)
from .reports.range import rate_of
from .services import HolidayService, TimetableService
from .today import period_state

# What a day on the attendance calendar can be.
PRESENT = AttendanceStatus.PRESENT
ABSENT = AttendanceStatus.ABSENT
LEAVE = AttendanceStatus.LEAVE
NOT_MARKED = "not_marked"
HOLIDAY = "holiday"
CLOSED = "closed"
FUTURE = "future"


def money(value) -> str:
    """An amount as the API sends every amount: a two-place decimal string."""
    return f"{value:.2f}"


def school_today(student: Student, at: dt.datetime | None = None) -> dt.datetime:
    clock = SchoolClock.for_school(student.school_id)
    return at.astimezone(clock.now().tzinfo) if at is not None else clock.now()


def holidays_between(school_id, start: dt.date, end: dt.date) -> list[Holiday]:
    return list(
        Holiday.objects.filter(school_id=school_id, start_date__lte=end, end_date__gte=start).order_by(
            "start_date", "id"
        )
    )


def holiday_covering(holidays: list[Holiday], day: dt.date) -> Holiday | None:
    return next((holiday for holiday in holidays if holiday.start_date <= day <= holiday.end_date), None)


# -- today ----------------------------------------------------------------------


def today_for(student: Student, at: dt.datetime | None = None) -> dict:
    now = school_today(student, at)
    today = now.date()
    school = School.objects.get(pk=student.school_id)
    shape = week.WorkingWeek(school.working_days).shape_on(today)
    holiday = HolidayService.holiday_on(student.school_id, today)
    is_open = shape is not None and holiday is None

    return {
        "date": today.isoformat(),
        "now": now.strftime("%H:%M"),
        "school_day": {
            "is_open": is_open,
            "shape": shape,
            "holiday": {"name": holiday.name, "type": holiday.type} if holiday else None,
        },
        "attendance": attendance_on(student, today) if is_open else None,
        "bus": bus_today(student, today),
        "fee": next_fee(student, today),
        "periods": periods_for(student, today, shape, now.time()) if is_open else [],
        "breaks": breaks_for(student.school_id, shape, now.time()) if is_open else [],
    }


def attendance_on(student: Student, day: dt.date) -> dict:
    """The register's word for the child today, or "not marked yet"."""
    mark = Attendance.objects.filter(student_id=student.id, attendance_date=day).first()

    if mark is None:
        return {"status": NOT_MARKED, "remarks": None}

    return {"status": mark.status, "remarks": mark.remarks or None}


def bus_today(student: Student, today: dt.date) -> dict | None:
    """The child's route and stop, and each of today's trips as it stands for
    them. None for a child the school does not carry."""
    assignment = (
        StudentTransportAssignment.objects.select_related("route", "transport_stop")
        .filter(student_id=student.id)
        .first()
    )

    if assignment is None:
        return None

    clock = SchoolClock.for_school(student.school_id)
    trips = TransportTrip.objects.filter(route_id=assignment.route_id, trip_date=today).order_by("id")
    riders = {
        rider.trip_id: rider
        for rider in TransportTripRider.objects.filter(student_id=student.id, trip__in=trips)
    }
    stop = assignment.transport_stop

    zone = clock.now().tzinfo

    def at(instant):
        """A boarding or drop time on the school's clock, "07:42"."""
        return instant.astimezone(zone).strftime("%H:%M") if instant else None

    return {
        "route": assignment.route.name,
        "stop": stop.name if stop else None,
        "pickup_time": stop.pickup_time.strftime("%H:%M") if stop and stop.pickup_time else None,
        "drop_time": stop.drop_time.strftime("%H:%M") if stop and stop.drop_time else None,
        "trips": [
            {
                "direction": trip.direction,
                "status": trip.status,
                # Pending until the attendant marks them; a child not on this
                # trip's list (joined the route today) has no row at all.
                "rider_status": riders[trip.id].status if trip.id in riders else None,
                "boarded_at": at(riders[trip.id].boarded_at) if trip.id in riders else None,
                "dropped_at": at(riders[trip.id].dropped_at) if trip.id in riders else None,
            }
            for trip in trips
        ],
    }


def next_fee(student: Student, today: dt.date) -> dict | None:
    """The earliest due the child still owes on, whatever the year."""
    due = owed(StudentFeeDue.objects.filter(student_id=student.id)).order_by("due_date", "id").first()

    if due is None:
        return None

    return {
        "label": due.label,
        "due_date": due.due_date.isoformat(),
        "amount": money(balance_of(due)),
        "currency_code": due.currency_code,
        "is_overdue": is_overdue(due, today),
    }


def periods_for(student: Student, today: dt.date, shape: str, now: dt.time) -> list[dict]:
    """The child's class's periods today, earliest first - only the periods
    of today's shape, as a teacher's Today counts them."""
    if student.class_section_id is None:
        return []

    entries = (
        TimetableService.this_year(TimetableService.for_class_section(student.class_section_id), student.school_id)
        .filter(day_of_week=week.DAYS[today.weekday()], period__day_shape=shape)
        .order_by("period__start_time", "period__period_number")
    )

    return [
        {
            "period_number": entry.period.period_number,
            "start_time": entry.period.start_time.strftime("%H:%M"),
            "end_time": entry.period.end_time.strftime("%H:%M"),
            "state": period_state(entry.period.start_time, entry.period.end_time, now),
            "subject": entry.subject.name if entry.subject_id else None,
            "teacher": entry.teacher.name if entry.teacher_id else None,
        }
        for entry in entries
    ]


def breaks_for(school_id, shape: str, now: dt.time) -> list[dict]:
    return [
        {
            "name": row.name,
            "start_time": row.start_time.strftime("%H:%M"),
            "end_time": row.end_time.strftime("%H:%M"),
            "state": period_state(row.start_time, row.end_time, now),
        }
        for row in SchoolBreak.objects.filter(school_id=school_id, day_shape=shape).order_by("start_time", "id")
    ]


# -- attendance -------------------------------------------------------------------


def counts(student: Student, working: list[dt.date]) -> dict:
    """Present, absent and leave over these working days, and the rate.

    A mark on a day that later became a holiday stops counting, as in the
    Phase 18 reports, and leave is not present. But for a parent the rate is
    over the days the register was *marked*: a day the school never marked
    is the school's gap, not the child's absence, and counting it would show
    a child who came every day at 15%. How many were not marked is sent too,
    so the app can say so.
    """
    marks = Attendance.objects.filter(student_id=student.id, attendance_date__in=working).values_list(
        "status", flat=True
    )
    tally = {PRESENT: 0, ABSENT: 0, LEAVE: 0}
    for status in marks:
        if status in tally:
            tally[status] += 1

    days = len(working)
    marked = sum(tally.values())
    return {
        "working_days": days,
        "marked_days": marked,
        "present": tally[PRESENT],
        "absent": tally[ABSENT],
        "leave": tally[LEAVE],
        "not_marked": max(0, days - marked),
        "rate": rate_of(tally[PRESENT], marked) if marked else None,
    }


def month_for(student: Student, year: int, month: int, at: dt.datetime | None = None) -> dict:
    today = school_today(student, at).date()
    first = dt.date(year, month, 1)
    last = dt.date(year, month, calendar.monthrange(year, month)[1])
    school = School.objects.get(pk=student.school_id)
    working_week = week.WorkingWeek(school.working_days)
    holidays = holidays_between(student.school_id, first, last)
    marks = {
        mark.attendance_date: mark
        for mark in Attendance.objects.filter(student_id=student.id, attendance_date__range=(first, last))
    }

    days = []
    for number in range(1, last.day + 1):
        day = dt.date(year, month, number)
        holiday = holiday_covering(holidays, day)
        mark = marks.get(day)

        if holiday is not None:
            kind = HOLIDAY
        elif not working_week.runs_on(day):
            kind = CLOSED
        elif day > today:
            kind = FUTURE
        elif mark is not None:
            kind = mark.status
        else:
            kind = NOT_MARKED

        days.append(
            {
                "date": day.isoformat(),
                "kind": kind,
                "holiday": holiday.name if holiday else None,
                # The teacher's note on an absence or a leave - the reason.
                "remarks": (mark.remarks or None) if mark is not None and kind in (ABSENT, LEAVE) else None,
            }
        )

    return {
        "month": f"{year:04d}-{month:02d}",
        "today": today.isoformat(),
        "days": days,
        "month_summary": counts(student, HolidayService.working_dates(student.school_id, first, min(last, today))),
        "year_summary": year_summary(student, today),
    }


def year_summary(student: Student, today: dt.date) -> dict | None:
    """The school year so far, which is what "your child's attendance" means
    to a parent. None before the year has a current academic year."""
    year = AcademicYear.objects.filter(school_id=student.school_id, is_current=True).first()

    if year is None or today < year.start_date:
        return None

    working = HolidayService.working_dates(student.school_id, year.start_date, min(today, year.end_date))
    return {"label": year.name, "since": year.start_date.isoformat(), **counts(student, working)}


# -- the school calendar ------------------------------------------------------------


def calendar_for(school_id, year: int, month: int, at: dt.datetime | None = None) -> dict:
    """The school's holidays this month, the next few coming up, and the
    days of the week it never opens. The same for every child at it."""
    clock = SchoolClock.for_school(school_id)
    today = (at.astimezone(clock.now().tzinfo) if at is not None else clock.now()).date()
    first = dt.date(year, month, 1)
    last = dt.date(year, month, calendar.monthrange(year, month)[1])
    school = School.objects.get(pk=school_id)
    working_week = week.WorkingWeek(school.working_days)
    # Any Monday, to ask the week about each weekday in turn.
    monday = dt.date(2024, 1, 1)

    upcoming = Holiday.objects.filter(school_id=school_id, end_date__gte=today).order_by("start_date", "id")

    return {
        "month": f"{year:04d}-{month:02d}",
        "today": today.isoformat(),
        "closed_weekdays": [
            week.DAYS[index] for index in range(7) if not working_week.runs_on(monday + dt.timedelta(days=index))
        ],
        "holidays": [holiday_resource(holiday) for holiday in holidays_between(school_id, first, last)],
        "upcoming": [holiday_resource(holiday) for holiday in upcoming[:3]],
    }


def holiday_resource(holiday: Holiday) -> dict:
    return {
        "name": holiday.name,
        "type": holiday.type,
        "start_date": holiday.start_date.isoformat(),
        "end_date": holiday.end_date.isoformat(),
    }
