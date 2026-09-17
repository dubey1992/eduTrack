"""The business rules, away from the HTTP.

app/Services, ported. Controllers stay thin - request, validation, service,
response (CLAUDE.md rule 8) - so anything here is a rule about the product
rather than about the web, and can be tested without one.
"""

from __future__ import annotations

import datetime as dt
from decimal import ROUND_HALF_UP, Decimal

from django.db import transaction
from django.db.models import Count, F, Min, Q, Sum
from django.utils import timezone

from . import hashing, jobs, money, notifications, queue, tokens, working_hours
from .clock import SchoolClock
from .enums import (
    AttendanceStatus,
    LeaveStatus,
    LeaveType,
    MessageEvent,
    PaymentStatus,
    SchoolStatus,
    StaffAttendanceStatus,
    StudentStatus,
    UserRole,
    UserStatus,
)
from .errors import (
    AccountInactive,
    AttendanceAlreadySubmitted,
    AttendanceOnHoliday,
    HasDependentRecords,
    HolidayOverlap,
    LeaveAlreadyReviewed,
    LeaveOnNonWorkingDays,
    LeaveOverlap,
    NonWorkingDay,
    TeacherScheduleConflict,
    TeachingReportAlreadyReviewed,
    TeachingReportAlreadySubmitted,
    TeachingReportOnHoliday,
    Unauthenticated,
)
from .models import (
    AcademicYear,
    Attendance,
    ClassSection,
    DailyTeachingReport,
    Department,
    Holiday,
    Payment,
    Period,
    StaffAttendance,
    StaffLeave,
    SyllabusTopic,
    SyllabusTopicProgress,
    TimetableEntry,
    EarlyAccessRequest,
    PersonalAccessToken,
    School,
    SchoolClass,
    StaffProfile,
    Student,
    Subject,
    User,
)
from .resources import timestamp
from .scope import SchoolScope


class AuthService:
    @staticmethod
    def login(email: str, password: str) -> tuple[User, str]:
        """Checks credentials and issues a token.

        The same 401 for an address nobody has and for the wrong password: the
        two are indistinguishable to the caller on purpose, so the login form
        cannot be used to find out which addresses have accounts.

        A deactivated account is different, and deliberately so - those
        credentials *were* right, and the person needs to be told why they
        cannot get in rather than left retyping a correct password.
        """
        user = User.objects.select_related("school").filter(email=email).first()

        # A password is verified even when there is no such account, against a
        # hash of nothing in particular, so that "no such address" does not
        # answer measurably faster than "wrong password". Laravel does not do
        # this - its provider returns before hashing - but it costs one bcrypt
        # round on a failed login and closes an oracle that the identical 401
        # message above was already trying to close.
        stored = user.password if user is not None else hashing.NO_SUCH_ACCOUNT

        if not hashing.check(password, stored) or user is None:
            raise Unauthenticated("These credentials do not match our records.")

        if not user.is_active():
            raise AccountInactive()

        return user, tokens.issue(user)

    @staticmethod
    def change_password(user: User, new_password: str, current_token: PersonalAccessToken) -> None:
        """Sets a new password and revokes every other session.

        If an imported account's temporary password reached the wrong person,
        this is the moment that stops mattering. The token in the caller's own
        hand keeps working, so nobody is signed out of the browser they are
        changing it from.
        """
        User.objects.filter(pk=user.pk).update(
            password=hashing.make(new_password),
            must_change_password=False,
            updated_at=timezone.now(),
        )

        others = PersonalAccessToken.objects.filter(
            tokenable_type=tokens.TOKENABLE_TYPE, tokenable_id=user.pk
        )

        if current_token is not None:
            others = others.exclude(pk=current_token.pk)

        others.delete()

    @staticmethod
    def logout(current_token: PersonalAccessToken) -> None:
        if current_token is not None:
            PersonalAccessToken.objects.filter(pk=current_token.pk).delete()


class EarlyAccessService:
    """Only the one method the schools module needs.

    Early access is M11's module. `mark_converted` comes early because
    `POST /schools` calls it - onboarding a school from a signup request has
    to close the loop, or the panel shows "Converted" with no school behind
    it. The rest of the service arrives with its own phase.
    """

    @staticmethod
    def mark_converted(request, school: School, actor: User):
        """Marks a request as having become a school.

        Set by the system when the school is actually created, never by hand:
        a list that says "Converted" with no school behind it is worse than
        one that says nothing.
        """
        EarlyAccessRequest.objects.filter(pk=request.pk).update(
            status="converted",
            converted_school_id=school.id,
            reviewed_by_id=actor.id,
            reviewed_at=timezone.now(),
            updated_at=timezone.now(),
        )

        return EarlyAccessRequest.objects.get(pk=request.pk)


class SchoolService:
    @staticmethod
    def visible_to(actor: User):
        """The schools this actor may see.

        Scoped on the table's own `id`, not a `school_id` column - a school
        *is* the tenant. A Group Admin sees their group; a Super Admin sees
        every school there is.
        """
        schools = School.objects.select_related("parent_school")

        schools = SchoolScope.for_actor(actor).apply_to(schools, column="id")

        # Counted in the query rather than per row, so a list of branches does
        # not fire a query each (CLAUDE.md rule 22). Ordered by name with id
        # as a tiebreaker - see StudentService.visible_to for why the second
        # column is not optional.
        return schools.annotate(branch_count=Count("school")).order_by("name", "id")

    @staticmethod
    def create(data: dict) -> School:
        now = timezone.now()

        return School.objects.create(
            status=SchoolStatus.ACTIVE, created_at=now, updated_at=now, **data
        )

    @staticmethod
    def update(school: School, data: dict) -> School:
        for field, value in data.items():
            setattr(school, field, value)

        school.updated_at = timezone.now()
        school.save()

        return school

    @classmethod
    def activate(cls, school: School) -> School:
        return cls.set_status(school, SchoolStatus.ACTIVE)

    @classmethod
    def deactivate(cls, school: School) -> School:
        return cls.set_status(school, SchoolStatus.INACTIVE)

    @staticmethod
    def set_status(school: School, status: str) -> School:
        school.status = status
        school.updated_at = timezone.now()
        school.save(update_fields=["status", "updated_at"])

        return school

    @staticmethod
    def branch_count(school: School) -> int:
        return School.objects.filter(parent_school_id=school.id).count()


class AttendanceService:
    """The daily register.

    Two rules carry the risk here, and both are about a day rather than a
    student.

    **A register can only be taken for a day the school actually ran.** A
    holiday names itself in the refusal; a weekend is refused too, because
    every working-day figure in the product excludes both and a Saturday
    register that no percentage counts is worse than none.

    **Submitting is not the same action as correcting.** A first submission
    for a class and day is refused if one already exists, so a duplicate tap
    cannot silently overwrite a different set of marks.
    """

    @staticmethod
    def register(section: ClassSection, date) -> dict:
        """The class's active roster for one day, each student paired with
        their existing mark - or null where the day has not been submitted.
        """
        students = Student.objects.filter(
            class_section_id=section.id, status=StudentStatus.ACTIVE
        ).order_by("first_name", "id")

        existing = {
            row.student_id: row
            for row in Attendance.objects.filter(
                class_section_id=section.id, attendance_date=date
            )
        }

        holiday = HolidayService.holiday_on(section.school_class.school_id, date)

        return {
            "class_section_id": section.id,
            "attendance_date": str(date),
            "submitted": bool(existing),
            "holiday": None if holiday is None else holiday_summary(holiday),
            "students": [
                {
                    "student_id": student.id,
                    "name": student.name,
                    "roll_number": student.roll_number,
                    "status": existing[student.id].status if student.id in existing else None,
                    "remarks": existing[student.id].remarks if student.id in existing else None,
                }
                for student in students
            ],
        }

    @classmethod
    def submit(cls, section: ClassSection, data: dict, actor: User) -> dict:
        already = Attendance.objects.filter(
            class_section_id=section.id, attendance_date=data["attendance_date"]
        ).exists()

        if already:
            raise AttendanceAlreadySubmitted("Attendance has already been submitted.")

        return cls.save(section, data, actor)

    @classmethod
    def update(cls, section: ClassSection, data: dict, actor: User) -> dict:
        """Corrects an already-submitted day, or fills in a student the first
        submission missed. An explicit, separate action from submit()."""
        return cls.save(section, data, actor)

    @classmethod
    def save(cls, section: ClassSection, data: dict, actor: User) -> dict:
        # Never trusted from the client - taken from the section's own class,
        # the same way a payment's currency is taken from its school.
        school_id = section.school_class.school_id
        academic_year_id = section.school_class.academic_year_id
        date = data["attendance_date"]

        cls.assert_school_is_open(school_id, date)

        with transaction.atomic():
            changed = {}

            for record in data["records"]:
                attendance, created = Attendance.objects.get_or_create(
                    class_section_id=section.id,
                    student_id=record["student_id"],
                    attendance_date=date,
                    defaults={
                        "school_id": school_id,
                        "academic_year_id": academic_year_id,
                        "status": record["status"],
                        "remarks": record.get("remarks"),
                        "marked_by_id": actor.id,
                        "created_at": timezone.now(),
                        "updated_at": timezone.now(),
                    },
                )

                if created:
                    changed[attendance.student_id] = attendance.status
                else:
                    was = attendance.status

                    attendance.status = record["status"]
                    attendance.remarks = record.get("remarks")
                    attendance.marked_by_id = actor.id
                    attendance.updated_at = timezone.now()
                    attendance.save()

                    # Only a new mark or a changed one alerts the guardian, so
                    # correcting a remark does not text a parent twice.
                    if was != attendance.status:
                        changed[attendance.student_id] = attendance.status

            cls.alert_guardians(section, date, changed, actor)

            return cls.register(section, date)

    @staticmethod
    def assert_school_is_open(school_id: int, date) -> None:
        holiday = HolidayService.holiday_on(school_id, date)

        if holiday is not None:
            raise AttendanceOnHoliday(
                f"Attendance cannot be marked on {holiday.name} - it is a holiday."
            )

        if not HolidayService.is_working_day(school_id, date):
            raise NonWorkingDay(
                "Attendance cannot be marked on a weekend - the school is closed."
            )

    @staticmethod
    def alert_guardians(section: ClassSection, date, changed: dict, actor: User) -> None:
        """Tells guardians what was marked.

        Which statuses actually go out is the school's choice, and the sending
        is queued - marking a register is never held up by a gateway.
        """
        if not changed:
            return

        events = {
            AttendanceStatus.ABSENT: MessageEvent.ATTENDANCE_ABSENT,
            AttendanceStatus.PRESENT: MessageEvent.ATTENDANCE_PRESENT,
        }

        for student in Student.objects.select_related("school").filter(id__in=changed):
            event = events.get(changed[student.id])

            # A student marked "leave" is not news to the person who asked for
            # it, so there is no event for it.
            if event is None:
                continue

            notifications.notify_guardian(
                event,
                student,
                {
                    "class_name": f"{section.school_class.name} {section.name}".strip(),
                    "date": as_date(date).strftime("%m/%d/%Y"),
                },
                actor=actor,
            )

    @staticmethod
    def visible_to(actor: User, filters: dict):
        marks = Attendance.objects.select_related(
            "student", "class_section__school_class", "marked_by"
        )

        marks = SchoolScope.for_actor(actor).apply_to(marks, filters.get("school_id"))

        # A teacher only ever sees attendance for sections they are the class
        # teacher of - never another class, regardless of filters.
        if actor.role == UserRole.TEACHER:
            marks = marks.filter(class_section__class_teacher_id=actor.id)

        for field in ("class_section_id", "student_id", "status"):
            if filters.get(field):
                marks = marks.filter(**{field: filters[field]})

        if filters.get("date_from"):
            marks = marks.filter(attendance_date__gte=filters["date_from"])

        if filters.get("date_to"):
            marks = marks.filter(attendance_date__lte=filters["date_to"])

        return marks.order_by("-attendance_date", "student_id", "id")


