"""Whether a member of staff was at work on a day (decided 2026-11-02).

Teaching reports say what a teacher taught, so they are filed only for days
the teacher was marked present - by checking in, a fingerprint punch, or the
office - and never for a day of leave, approved or applied for. A school may
switch the rule off (teaching_reports module, `needs_attendance`).

A teacher with no staff record has no attendance to read, so the rule does
not apply to them: there is nothing they could do to satisfy it.
"""

from __future__ import annotations

import datetime as dt

from . import dates
from .check_in import full_day_leave
from .clock import SchoolClock
from .enums import LeaveStatus, StaffAttendanceStatus
from .errors import AttendanceRequired
from .models import StaffAttendance, StaffProfile, User

AT_WORK = (StaffAttendanceStatus.PRESENT, StaffAttendanceStatus.HALF_DAY)


def assert_present_for_report(teacher: User, school_id: int, date: dt.date) -> None:
    profile = StaffProfile.objects.filter(user_id=teacher.id).first()

    if profile is None:
        return

    today = SchoolClock.for_school(school_id).now().date()
    is_today = date == today
    when = "today" if is_today else f"on {dates.us(date)}"

    leave = full_day_leave(profile, date)

    if leave is not None:
        if leave.status == LeaveStatus.PENDING:
            raise AttendanceRequired(
                f"You have applied for leave {when}. Withdraw the request and check in to file reports for it.",
                code="LEAVE_APPLIED",
            )

        raise AttendanceRequired(f"You were on leave {when}, so there is nothing to report for it.", code="ON_LEAVE")

    row = StaffAttendance.objects.filter(staff_profile_id=profile.id, attendance_date=date).first()

    if row is not None and row.status in AT_WORK:
        return

    if row is not None and row.status == StaffAttendanceStatus.LEAVE:
        raise AttendanceRequired(f"You were on leave {when}, so there is nothing to report for it.", code="ON_LEAVE")

    if is_today and row is None:
        raise AttendanceRequired(
            "Check in first. Your teaching reports open once you are marked present today.",
            code="CHECK_IN_REQUIRED",
        )

    if is_today:
        raise AttendanceRequired(
            "You are marked absent today, so reports cannot be filed. Ask the office if that is wrong.",
            code="MARKED_ABSENT",
        )

    raise AttendanceRequired(
        f"You were not marked present on {dates.us(date)}, so a report cannot be filed for it. "
        "Ask the office to correct your attendance if you were in.",
        code="NOT_PRESENT",
    )
