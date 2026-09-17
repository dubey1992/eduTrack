"""The landing screen's figures, which differ by who is looking.

Port of App\\Services\\DashboardService. Every role gets the same shape - a
list of cards, an attendance trend and a list of things wanting attention - so
the client renders one layout rather than six. What goes in them is decided
per role here, where the authorization rules already live, rather than by the
client asking for whatever it fancies.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from django.db.models import Count, Exists, OuterRef, Sum

from .clock import SchoolClock
from .enums import (
    AttendanceStatus,
    LeaveStatus,
    MessageChannel,
    MessageStatus,
    PaymentStatus,
    SchoolStatus,
    StudentStatus,
    TransportStatus,
    TripStatus,
    UserRole,
    UserStatus,
)
from .models import (
    Attendance,
    ClassSection,
    DailyTeachingReport,
    Department,
    Message,
    Payment,
    School,
    StaffLeave,
    StaffProfile,
    Student,
    TimetableEntry,
    TransportRoute,
    TransportTrip,
    User,
)
from .requests import php_int
from .scope import SchoolScope, group_school_ids
from .services import HolidayService, php_number, php_round_1


class DashboardService:
    @classmethod
    def for_user(cls, actor: User, school_filter) -> dict:
        school_id = cls._school_id_for(actor, school_filter)
        clock = SchoolClock.platform() if school_id is None else SchoolClock.for_school(school_id)
        today = clock.now().date()

        role = actor.role

        if role == UserRole.SUPER_ADMIN:
            payload = cls._platform() if school_id is None else cls._school(school_id, today)
        elif role in (UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN):
            # A branch they named, or the group as a whole. An admin of a
            # standalone school never reaches the group arm: their scope is one
            # school, so it has already been resolved for them.
            payload = cls._group(actor, today) if school_id is None else cls._school(school_id, today)
        elif role == UserRole.HOD:
            payload = cls._hod(actor, today)
        elif role == UserRole.TEACHER:
            payload = cls._teacher(actor, today)
        elif role == UserRole.TRANSPORT_MANAGER:
            payload = cls._transport(actor.school_id, today)
        else:
            payload = cls._staff(actor)

        holiday = None if school_id is None else HolidayService.holiday_on(school_id, today)

        return {
            "role": role,
            "school_id": school_id,
            "as_of": today.isoformat(),
            "is_working_day": school_id is not None and HolidayService.is_working_day(school_id, today),
            "holiday": holiday.name if holiday else None,
            **payload,
        }

    # -- per role -----------------------------------------------------------

    @classmethod
    def _platform(cls) -> dict:
        """The Super Admin across every school. Money is grouped by currency
        and never blended - CLAUDE.md rule 5."""
        collected = " + ".join(
            f"{row['currency_code']} {number_format(row['total'])}"
            for row in Payment.objects.exclude(status=PaymentStatus.CANCELLED)
            .values("currency_code")
            .annotate(total=Sum("paid_amount"))
            .filter(total__gt=0)
            .order_by("currency_code")
        )

        outstanding = Payment.objects.filter(status__in=(PaymentStatus.PENDING, PaymentStatus.PARTIAL)).count()

        return {
            "cards": [
                card(
                    "schools", "Schools", str(School.objects.count()),
                    f"{School.objects.filter(status=SchoolStatus.ACTIVE).count()} active",
                ),
                card("users", "User accounts", str(User.objects.filter(status=UserStatus.ACTIVE).count()), "active"),
                card("collected", "Collected", collected or "-", "money received"),
                card(
                    "outstanding", "Payments owing", str(outstanding), "pending or part paid",
                    "warning" if outstanding > 0 else "ok",
                ),
            ],
            "attendance_trend": [],
            "attention": [],
        }

    @classmethod
    def _group(cls, actor: User, today: dt.date) -> dict:
        """A whole school group at once. Roll-ups, not a blend: attendance is
        the group's present marks over its marked total, and each branch that
        has not marked yet is named rather than averaged away."""
        school_ids = group_school_ids(actor.school_id) or []
        branches = list(School.objects.filter(id__in=school_ids).order_by("name", "id"))

        students = Student.objects.filter(school_id__in=school_ids, status=StudentStatus.ACTIVE).count()
        staff = StaffProfile.objects.filter(school_id__in=school_ids).count()
        rate = attendance_rate(Attendance.objects.filter(school_id__in=school_ids), today)

        unmarked = [
            note(f"attendance-{branch.id}", f"{branch.name} has not marked attendance today.")
            for branch in branches
            if attendance_rate(Attendance.objects.filter(school_id=branch.id), today) is None
        ]

        return {
            "cards": [
                card("branches", "Schools in group", str(len(branches)), "including the parent"),
                card("students", "Students", str(students), "across the group"),
                card("staff", "Teachers & staff", str(staff), "across the group"),
                attendance_card(rate),
            ],
            "attendance_trend": [],
            "attention": unmarked,
        }

    @classmethod
    def _school(cls, school_id: int, today: dt.date) -> dict:
        students = Student.objects.filter(school_id=school_id, status=StudentStatus.ACTIVE).count()
        staff = StaffProfile.objects.filter(school_id=school_id).count()
        rate = school_attendance_rate(school_id, today)
        trips_today = TransportTrip.objects.filter(school_id=school_id, trip_date=today).count()
        routes = TransportRoute.objects.filter(school_id=school_id, status=TransportStatus.ACTIVE).count()

        return {
            "cards": [
                card("students", "Students", str(students), "on the roll"),
                card("staff", "Teachers & staff", str(staff), "on the payroll"),
                attendance_card(rate),
                card("transport", "Trips today", str(trips_today), f"{routes} active routes"),
            ],
            "attendance_trend": attendance_trend(school_id, today),
            "attention": school_attention(school_id, today),
        }

    @classmethod
    def _hod(cls, actor: User, today: dt.date) -> dict:
        school_id = actor.school_id
        department_ids = list(
            Department.objects.filter(school_id=school_id, hod_user_id=actor.id).values_list("id", flat=True)
        )

        teachers = StaffProfile.objects.filter(school_id=school_id, department_id__in=department_ids).count()
        pending_reviews = DailyTeachingReport.objects.filter(
            school_id=school_id,
            reviewed_at__isnull=True,
            timetable_entry__subject__department_id__in=department_ids,
        ).count()

        return {
            "cards": [
                card("departments", "Departments", str(len(department_ids)), "you head"),
                card("teachers", "Teachers", str(teachers), "in your departments"),
                card(
                    "reviews", "Reports to review", str(pending_reviews), "awaiting you",
                    "warning" if pending_reviews > 0 else "ok",
                ),
            ],
            "attendance_trend": attendance_trend(school_id, today),
            "attention": (
                []
                if pending_reviews == 0
                else [note("reviews", f"{pending_reviews} teaching reports are waiting for your review.")]
            ),
        }

    @classmethod
    def _teacher(cls, actor: User, today: dt.date) -> dict:
        school_id = actor.school_id

        periods_today = TimetableEntry.objects.filter(
            school_id=school_id, teacher_id=actor.id, day_of_week=today.strftime("%A").lower()
        ).count()
        reports_filed = DailyTeachingReport.objects.filter(
            school_id=school_id, teacher_id=actor.id, report_date=today
        ).count()
        sections_to_mark = sections_awaiting_register(actor, today)

        return {
            "cards": [
                card("periods", "Periods today", str(periods_today), "on your timetable"),
                card(
                    "reports", "Reports filed", f"{reports_filed}/{periods_today}", "for today",
                    "warning" if reports_filed < periods_today else "ok",
                ),
                card(
                    "register", "Registers to mark", str(sections_to_mark), "your class sections",
                    "warning" if sections_to_mark > 0 else "ok",
                ),
            ],
            "attendance_trend": [],
            "attention": (
                []
                if sections_to_mark == 0
                else [note("register", "Today's register has not been marked for your class yet.")]
            ),
        }

    @classmethod
    def _transport(cls, school_id: int, today: dt.date) -> dict:
        trips = TransportTrip.objects.filter(school_id=school_id, trip_date=today)
        routes = TransportRoute.objects.filter(school_id=school_id, status=TransportStatus.ACTIVE).count()

        return {
            "cards": [
                card("routes", "Active routes", str(routes), "in service"),
                card("running", "Trips running", str(trips.filter(status=TripStatus.IN_PROGRESS).count()), "right now"),
                card("completed", "Trips completed", str(trips.filter(status=TripStatus.COMPLETED).count()), "today"),
            ],
            "attendance_trend": [],
            "attention": [],
        }

    @classmethod
    def _staff(cls, actor: User) -> dict:
        profile = StaffProfile.objects.filter(user_id=actor.id).first()

        pending_leave = (
            0
            if profile is None
            else StaffLeave.objects.filter(staff_profile_id=profile.id, status=LeaveStatus.PENDING).count()
        )
        unread = Message.objects.filter(user_id=actor.id, channel=MessageChannel.IN_APP, read_at__isnull=True).count()

        return {
            "cards": [
                card("leave", "Leave requests", str(pending_leave), "awaiting a decision"),
                card("inbox", "Unread messages", str(unread), "in your inbox", "warning" if unread > 0 else "ok"),
            ],
            "attendance_trend": [],
            "attention": [],
        }

    @staticmethod
    def _school_id_for(actor: User, school_filter) -> int | None:
        """`(int) $filters['school_id']` when one was sent - an empty value
        was already nothing by the time Laravel's controller saw it."""
        requested = None if school_filter is None or str(school_filter).strip() == "" else php_int(school_filter)

        return SchoolScope.for_actor(actor).writable_school_id(requested)