def holiday_summary(holiday) -> dict:
    """Just enough of a holiday for the register screen to name it.

    Three fields, matching Laravel's holidayPayload() exactly. The first
    version of this returned the dates too, which no client reads and which
    the cross-backend diff would not have caught - neither date it compared
    happened to be a holiday. Extra fields are harmless to the contract suite
    by design, which is precisely why adding them quietly is easy.
    """
    return {"id": holiday.id, "name": holiday.name, "type": holiday.type}


class StaffAttendanceService:
    """The staff register.

    The same day-rules as the student one - no holiday, no weekend, and
    submitting is not correcting - plus one of its own: **an HOD's roster is
    always narrowed to the departments they head**, whatever `department_id`
    was asked for. Never trusted from the client, the same principle as a
    teacher only seeing their own sections.
    """

    @staticmethod
    def roster(school_id: int, department_id, actor: User):
        staff = (
            StaffProfile.objects.select_related("user", "department")
            .filter(school_id=school_id, user__status=UserStatus.ACTIVE)
            .order_by("employee_id", "id")
        )

        if actor.role == UserRole.HOD:
            return staff.filter(department__hod_user_id=actor.id)

        if department_id:
            staff = staff.filter(department_id=department_id)

        return staff

    @classmethod
    def register(cls, school_id: int, department_id, date, actor: User) -> dict:
        staff = list(cls.roster(school_id, department_id, actor))

        existing = {
            row.staff_profile_id: row
            for row in StaffAttendance.objects.filter(
                school_id=school_id,
                attendance_date=date,
                staff_profile_id__in=[profile.id for profile in staff],
            )
        }

        holiday = HolidayService.holiday_on(school_id, date)

        return {
            "school_id": school_id,
            "attendance_date": str(date),
            "submitted": bool(existing),
            "holiday": None if holiday is None else holiday_summary(holiday),
            "staff": [
                {
                    "staff_profile_id": profile.id,
                    "employee_id": profile.employee_id,
                    "name": profile.user.name,
                    "department_name": (
                        profile.department.name if profile.department_id else None
                    ),
                    "status": mark(existing, profile, "status"),
                    "check_in": working_hours.clock(mark(existing, profile, "check_in")),
                    "check_out": working_hours.clock(mark(existing, profile, "check_out")),
                    "working_hours": working_hours.format_span(
                        working_hours.clock(mark(existing, profile, "check_in")),
                        working_hours.clock(mark(existing, profile, "check_out")),
                    ),
                    "remarks": mark(existing, profile, "remarks"),
                }
                for profile in staff
            ],
        }

    @classmethod
    def submit(cls, school_id: int, data: dict, actor: User) -> dict:
        already = StaffAttendance.objects.filter(
            school_id=school_id,
            attendance_date=data["attendance_date"],
            staff_profile_id__in=[r["staff_profile_id"] for r in data["records"]],
        ).exists()

        if already:
            raise AttendanceAlreadySubmitted("Attendance has already been submitted.")

        return cls.save(school_id, data, actor)

    @classmethod
    def update(cls, school_id: int, data: dict, actor: User) -> dict:
        return cls.save(school_id, data, actor)

    @classmethod
    def save(cls, school_id: int, data: dict, actor: User) -> dict:
        AttendanceService.assert_school_is_open(school_id, data["attendance_date"])

        with transaction.atomic():
            for record in data["records"]:
                now = timezone.now()

                StaffAttendance.objects.update_or_create(
                    staff_profile_id=record["staff_profile_id"],
                    attendance_date=data["attendance_date"],
                    defaults={
                        "school_id": school_id,
                        "status": record["status"],
                        "check_in": record.get("check_in"),
                        "check_out": record.get("check_out"),
                        "remarks": record.get("remarks"),
                        "marked_by_id": actor.id,
                        "updated_at": now,
                    },
                    create_defaults={
                        "school_id": school_id,
                        "status": record["status"],
                        "check_in": record.get("check_in"),
                        "check_out": record.get("check_out"),
                        "remarks": record.get("remarks"),
                        "marked_by_id": actor.id,
                        "created_at": now,
                        "updated_at": now,
                    },
                )

            # No guardian to tell. Staff attendance is a record the school
            # keeps, not news anybody is waiting for - which is why this
            # module has no notification step and the student one does.
            return cls.register(school_id, data.get("department_id"), data["attendance_date"], actor)

    @staticmethod
    def visible_to(actor: User, filters: dict):
        marks = StaffAttendance.objects.select_related(
            "staff_profile__user", "staff_profile__department", "marked_by"
        )

        marks = SchoolScope.for_actor(actor).apply_to(marks, filters.get("school_id"))

        # An HOD only ever sees attendance for staff in the departments they
        # head - never another department, regardless of filters.
        if actor.role == UserRole.HOD:
            marks = marks.filter(staff_profile__department__hod_user_id=actor.id)

        if filters.get("staff_profile_id"):
            marks = marks.filter(staff_profile_id=filters["staff_profile_id"])

        if filters.get("department_id"):
            marks = marks.filter(staff_profile__department_id=filters["department_id"])

        if filters.get("status"):
            marks = marks.filter(status=filters["status"])

        if filters.get("date_from"):
            marks = marks.filter(attendance_date__gte=filters["date_from"])

        if filters.get("date_to"):
            marks = marks.filter(attendance_date__lte=filters["date_to"])

        return marks.order_by("-attendance_date", "staff_profile_id", "id")


def mark(existing: dict, profile, field: str):
    """One field of a staff member's mark, or None when the day is unmarked."""
    row = existing.get(profile.id)

    return None if row is None else getattr(row, field)


