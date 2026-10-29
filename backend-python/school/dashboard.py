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

from django.db.models import Count, Exists, F, OuterRef, Sum

from . import dates, modules, money, permissions
from .clock import SchoolClock
from .fees import ledger as fee_ledger
from .reports.performance import term_summary
from .enums import (
    AttendanceStatus,
    FeeReceiptStatus,
    LeaveStatus,
    MessageChannel,
    MessageStatus,
    PaymentStatus,
    PayrollRunStatus,
    PayslipStatus,
    SchoolCategory,
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
    FeeReceipt,
    Message,
    Payment,
    PayrollRun,
    Payslip,
    School,
    StaffLeave,
    StaffProfile,
    Student,
    StudentFeeDue,
    TimetableEntry,
    TransportRoute,
    TransportTrip,
    User,
)
from .payroll.service import PayrollRunService, period_label
from .requests import php_int
from .scope import SchoolScope, group_school_ids
from .services import DailyTeachingReportService, HolidayService, TimetableService, php_number, php_round_1


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
        elif role == UserRole.ACCOUNTANT:
            payload = cls._accountant(actor, today)
        else:
            payload = cls._staff(actor)

        # Fee Management (docs/fees.md, F5): three more cards for whoever
        # keeps the school's books, where the school uses it.
        fee_schools = cls._fee_school_ids(actor, school_id)
        if fee_schools:
            payload = {**payload, "cards": [*payload["cards"], *fee_cards(fee_schools, today)]}

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
        and never blended - CLAUDE.md rule 5.

        Live and trial schools only (docs/school-categories.md): demo and
        testing schools are not customers, and would only inflate the figures.
        """
        counted = School.objects.filter(category__in=SchoolCategory.counted())
        not_counted = School.objects.exclude(category__in=SchoolCategory.counted()).count()
        payments = Payment.objects.filter(school__category__in=SchoolCategory.counted())

        collected = " + ".join(
            f"{row['currency_code']} {number_format(row['total'])}"
            for row in payments.exclude(status=PaymentStatus.CANCELLED)
            .values("currency_code")
            .annotate(total=Sum("paid_amount"))
            .filter(total__gt=0)
            .order_by("currency_code")
        )

        outstanding = payments.filter(status__in=(PaymentStatus.PENDING, PaymentStatus.PARTIAL)).count()
        active = counted.filter(status=SchoolStatus.ACTIVE).count()

        return {
            "cards": [
                card(
                    "schools", "Schools", str(counted.count()),
                    f"{active} active" + (f", {not_counted} demo or testing not counted" if not_counted else ""),
                ),
                card(
                    "users", "User accounts",
                    str(User.objects.filter(status=UserStatus.ACTIVE, school__category__in=SchoolCategory.counted()).count()),
                    "active",
                ),
                card("collected", "Collected", collected or "-", "money received"),
                card(
                    "outstanding", "Payments owing", str(outstanding), "pending or part paid",
                    "warning" if outstanding > 0 else "ok",
                ),
            ],
            "attendance_trend": [],
            "attention": trial_notes(),
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
                performance_card(term_summary(school_id, today)),
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
                # Their own departments' results, not the school's.
                performance_card(term_summary(school_id, today, department_ids)),
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

        # This year's grid only: a school in its second year would otherwise
        # count last year's Monday as well (docs/promotion.md).
        #
        # And nothing at all on a day the school approved their leave for.
        # The Teaching Reports screen stopped counting those periods as
        # pending, and a dashboard reading "0/2 filed" in warning orange
        # beside it would be the product arguing with itself.
        on_leave = actor.id in DailyTeachingReportService.on_leave(school_id, today)
        periods_today = 0 if on_leave else TimetableService.this_year(
            TimetableEntry.objects.filter(
                school_id=school_id, teacher_id=actor.id, day_of_week=today.strftime("%A").lower()
            ),
            school_id,
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
    def _accountant(cls, actor: User, today: dt.date) -> dict:
        """Payroll first - this month's run, who cannot be paid yet, what is
        still owed - then the two cards every employee has."""
        school = School.objects.get(pk=actor.school_id)
        run = PayrollRun.objects.filter(school=school, year=today.year, month=today.month).first()
        _, missing = PayrollRunService.eligible(school)
        unpaid = Payslip.objects.filter(
            school=school, status=PayslipStatus.UNPAID, payroll_run__status=PayrollRunStatus.FINALIZED
        ).count()
        employee = cls._staff(actor)

        notes = []
        if missing:
            notes.append(note("salaries", f"{len(missing)} employees cannot be paid until their salary is set."))
        if unpaid:
            notes.append(note("unpaid", f"{unpaid} finalized payslips have not been marked paid."))

        return {
            "cards": [
                card(
                    "payroll", "Payroll this month", "Not started" if run is None else PayrollRunStatus(run.status).label,
                    period_label(today.year, today.month),
                    "ok" if run is not None and run.status == PayrollRunStatus.PAID else "neutral",
                ),
                card(
                    "salaries", "Salaries not set", str(len(missing)), "cannot be paid yet",
                    "warning" if missing else "ok",
                ),
                card("unpaid", "Unpaid payslips", str(unpaid), "finalized, not paid", "warning" if unpaid else "ok"),
                *employee["cards"],
            ],
            "attendance_trend": [],
            "attention": notes,
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
    def _fee_school_ids(actor: User, school_id: int | None) -> list[int]:
        """The schools whose fee cards this dashboard shows: the one in view
        for a School Admin, an Accountant or a Super Admin looking at a
        school; every branch for a Group Admin looking at the whole group -
        each only with the fees module on, and only for a role the matrix
        lets read fees. Nobody else's dashboard changes."""
        if actor.role not in FEE_CARD_ROLES or not permissions.may_view(actor, "fees"):
            return []

        if school_id is not None:
            candidates = [school_id]
        elif actor.role in (UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN):
            candidates = group_school_ids(actor.school_id) or []
        else:
            # A Super Admin across the platform: there is no one school's
            # money to show.
            return []

        return [candidate for candidate in candidates if modules.is_enabled(candidate, "fees")]

    @staticmethod
    def _school_id_for(actor: User, school_filter) -> int | None:
        """`(int) $filters['school_id']` when one was sent - an empty value
        was already nothing by the time Laravel's controller saw it."""
        requested = None if school_filter is None or str(school_filter).strip() == "" else php_int(school_filter)

        return SchoolScope.for_actor(actor).writable_school_id(requested)