# -- shared pieces ------------------------------------------------------------


def attendance_rate(marks, date: dt.date) -> float | None:
    """The percentage of students present on one day, or None when nobody has
    marked a register yet - "not marked" and "everybody absent" are very
    different things to show a head teacher. One ratio across whatever
    schools `marks` covers, never an average of averages."""
    counts = dict(
        marks.filter(attendance_date=date).values("status").annotate(total=Count("id")).values_list("status", "total")
    )
    total = sum(counts.values())

    if total == 0:
        return None

    return php_round_1(counts.get(AttendanceStatus.PRESENT, 0) / total * 100)


def school_attendance_rate(school_id: int, date: dt.date) -> float | None:
    return attendance_rate(Attendance.objects.filter(school_id=school_id), date)


def attendance_card(rate: float | None) -> dict:
    # `$rate.'%'`: PHP writes a whole float without its ".0".
    return card(
        "attendance",
        "Attendance today",
        "-" if rate is None else f"{php_number(rate)}%",
        "not marked yet" if rate is None else "of students present",
    )


def attendance_trend(school_id: int, today: dt.date, days: int = 7) -> list[dict]:
    """The last working days, oldest first. Working days rather than calendar
    days, so a chart never shows a weekend sitting at zero."""
    dates = HolidayService.working_dates(school_id, today - dt.timedelta(days=days * 3), today)[-days:]

    return [
        {
            "date": date.isoformat(),
            "label": date.strftime("%d %b"),
            "attendance_rate": php_number(school_attendance_rate(school_id, date)),
        }
        for date in dates
    ]