class StaffLeaveService:
    """Applying for leave, and deciding it.

    Two things here are not bookkeeping.

    **Approving writes attendance.** Every working day in an approved range is
    marked `leave` on the staff register, so an approved request and the
    register can never quietly disagree about whether somebody was expected
    in. Weekends and holidays inside the range are left alone - they are not
    attendance days, and marking them would contradict the holiday calendar.

    **A School Admin's own request approves itself.** Nobody else has standing
    to review the head of a school: a Sub Admin cannot manage an admin
    account, and a peer School Admin reviewing the actual head is backwards.
    So it is approved on application with a remark saying why, rather than
    sitting pending for ever. A Sub Admin is still subordinate to the School
    Admin who created them and goes through the normal flow.
    """

    WITH = ("staff_profile__user", "staff_profile__department", "applied_by", "reviewed_by")

    @classmethod
    def apply(cls, profile: StaffProfile, data: dict, actor: User):
        cls.assert_covers_a_working_day(
            profile.school_id, data["start_date"], data["end_date"]
        )
        cls.assert_no_overlap(profile.id, data["start_date"], data["end_date"])

        is_school_head = actor.role == UserRole.SCHOOL_ADMIN and not actor.is_sub_admin

        with transaction.atomic():
            now = timezone.now()

            leave = StaffLeave.objects.create(
                school_id=profile.school_id,
                staff_profile_id=profile.id,
                leave_type=data["leave_type"],
                start_date=data["start_date"],
                end_date=data["end_date"],
                reason=data["reason"],
                status=LeaveStatus.APPROVED if is_school_head else LeaveStatus.PENDING,
                applied_by_id=actor.id,
                reviewed_by_id=actor.id if is_school_head else None,
                review_remarks=(
                    "Auto-approved - School Admin is the head of the school."
                    if is_school_head
                    else None
                ),
                created_at=now,
                updated_at=now,
            )

            if is_school_head:
                cls.sync_attendance(leave, actor)

            return cls.fresh(leave)

    @classmethod
    def approve(cls, leave, actor: User, remarks):
        cls.assert_pending(leave)

        with transaction.atomic():
            cls.record_decision(leave, LeaveStatus.APPROVED, actor, remarks)

            cls.sync_attendance(leave, actor)
            cls.notify_applicant(leave, MessageEvent.LEAVE_APPROVED, actor)

            return cls.fresh(leave)

    @classmethod
    def reject(cls, leave, actor: User, remarks):
        cls.assert_pending(leave)

        cls.record_decision(leave, LeaveStatus.REJECTED, actor, remarks)

        cls.notify_applicant(leave, MessageEvent.LEAVE_REJECTED, actor)

        return cls.fresh(leave)

    @staticmethod
    def record_decision(leave, status: str, actor: User, remarks) -> None:
        leave.status = status
        leave.reviewed_by_id = actor.id
        leave.review_remarks = remarks
        leave.updated_at = timezone.now()
        leave.save(update_fields=["status", "reviewed_by", "review_remarks", "updated_at"])

    @classmethod
    def fresh(cls, leave):
        """The row again, with every relation the resource reads.

        Re-fetched rather than reusing the instance in hand: the one being
        returned has to carry the names, and an instance built by `create()`
        has none of them cached.
        """
        return StaffLeave.objects.select_related(*cls.WITH).get(pk=leave.pk)

    @staticmethod
    def notify_applicant(leave, event: str, actor: User) -> None:
        """Tells the staff member what was decided, in their inbox and by SMS.

        The reviewer's own action is never held up by the send - the message
        is written and queued, and the cron worker does the talking.
        """
        applicant = leave.staff_profile.user if leave.staff_profile_id else None

        if applicant is None:
            return

        notifications.notify_staff(
            event,
            applicant,
            {
                "leave_type": LeaveType.label_for(leave.leave_type),
                "start_date": leave.start_date.strftime("%m/%d/%Y"),
                "end_date": leave.end_date.strftime("%m/%d/%Y"),
                "days": str((leave.end_date - leave.start_date).days + 1),
                "remarks": leave.review_remarks,
            },
            actor=actor,
        )

    @classmethod
    def visible_to(cls, actor: User, filters: dict):
        leaves = StaffLeave.objects.select_related(*cls.WITH)

        leaves = cls.scoped(leaves, actor, filters.get("school_id"))

        if filters.get("staff_profile_id"):
            leaves = leaves.filter(staff_profile_id=filters["staff_profile_id"])

        if filters.get("department_id"):
            leaves = leaves.filter(staff_profile__department_id=filters["department_id"])

        if filters.get("status"):
            leaves = leaves.filter(status=filters["status"])

        # Newest first, and id to break the tie: two requests applied for in
        # the same second would otherwise be in no fixed order, which shows
        # one row twice and skips another as the reviewer pages through.
        return leaves.order_by("-created_at", "-id")

    @classmethod
    def summary(cls, actor: User, filters: dict) -> dict:
        """The stat cards above the leave list.

        Counted over the same visibility the list uses, not over the page in
        front of the reviewer - "3 pending" means three they can act on.
        """
        base = cls.scoped(StaffLeave.objects.all(), actor, filters.get("school_id"))

        # start_date and end_date are calendar dates at the school, so "today"
        # and "this month" are read on the school's calendar too.
        clock = SchoolClock.for_scope(actor, filters.get("school_id"))
        today = clock.date()
        month_start = clock.now().date().replace(day=1)

        return {
            "pending": base.filter(status=LeaveStatus.PENDING).count(),
            "approved_this_month": base.filter(
                status=LeaveStatus.APPROVED, start_date__gte=month_start
            ).count(),
            "rejected": base.filter(status=LeaveStatus.REJECTED).count(),
            "on_leave_today": base.filter(
                status=LeaveStatus.APPROVED, start_date__lte=today, end_date__gte=today
            ).count(),
        }

    @staticmethod
    def scoped(leaves, actor: User, school_id_filter):
        leaves = SchoolScope.for_actor(actor).apply_to(leaves, school_id_filter)

        # An HOD only ever sees leave for staff in the departments they head -
        # the same rule the staff register applies.
        if actor.role == UserRole.HOD:
            return leaves.filter(staff_profile__department__hod_user_id=actor.id)

        # A Teacher, Staff member or Transport Manager only ever sees their
        # own history. They are not reviewers; this screen is self-service.
        if actor.role in (UserRole.TEACHER, UserRole.STAFF, UserRole.TRANSPORT_MANAGER):
            profile = actor.staff_profile

            return leaves.filter(staff_profile_id=profile.id if profile else 0)

        return leaves

    @staticmethod
    def assert_no_overlap(staff_profile_id: int, start, end) -> None:
        overlaps = StaffLeave.objects.filter(
            staff_profile_id=staff_profile_id,
            status__in=(LeaveStatus.PENDING, LeaveStatus.APPROVED),
            start_date__lte=end,
            end_date__gte=start,
        ).exists()

        if overlaps:
            raise LeaveOverlap(
                "This staff member already has a leave request overlapping these dates."
            )

    @staticmethod
    def assert_pending(leave) -> None:
        if leave.status != LeaveStatus.PENDING:
            raise LeaveAlreadyReviewed("This leave request has already been reviewed.")

    @staticmethod
    def assert_covers_a_working_day(school_id: int, start, end) -> None:
        if not HolidayService.working_dates(school_id, start, end):
            raise LeaveOnNonWorkingDays(
                "The selected dates fall entirely on weekends or holidays - "
                "there is no working day to take leave from."
            )

    @staticmethod
    def sync_attendance(leave, actor: User) -> None:
        """Marks the approved range on the staff register.

        Only working days get a mark: a weekend or a holiday inside the range
        is not an attendance day, and marking it would contradict the holiday
        calendar, which refuses attendance on exactly those days.
        """
        now = timezone.now()

        for date in HolidayService.working_dates(
            leave.school_id, leave.start_date, leave.end_date
        ):
            StaffAttendance.objects.update_or_create(
                staff_profile_id=leave.staff_profile_id,
                attendance_date=date,
                defaults={
                    "school_id": leave.school_id,
                    "status": StaffAttendanceStatus.LEAVE,
                    "marked_by_id": actor.id,
                    "updated_at": now,
                },
                create_defaults={
                    "school_id": leave.school_id,
                    "status": StaffAttendanceStatus.LEAVE,
                    "marked_by_id": actor.id,
                    "created_at": now,
                    "updated_at": now,
                },
            )



class TimetableService:
    """The week's grid, edited one cell at a time.

    One cell rather than a whole week submitted at once, because that is how
    the screen works: a person drops a subject into Tuesday's third period and
    expects that to be the change. A week-shaped write would also have to
    decide what an omitted cell means, and "the teacher forgot to scroll" is
    not a decision worth making.
    """

    WITH = ("class_section__school_class", "period", "subject", "teacher")

    @classmethod
    def for_class_section(cls, class_section_id: int):
        """One class's whole week, in no particular order - the client lays it
        out against the school's periods itself, because it already has them
        for the header row."""
        return TimetableEntry.objects.select_related(*cls.WITH).filter(
            class_section_id=class_section_id
        )

    @classmethod
    def for_teacher(cls, teacher_id: int):
        """One teacher's periods across every class they teach."""
        return TimetableEntry.objects.select_related(*cls.WITH).filter(
            teacher_id=teacher_id
        )

    @classmethod
    def upsert(cls, data: dict):
        cls.assert_the_teacher_is_free(data)

        now = timezone.now()

        entry, _ = TimetableEntry.objects.update_or_create(
            class_section_id=data["class_section_id"],
            period_id=data["period_id"],
            day_of_week=data["day_of_week"],
            defaults={
                "school_id": data["school_id"],
                "subject_id": data["subject_id"],
                "teacher_id": data["teacher_id"],
                "updated_at": now,
            },
            create_defaults={
                "school_id": data["school_id"],
                "subject_id": data["subject_id"],
                "teacher_id": data["teacher_id"],
                "created_at": now,
                "updated_at": now,
            },
        )

        return TimetableEntry.objects.select_related(*cls.WITH).get(pk=entry.pk)

    @staticmethod
    def delete(entry) -> None:
        entry.delete()

    @staticmethod
    def assert_the_teacher_is_free(data: dict) -> None:
        """Nobody teaches two class sections at once.

        The one clash the table's own unique key cannot catch: that key guards
        a single class section's grid, and this is a collision between two of
        them.
        """
        clashes = (
            TimetableEntry.objects.filter(
                teacher_id=data["teacher_id"],
                day_of_week=data["day_of_week"],
                period_id=data["period_id"],
            )
            .exclude(class_section_id=data["class_section_id"])
            .exists()
        )

        if clashes:
            raise TeacherScheduleConflict(
                "This teacher is already scheduled for another class section "
                "at this day and period."
            )