# -- shared pieces ------------------------------------------------------------

FEE_CARD_ROLES = (UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN, UserRole.ACCOUNTANT)


def fee_cards(school_ids: list[int], today: dt.date) -> list[dict]:
    """Collected this month, outstanding and students overdue, over the
    given schools (docs/fees.md, F5). Money is per currency, never added
    across two (CLAUDE.md rule 5). Four aggregate queries, whatever the size
    of the school.

    - **Collected** - valid receipts dated from the 1st of this month to
      today, the school's month.
    - **Outstanding** - what is still owed on dues that have fallen due (on
      or before today), as the Outstanding fees report has it.
    - **Overdue** - students owing on a due whose date has passed.
    """
    month_start = today.replace(day=1)
    collected_rows = list(
        FeeReceipt.objects.filter(
            school_id__in=school_ids, status=FeeReceiptStatus.VALID,
            receipt_date__gte=month_start, receipt_date__lte=today,
        )
        .order_by()
        .values("currency_code")
        .annotate(total=Sum("amount"), receipts=Count("id"))
        .order_by("currency_code")
    )
    owed = fee_ledger.owed(StudentFeeDue.objects.filter(school_id__in=school_ids, due_date__lte=today))
    outstanding_rows = list(
        owed.order_by()
        .values("currency_code")
        .annotate(total=Sum(F("amount") - F("discount_amount") - F("paid_amount")))
        .order_by("currency_code")
    )
    owing = owed.values("student_id").distinct().count()
    overdue = owed.filter(due_date__lt=today).values("student_id").distinct().count()

    def amounts(rows) -> str:
        shown = [money.formatted(row["total"], row["currency_code"]) for row in rows if row["total"]]

        if shown:
            return " + ".join(shown)

        # Nothing yet: a zero in the school's own currency, not a dash that
        # would read as "not worked out".
        codes = sorted(set(School.objects.filter(id__in=school_ids).values_list("currency_code", flat=True)))
        return " + ".join(money.formatted(Decimal("0.00"), code) for code in codes) or "-"

    receipts = sum(row["receipts"] for row in collected_rows)

    return [
        card(
            "fees_collected", "Fees collected this month", amounts(collected_rows),
            f"{plural(receipts, 'receipt')} in {period_label(today.year, today.month)}",
        ),
        card(
            # "Due and unpaid": only what has fallen due counts, so the name
            # says so - next term's fees are charged, not yet owed, and a
            # card reading "outstanding 0" beside a list of balances read as
            # a mistake.
            "fees_outstanding", "Fees due and unpaid", amounts(outstanding_rows),
            f"{plural(owing, 'student')} owing on fees already due", "warning" if owing else "ok",
        ),
        card(
            "fees_overdue", "Students overdue", str(overdue), "past a due date", "warning" if overdue else "ok",
        ),
    ]