def school_attention(school_id: int, today: dt.date) -> list[dict]:
    notes = []

    if HolidayService.is_working_day(school_id, today) and school_attendance_rate(school_id, today) is None:
        notes.append(note("attendance", "No attendance has been marked yet today."))

    failed = Message.objects.filter(school_id=school_id, status=MessageStatus.FAILED).count()
    if failed > 0:
        notes.append(note("messages", f"{failed} messages failed to send and can be retried."))

    pending_leave = StaffLeave.objects.filter(school_id=school_id, status=LeaveStatus.PENDING).count()
    if pending_leave > 0:
        notes.append(note("leave", f"{pending_leave} leave requests are waiting for a decision."))

    return notes


def sections_awaiting_register(actor: User, today: dt.date) -> int:
    """Class sections this teacher is responsible for with no register for
    the day yet."""
    if not HolidayService.is_working_day(actor.school_id, today):
        return 0

    return (
        ClassSection.objects.filter(class_teacher_id=actor.id)
        # NOT EXISTS, the query whereDoesntHave() writes.
        .filter(~Exists(Attendance.objects.filter(class_section_id=OuterRef("pk"), attendance_date=today)))
        .count()
    )


def number_format(amount) -> str:
    """PHP's number_format($amount, 2): halves away from zero, commas between
    thousands."""
    return f"{Decimal(amount).quantize(Decimal('0.01'), rounding='ROUND_HALF_UP'):,.2f}"


def card(key: str, label: str, value: str, hint: str | None = None, tone: str = "neutral") -> dict:
    return {"key": key, "label": label, "value": value, "hint": hint, "tone": tone}


def note(key: str, message: str) -> dict:
    return {"key": key, "message": message}