class DailyTeachingReportService:
    """What each period actually covered, filed by the teacher who taught it.

    Scheduled comes from the timetable and submitted from this table, both
    counted over the same visibility, so "3 pending" on the KPI row means
    three periods this viewer could chase. There is no separate "conducted"
    figure: the system has no signal for it other than a report being filed.
    """

    WITH = (
        "timetable_entry__class_section__school_class",
        "timetable_entry__period",
        "timetable_entry__subject",
        "teacher",
        "reviewed_by",
    )

    @classmethod
    def create(cls, entry, data: dict, actor: User):
        holiday = HolidayService.holiday_on(entry.school_id, data["report_date"])

        if holiday is not None:
            raise TeachingReportOnHoliday(
                f"No periods are taught on {holiday.name} - it is a holiday."
            )

        # The timetable runs Monday to Friday, so a weekend period is not a
        # period that existed to be taught.
        if not HolidayService.is_working_day(entry.school_id, data["report_date"]):
            raise NonWorkingDay("No periods are taught at the weekend - the school is closed.")

        already = DailyTeachingReport.objects.filter(
            timetable_entry_id=entry.id, report_date=data["report_date"]
        ).exists()

        if already:
            raise TeachingReportAlreadySubmitted(
                "A report has already been submitted for this period and date."
            )

        now = timezone.now()

        report = DailyTeachingReport.objects.create(
            school_id=entry.school_id,
            timetable_entry_id=entry.id,
            teacher_id=actor.id,
            report_date=data["report_date"],
            topic_taught=data["topic_taught"],
            homework=data.get("homework"),
            remarks=data.get("remarks"),
            created_at=now,
            updated_at=now,
        )

        return cls.fresh(report)

    @classmethod
    def review(cls, report, actor: User):
        if report.reviewed_by_id is not None:
            raise TeachingReportAlreadyReviewed("This report has already been reviewed.")

        now = timezone.now()
        report.reviewed_by_id = actor.id
        report.reviewed_at = now
        report.updated_at = now
        report.save(update_fields=["reviewed_by", "reviewed_at", "updated_at"])

        return cls.fresh(report)

    @classmethod
    def fresh(cls, report):
        return DailyTeachingReport.objects.select_related(*cls.WITH).get(pk=report.pk)

    @classmethod
    def visible_to(cls, actor: User, filters: dict):
        reports = cls.scoped(
            DailyTeachingReport.objects.select_related(*cls.WITH),
            actor,
            filters.get("school_id"),
        )

        if filters.get("teacher_id"):
            reports = reports.filter(teacher_id=filters["teacher_id"])

        if filters.get("report_date"):
            reports = reports.filter(report_date=filters["report_date"])

        # One teacher files a report per period, so a teacher and a date are
        # nowhere near unique - id breaks the tie, or paging repeats a report
        # and skips another.
        return reports.order_by("-report_date", "teacher_id", "id")

    @classmethod
    def summary(cls, actor: User, filters: dict, date) -> dict:
        school_id = SchoolScope.for_actor(actor).writable_school_id(
            SchoolScope.requested_id(filters.get("school_id"))
        )

        # Only nameable when the question is about one school: a Super Admin
        # looking across every school has no single calendar to consult.
        holiday = None if school_id is None else HolidayService.holiday_on(school_id, date)

        if holiday is not None:
            scheduled = 0
        else:
            scheduled = cls.scoped(
                TimetableEntry.objects.all(), actor, filters.get("school_id")
            ).filter(day_of_week=date.strftime("%A").lower()).count()

        submitted = cls.scoped(
            DailyTeachingReport.objects.all(), actor, filters.get("school_id")
        ).filter(report_date=date).count()

        return {
            "scheduled": scheduled,
            "submitted": submitted,
            "pending": max(0, scheduled - submitted),
            "holiday": holiday.name if holiday else None,
        }

    @staticmethod
    def scoped(rows, actor: User, school_id_filter):
        """Reports and timetable entries narrow the same way: an HOD to the
        departments they head, a teacher to their own."""
        rows = SchoolScope.for_actor(actor).apply_to(rows, school_id_filter)

        if actor.role == UserRole.HOD:
            return rows.filter(teacher__staffprofile__department__hod_user_id=actor.id)

        if actor.role == UserRole.TEACHER:
            return rows.filter(teacher_id=actor.id)

        return rows


class SyllabusTopicService:
    """A subject's outline: its topics, in teaching order."""

    @staticmethod
    def for_subject(subject_id: int):
        return (
            SyllabusTopic.objects.select_related("subject")
            .filter(subject_id=subject_id)
            .order_by("sequence_number")
        )

    @staticmethod
    def create(subject, data: dict):
        now = timezone.now()

        topic = SyllabusTopic.objects.create(
            school_id=subject.school_id,
            subject_id=subject.id,
            title=data["title"],
            sequence_number=data["sequence_number"],
            created_at=now,
            updated_at=now,
        )

        return SyllabusTopic.objects.select_related("subject").get(pk=topic.pk)

    @staticmethod
    def update(topic, data: dict):
        changed = [field for field, value in data.items() if getattr(topic, field) != value]

        # Eloquent saves nothing, timestamp included, when nothing changed;
        # an edit that sends back the same title is not an edit.
        if changed:
            for field in changed:
                setattr(topic, field, data[field])

            topic.updated_at = timezone.now()
            topic.save(update_fields=[*changed, "updated_at"])

        return SyllabusTopic.objects.select_related("subject").get(pk=topic.pk)

    @staticmethod
    def delete(topic) -> None:
        topic.delete()


def percent_of(part: int, whole: int) -> int:
    """A whole-number percentage, halves rounded *up*.

    PHP's round() takes 12.5 to 13; Python's round() takes it to 12, because
    it rounds halves to even. One topic of eight is exactly that case, so a
    bare round() here would disagree with Laravel on an ordinary syllabus.
    """
    if whole == 0:
        return 0

    return int(Decimal(part * 100) / Decimal(whole) + Decimal("0.5"))


class SyllabusProgressService:
    @staticmethod
    def checklist(subject, section) -> dict:
        """A subject's topics in order, each with this section's completion
        mark or none - the syllabus equivalent of the attendance register."""
        topics = list(SyllabusTopic.objects.filter(subject_id=subject.id).order_by("sequence_number"))

        marks = {
            mark.syllabus_topic_id: mark
            for mark in SyllabusTopicProgress.objects.select_related("completed_by").filter(
                class_section_id=section.id, syllabus_topic_id__in=[topic.id for topic in topics]
            )
        }

        return {
            "subject_id": subject.id,
            "subject_name": subject.name,
            "class_section_id": section.id,
            "total_topics": len(topics),
            "completed_topics": len(marks),
            "progress_percent": percent_of(len(marks), len(topics)),
            "topics": [
                {
                    "id": topic.id,
                    "title": topic.title,
                    "sequence_number": topic.sequence_number,
                    "completed": topic.id in marks,
                    "completed_by_name": (
                        marks[topic.id].completed_by.name if topic.id in marks else None
                    ),
                    "completed_at": (
                        timestamp(marks[topic.id].completed_at) if topic.id in marks else None
                    ),
                }
                for topic in topics
            ],
        }

    @staticmethod
    def toggle(topic, section, completed: bool, actor: User) -> None:
        """Ticking records who and when, again if it was already ticked;
        unticking removes the mark rather than keeping a "not done" row."""
        if not completed:
            SyllabusTopicProgress.objects.filter(
                syllabus_topic_id=topic.id, class_section_id=section.id
            ).delete()

            return

        now = timezone.now()

        SyllabusTopicProgress.objects.update_or_create(
            syllabus_topic_id=topic.id,
            class_section_id=section.id,
            defaults={
                "school_id": topic.school_id,
                "completed_by_id": actor.id,
                "completed_at": now,
                "updated_at": now,
            },
            create_defaults={
                "school_id": topic.school_id,
                "completed_by_id": actor.id,
                "completed_at": now,
                "created_at": now,
                "updated_at": now,
            },
        )



def php_number(value):
    """A number as PHP's json_encode writes it.

    PHP drops a whole float's fraction - 50.0 goes out as `50`, 0.0 as `0` -
    and Python's json keeps it. A client that reads the field as an int
    would break on `50.0`, so whole floats become ints here.
    """
    if isinstance(value, float) and value.is_integer():
        return int(value)

    return value


def php_round_1(value: float) -> float:
    """PHP 8.3's round($value, 1).

    Halves go away from zero, where Python's round() goes to even (6.25 is
    6.3 in PHP and 6.2 in Python). And PHP first pre-rounds to 15 significant
    digits, so a float a hair under a half, the way binary arithmetic leaves
    them, still rounds up. `.15g` is that pre-round.
    """
    return float(Decimal(f"{value:.15g}").quantize(Decimal("0.1"), rounding=ROUND_HALF_UP))