def plural(count: int, word: str) -> str:
    return f"{count} {word}" if count == 1 else f"{count} {word}s"


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


def performance_card(summary: dict) -> dict:
    """This term's results, in a line (docs/assessments.md).

    A school with no terms, or a term nobody has published a result in yet,
    gets a dash and a hint saying so - never a 0% that would read as
    everybody having failed.
    """
    if summary["term"] is None:
        return card("performance", "Results this term", "-", "no terms set out yet")

    if summary["average_percentage"] is None:
        return card("performance", f"Results · {summary['term']}", "-", "nothing published yet")

    below = summary["students_below_the_mark"]
    hint = f"{summary['students']} students" if below == 0 else f"{below} below the school's mark"

    return card(
        "performance",
        f"Results · {summary['term']}",
        f"{summary['average_percentage']}%",
        hint,
        "warning" if below > 0 else "ok",
    )


def attendance_trend(school_id: int, today: dt.date, days: int = 7) -> list[dict]:
    """The last working days, oldest first. Working days rather than calendar
    days, so a chart never shows a weekend sitting at zero."""
    dates = HolidayService.working_dates(school_id, today - dt.timedelta(days=days * 3), today)[-days:]

    return [
        {
            "date": date.isoformat(),
            # US order, like every other date a person reads here: "Sep 29",
            # not "29 Sep" (docs/timezones.md, App\Support\DateFormats).
            "label": date.strftime("%b %d"),
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


TRIAL_WARNING_DAYS = 14


def trial_notes() -> list[dict]:
    """Active trials that have ended or end within two weeks, soonest first.
    A warning only: the school keeps working (CLAUDE.md rule 4)."""
    today = SchoolClock.platform().now().date()
    trials = School.objects.filter(
        category=SchoolCategory.TRIAL,
        status=SchoolStatus.ACTIVE,
        trial_ends_on__lte=today + dt.timedelta(days=TRIAL_WARNING_DAYS),
    ).order_by("trial_ends_on", "name")

    notes = []
    for school in trials:
        days = (school.trial_ends_on - today).days
        if days < 0:
            message = f"{school.name}'s trial ended on {dates.us(school.trial_ends_on)}. Move it to Live, or make it inactive."
        elif days == 0:
            message = f"{school.name}'s trial ends today."
        else:
            message = f"{school.name}'s trial ends in {days} day{'' if days == 1 else 's'}, on {dates.us(school.trial_ends_on)}."
        notes.append(note(f"trial-{school.id}", message))

    return notes

