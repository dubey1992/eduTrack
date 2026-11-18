"""Reminders for staff, from the school's own day (docs/mobile-apps-review.md,
5.1, decided 2026-11-18).

Three, each a switch in the school's module settings, **off for schools that
were already live** and on for schools created since:

- **Register not taken** (Student Attendance -> `remind_register`): to a class
  teacher whose register is still not taken once the first period has ended.
- **Not checked in** (Staff Attendance -> `remind_check_in`): to anyone with a
  staff record and no attendance for the day, 30 minutes into the first
  period - only where staff check in from the app.
- **Reports still owed** (Teaching Reports -> `remind_reports_owed`): to a
  teacher with periods unreported once the last period has ended.

The school has no "school starts at" setting, so the times come from that
day's own periods - a half day rings its own, earlier bells. Nothing on a
day the school is closed, by its week or a holiday, and nothing to anybody on
leave; Today's own answer (today.day_for) decides what is owed, so a teacher
is never reminded of something their phone says is done.

The inbox and the push that rides on it only - teaching events never go by
SMS (MessageEvent.channels), so a reminder costs the school nothing. Each
goes at most once per person per school day: the inbox row it writes is the
proof it went, so a run every 15 minutes, or a second run, sends nothing new.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass

from . import modules, notifications, today as my_day, week
from .clock import SchoolClock
from .enums import MessageEvent, SchoolStatus, UserRole, UserStatus
from .models import Message, Period, School, StaffAttendance, StaffProfile, User
from .services import STAFF_REMINDER_SWITCHES, HolidayService

# How far into the first period someone counts as late enough to remind.
CHECK_IN_GRACE = dt.timedelta(minutes=30)

TEACHERS = (UserRole.TEACHER, UserRole.HOD)

# The bus crew check in on their own app's trip, not here.
NOT_CHECKING_IN = (UserRole.DRIVER, UserRole.BUS_ATTENDANT, UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN)

# (module, setting) for each reminder - the school's switch. The same three
# a new school is created with on (services.STAFF_REMINDER_SWITCHES).
SWITCHES = dict(
    zip(
        (MessageEvent.REGISTER_REMINDER, MessageEvent.CHECK_IN_REMINDER, MessageEvent.REPORTS_REMINDER),
        STAFF_REMINDER_SWITCHES,
    )
)


@dataclass
class SchoolDay:
    """When a school's day rings, today, on its own clock."""

    school: School
    clock: SchoolClock
    now: dt.datetime
    first_start: dt.time
    first_end: dt.time
    last_end: dt.time

    def at(self, time: dt.time) -> dt.datetime:
        return dt.datetime.combine(self.now.date(), time, tzinfo=self.now.tzinfo)


def school_day(school: School, at: dt.datetime | None = None) -> SchoolDay | None:
    """Today at [school], or None when it is closed or rings no bells."""
    clock = SchoolClock.for_school(school.id)
    now = at.astimezone(clock.now().tzinfo) if at is not None else clock.now()
    today = now.date()

    shape = week.WorkingWeek(school.working_days).shape_on(today)
    if shape is None or HolidayService.holiday_on(school.id, today) is not None:
        return None

    periods = list(Period.objects.filter(school_id=school.id, day_shape=shape).order_by("start_time", "period_number"))
    if not periods:
        return None

    return SchoolDay(
        school=school,
        clock=clock,
        now=now,
        first_start=periods[0].start_time,
        first_end=periods[0].end_time,
        last_end=max(period.end_time for period in periods),
    )


def already_reminded(user: User, event: str, day: SchoolDay) -> bool:
    start = day.clock.start_of_day_utc(day.now.date())

    return Message.objects.filter(user_id=user.id, event=event, created_at__gte=start).exists()


def switched_on(school_id: int, event: str) -> bool:
    module, key = SWITCHES[event]

    return modules.is_enabled(school_id, module) and bool(modules.setting(school_id, module, key))


def send(at: dt.datetime | None = None, school_id: int | None = None) -> int:
    """Every reminder due now, across every active school. Returns how many
    went. [at] is for tests; cron always asks about now."""
    schools = School.objects.filter(status=SchoolStatus.ACTIVE)
    if school_id is not None:
        schools = schools.filter(pk=school_id)

    sent = 0
    for school in schools:
        on = [event for event in SWITCHES if switched_on(school.id, event)]
        if not on:
            continue

        day = school_day(school, at)
        if day is None:
            continue

        sent += send_for(day, on)

    return sent


def send_for(day: SchoolDay, on: list[str]) -> int:
    sent = 0
    now = day.now

    if MessageEvent.REGISTER_REMINDER in on and now >= day.at(day.first_end):
        sent += _teachers(day, MessageEvent.REGISTER_REMINDER)

    if MessageEvent.REPORTS_REMINDER in on and now >= day.at(day.last_end):
        sent += _teachers(day, MessageEvent.REPORTS_REMINDER)

    if (
        MessageEvent.CHECK_IN_REMINDER in on
        and modules.setting(day.school.id, "staff_attendance", "app_check_in")
        and day.at(day.first_start) + CHECK_IN_GRACE <= now < day.at(day.last_end)
    ):
        sent += _not_checked_in(day)

    return sent


def _teachers(day: SchoolDay, event: str) -> int:
    sent = 0
    teachers = User.objects.filter(school_id=day.school.id, role__in=TEACHERS, status=UserStatus.ACTIVE)

    for teacher in teachers:
        if already_reminded(teacher, event, day):
            continue

        day_now = my_day.day_for(teacher, at=day.now)
        owed = day_now["owed"]

        if event == MessageEvent.REGISTER_REMINDER and owed["registers"]:
            classes = [r["class_section"] for r in day_now["registers"] if not r["submitted"]]
            notifications.notify_staff(event, teacher, {"count": str(len(classes)), "classes": " and ".join(classes)})
            sent += 1

        if event == MessageEvent.REPORTS_REMINDER and owed["reports"]:
            count = owed["reports"]
            notifications.notify_staff(event, teacher, {
                "count": str(count),
                "reports": "a teaching report" if count == 1 else f"{count} teaching reports",
            })
            sent += 1

    return sent


def _not_checked_in(day: SchoolDay) -> int:
    sent = 0
    today = day.now.date()
    profiles = (
        StaffProfile.objects.filter(school_id=day.school.id, user__status=UserStatus.ACTIVE)
        .exclude(user__role__in=NOT_CHECKING_IN)
        .select_related("user", "user__school")
    )
    marked = set(
        StaffAttendance.objects.filter(school_id=day.school.id, attendance_date=today).values_list(
            "staff_profile_id", flat=True
        )
    )

    for profile in profiles:
        # Any mark at all counts - checked in, punched in, marked by the
        # office, or leave already written to the register.
        if profile.id in marked or already_reminded(profile.user, MessageEvent.CHECK_IN_REMINDER, day):
            continue

        if my_day.leave_for(profile.user, today)["today"] is not None:
            continue

        notifications.notify_staff(MessageEvent.CHECK_IN_REMINDER, profile.user, {})
        sent += 1

    return sent