class HodReportService:
    """One month of a department's teaching, computed from what the earlier
    modules already record. Nothing here is stored.

    The definitions were fixed on 2026-09-09 and are the contract:

    - **Working days**: weekdays in the month that are not school holidays,
      and for the current month only up to today - today at the *school*.
    - **Attendance %**: (present + half a day for each half-day) / working
      days. Every present or half-day mark in the month counts, including one
      on a date a later holiday removed from the working days - the numerator
      is the register as it stands.
    - **Leave days**: approved leave on working days, clipped to the month; a
      half-day leave is half a day.
    - **Late marks**: check-ins after the school's earliest period starts.
    - **Classes assigned**: timetable slots on working days; **taught**: those
      on days the teacher was present or on a half day.
    - **Syllabus %**: completed over total topics across every subject and
      section the teacher is timetabled for - cumulative, not this month's.
    - **Status**: "review" when reports await review or fewer were filed than
      classes taught; otherwise "on_track".
    """

    TEACHING_ROLES = (UserRole.TEACHER, UserRole.HOD)

    @classmethod
    def department_report(cls, actor: User, school, department, month: str, page: int, per_page: int) -> dict:
        departments = cls.departments_in_scope(actor, school, department)
        department_ids = [row.id for row in departments]

        year, month_number = (int(part) for part in month.split("-"))
        month_start = dt.date(year, month_number, 1)
        month_end = (month_start + dt.timedelta(days=32)).replace(day=1) - dt.timedelta(days=1)

        # Never count working days the school has not reached yet.
        today = SchoolClock.for_school(school).now().date()
        working_dates = HolidayService.working_dates(school.id, month_start, min(month_end, today))
        weekdays = [date.strftime("%A").lower() for date in working_dates]

        late_after = Period.objects.filter(school_id=school.id).aggregate(first=Min("start_time"))["first"]

        teachers = StaffProfile.objects.filter(
            school_id=school.id,
            department_id__in=department_ids,
            user__role__in=cls.TEACHING_ROLES,
            user__status=UserStatus.ACTIVE,
        )
        scoped_ids = list(teachers.values_list("id", flat=True))

        leaves = list(
            StaffLeave.objects.filter(
                staff_profile_id__in=scoped_ids,
                status=LeaveStatus.APPROVED,
                start_date__lte=month_end,
                end_date__gte=month_start,
            )
        )

        total = len(scoped_ids)
        last_page = max(1, -(-total // per_page))
        offset = (page - 1) * per_page

        # First name, then id - the id so two teachers called Priya page
        # without repeating one and skipping the other.
        profiles = list(
            teachers.select_related("user", "department").order_by("user__first_name", "id")[
                offset : offset + per_page
            ]
        )
        profile_ids = [profile.id for profile in profiles]
        user_ids = [profile.user_id for profile in profiles]

        attendance = {}
        for row in StaffAttendance.objects.filter(
            staff_profile_id__in=profile_ids, attendance_date__range=(month_start, month_end)
        ):
            attendance.setdefault(row.staff_profile_id, []).append(row)

        entries = {}
        for entry in TimetableEntry.objects.filter(school_id=school.id, teacher_id__in=user_ids).values(
            "teacher_id", "day_of_week", "subject_id", "class_section_id"
        ):
            entries.setdefault(entry["teacher_id"], []).append(entry)

        reports = {
            row["teacher_id"]: row
            for row in DailyTeachingReport.objects.filter(
                teacher_id__in=user_ids, report_date__range=(month_start, month_end)
            )
            .values("teacher_id")
            .annotate(submitted=Count("id"), pending=Count("id", filter=Q(reviewed_by__isnull=True)))
        }

        syllabus = cls.syllabus_coverage([entry for rows in entries.values() for entry in rows])

        rows = [
            cls.teacher_row(
                profile,
                working_dates,
                weekdays,
                late_after,
                attendance.get(profile.id, []),
                [leave for leave in leaves if leave.staff_profile_id == profile.id],
                entries.get(profile.user_id, []),
                reports.get(profile.user_id),
                syllabus,
            )
            for profile in profiles
        ]

        working_days = len(working_dates)
        credit = cls.attendance_credit(scoped_ids, month_start, month_end)

        return {
            "month": month,
            "school_id": school.id,
            "departments": [{"id": row.id, "name": row.name} for row in departments],
            "working_days": working_days,
            "teacher_count": total,
            "avg_attendance_percent": php_number(
                0.0
                if working_days == 0 or total == 0
                else php_round_1(credit / (working_days * total) * 100)
            ),
            "leave_days": php_number(sum((cls.leave_days_within(leave, working_dates) for leave in leaves), 0)),
            "late_marks": cls.late_marks(scoped_ids, month_start, month_end, late_after),
            "data": rows,
            "meta": {
                "current_page": page,
                "last_page": last_page,
                "total": total,
                "per_page": per_page,
            },
        }

    @classmethod
    def teacher_row(cls, profile, working_dates, weekdays, late_after, attendance, leaves, entries, reports, syllabus) -> dict:
        status_by_date = {row.attendance_date: row.status for row in attendance}
        present = sum(1 for row in attendance if row.status == StaffAttendanceStatus.PRESENT)
        half_day = sum(1 for row in attendance if row.status == StaffAttendanceStatus.HALF_DAY)
        working_days = len(working_dates)

        slots_by_day = {}
        for entry in entries:
            slots_by_day[entry["day_of_week"]] = slots_by_day.get(entry["day_of_week"], 0) + 1

        assigned = 0
        taught = 0
        for date, weekday in zip(working_dates, weekdays):
            slots = slots_by_day.get(weekday, 0)
            assigned += slots

            if status_by_date.get(date) in (StaffAttendanceStatus.PRESENT, StaffAttendanceStatus.HALF_DAY):
                taught += slots

        submitted = reports["submitted"] if reports else 0
        pending = reports["pending"] if reports else 0

        topics_total = 0
        topics_completed = 0
        for subject_id, section_id in dict.fromkeys(
            (entry["subject_id"], entry["class_section_id"]) for entry in entries
        ):
            topics_total += syllabus["totals"].get(subject_id, 0)
            topics_completed += syllabus["completed"].get((subject_id, section_id), 0)

        return {
            "staff_profile_id": profile.id,
            "user_id": profile.user_id,
            "teacher_name": profile.user.name,
            "employee_id": profile.employee_id,
            "department_id": profile.department_id,
            "department_name": profile.department.name if profile.department_id else None,
            "attendance_percent": php_number(
                0.0 if working_days == 0 else php_round_1((present + 0.5 * half_day) / working_days * 100)
            ),
            "leave_days": php_number(sum((cls.leave_days_within(leave, working_dates) for leave in leaves), 0)),
            "late_marks": 0
            if late_after is None
            else sum(1 for row in attendance if row.check_in is not None and row.check_in > late_after),
            "classes_assigned": assigned,
            "classes_taught": taught,
            "reports_submitted": submitted,
            "reports_pending_review": pending,
            "syllabus_percent": percent_of(topics_completed, topics_total),
            "status": "review" if pending > 0 or submitted < taught else "on_track",
        }

    @staticmethod
    def departments_in_scope(actor: User, school, department) -> list:
        if department is not None:
            return [department]

        departments = Department.objects.filter(school_id=school.id)

        if actor.role == UserRole.HOD:
            departments = departments.filter(hod_user_id=actor.id)

        return list(departments.order_by("name"))

    @staticmethod
    def leave_days_within(leave, working_dates) -> float:
        days = sum(1 for date in working_dates if leave.start_date <= date <= leave.end_date)

        return days * 0.5 if leave.leave_type == LeaveType.HALF_DAY else float(days)

    @staticmethod
    def attendance_credit(profile_ids, start, end) -> float:
        """Day credits across the whole scope: present 1, half day 0.5."""
        counts = dict(
            StaffAttendance.objects.filter(
                staff_profile_id__in=profile_ids,
                attendance_date__range=(start, end),
                status__in=(StaffAttendanceStatus.PRESENT, StaffAttendanceStatus.HALF_DAY),
            )
            .values_list("status")
            .annotate(total=Count("id"))
        )

        return counts.get(StaffAttendanceStatus.PRESENT, 0) + 0.5 * counts.get(StaffAttendanceStatus.HALF_DAY, 0)

    @staticmethod
    def late_marks(profile_ids, start, end, late_after) -> int:
        if late_after is None:
            return 0

        return StaffAttendance.objects.filter(
            staff_profile_id__in=profile_ids,
            attendance_date__range=(start, end),
            check_in__isnull=False,
            check_in__gt=late_after,
        ).count()

    @staticmethod
    def syllabus_coverage(entries) -> dict:
        """Topic totals per subject, and completed counts per subject and
        section, for every pair the page's teachers are timetabled for."""
        subject_ids = {entry["subject_id"] for entry in entries}
        section_ids = {entry["class_section_id"] for entry in entries}

        if not subject_ids:
            return {"totals": {}, "completed": {}}

        totals = dict(
            SyllabusTopic.objects.filter(subject_id__in=subject_ids)
            .values_list("subject_id")
            .annotate(total=Count("id"))
        )

        completed = {
            (row["syllabus_topic__subject_id"], row["class_section_id"]): row["done"]
            for row in SyllabusTopicProgress.objects.filter(
                syllabus_topic__subject_id__in=subject_ids, class_section_id__in=section_ids
            )
            .values("syllabus_topic__subject_id", "class_section_id")
            .annotate(done=Count("id"))
        }

        return {"totals": totals, "completed": completed}


class StaffProfileService:
    """Teachers and other staff: the login and the employment record together.

    The Add Employee screen is one form and this is why - a login with no
    employment record is invisible to Attendance and Leave, and a profile with
    no login is somebody on a roster who cannot sign in.
    """

    WITH = ("user", "school", "department")

    @classmethod
    def visible_to(cls, actor: User, filters: dict):
        staff = StaffProfile.objects.select_related(*cls.WITH)

        staff = SchoolScope.for_actor(actor).apply_to(staff, filters.get("school_id"))

        # Never the placeholder profile a School Admin account gets so it can
        # use Leave and Staff Attendance (see UserService.create). This list
        # is real employment records only - the ones Add Employee produces.
        staff = staff.exclude(user__role=UserRole.SCHOOL_ADMIN)

        if filters.get("department_id"):
            staff = staff.filter(department_id=filters["department_id"])

        if filters.get("role"):
            staff = staff.filter(user__role=filters["role"])

        if filters.get("status"):
            staff = staff.filter(user__status=filters["status"])

        search = filters.get("search")

        if search:
            # icontains on both databases - see StudentService for why a bare
            # LIKE cannot be trusted across the two.
            staff = staff.filter(
                Q(user__first_name__icontains=search)
                | Q(user__last_name__icontains=search)
                | Q(user__email__icontains=search)
            )

        # `employee_id` is unique within a school but not across them, so a
        # Super Admin's roster ties - EMP-001 exists at every school.
        return staff.order_by("employee_id", "id")

    @staticmethod
    def classes_taught_by(user_ids) -> dict:
        """Which classes each of these people is class teacher of.

        One query for a whole page. The value is what the screen shows -
        "Grade 8 A" - rather than ids the client would have to join itself.
        """
        taught: dict[int, list[str]] = {}

        for section in ClassSection.objects.select_related("school_class").filter(
            class_teacher_id__in=list(user_ids)
        ).order_by("school_class__name", "name"):
            label = f"{section.school_class.name} {section.name}".strip()
            taught.setdefault(section.class_teacher_id, []).append(label)

        return taught

    @staticmethod
    def create_employee(user_data: dict, profile_data: dict, actor: User) -> StaffProfile:
        """Both rows, in one transaction. Half an employee is not a state the
        product has a screen for."""
        with transaction.atomic():
            user = UserService.create(actor, user_data)
            now = timezone.now()

            return StaffProfile.objects.create(
                user_id=user.id,
                # Always the account's own school, resolved by UserService
                # above - never re-derived from client input here.
                school_id=user.school_id,
                employee_id=profile_data["employee_id"],
                department_id=profile_data.get("department_id"),
                designation=profile_data.get("designation"),
                joining_date=profile_data["joining_date"],
                address=profile_data.get("address"),
                created_at=now,
                updated_at=now,
            )

    @staticmethod
    def update(profile: StaffProfile, data: dict) -> StaffProfile:
        for field, value in data.items():
            setattr(profile, field, value)

        profile.updated_at = timezone.now()
        profile.save()

        return profile


class PaymentService:
    """Payments a school has made to the platform.

    Not a subscription system and not an accounting one (CLAUDE.md rule 4):
    this records money that arrived. No plans, no renewals, and nothing here
    decides whether a school can use the product.
    """

    WITH = ("school", "created_by")

    @classmethod
    def visible_to(cls, filters: dict):
        # No SchoolScope: only a Super Admin reaches payments at all, and a
        # Super Admin is unrestricted. The school filter is an ordinary filter
        # rather than a scope narrowing.
        payments = Payment.objects.select_related(*cls.WITH)

        for field in ("school_id", "status", "payment_type"):
            if filters.get(field):
                payments = payments.filter(**{field: filters[field]})

        # Newest first, and already deterministic - `id` breaks the tie.
        return payments.order_by("-payment_date", "-id")

    @classmethod
    def create(cls, data: dict, actor: User) -> Payment:
        data = dict(data)
        school = School.objects.get(pk=data["school_id"])

        total = money.amount(data["amount"])
        paid = money.paid_amount_for(data, total)
        now = timezone.now()

        with transaction.atomic():
            payment = Payment.objects.create(
                school_id=school.id,
                payment_type=data["payment_type"],
                amount=total,
                paid_amount=paid,
                # Derived from the figures rather than taken at face value, so
                # a payment can never read "Paid" with a balance outstanding.
                status=money.status_for(total, paid, data.get("status")),
                # Never trusted from the client - always the owning school's
                # currency at the moment of payment (CLAUDE.md rule 5).
                currency_code=school.currency_code,
                payment_date=data["payment_date"],
                payment_mode=data["payment_mode"],
                reference_number=data.get("reference_number"),
                notes=data.get("notes"),
                created_by_id=actor.id,
                created_at=now,
                updated_at=now,
            )

            cls.send_receipt(payment)

        return payment

    @classmethod
    def update(cls, payment: Payment, data: dict) -> Payment:
        total = money.amount(data.get("amount", payment.amount))
        paid = money.paid_amount_for(data, total, fallback=money.amount(payment.paid_amount))

        before = (money.amount(payment.amount), money.amount(payment.paid_amount), payment.status)

        with transaction.atomic():
            for field, value in data.items():
                setattr(payment, field, value)

            payment.amount = total
            payment.paid_amount = paid
            payment.status = money.status_for(total, paid, data.get("status"))
            payment.updated_at = timezone.now()
            payment.save()

            after = (payment.amount, payment.paid_amount, payment.status)

            # Only when the money or the standing changed. Re-sending a receipt
            # because somebody corrected a reference number would be noise.
            if before != after:
                cls.send_receipt(payment)

        return payment

    @staticmethod
    def send_receipt(payment: Payment) -> None:
        """Queues the receipt email.

        Queued, not sent: rendering a PDF and talking to an SMTP server has no
        business holding up the person recording the payment, and a mail
        server being down must never be why a payment fails to save.

        The row is written inside the caller's transaction, so the job exists
        if and only if the payment it is about was committed.
        """
        queue.push(jobs.SEND_PAYMENT_RECEIPT, {"payment_id": payment.id})

    @staticmethod
    def collection_summary() -> dict:
        """Totals for the payments dashboard.

        **Every figure is grouped by currency and never summed across them**
        (CLAUDE.md rule 5). This is a recording system, not a forex one, and a
        single blended total would be a number that is true in no currency.
        """
        platform_now = SchoolClock.platform().now()

        # Collected means money that actually arrived, so it sums paid_amount
        # and counts a part-payment for the part that was paid. Summing
        # `amount` over settled rows only would miss those entirely.
        def collected():
            return (
                Payment.objects.exclude(status=PaymentStatus.CANCELLED)
                .values("currency_code")
                .annotate(total=Sum("paid_amount"))
                .filter(total__gt=0)
                .order_by("currency_code")
            )

        monthly = collected().filter(
            # Cross-school totals belong to no single school, so "this month"
            # is the platform's month.
            payment_date__year=platform_now.year,
            payment_date__month=platform_now.month,
        )

        # Outstanding is what is still owed, which includes the unpaid part of
        # a partial payment - not only the rows nobody has paid at all.
        outstanding = Payment.objects.filter(
            status__in=[PaymentStatus.PENDING, PaymentStatus.PARTIAL]
        )

        by_currency = (
            outstanding.values("currency_code")
            .annotate(total=Sum(F("amount") - F("paid_amount")))
            .filter(total__gt=0)
            .order_by("currency_code")
        )

        return {
            "total_by_currency": [as_total(row) for row in collected()],
            "monthly_by_currency": [as_total(row) for row in monthly],
            "pending_by_currency": [as_total(row) for row in by_currency],
            "pending_count": outstanding.count(),
        }


def as_total(row: dict) -> dict:
    """One currency's total, as a string. See payment_resource for why."""
    return {"currency_code": row["currency_code"], "total": str(money.amount(row["total"]))}


class PeriodService:
    """The school day's shape. Not paginated - a school has eight or nine
    periods, and paging a list that short would be a control nobody uses."""

    @staticmethod
    def visible_to(actor: User, filters: dict):
        periods = Period.objects.all()

        periods = SchoolScope.for_actor(actor).apply_to(periods, filters.get("school_id"))

        return periods.order_by("period_number", "id")

    @staticmethod
    def create(data: dict, actor: User) -> Period:
        data = dict(data)
        school_id = SchoolScope.for_actor(actor).writable_school_id(data.pop("school_id", None))
        now = timezone.now()

        return Period.objects.create(
            school_id=school_id,
            period_number=data["period_number"],
            start_time=data["start_time"],
            end_time=data["end_time"],
            created_at=now,
            updated_at=now,
        )

    @staticmethod
    def update(period: Period, data: dict) -> Period:
        for field, value in data.items():
            setattr(period, field, value)

        period.updated_at = timezone.now()
        period.save()

        return period

    @staticmethod
    def delete(period: Period) -> None:
        if TimetableEntry.objects.filter(period_id=period.id).exists():
            raise HasDependentRecords(
                "This period still has timetable entries scheduled against it. "
                "Remove them first."
            )

        period.delete()


class HolidayService:
    """The school holiday calendar.

    The working-day questions every date-driven module asks of it - is this a
    working day, which dates in a range are - arrive with the modules that ask
    them, in M10. What is here is the calendar itself.
    """

    @staticmethod
    def visible_to(actor: User, filters: dict):
        holidays = Holiday.objects.select_related("school")

        holidays = SchoolScope.for_actor(actor).apply_to(holidays, filters.get("school_id"))

        # A range filter that overlaps, not one that contains: a holiday
        # running across the boundary of the window is still in the window.
        if filters.get("date_from"):
            holidays = holidays.filter(end_date__gte=filters["date_from"])

        if filters.get("date_to"):
            holidays = holidays.filter(start_date__lte=filters["date_to"])

        return holidays.order_by("start_date", "id")

    @classmethod
    def create(cls, data: dict, actor: User) -> Holiday:
        data = dict(data)
        school_id = SchoolScope.for_actor(actor).writable_school_id(data.pop("school_id", None))

        cls._assert_no_overlap(school_id, data["start_date"], data["end_date"])

        now = timezone.now()

        return Holiday.objects.create(
            school_id=school_id,
            name=data["name"],
            type=data["type"],
            start_date=data["start_date"],
            end_date=data["end_date"],
            created_at=now,
            updated_at=now,
        )

    @classmethod
    def update(cls, holiday: Holiday, data: dict) -> Holiday:
        start = data.get("start_date", holiday.start_date)
        end = data.get("end_date", holiday.end_date)

        cls._assert_no_overlap(holiday.school_id, start, end, ignoring=holiday.pk)

        for field, value in data.items():
            setattr(holiday, field, value)

        holiday.updated_at = timezone.now()
        holiday.save()

        return holiday

    @staticmethod
    def delete(holiday: Holiday) -> None:
        holiday.delete()

    @staticmethod
    def affected_records(holiday: Holiday) -> dict:
        """The day's records that now sit on a non-working day.

        A holiday declared after the fact is a legitimate correction - a
        strike day, a closure nobody knew about on the morning. What is not
        legitimate is doing it silently: those records stop counting towards
        every working-day figure in the product, so whoever declared it is
        told how many there are and can go and clear them.
        """
        between = (holiday.start_date, holiday.end_date)

        return {
            "attendance": Attendance.objects.filter(
                school_id=holiday.school_id, attendance_date__range=between
            ).count(),
            "staff_attendance": StaffAttendance.objects.filter(
                school_id=holiday.school_id, attendance_date__range=between
            ).count(),
            "teaching_reports": DailyTeachingReport.objects.filter(
                school_id=holiday.school_id, report_date__range=between
            ).count(),
        }

    # -- the working-day questions every date-driven module asks ----------
    #
    # A working day is a Monday-to-Friday date not covered by a holiday.
    # Weekends are fixed, matching the Monday-to-Friday timetable, and both
    # halves matter: every working-day figure in the product excludes both, so
    # a Saturday register that no percentage counts is worse than none.

    @staticmethod
    def holiday_on(school_id: int, date):
        return Holiday.objects.filter(
            school_id=school_id, start_date__lte=date, end_date__gte=date
        ).first()

    @classmethod
    def is_working_day(cls, school_id: int, date) -> bool:
        return bool(cls.working_dates(school_id, date, date))

    @staticmethod
    def working_dates(school_id: int, start, end) -> list:
        """Every working date from `start` to `end` inclusive, in order.

        Empty when `start` is after `end`, rather than an error: a report for
        a range nobody has chosen yet asks this before it has both ends.
        """
        start = as_date(start)
        end = as_date(end)

        if start > end:
            return []

        holidays = list(
            Holiday.objects.filter(
                school_id=school_id, start_date__lte=end, end_date__gte=start
            ).values_list("start_date", "end_date")
        )

        dates = []
        day = start

        while day <= end:
            # Monday is 0, Saturday 5, Sunday 6.
            if day.weekday() < 5 and not any(
                first <= day <= last for first, last in holidays
            ):
                dates.append(day)

            day += dt.timedelta(days=1)

        return dates

    @staticmethod
    def _assert_no_overlap(school_id, start, end, ignoring=None) -> None:
        overlapping = Holiday.objects.filter(
            school_id=school_id, start_date__lte=end, end_date__gte=start
        )

        if ignoring is not None:
            overlapping = overlapping.exclude(pk=ignoring)

        clash = overlapping.first()

        if clash is not None:
            raise HolidayOverlap(f'These dates overlap the existing holiday "{clash.name}".')


class SchoolClassService:
    WITH = ("school", "academic_year")

    @classmethod
    def visible_to(cls, actor: User, filters: dict):
        classes = SchoolClass.objects.select_related(*cls.WITH)

        classes = SchoolScope.for_actor(actor).apply_to(classes, filters.get("school_id"))

        if filters.get("academic_year_id"):
            classes = classes.filter(academic_year_id=filters["academic_year_id"])

        # By level then name, which is the order a school reads its own
        # timetable in. Both repeat across schools and years, hence the id.
        return classes.order_by("level", "name", "id")

    @staticmethod
    def sections_of(class_ids) -> dict:
        """Every section of the given classes, grouped by class.

        One query for a whole page rather than one per class, which is what a
        resource walking the relation itself would cost (CLAUDE.md rule 22).
        """
        grouped: dict[int, list] = {}

        for section in ClassSection.objects.select_related("class_teacher").filter(
            school_class_id__in=list(class_ids)
        ).order_by("name", "id"):
            grouped.setdefault(section.school_class_id, []).append(section)

        return grouped

    @staticmethod
    def create(data: dict, actor: User) -> SchoolClass:
        data = dict(data)
        school_id = SchoolScope.for_actor(actor).writable_school_id(data.pop("school_id", None))
        now = timezone.now()

        return SchoolClass.objects.create(
            school_id=school_id,
            academic_year_id=data["academic_year_id"],
            name=data["name"],
            level=data["level"],
            created_at=now,
            updated_at=now,
        )

    @staticmethod
    def update(school_class: SchoolClass, data: dict) -> SchoolClass:
        for field, value in data.items():
            setattr(school_class, field, value)

        school_class.updated_at = timezone.now()
        school_class.save()

        return school_class

    @staticmethod
    def delete(school_class: SchoolClass) -> None:
        if ClassSection.objects.filter(school_class_id=school_class.id).exists():
            raise HasDependentRecords("This class still has sections under it. Remove them first.")

        school_class.delete()

    @staticmethod
    def add_section(school_class: SchoolClass, data: dict) -> ClassSection:
        now = timezone.now()

        return ClassSection.objects.create(
            school_class_id=school_class.id,
            name=data["name"],
            room_number=data.get("room_number"),
            class_teacher_id=data.get("class_teacher_id"),
            created_at=now,
            updated_at=now,
        )

    @staticmethod
    def update_section(section: ClassSection, data: dict) -> ClassSection:
        for field, value in data.items():
            setattr(section, field, value)

        section.updated_at = timezone.now()
        section.save()

        return section

    @staticmethod
    def delete_section(section: ClassSection) -> None:
        if Student.objects.filter(class_section_id=section.id).exists():
            raise HasDependentRecords(
                "This section still has students assigned to it. "
                "Reassign or remove them first."
            )

        section.delete()


class DepartmentService:
    WITH = ("school", "hod_user")

    @classmethod
    def visible_to(cls, actor: User, filters: dict):
        departments = Department.objects.select_related(*cls.WITH)

        departments = SchoolScope.for_actor(actor).apply_to(departments, filters.get("school_id"))

        # `name` is unique per school but not across them, so the id still
        # matters - see StudentService.visible_to.
        return departments.order_by("name", "id")

    @staticmethod
    def create(data: dict, actor: User) -> Department:
        data = dict(data)
        school_id = SchoolScope.for_actor(actor).writable_school_id(data.pop("school_id", None))
        now = timezone.now()

        return Department.objects.create(
            school_id=school_id,
            name=data["name"],
            hod_user_id=data.get("hod_user_id"),
            created_at=now,
            updated_at=now,
        )

    @staticmethod
    def update(department: Department, data: dict) -> Department:
        for field, value in data.items():
            setattr(department, field, value)

        department.updated_at = timezone.now()
        department.save()

        return department

    @staticmethod
    def delete(department: Department) -> None:
        if Subject.objects.filter(department_id=department.id).exists():
            raise HasDependentRecords(
                "This department still has subjects assigned to it. "
                "Reassign or remove them first."
            )

        department.delete()


class SubjectService:
    WITH = ("school", "department", "lead_teacher")

    @classmethod
    def visible_to(cls, actor: User, filters: dict):
        subjects = Subject.objects.select_related(*cls.WITH)

        subjects = SchoolScope.for_actor(actor).apply_to(subjects, filters.get("school_id"))

        if filters.get("department_id"):
            subjects = subjects.filter(department_id=filters["department_id"])

        return subjects.order_by("name", "id")

    @staticmethod
    def create(data: dict, actor: User) -> Subject:
        data = dict(data)
        school_id = SchoolScope.for_actor(actor).writable_school_id(data.pop("school_id", None))
        now = timezone.now()

        return Subject.objects.create(
            school_id=school_id,
            department_id=data["department_id"],
            code=data["code"],
            name=data["name"],
            min_class_level=data["min_class_level"],
            max_class_level=data["max_class_level"],
            lead_teacher_id=data.get("lead_teacher_id"),
            created_at=now,
            updated_at=now,
        )

    @staticmethod
    def update(subject: Subject, data: dict) -> Subject:
        for field, value in data.items():
            setattr(subject, field, value)

        subject.updated_at = timezone.now()
        subject.save()

        return subject

    @staticmethod
    def delete(subject: Subject) -> None:
        # No dependency check, matching Laravel. A subject is removed from the
        # catalogue; the timetable entries and syllabus topics that referenced
        # it are handled by the database's own foreign keys.
        subject.delete()


class AcademicYearService:
    @staticmethod
    def visible_to(actor: User, filters: dict):
        years = AcademicYear.objects.select_related("school")

        years = SchoolScope.for_actor(actor).apply_to(years, filters.get("school_id"))

        # Newest first - the year somebody is working in is almost always the
        # latest one. `id` breaks the tie, since two years can start on the
        # same date at different schools.
        return years.order_by("-start_date", "-id")

    @classmethod
    def create(cls, data: dict, actor: User) -> AcademicYear:
        data = dict(data)

        # Never the client's school_id (CLAUDE.md rule 10).
        school_id = SchoolScope.for_actor(actor).writable_school_id(data.pop("school_id", None))
        is_current = data.pop("is_current", False)
        now = timezone.now()

        with transaction.atomic():
            if is_current:
                cls._clear_current_for(school_id)

            return AcademicYear.objects.create(
                school_id=school_id,
                name=data["name"],
                start_date=data["start_date"],
                end_date=data["end_date"],
                # Never None. The column is NOT NULL with a default of false,
                # and a request that omits the field used to leave the API
                # answering `"is_current": null` for a column that cannot be
                # null - a client reading it as a boolean would fail on the
                # backend's own contract. Found by the contract suite, which
                # omits the field where the Flutter client always sends it.
                is_current=bool(is_current),
                created_at=now,
                updated_at=now,
            )

    @staticmethod
    def update(year: AcademicYear, data: dict) -> AcademicYear:
        for field, value in data.items():
            setattr(year, field, value)

        year.updated_at = timezone.now()
        year.save()

        return year

    @classmethod
    def set_current(cls, year: AcademicYear) -> AcademicYear:
        with transaction.atomic():
            cls._clear_current_for(year.school_id)

            year.is_current = True
            year.updated_at = timezone.now()
            year.save(update_fields=["is_current", "updated_at"])

        return year

    @staticmethod
    def delete(year: AcademicYear) -> None:
        if SchoolClass.objects.filter(academic_year_id=year.id).exists():
            raise HasDependentRecords(
                "This academic year still has classes set up under it. Remove them first."
            )

        year.delete()

    @staticmethod
    def _clear_current_for(school_id) -> None:
        """Exactly one year is current per school, so setting one clears the
        rest in the same transaction."""
        AcademicYear.objects.filter(school_id=school_id).update(
            is_current=False, updated_at=timezone.now()
        )


class UserService:
    @staticmethod
    def visible_to(actor: User, filters: dict):
        users = User.objects.select_related("school")

        # Never trust a client-supplied school filter: the scope decides what
        # is reachable and the filter can only narrow within it.
        users = SchoolScope.for_actor(actor).apply_to(users, filters.get("school_id"))

        if filters.get("role"):
            users = users.filter(role=filters["role"])

        # Comma-separated shorthand for "any of these roles" - used by the
        # academic-config pickers (HOD, lead teacher, class teacher).
        if filters.get("roles"):
            users = users.filter(role__in=str(filters["roles"]).split(","))

        if filters.get("status"):
            users = users.filter(status=filters["status"])

        # See StudentService.visible_to for why the id is not optional.
        return users.order_by("first_name", "id")

    @staticmethod
    def create(actor: User, data: dict) -> User:
        data = dict(data)

        # Never the client's school_id: an actor pinned to one school writes
        # into it whatever the request said (CLAUDE.md rule 10).
        school_id = SchoolScope.for_actor(actor).writable_school_id(data.pop("school_id", None))

        # Only meaningful for a SCHOOL_ADMIN: one created by a Super Admin can
        # create further admin accounts; one created by another admin - a "Sub
        # Admin" - has the same permissions everywhere else but cannot.
        is_sub_admin = (
            data.get("role") == UserRole.SCHOOL_ADMIN and actor.role != UserRole.SUPER_ADMIN
        )

        now = timezone.now()

        user = User.objects.create(
            first_name=data["first_name"],
            last_name=data["last_name"],
            email=data["email"],
            mobile=data.get("mobile"),
            password=hashing.make(data["password"]),
            role=data["role"],
            school_id=school_id,
            is_sub_admin=is_sub_admin,
            must_change_password=False,
            status=UserStatus.ACTIVE,
            created_at=now,
            updated_at=now,
        )

        # A School or Sub Admin otherwise has no StaffProfile at all, which
        # blocks them from the self-service actions that key off one - Staff
        # Leave and Staff Attendance. A minimal profile is enough for those;
        # it deliberately does not appear in the Teachers & Staff roster,
        # since it is not a real employment record the way onboarding through
        # that screen produces one.
        if user.role == UserRole.SCHOOL_ADMIN:
            StaffProfile.objects.create(
                user_id=user.id,
                school_id=user.school_id,
                employee_id=f"ADMIN-{user.id}",
                department_id=None,
                designation="Sub Admin" if user.is_sub_admin else "School Admin",
                joining_date=SchoolClock.for_school(user.school_id).date(),
                created_at=now,
                updated_at=now,
            )

        return user

    @staticmethod
    def update(user: User, data: dict) -> User:
        for field, value in data.items():
            # The model has no hashing cast the way Eloquent does, so the one
            # field that must never be stored as typed is hashed here.
            setattr(user, field, hashing.make(value) if field == "password" else value)

        user.updated_at = timezone.now()
        user.save()

        return user

    @classmethod
    def activate(cls, user: User) -> User:
        return cls.set_status(user, UserStatus.ACTIVE)

    @classmethod
    def deactivate(cls, user: User) -> User:
        user = cls.set_status(user, UserStatus.INACTIVE)

        # Deactivating signs them out everywhere. Without this the account is
        # switched off but whatever browser it was open in keeps working
        # until the token happens to be used against a check that notices.
        PersonalAccessToken.objects.filter(
            tokenable_type=tokens.TOKENABLE_TYPE, tokenable_id=user.pk
        ).delete()

        return user

    @staticmethod
    def set_status(user: User, status: str) -> User:
        user.status = status
        user.updated_at = timezone.now()
        user.save(update_fields=["status", "updated_at"])

        return user


class StudentService:
    # Laravel's `['school', 'classSection.schoolClass',
    # 'transportAssignment.route.vehicle', 'transportAssignment.stop']`, in
    # Django's spelling. The transport half is loaded even though transport is
    # M11's work: the key is part of the student's shape today, and Laravel
    # sends it as null for every student who does not ride a bus.
    WITH = (
        "school",
        "class_section__school_class",
        "studenttransportassignment__route__vehicle",
        "studenttransportassignment__transport_stop",
    )

    @classmethod
    def visible_to(cls, actor: User, filters: dict):
        """The students this actor may see, filtered as they asked."""
        students = Student.objects.select_related(*cls.WITH)

        students = SchoolScope.for_actor(actor).apply_to(students, filters.get("school_id"))

        # A teacher only ever sees students in sections they are the class
        # teacher of - never another class, regardless of filters.
        if actor.role == UserRole.TEACHER:
            students = students.filter(class_section__class_teacher_id=actor.id)

        if filters.get("class_section_id"):
            students = students.filter(class_section_id=filters["class_section_id"])

        if filters.get("status"):
            students = students.filter(status=filters["status"])

        search = filters.get("search")

        if search:
            # icontains, not contains. MySQL's collation is case-insensitive
            # and PostgreSQL's is not, so a plain LIKE means two different
            # things and the difference is silent - which is exactly the bug
            # M2 went looking for. This compiles to ILIKE.
            students = students.filter(
                Q(first_name__icontains=search)
                | Q(last_name__icontains=search)
                | Q(admission_number__icontains=search)
            )

        # `first_name` is not unique, so it needs a tiebreaker: without one a
        # page boundary can fall between two students called Aarav and show
        # one of them twice while skipping the other. MySQL and PostgreSQL
        # order ties differently, which is how the two backends were caught
        # disagreeing about a list they both thought they had sorted.
        #
        # Changed on both backends in the same commit, deliberately - a fix
        # applied to one would have been a behaviour difference this migration
        # exists not to introduce.
        return students.order_by("first_name", "id")

    @staticmethod
    def create(data: dict, actor: User) -> Student:
        # Never the client's school_id: an actor pinned to one school writes
        # into it whatever the request said (CLAUDE.md rule 10). The form has
        # already resolved it; this re-asks so a caller that builds the dict
        # itself - the bulk importer - cannot skip the rule.
        school_id = SchoolScope.for_actor(actor).writable_school_id(data.get("school_id"))
        now = timezone.now()

        return Student.objects.create(
            school_id=school_id,
            class_section_id=data.get("class_section_id"),
            admission_number=data["admission_number"],
            first_name=data["first_name"],
            last_name=data["last_name"],
            roll_number=data.get("roll_number"),
            guardian_name=data["guardian_name"],
            guardian_mobile=data.get("guardian_mobile"),
            address=data.get("address"),
            status=StudentStatus.ACTIVE,
            created_at=now,
            updated_at=now,
        )

    @staticmethod
    def update(student: Student, data: dict) -> Student:
        for field, value in data.items():
            setattr(student, field, value)

        student.updated_at = timezone.now()
        student.save()

        return student

    @classmethod
    def activate(cls, student: Student) -> Student:
        return cls.set_status(student, StudentStatus.ACTIVE)

    @classmethod
    def deactivate(cls, student: Student) -> Student:
        return cls.set_status(student, StudentStatus.INACTIVE)

    @staticmethod
    def set_status(student: Student, status: str) -> Student:
        student.status = status
        student.updated_at = timezone.now()
        student.save(update_fields=["status", "updated_at"])

        return student


def as_date(value) -> dt.date:
    """A date from either a date or a `YYYY-MM-DD` string."""
    if isinstance(value, dt.date):
        return value

    return dt.date.fromisoformat(str(value)[:10])
