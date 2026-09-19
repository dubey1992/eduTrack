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

from . import (
    audit,
    crypto,
    hashing,
    jobs,
    mailer,
    modules,
    money,
    notices,
    notifications,
    permissions,
    queue,
    sms,
    tokens,
    whatsapp,
    working_hours,
)
from .gateways import Template
from .clock import TIME, SchoolClock
from .fields import as_utc
from .enums import (
    NoticeAudience,
    NoticeKind,
    NoticeRecipients,
    EarlyAccessStatus,
    TripEventType,
    TripRiderStatus,
    TripStatus,
    TransportStatus,
    AnnouncementAudience,
    AnnouncementChannels,
    AttendanceStatus,
    LeaveStatus,
    LeaveType,
    MessageChannel,
    MessageEvent,
    MessageStatus,
    PaymentStatus,
    SchoolStatus,
    StaffAttendanceStatus,
    StudentStatus,
    UserRole,
    UserStatus,
)
from .errors import (
    GatewayTestFailed,
    SettingRefused,
    AccountInactive,
    AccountLocked,
    AttendanceAlreadySubmitted,
    AttendanceOnHoliday,
    HasDependentRecords,
    HolidayOverlap,
    LeaveAlreadyReviewed,
    LeaveOnNonWorkingDays,
    LeaveOverlap,
    NonWorkingDay,
    TeacherScheduleConflict,
    UnreachableAudience,
    RouteCapacityFull,
    TripRule,
    TeachingReportAlreadyReviewed,
    TeachingReportAlreadySubmitted,
    TeachingReportOnHoliday,
    Unauthenticated,
)
from .models import (
    MailSetting,
    ModuleSetting,
    RolePermission,
    WhatsappTemplate,
    AcademicYear,
    Announcement,
    Attendance,
    ClassSection,
    MessageTemplate,
    Message,
    CommunicationSetting,
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
    Driver,
    StudentTransportAssignment,
    TransportRoute,
    TransportStop,
    TransportTrip,
    Vehicle,
    TransportTripEvent,
    TransportTripRider,
    PasswordResetToken,
    User,
)
from .requests import php_int
from .resources import timestamp
from .scope import SchoolScope


class AuthService:
    MODULE = "auth"

    @classmethod
    def login(cls, email: str, password: str, device: str | None = None) -> tuple[User, str]:
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
        correct = hashing.check(password, stored)

        # A locked account refuses even the right password until the lock
        # runs out - otherwise the lock would only slow a guesser down.
        if user is not None and cls.locked_for(user):
            raise AccountLocked(cls.locked_for(user))

        if not correct or user is None:
            cls._failed(user, email)
            raise Unauthenticated("These credentials do not match our records.")

        if not user.is_active():
            raise AccountInactive()

        User.objects.filter(pk=user.pk).update(failed_login_attempts=0, locked_until=None)
        token = tokens.issue(user, device)
        cls._record(user, "user.signed_in", {"device": tokens.describe_device(device)})

        return user, token

    @staticmethod
    def locked_for(user: User) -> int:
        """Whole minutes the account stays locked, rounded up; 0 when it is not."""
        if user.locked_until is None:
            return 0

        remaining = (as_utc(user.locked_until) - timezone.now()).total_seconds()

        return 0 if remaining <= 0 else -(-int(remaining) // 60)

    @classmethod
    def _failed(cls, user: User | None, email: str) -> None:
        """Counts a wrong password, and locks the account at the limit.

        Counted with an UPDATE ... + 1 so two guesses at once cannot both read
        nine and both write ten. An address with no account has nothing to
        count, but the attempt is still recorded - a run of them is exactly
        what a security review looks for.
        """
        from django.conf import settings

        if user is None:
            audit.record(actor=None, action="user.sign_in_failed", module=cls.MODULE, entity_type="user",
                         entity_id=None, school_id=None, new={"email": email})
            return

        User.objects.filter(pk=user.pk).update(failed_login_attempts=F("failed_login_attempts") + 1)
        attempts = User.objects.values_list("failed_login_attempts", flat=True).get(pk=user.pk)
        cls._record(user, "user.sign_in_failed", {"attempts": attempts})

        if attempts >= settings.LOCKOUT_ATTEMPTS:
            until = timezone.now() + dt.timedelta(minutes=settings.LOCKOUT_MINUTES)
            User.objects.filter(pk=user.pk).update(failed_login_attempts=0, locked_until=until)
            cls._record(user, "user.locked", {"locked_until": until, "attempts": attempts})

    @classmethod
    def unlock(cls, user: User) -> None:
        """An administrator lets a locked-out user try again straight away."""
        User.objects.filter(pk=user.pk).update(failed_login_attempts=0, locked_until=None)
        audit.record(action="user.unlocked", module=cls.MODULE, entity_type="user", entity_id=user.id,
                     school_id=user.school_id)

    @classmethod
    def _record(cls, user: User, action: str, new: dict | None = None) -> None:
        # Sign-in happens before anybody is authenticated, so the actor is
        # named rather than taken from the request.
        audit.record(actor=user, action=action, module=cls.MODULE, entity_type="user", entity_id=user.id,
                     school_id=user.school_id, new=new)

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

        ended = tokens.revoke_all(user, keep=current_token)
        AuthService._record(user, "user.password_changed", {"other_sessions_ended": ended})

    @staticmethod
    def logout(user: User, current_token: PersonalAccessToken) -> None:
        if current_token is not None:
            PersonalAccessToken.objects.filter(pk=current_token.pk).delete()
            AuthService._record(user, "user.signed_out")

    @staticmethod
    def end_session(user: User, session_id: int) -> bool:
        """Signs one of the user's own devices out. False when it is not theirs."""
        deleted, _ = PersonalAccessToken.objects.filter(
            pk=session_id, tokenable_type=tokens.TOKENABLE_TYPE, tokenable_id=user.pk
        ).delete()

        if deleted:
            AuthService._record(user, "user.session_ended", {"session_id": session_id})

        return bool(deleted)

    @staticmethod
    def end_other_sessions(user: User, current_token: PersonalAccessToken) -> int:
        ended = tokens.revoke_all(user, keep=current_token)
        AuthService._record(user, "user.other_sessions_ended", {"sessions_ended": ended})

        return ended


class EarlyAccessService:
    """The marketing page's signups, and the Super Admin's queue of them."""

    FIELDS = (
        "school_name", "contact_name", "contact_role", "email", "phone", "city", "country",
        "expected_students", "current_software", "message",
    )

    @classmethod
    def record(cls, data: dict) -> None:
        """A signup - or a correction to one still open.

        The same address asking again, while its request is new or being
        followed up, updates that request rather than queueing a second: their
        latest answers win, and the request keeps its place and whatever
        status somebody has already given it.
        """
        now = timezone.now()
        existing = (
            EarlyAccessRequest.objects.filter(email=data["email"], status__in=EarlyAccessStatus.open())
            .order_by("-id")
            .first()
        )

        if existing is None:
            request = EarlyAccessRequest.objects.create(
                **{field: data.get(field) for field in cls.FIELDS},
                status=EarlyAccessStatus.NEW, created_at=now, updated_at=now,
            )
            # Nobody is signed in to apply: the applicant is the actor, and
            # they have no account yet.
            audit.created("schools", request)

            return

        changed = [field for field in cls.FIELDS if field in data and getattr(existing, field) != data[field]]

        if changed:
            for field in changed:
                setattr(existing, field, data[field])

            existing.updated_at = now
            existing.save(update_fields=[*changed, "updated_at"])

    @staticmethod
    def visible_to(filters: dict):
        requests = EarlyAccessRequest.objects.select_related("converted_school", "reviewed_by")

        if filters.get("status"):
            requests = requests.filter(status=filters["status"])

        if filters.get("q"):
            like = f"%{filters['q']}%"
            requests = requests.filter(Q(school_name__ilike=like) | Q(contact_name__ilike=like) | Q(email__ilike=like))

        # Newest first: the panel is a queue, and what nobody has looked at
        # yet is what matters.
        return requests.order_by("-id")

    @staticmethod
    def review(request, data: dict, actor: User):
        before = audit.fields_of(request)

        now = timezone.now()

        for field, value in data.items():
            setattr(request, field, value)

        request.reviewed_by_id = actor.id
        request.reviewed_at = now
        request.updated_at = now
        request.save(update_fields=[*data.keys(), "reviewed_by", "reviewed_at", "updated_at"])
        audit.updated("schools", request, before, action="early_access_request.reviewed")

        return EarlyAccessRequest.objects.select_related("converted_school", "reviewed_by").get(pk=request.pk)

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
        audit.record(action="early_access_request.converted", module="schools", entity_type="early_access_request",
                     entity_id=request.pk, school_id=None, new={"converted_school_id": school.id})

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

        school = School.objects.create(
            status=SchoolStatus.ACTIVE, created_at=now, updated_at=now, **data
        )

        audit.created("schools", school)

        return school

    @staticmethod
    def update(school: School, data: dict) -> School:
        before = audit.fields_of(school)

        for field, value in data.items():
            setattr(school, field, value)

        school.updated_at = timezone.now()
        school.save()
        audit.updated("schools", school, before)

        return school

    @classmethod
    def activate(cls, school: School) -> School:
        return cls.set_status(school, SchoolStatus.ACTIVE)

    @classmethod
    def deactivate(cls, school: School) -> School:
        return cls.set_status(school, SchoolStatus.INACTIVE)

    @staticmethod
    def set_status(school: School, status: str) -> School:
        before = audit.fields_of(school)

        school.status = status
        school.updated_at = timezone.now()
        school.save(update_fields=["status", "updated_at"])
        action = "school.activated" if status == SchoolStatus.ACTIVE else "school.deactivated"
        audit.updated("schools", school, before, action=action)

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
        assert_not_too_late(school_id, "attendance", date)

        with transaction.atomic():
            changed = {}
            previous = {}

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
                        previous[attendance.student_id] = was

            # One entry for the register, not one per child: "8 A, 14 Sep,
            # these three changed" is what someone reviewing it needs.
            if changed:
                audit.record(
                    action="attendance.corrected" if previous else "attendance.marked", module="attendance",
                    entity_type="class_section", entity_id=section.id, school_id=school_id,
                    old={"attendance_date": date, "marks": previous} if previous else None,
                    new={"attendance_date": date, "marks": changed},
                )

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
        assert_not_too_late(school_id, "staff_attendance", data["attendance_date"])

        with transaction.atomic():
            before = dict(
                StaffAttendance.objects.filter(
                    staff_profile_id__in=[record["staff_profile_id"] for record in data["records"]],
                    attendance_date=data["attendance_date"],
                ).values_list("staff_profile_id", "status")
            )

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

            changed = {
                record["staff_profile_id"]: record["status"]
                for record in data["records"]
                if before.get(record["staff_profile_id"]) != record["status"]
            }
            if changed:
                corrected = {key: before[key] for key in changed if key in before}
                audit.record(
                    action="staff_attendance.corrected" if corrected else "staff_attendance.marked",
                    module="staff_attendance", entity_type="school", entity_id=school_id, school_id=school_id,
                    old={"attendance_date": data["attendance_date"], "marks": corrected} if corrected else None,
                    new={"attendance_date": data["attendance_date"], "marks": changed},
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
        cls.assert_enough_notice(profile.school_id, data["start_date"])
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
            audit.created("leave", leave, action="staff_leave.applied")

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
        before = audit.fields_of(leave)

        leave.status = status
        leave.reviewed_by_id = actor.id
        leave.review_remarks = remarks
        leave.updated_at = timezone.now()
        leave.save(update_fields=["status", "reviewed_by", "review_remarks", "updated_at"])
        audit.updated("leave", leave, before, action=f"staff_leave.{status}")

    @classmethod
    def fresh(cls, leave):
        """The row again, with every relation the resource reads.

        Re-fetched rather than reusing the instance in hand: the one being
        returned has to carry the names, and an instance built by `create()`
        has none of them cached.
        """
        return StaffLeave.objects.select_related(*cls.WITH).get(pk=leave.pk)

    @staticmethod
    def assert_enough_notice(school_id: int, start_date) -> None:
        """The school's minimum notice (module settings, docs/settings.md):
        leave must start this many days after today, on the school's clock.
        Zero, the default, allows leave from today."""
        notice = modules.setting(school_id, "leave", "min_notice_days")

        if notice and as_date(start_date) < SchoolClock.for_school(school_id).now().date() + dt.timedelta(days=notice):
            raise SettingRefused(
                f"Leave must be applied for at least {notice} day{'s' if notice != 1 else ''} in advance."
            )

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

        # Admins see their whole scope, already applied above.
        if actor.role == UserRole.SUPER_ADMIN or UserRole.administers_school(actor.role):
            return leaves

        # Everybody else - Teacher, Staff, Transport Manager, Accountant, and
        # any role added later - only ever sees their own history. Listed the
        # other way round, a new role would have seen the whole school's leave
        # until somebody remembered to add it.
        profile = actor.staff_profile

        return leaves.filter(staff_profile_id=profile.id if profile else 0)

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
        existing = TimetableEntry.objects.filter(
            class_section_id=data["class_section_id"], period_id=data["period_id"], day_of_week=data["day_of_week"]
        ).first()
        before = audit.fields_of(existing) if existing is not None else None

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

        if before is None:
            audit.created("timetable", entry)
        else:
            audit.updated("timetable", entry, before)

        return TimetableEntry.objects.select_related(*cls.WITH).get(pk=entry.pk)

    @staticmethod
    def delete(entry) -> None:
        audit.deleted("timetable", entry)
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

        # The school's filing window (module settings): 0 means no limit.
        window = modules.setting(entry.school_id, "teaching_reports", "filing_window_days")

        if window and as_date(data["report_date"]) < SchoolClock.for_school(entry.school_id).now().date() - dt.timedelta(days=window):
            raise SettingRefused(
                f"A report can only be filed up to {window} day{'s' if window != 1 else ''} after the period."
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
        audit.created("teaching", report)

        return cls.fresh(report)

    @classmethod
    def review(cls, report, actor: User):
        before = audit.fields_of(report)

        if report.reviewed_by_id is not None:
            raise TeachingReportAlreadyReviewed("This report has already been reviewed.")

        now = timezone.now()
        report.reviewed_by_id = actor.id
        report.reviewed_at = now
        report.updated_at = now
        report.save(update_fields=["reviewed_by", "reviewed_at", "updated_at"])
        audit.updated("teaching", report, before, action="daily_teaching_report.reviewed")

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
        audit.created("syllabus", topic)

        return SyllabusTopic.objects.select_related("subject").get(pk=topic.pk)

    @staticmethod
    def update(topic, data: dict):
        before = audit.fields_of(topic)

        changed = [field for field, value in data.items() if getattr(topic, field) != value]

        # Eloquent saves nothing, timestamp included, when nothing changed;
        # an edit that sends back the same title is not an edit.
        if changed:
            for field in changed:
                setattr(topic, field, data[field])

            topic.updated_at = timezone.now()
            topic.save(update_fields=[*changed, "updated_at"])
            audit.updated("syllabus", topic, before)

        return SyllabusTopic.objects.select_related("subject").get(pk=topic.pk)

    @staticmethod
    def delete(topic) -> None:
        audit.deleted("syllabus", topic)
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
            deleted, _ = SyllabusTopicProgress.objects.filter(
                syllabus_topic_id=topic.id, class_section_id=section.id
            ).delete()

            if deleted:
                audit.record(action="syllabus_topic.unticked", module="syllabus", entity_type="syllabus_topic",
                             entity_id=topic.id, school_id=topic.school_id, old={"class_section_id": section.id})

            return

        now = timezone.now()
        audit.record(action="syllabus_topic.ticked", module="syllabus", entity_type="syllabus_topic",
                     entity_id=topic.id, school_id=topic.school_id, new={"class_section_id": section.id})

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



def php_truthy(value) -> bool:
    """PHP's truthiness for a query-string value: "" and "0" are false,
    every other string is true - "false" included."""
    if isinstance(value, str):
        # Trimmed first, as Laravel's middleware trims every input.
        value = value.strip()

    return value not in (None, "", "0")


class MessageService:
    """Reading and re-driving the message log. Sending lives in
    notifications.py; nothing here writes a message from scratch."""

    @staticmethod
    def scoped(actor: User, filters: dict):
        clock = SchoolClock.for_scope(actor, filters.get("school_id"))
        messages = SchoolScope.for_actor(actor).apply_to(Message.objects.all(), filters.get("school_id"))

        for field in ("category", "channel", "status"):
            if filters.get(field):
                messages = messages.filter(**{field: filters[field]})

        # The dates come off a date picker, so they are days at the school;
        # created_at is a UTC instant. Windows are compared, not dates.
        if filters.get("date_from"):
            messages = messages.filter(created_at__gte=clock.start_of_day_utc(filters["date_from"]))

        if filters.get("date_to"):
            messages = messages.filter(created_at__lt=clock.end_of_day_utc(filters["date_to"]))

        if filters.get("q"):
            like = f"%{filters['q']}%"
            messages = messages.filter(
                Q(recipient_name__ilike=like)
                | Q(student_name__ilike=like)
                | Q(recipient_mobile__ilike=like)
                | Q(body__ilike=like)
            )

        return messages

    @classmethod
    def visible_to(cls, actor: User, filters: dict):
        return (
            cls.scoped(actor, filters)
            .select_related("student", "user", "school")
            .order_by("-created_at", "-id")
        )

    @classmethod
    def summary(cls, actor: User, filters: dict) -> dict:
        """The KPI tiles: today's volume, what landed, what failed, and what
        never left the building - all counted on the school's day."""
        start, end = SchoolClock.for_scope(actor, filters.get("school_id")).today_range()

        school_id = SchoolScope.for_actor(actor).writable_school_id(filters.get("school_id"))
        provider = CommunicationSetting.objects.filter(school_id=school_id).values_list("provider", flat=True).first()

        today = cls.scoped(actor, filters).filter(created_at__gte=start, created_at__lt=end)

        sent = today.filter(status=MessageStatus.SENT).count()
        failed = today.filter(status=MessageStatus.FAILED).count()
        attempted = sent + failed

        return {
            "sent_today": sent,
            # "SMS Sent Today" on the tile, so the in-app copies beside them
            # do not count.
            "sms_sent_today": today.filter(status=MessageStatus.SENT, channel=MessageChannel.SMS).count(),
            "queued_today": today.filter(status=MessageStatus.QUEUED).count(),
            "failed_today": failed,
            "skipped_today": today.filter(status=MessageStatus.SKIPPED).count(),
            "delivery_rate": None if attempted == 0 else php_number(php_round_1(sent / attempted * 100)),
            "total": cls.scoped(actor, filters).count(),
            # What actually carries these messages. Until a real provider is
            # set up it is a gateway that delivers nothing, and the screen has
            # to say so next to the word "Sent".
            "provider_label": sms.label(provider),
            "provider_delivers": sms.delivers(provider),
        }

    @staticmethod
    def retry(message):
        """Back on the queue. The body is not rebuilt: the log must keep
        showing what was actually sent."""
        message.status = MessageStatus.QUEUED
        message.failure_reason = None
        message.updated_at = timezone.now()
        message.save(update_fields=["status", "failure_reason", "updated_at"])

        queue.push(notifications.SEND_MESSAGE, {"message_id": message.id})

        return Message.objects.get(pk=message.pk)

    @staticmethod
    def inbox_of(actor: User):
        """The in-app channel only. A leave decision also goes out by SMS, and
        that copy belongs in the log, not the reader's inbox. An announcement
        that was deleted or has expired drops out of the feed; its messages
        stay in the log either way."""
        today = SchoolClock.for_user(actor).date()

        return Message.objects.filter(
            Q(announcement_id__isnull=True)
            | Q(
                announcement__deleted_at__isnull=True,
                announcement__isnull=False,
            )
            & (Q(announcement__expires_at__isnull=True) | Q(announcement__expires_at__gte=today)),
            user_id=actor.id,
            channel=MessageChannel.IN_APP,
            status__in=(MessageStatus.SENT, MessageStatus.QUEUED),
        )

    @classmethod
    def inbox(cls, actor: User, unread):
        messages = cls.inbox_of(actor).select_related("school")

        if php_truthy(unread):
            messages = messages.filter(read_at__isnull=True)

        return messages.order_by("-created_at", "-id")

    @classmethod
    def unread_count(cls, actor: User) -> int:
        return cls.inbox_of(actor).filter(read_at__isnull=True).count()

    @staticmethod
    def mark_read(message):
        if message.read_at is None:
            now = timezone.now()
            message.read_at = now
            message.updated_at = now
            message.save(update_fields=["read_at", "updated_at"])

        return Message.objects.get(pk=message.pk)

    @classmethod
    def mark_all_read(cls, actor: User) -> int:
        now = timezone.now()

        return cls.inbox_of(actor).filter(read_at__isnull=True).update(read_at=now, updated_at=now)


class MessageTemplateService:
    """The wording of every automatic message. A school only has a row for an
    event it rewords, so the defaults on MessageEvent stay the source of truth
    for everybody else."""

    @staticmethod
    def list_for(school_id: int) -> list[dict]:
        overrides = {
            row.event: row
            for row in MessageTemplate.objects.select_related("updated_by").filter(school_id=school_id)
        }

        rows = []
        whatsapp_rows = WhatsappTemplateService.by_event(school_id)

        for event in MessageEvent.values:
            override = overrides.get(event)
            custom = override is not None and override.is_active

            rows.append(
                {
                    "event": event,
                    "body": override.body if custom else MessageEvent.default_body(event),
                    "default_body": MessageEvent.default_body(event),
                    "is_custom": custom,
                    "whatsapp": whatsapp_rows.get(event),
                    "updated_at": override.updated_at if override else None,
                    "updated_by_name": (
                        override.updated_by.name if override and override.updated_by_id else None
                    ),
                }
            )

        return rows

    @classmethod
    def row_for(cls, school_id: int, event: str) -> dict:
        return next(row for row in cls.list_for(school_id) if row["event"] == event)

    @staticmethod
    def update(school_id: int, event: str, body: str, actor: User) -> None:
        existing = MessageTemplate.objects.filter(school_id=school_id, event=event).first()
        now = timezone.now()

        if existing is None:
            template = MessageTemplate.objects.create(
                school_id=school_id, event=event, body=body, is_active=True,
                updated_by_id=actor.id, created_at=now, updated_at=now,
            )
            audit.created("communication", template)

            return

        # Eloquent writes nothing, updated_at included, when nothing changed.
        if (existing.body, existing.is_active, existing.updated_by_id) != (body, True, actor.id):
            before = audit.fields_of(existing)
            existing.body = body
            existing.is_active = True
            existing.updated_by_id = actor.id
            existing.updated_at = now
            existing.save(update_fields=["body", "is_active", "updated_by", "updated_at"])
            audit.updated("communication", existing, before)

    @staticmethod
    def reset(school_id: int, event: str) -> None:
        """Drops the override, so the event falls back to its shipped wording."""
        for template in MessageTemplate.objects.filter(school_id=school_id, event=event):
            audit.deleted("communication", template)
            template.delete()


class CommunicationSettingService:
    SWITCHES = (
        "sms_enabled", "attendance_alerts", "transport_alerts_enabled", "leave_alerts_enabled", "provider",
        "whatsapp_enabled", "whatsapp_provider", "email_enabled",
    )

    @classmethod
    def update(cls, school_id: int, data: dict):
        setting = notifications.settings_for(school_id)
        values = {field: data[field] for field in cls.SWITCHES if field in data}

        # Absent leaves the sender alone; an explicit null clears it.
        if "sender_id" in data:
            values["sender_id"] = data["sender_id"]

        # Credentials merge: a field that is sent replaces the stored one, an
        # empty one clears it, and a field left out is kept - so the screen
        # never has to send a secret back to keep it.
        if data.get("credentials") is not None:
            current = crypto.decrypt_json(setting.credentials)
            merged = cls.merged_credentials(current, data["credentials"])

            if merged != current:
                values["credentials"] = crypto.encrypt_json(merged) if merged else None

        changed = [field for field, value in values.items() if getattr(setting, field) != value]
        now = timezone.now()
        before = audit.fields_of(setting)

        for field in changed:
            setattr(setting, field, values[field])

        if setting.pk is None:
            setting.school_id = school_id
            setting.created_at = now
            setting.updated_at = now
            setting.save()
        elif changed:
            setting.updated_at = now
            setting.save(update_fields=[*changed, "updated_at"])

        audit.updated("communication", setting, before)

        return CommunicationSetting.objects.get(pk=setting.pk)

    @staticmethod
    def merged_credentials(current: dict, submitted: dict) -> dict:
        merged = {provider: dict(fields) for provider, fields in current.items()}

        for provider, fields in submitted.items():
            account = merged.setdefault(provider, {})

            for key, value in fields.items():
                if value in (None, ""):
                    account.pop(key, None)
                else:
                    account[key] = value

            if not account:
                merged.pop(provider)

        return merged

    @staticmethod
    def test(school_id: int, channel: str, to: str):
        """One message through the school's own provider, now, so an
        administrator learns whether the account works before a parent does.
        A WhatsApp test needs the "Message" event's template mapped, since
        WhatsApp carries nothing else."""
        setting = notifications.settings_for(school_id)
        school = School.objects.get(pk=school_id)
        body = f"This is a test message from {school.name}. Your messaging settings work."

        if channel == MessageChannel.SMS:
            provider = sms.resolve(setting.provider)

            return sms.gateway(provider).send(
                to, body, setting.sender_id, notifications.credentials_of(setting, provider)
            )

        tokens = {"recipient_name": "Test", "subject": "Test message", "body": body, "school_name": school.name}
        payload = notifications.whatsapp_payload(school_id, MessageEvent.GENERAL_MESSAGE, tokens)

        if payload is None:
            raise GatewayTestFailed('Map a WhatsApp template to the "Message" event first, then test again.')

        provider = whatsapp.resolve(setting.whatsapp_provider)

        return whatsapp.gateway(provider).send_template(
            to,
            Template(name=payload["template"], language=payload["language"], values=payload["values"]),
            notifications.credentials_of(setting, provider),
        )


class WhatsappTemplateService:
    """Which registered WhatsApp template carries each event for a school.
    A row exists only for an event the school has mapped; the rest are
    skipped on the WhatsApp channel, with that as the reason."""

    @staticmethod
    def by_event(school_id: int) -> dict:
        return {row.event: row for row in WhatsappTemplate.objects.filter(school_id=school_id)}

    @staticmethod
    def set(school_id: int, event: str, data: dict, actor: User):
        now = timezone.now()
        values = {
            "template_name": data["template_name"],
            "language": data.get("language") or "en",
            "parameters": ",".join(data.get("parameters") or []) or None,
        }
        existing = WhatsappTemplate.objects.filter(school_id=school_id, event=event).first()

        if existing is None:
            row = WhatsappTemplate.objects.create(
                school_id=school_id, event=event, updated_by_id=actor.id, created_at=now, updated_at=now, **values
            )
            audit.created("communication", row)

            return row

        before = audit.fields_of(existing)

        for field, value in values.items():
            setattr(existing, field, value)

        existing.updated_by_id = actor.id
        existing.updated_at = now
        existing.save()
        audit.updated("communication", existing, before)

        return existing

    @staticmethod
    def clear(school_id: int, event: str) -> None:
        for row in WhatsappTemplate.objects.filter(school_id=school_id, event=event):
            audit.deleted("communication", row)
            row.delete()


class MailSettingService:
    """The platform's SMTP server (docs/communication.md). One row, Super
    Admin only, password encrypted and never returned."""

    FIELDS = ("is_active", "host", "port", "encryption", "username", "from_address", "from_name")

    @staticmethod
    def current():
        return mailer.stored()

    @classmethod
    def save(cls, data: dict, actor: User):
        row = mailer.stored()
        now = timezone.now()
        creating = row is None

        if creating:
            row = MailSetting(created_at=now)

        before = audit.fields_of(row)

        for field in cls.FIELDS:
            if field in data:
                setattr(row, field, data[field])

        # Absent keeps the password; blank or null clears it.
        if "password" in data:
            row.password = crypto.encrypt(data["password"]) if data["password"] else None

        row.updated_by_id = actor.id
        row.updated_at = now
        row.save()

        if creating:
            audit.created("mail", row)
        else:
            audit.updated("mail", row, before)

        return MailSetting.objects.get(pk=row.pk)

    @staticmethod
    def test(row, to: str, actor: User) -> None:
        """Sends the test and keeps the outcome on the row, whichever way it
        went - the screen shows the last result beside the settings."""
        try:
            mailer.send_test(row, to)
        finally:
            row.updated_at = timezone.now()
            row.save(update_fields=["last_tested_at", "last_test_error", "updated_at"])
            audit.record(
                action="mail_setting.tested", module="mail", entity_type="mail_setting", entity_id=row.id,
                school_id=None, new={"to": to, "error": row.last_test_error},
            )


class NoticeService:
    """A message somebody wrote in the Communication Center: to one person,
    a class, a department, everybody. There is no row for a notice - only the
    messages it becomes, which is what the log shows and what the audit
    trail records the sending of."""

    @staticmethod
    def preview(school_id: int, data: dict) -> dict:
        setting = notifications.settings_for(school_id)
        audience = data["audience_type"]
        target = data.get("audience_id")

        counts = notices.count(school_id, audience, target, data.get("recipients"), data["channels"], setting)
        counts["audience_label"] = notices.audience_label(school_id, audience, target)

        return counts

    @classmethod
    def send(cls, data: dict, actor: User) -> dict:
        school_id = data["school_id"]
        audience = data["audience_type"]
        counts = cls.preview(school_id, data)

        if counts["recipients"] == 0:
            raise UnreachableAudience("Nobody in this audience can be reached on the channels chosen.")

        payload = {
            "school_id": school_id,
            "kind": data["kind"],
            "audience_type": audience,
            "audience_id": data.get("audience_id"),
            "audience_label": counts["audience_label"],
            "recipients": NoticeRecipients.for_audience(audience, data.get("recipients")),
            "channels": counts["channels"],
            "subject": data.get("subject"),
            "body": data.get("body"),
            "amount": None if data.get("amount") is None else str(data["amount"]),
            "due_date": None if data.get("due_date") is None else data["due_date"].isoformat(),
            "actor_id": actor.id,
        }

        audit.record(
            action="notice.sent", module="communication", entity_type="notice", entity_id=None,
            school_id=school_id, new={**payload, "recipients_count": counts["recipients"]},
        )

        # One person is told now; a group is handed to the queue, so a
        # whole-school emergency does not hold the request open.
        if NoticeAudience.is_individual(audience):
            return {**counts, "queued": False, "messages": cls.fan_out(payload)}

        queue.push(jobs.SEND_NOTICE, payload)

        return {**counts, "queued": True, "messages": []}

    @classmethod
    def fan_out(cls, payload: dict) -> list:
        """Turns the audience into messages, through the same pipeline every
        automatic alert uses. Runs in the request for one person and on the
        queue for a group."""
        school = School.objects.filter(pk=payload["school_id"]).first()

        if school is None:
            return []

        event = NoticeKind.event(payload["kind"])
        actor = User.objects.filter(pk=payload.get("actor_id")).first() if payload.get("actor_id") else None
        audience = payload["audience_type"]
        target = payload.get("audience_id")
        channels = payload["channels"]
        external = [channel for channel in channels if channel != MessageChannel.IN_APP]
        subject = cls.subject_of(payload)
        tokens = cls.tokens_of(payload, school)
        sent = []

        students = notices.students_for(school.id, audience, target)

        if external and NoticeRecipients.includes_guardians(payload["recipients"]):
            for student in AnnouncementService.chunked(students):
                sent += notifications.notify_guardian(event, student, tokens, actor, channels=external, subject=subject)

        if external and NoticeRecipients.includes_students(payload["recipients"]):
            for student in AnnouncementService.chunked(students):
                sent += notifications.notify_student(event, student, tokens, actor, channels=external, subject=subject)

        users = notices.users_for(school.id, audience, target).select_related("school")

        for user in AnnouncementService.chunked(users):
            sent += notifications.notify_staff(event, user, tokens, actor, channels=channels, subject=subject)

        return sent

    @staticmethod
    def subject_of(payload: dict) -> str:
        if payload["kind"] == NoticeKind.FEE_REMINDER:
            return "Fee reminder"

        if payload["kind"] == NoticeKind.EMERGENCY:
            return payload.get("subject") or "Emergency alert"

        return payload.get("subject") or "Message"

    @staticmethod
    def tokens_of(payload: dict, school) -> dict:
        tokens = {"subject": payload.get("subject"), "body": payload.get("body")}

        if payload.get("amount") is not None:
            tokens["amount"] = money.formatted(Decimal(payload["amount"]), school.currency_code)

        if payload.get("due_date"):
            tokens["due_date"] = dt.date.fromisoformat(payload["due_date"]).strftime("%m/%d/%Y")

        return tokens



def php_filter_bool(value) -> bool:
    """PHP's filter_var(..., FILTER_VALIDATE_BOOLEAN): "1", "true", "on" and
    "yes", in any case, are true; everything else is false."""
    return str(value).strip().lower() in ("1", "true", "on", "yes") if value is not None else False


class AnnouncementService:
    """Publishing a notice to part of a school. The audience is counted here;
    turning it into messages runs on the queue, so a whole-school notice does
    not hold up the request."""

    CHUNK = 200

    @staticmethod
    def visible_to(actor: User, filters: dict):
        announcements = SchoolScope.for_actor(actor).apply_to(
            Announcement.objects.select_related("school", "published_by").filter(deleted_at__isnull=True),
            filters.get("school_id"),
        )

        # A head of department manages their own department's notices and
        # nothing else, so the list must not show them the rest.
        if actor.role == UserRole.HOD:
            announcements = announcements.filter(
                audience_type=AnnouncementAudience.DEPARTMENT,
                audience_id__in=Department.objects.filter(
                    school_id=actor.school_id, hod_user_id=actor.id
                ).values("id"),
            )

        if filters.get("audience_type"):
            announcements = announcements.filter(audience_type=filters["audience_type"])

        if filters.get("q"):
            like = f"%{filters['q']}%"
            announcements = announcements.filter(Q(title__ilike=like) | Q(body__ilike=like))

        # "Still showing" means at the school: an expiry is a day on its
        # calendar, not the server's.
        if php_filter_bool(filters.get("active_only")):
            raw = filters.get("school_id")
            today = SchoolClock.for_scope(actor, None if raw in (None, "") else php_int(raw)).date()
            announcements = announcements.filter(Q(expires_at__isnull=True) | Q(expires_at__gte=today))

        return announcements.order_by("-published_at", "-id")

    @classmethod
    def publish(cls, data: dict, actor: User):
        school_id = data["school_id"]
        audience = data["audience_type"]
        channels = data["channels"]
        target = data.get("audience_id") if AnnouncementAudience.needs_target(audience) else None

        counts = cls.count_recipients(school_id, audience, target, channels)

        if counts["recipients"] == 0:
            raise UnreachableAudience(cls.unreachable_reason(audience, channels))

        now = timezone.now()

        with transaction.atomic():
            announcement = Announcement.objects.create(
                school_id=school_id,
                title=data["title"],
                body=data["body"],
                audience_type=audience,
                audience_id=target,
                audience_label=cls.audience_label(school_id, audience, target),
                channels=channels,
                expires_at=data.get("expires_at"),
                published_by_id=actor.id,
                published_at=now,
                recipients_count=counts["recipients"],
                sms_count=counts["sms"],
                in_app_count=counts["in_app"],
                created_at=now,
                updated_at=now,
            )
            audit.created("announcements", announcement, action="announcement.published")

            # In the same transaction: the fan-out is queued if and only if
            # the announcement it is for was committed.
            queue.push(PUBLISH_ANNOUNCEMENT, {"announcement_id": announcement.id, "actor_id": actor.id})

        return Announcement.objects.select_related("school", "published_by").get(pk=announcement.pk)

    @classmethod
    def fan_out(cls, announcement, actor) -> None:
        """Turns the audience into messages, a chunk at a time."""
        tokens = {
            "title": announcement.title,
            "body": announcement.body,
            "school_name": announcement.school.name if announcement.school_id else None,
            "audience": announcement.audience_label,
        }
        audience = announcement.audience_type

        channels = AnnouncementChannels.message_channels(announcement.channels)
        external = [channel for channel in channels if channel != MessageChannel.IN_APP]

        if external and AnnouncementAudience.reaches_guardians(audience):
            # No address filter here on purpose: a guardian with no number still
            # gets a "skipped" row, so an admin can see who was missed.
            students = cls.students(announcement.school_id, audience, announcement.audience_id)

            for student in cls.chunked(students):
                notifications.notify_guardian(
                    MessageEvent.ANNOUNCEMENT_PUBLISHED, student, tokens, actor,
                    channels=external, announcement=announcement,
                )

        if AnnouncementAudience.reaches_staff(audience):
            users = cls.users(announcement.school_id, audience, announcement.audience_id).select_related("school")

            for user in cls.chunked(users):
                notifications.notify_staff(
                    MessageEvent.ANNOUNCEMENT_PUBLISHED, user, tokens, actor,
                    channels=channels, announcement=announcement,
                )

    @classmethod
    def chunked(cls, rows):
        """Laravel's chunkById: by id, a page at a time, so a school with a
        thousand students is never one huge read."""
        last = 0

        while True:
            page = list(rows.filter(pk__gt=last).order_by("pk")[: cls.CHUNK])

            if not page:
                return

            yield from page
            last = page[-1].pk

    @staticmethod
    def delete(announcement) -> None:
        """Out of the in-app feed. Messages already sent stay in the log."""
        before = audit.fields_of(announcement)

        now = timezone.now()
        announcement.deleted_at = now
        announcement.updated_at = now
        announcement.save(update_fields=["deleted_at", "updated_at"])
        audit.updated("announcements", announcement, before, action="announcement.deleted")

    @classmethod
    def count_recipients(cls, school_id: int, audience: str, target, channels: str) -> dict:
        """Who the notice reaches and how many copies each channel carries.
        A guardian counts once when any chosen external channel has an
        address for them; staff always have an inbox and an email address."""
        by_mobile = AnnouncementChannels.includes_sms(channels) or AnnouncementChannels.includes(
            channels, MessageChannel.WHATSAPP
        )
        by_email = AnnouncementChannels.includes(channels, MessageChannel.EMAIL)
        with_mobile = with_email = guardians = staff = 0

        if AnnouncementChannels.reaches_guardians(channels) and AnnouncementAudience.reaches_guardians(audience):
            students = cls.students(school_id, audience, target)
            reachable = Q(pk__in=[])

            if by_mobile:
                with_mobile = students.filter(guardian_mobile__isnull=False).count()
                reachable |= Q(guardian_mobile__isnull=False)

            if by_email:
                with_email = students.filter(guardian_email__isnull=False).count()
                reachable |= Q(guardian_email__isnull=False)

            guardians = students.filter(reachable).count()

        if AnnouncementAudience.reaches_staff(audience):
            staff = cls.users(school_id, audience, target).count()

        def copies(channel: str, guardian_copies: int) -> int:
            return guardian_copies + staff if AnnouncementChannels.includes(channels, channel) else 0

        return {
            "recipients": guardians + staff,
            "sms": copies(MessageChannel.SMS, with_mobile),
            "in_app": staff if AnnouncementChannels.includes_in_app(channels) else 0,
            "whatsapp": copies(MessageChannel.WHATSAPP, with_mobile),
            "email": copies(MessageChannel.EMAIL, with_email),
        }

    @staticmethod
    def audience_label(school_id: int, audience: str, target) -> str:
        """The name a class or department target goes by - looked up inside
        this school only. A target that is not this school's gets the same
        generic label as one that does not exist, so a preview cannot be used
        to read another school's class and department names."""
        if audience == AnnouncementAudience.CLASS_SECTION:
            section = (
                ClassSection.objects.select_related("school_class")
                .filter(pk=target, school_class__school_id=school_id)
                .first()
            )

            return "Class" if section is None else f"{section.school_class.name} {section.name}".strip()

        if audience == AnnouncementAudience.DEPARTMENT:
            department = Department.objects.filter(pk=target, school_id=school_id).first()

            return "Department" if department is None else department.name

        return AnnouncementAudience(audience).label

    @staticmethod
    def students(school_id: int, audience: str, target):
        students = Student.objects.filter(school_id=school_id, status=StudentStatus.ACTIVE)

        if audience == AnnouncementAudience.CLASS_SECTION:
            students = students.filter(class_section_id=target)

        return students

    @staticmethod
    def users(school_id: int, audience: str, target):
        """Active accounts of this school only - never the platform's Super
        Admins, who belong to none."""
        users = User.objects.filter(school_id=school_id, status=UserStatus.ACTIVE)

        if audience == AnnouncementAudience.TEACHERS:
            users = users.filter(role__in=(UserRole.TEACHER, UserRole.HOD))

        if audience == AnnouncementAudience.DEPARTMENT:
            users = users.filter(staffprofile__department_id=target)

        return users

    @staticmethod
    def unreachable_reason(audience: str, channels: str) -> str:
        if not AnnouncementChannels.reaches_guardians(channels) and not AnnouncementAudience.reaches_staff(audience):
            return "Guardians have no app login, so this audience can only be reached by SMS, WhatsApp or email."

        return "Nobody in this audience can be reached right now."


PUBLISH_ANNOUNCEMENT = "publish_announcement"



class FleetService:
    """Vehicles and drivers: the same list, create, update and delete rules
    over two tables. A record still on a route, or with trip history, is not
    deleted - it is taken off the route, or deactivated."""

    model = None
    in_use = ""
    has_history = ""

    @classmethod
    def visible_to(cls, actor: User, filters: dict):
        records = SchoolScope.for_actor(actor).apply_to(
            cls.model.objects.select_related("school"), filters.get("school_id")
        )

        if filters.get("status"):
            records = records.filter(status=filters["status"])

        # A name is unique within a school at most, and a Super Admin's list
        # spans every school - the id keeps paging honest.
        return records.order_by("name", "id")

    @classmethod
    def route_of(cls, record):
        return TransportRoute.objects.filter(**{cls.foreign_key: record.pk}).first()

    @classmethod
    def routes_of(cls, records) -> dict:
        """One query for a whole page's routes."""
        return {
            getattr(route, cls.foreign_key): route
            for route in TransportRoute.objects.filter(**{f"{cls.foreign_key}__in": [r.pk for r in records]})
        }

    @classmethod
    def create(cls, data: dict):
        now = timezone.now()
        record = cls.model.objects.create(**data, status=TransportStatus.ACTIVE, created_at=now, updated_at=now)
        audit.created("transport", record)

        return cls.model.objects.select_related("school").get(pk=record.pk)

    @classmethod
    def update(cls, record, data: dict):
        before = audit.fields_of(record)

        changed = [field for field, value in data.items() if getattr(record, field) != value]

        if changed:
            for field in changed:
                setattr(record, field, data[field])

            record.updated_at = timezone.now()
            record.save(update_fields=[*changed, "updated_at"])
            audit.updated("transport", record, before)

        return cls.model.objects.select_related("school").get(pk=record.pk)

    @classmethod
    def delete(cls, record) -> None:
        if TransportRoute.objects.filter(**{cls.foreign_key: record.pk}).exists():
            raise HasDependentRecords(cls.in_use)

        if TransportTrip.objects.filter(**{cls.foreign_key: record.pk}).exists():
            raise HasDependentRecords(cls.has_history)

        audit.deleted("transport", record)
        record.delete()


class VehicleService(FleetService):
    model = Vehicle
    foreign_key = "vehicle_id"
    in_use = "This vehicle is still serving a route. Remove it from the route first."
    has_history = "This vehicle has trip history and cannot be deleted. Deactivate it instead."


class DriverService(FleetService):
    model = Driver
    foreign_key = "driver_id"
    in_use = "This driver is still assigned to a route. Remove them from the route first."
    has_history = "This driver has trip history and cannot be deleted. Deactivate them instead."


class TransportRouteService:
    @staticmethod
    def with_counts(routes):
        return routes.select_related("school", "vehicle", "driver").annotate(
            stops_count=Count("transportstop", distinct=True),
            students_count=Count("studenttransportassignment", distinct=True),
        )

    @classmethod
    def visible_to(cls, actor: User, filters: dict):
        routes = SchoolScope.for_actor(actor).apply_to(TransportRoute.objects.all(), filters.get("school_id"))

        if filters.get("status"):
            routes = routes.filter(status=filters["status"])

        return cls.with_counts(routes).order_by("name", "id")

    @classmethod
    def detail(cls, route_id: int):
        route = cls.with_counts(TransportRoute.objects.filter(pk=route_id)).get()
        stops = list(cls.stops_of(route.pk))

        return route, stops

    @staticmethod
    def stops_of(route_id: int):
        return (
            TransportStop.objects.filter(route_id=route_id)
            .annotate(students_count=Count("studenttransportassignment"))
            .order_by("sequence_number")
        )

    @staticmethod
    def create(data: dict):
        now = timezone.now()

        route = TransportRoute.objects.create(**data, status=TransportStatus.ACTIVE, created_at=now, updated_at=now)

        audit.created("transport", route)

        return route

    @staticmethod
    def update(route, data: dict):
        before = audit.fields_of(route)

        changed = [field for field, value in data.items() if getattr(route, field) != value]

        if changed:
            for field in changed:
                setattr(route, field, data[field])

            route.updated_at = timezone.now()
            route.save(update_fields=[*changed, "updated_at"])
            audit.updated("transport", route, before)

        return route

    @staticmethod
    def delete(route) -> None:
        if StudentTransportAssignment.objects.filter(route_id=route.pk).exists():
            raise HasDependentRecords("Students are still assigned to this route. Move them to another route first.")

        if TransportTrip.objects.filter(route_id=route.pk).exists():
            raise HasDependentRecords("This route has trip history and cannot be deleted. Deactivate it instead.")

        # Its stops go with it. The real schema cascades this on its own; it
        # is spelled out anyway, in one transaction, because the test database
        # is built from the models and has no ON DELETE CASCADE to lean on -
        # a delete that only worked against production is not a tested one.
        with transaction.atomic():
            TransportStop.objects.filter(route_id=route.pk).delete()
            audit.deleted("transport", route)
            route.delete()

    @classmethod
    def add_stop(cls, route, data: dict):
        now = timezone.now()
        stop = TransportStop.objects.create(
            **data, route_id=route.pk, school_id=route.school_id, created_at=now, updated_at=now
        )
        audit.created("transport", stop)

        return cls.stops_of(route.pk).get(pk=stop.pk)

    @classmethod
    def update_stop(cls, stop, data: dict):
        before = audit.fields_of(stop)

        changed = [field for field, value in data.items() if cls.stored(stop, field) != value]

        if changed:
            for field in changed:
                setattr(stop, field, data[field])

            stop.updated_at = timezone.now()
            stop.save(update_fields=[*changed, "updated_at"])
            audit.updated("transport", stop, before)

        return cls.stops_of(stop.route_id).get(pk=stop.pk)

    @staticmethod
    def stored(stop, field):
        """A stop's value as a form would send it, so "07:30" matches 07:30."""
        value = getattr(stop, field)

        return value.strftime("%H:%M") if field in ("pickup_time", "drop_time") and value else value

    @staticmethod
    def delete_stop(stop) -> None:
        if StudentTransportAssignment.objects.filter(transport_stop_id=stop.pk).exists():
            raise HasDependentRecords("Students are still assigned to this stop. Move them to another stop first.")

        # A stop that trips have used can still go: riders and timeline events
        # keep its name, and lose only the link. The real schema nulls those
        # links itself (ON DELETE SET NULL); it is done here as well, in one
        # transaction, because the test database has no such rule and a delete
        # that only works in production is not a tested one.
        with transaction.atomic():
            TransportTrip.objects.filter(current_stop_id=stop.pk).update(current_stop=None)
            TransportTripRider.objects.filter(stop_id=stop.pk).update(stop=None)
            TransportTripEvent.objects.filter(stop_id=stop.pk).update(stop=None)
            audit.deleted("transport", stop)
            stop.delete()


class StudentTransportService:
    @staticmethod
    def assign(student, route, stop) -> None:
        with transaction.atomic():
            vehicle = route.vehicle if route.vehicle_id else None

            # The student being moved is not counted against the seats: moving
            # them between the route's own stops always works.
            if vehicle is not None:
                others = StudentTransportAssignment.objects.filter(route_id=route.pk).exclude(student_id=student.pk).count()

                if others >= vehicle.capacity:
                    label = f"{vehicle.name} - {route.name}"
                    raise RouteCapacityFull(f"{label} is full - its vehicle seats {vehicle.capacity} students.")

            now = timezone.now()
            existing = StudentTransportAssignment.objects.filter(student_id=student.pk).first()
            before = audit.fields_of(existing) if existing is not None else None

            assignment, _ = StudentTransportAssignment.objects.update_or_create(
                student_id=student.pk,
                defaults={"school_id": student.school_id, "route_id": route.pk, "transport_stop_id": stop.pk, "updated_at": now},
                create_defaults={
                    "school_id": student.school_id, "route_id": route.pk, "transport_stop_id": stop.pk,
                    "created_at": now, "updated_at": now,
                },
            )

            if before is None:
                audit.created("transport", assignment)
            else:
                audit.updated("transport", assignment, before)

    @staticmethod
    def unassign(student) -> None:
        assignment = StudentTransportAssignment.objects.filter(student_id=student.pk).first()

        if assignment is not None:
            audit.deleted("transport", assignment)
            assignment.delete()

    @staticmethod
    def students_on(route):
        return (
            StudentTransportAssignment.objects.filter(route_id=route.pk)
            .select_related("student__class_section__school_class", "transport_stop")
            # Two children called Aarav at the same stop are not unusual.
            .order_by("transport_stop__sequence_number", "student__first_name", "id")
        )



class TransportTripService:
    """Running a bus trip: start it, reach its stops, board and drop its
    riders, end or cancel it.

    Each step that changes state is re-checked under a row lock, because the
    person running it is tapping a phone on a moving bus: two taps on "Start",
    or a board racing an end, must not both get through.
    """

    LIST = ("route", "vehicle", "driver", "current_stop", "school")

    @classmethod
    def visible_to(cls, actor: User, filters: dict):
        trips = SchoolScope.for_actor(actor).apply_to(
            TransportTrip.objects.select_related(*cls.LIST).annotate(riders_count=Count("transporttriprider")),
            filters.get("school_id"),
        )

        for field, column in (("route_id", "route_id"), ("date", "trip_date"), ("status", "status")):
            if filters.get(field):
                trips = trips.filter(**{column: filters[field]})

        # Stored to the second, and a school's buses leave together.
        return trips.order_by("-trip_date", "-started_at", "-id")

    @staticmethod
    def detail(trip_id: int) -> dict:
        trip = TransportTrip.objects.select_related(
            "route", "vehicle", "driver", "current_stop", "started_by", "school"
        ).get(pk=trip_id)

        return {
            "trip": trip,
            "riders": list(
                TransportTripRider.objects.filter(trip_id=trip.pk)
                .select_related("student__class_section__school_class")
                .order_by("stop_sequence_number", "id")
            ),
            "events": list(
                TransportTripEvent.objects.filter(trip_id=trip.pk).select_related("recorded_by").order_by("recorded_at", "id")
            ),
            "stops": list(TransportStop.objects.filter(route_id=trip.route_id).order_by("sequence_number")),
        }

    @classmethod
    def start(cls, route, direction: str, actor: User) -> int:
        # "Today" is the school's date. A 7am pickup in Kolkata happens on the
        # previous UTC day.
        today = SchoolClock.for_school(route.school_id).now().date()
        vehicle = route.vehicle if route.vehicle_id else None
        driver = route.driver if route.driver_id else None

        if (
            route.status != TransportStatus.ACTIVE
            or vehicle is None or driver is None
            or vehicle.status != TransportStatus.ACTIVE or driver.status != TransportStatus.ACTIVE
        ):
            raise TripRule.route_not_ready(route.name)

        if not HolidayService.is_working_day(route.school_id, today):
            raise TripRule.non_working_day()

        cls.assert_route_is_free(route, direction, today)

        with transaction.atomic():
            # Two taps on "Start Trip" must not both get past the checks.
            TransportRoute.objects.select_for_update().filter(pk=route.pk).first()
            cls.assert_route_is_free(route, direction, today)

            now = timezone.now()
            trip = TransportTrip.objects.create(
                school_id=route.school_id, route_id=route.pk, vehicle_id=route.vehicle_id, driver_id=route.driver_id,
                trip_date=today, direction=direction, status=TripStatus.IN_PROGRESS,
                started_by_id=actor.id, started_at=now, created_at=now, updated_at=now,
            )
            audit.created("transport", trip, action="transport_trip.started")

            riders = [
                assignment
                for assignment in StudentTransportAssignment.objects.filter(route_id=route.pk)
                .select_related("student", "transport_stop")
                # In a fixed order, so riders' ids follow the assignments.
                .order_by("id")
                if assignment.student.status == StudentStatus.ACTIVE
            ]

            for assignment in riders:
                TransportTripRider.objects.create(
                    trip_id=trip.pk, student_id=assignment.student_id, stop_id=assignment.transport_stop_id,
                    stop_name=assignment.transport_stop.name, stop_sequence_number=assignment.transport_stop.sequence_number,
                    status=TripRiderStatus.PENDING, created_at=now, updated_at=now,
                )

            cls.record(trip, TripEventType.STARTED, actor, note=f"Trip started with {len(riders)} students expected")

        return trip.pk

    @staticmethod
    def assert_route_is_free(route, direction: str, today) -> None:
        if TransportTrip.objects.filter(route_id=route.pk, status=TripStatus.IN_PROGRESS).exists():
            raise TripRule.already_in_progress(route.name)

        already = (
            TransportTrip.objects.filter(route_id=route.pk, trip_date=today, direction=direction)
            .exclude(status=TripStatus.CANCELLED)
            .exists()
        )

        if already:
            raise TripRule.already_exists(route.name, direction)

    @staticmethod
    def locked(trip):
        return TransportTrip.objects.select_for_update().get(pk=trip.pk)

    @staticmethod
    def assert_in_progress(trip) -> None:
        if trip.status != TripStatus.IN_PROGRESS:
            raise TripRule.not_in_progress()

    @classmethod
    def reach_stop(cls, trip, stop, actor: User) -> None:
        cls.assert_in_progress(trip)

        with transaction.atomic():
            cls.assert_in_progress(cls.locked(trip))

            trip.current_stop_id = stop.pk
            trip.updated_at = timezone.now()
            trip.save(update_fields=["current_stop", "updated_at"])

            cls.record(trip, TripEventType.STOP_REACHED, actor, stop=stop)

    @classmethod
    def update_rider(cls, trip, student, status: str, actor: User) -> None:
        cls.assert_in_progress(trip)

        rider = TransportTripRider.objects.get(trip_id=trip.pk, student_id=student.pk)

        if not TripRiderStatus.can_become(rider.status, status):
            raise TripRule.invalid_rider_change(rider.status, status)

        with transaction.atomic():
            cls.assert_in_progress(cls.locked(trip))

            # Re-read under a lock: two quick taps must not board the same
            # student twice, or race a concurrent drop.
            rider = TransportTripRider.objects.select_for_update().get(pk=rider.pk)

            if not TripRiderStatus.can_become(rider.status, status):
                raise TripRule.invalid_rider_change(rider.status, status)

            now = timezone.now()
            rider.status = status
            rider.boarded_at = now if status == TripRiderStatus.BOARDED else rider.boarded_at
            rider.dropped_at = now if status == TripRiderStatus.DROPPED else rider.dropped_at
            rider.updated_at = now
            rider.save(update_fields=["status", "boarded_at", "dropped_at", "updated_at"])

            current_stop = TransportStop.objects.filter(pk=trip.current_stop_id).first() if trip.current_stop_id else None
            cls.record(trip, status, actor, stop=current_stop, student=student)

            cls.alert_guardian(trip, rider, status, student, actor)

    @staticmethod
    def alert_guardian(trip, rider, status: str, student, actor: User) -> None:
        event = {
            TripRiderStatus.BOARDED: MessageEvent.TRANSPORT_BOARDED,
            TripRiderStatus.DROPPED: MessageEvent.TRANSPORT_DROPPED,
            TripRiderStatus.ABSENT: MessageEvent.TRANSPORT_ABSENT,
        }[status]

        notifications.notify_guardian(
            event,
            student,
            {
                # The moment it happened, on the school's clock.
                "time": SchoolClock.for_school(trip.school_id).format(timezone.now(), TIME),
                "stop_name": rider.stop_name,
                "vehicle_name": trip.vehicle.name,
                "route_name": trip.route.name,
                "direction": trip.direction,
                "date": trip.trip_date.strftime("%m/%d/%Y"),
            },
            actor,
        )

    @classmethod
    def end(cls, trip, actor: User) -> None:
        before = audit.fields_of(trip)

        cls.assert_in_progress(trip)
        cls.assert_nobody_on_board(trip)

        with transaction.atomic():
            cls.assert_in_progress(cls.locked(trip))
            # Somebody may have boarded between the check above and here.
            cls.assert_nobody_on_board(trip, lock=True)

            now = timezone.now()
            marked_absent = TransportTripRider.objects.filter(
                trip_id=trip.pk, status=TripRiderStatus.PENDING
            ).update(status=TripRiderStatus.ABSENT, updated_at=now)

            trip.status = TripStatus.COMPLETED
            trip.ended_at = now
            trip.updated_at = now
            trip.save(update_fields=["status", "ended_at", "updated_at"])
            audit.updated("transport", trip, before, action="transport_trip.completed")

            note = f"Trip completed; {marked_absent} marked absent" if marked_absent > 0 else "Trip completed"
            cls.record(trip, TripEventType.COMPLETED, actor, note=note)

    @classmethod
    def cancel(cls, trip, actor: User) -> None:
        before = audit.fields_of(trip)

        cls.assert_in_progress(trip)

        with transaction.atomic():
            cls.assert_in_progress(cls.locked(trip))

            now = timezone.now()
            trip.status = TripStatus.CANCELLED
            trip.ended_at = now
            trip.updated_at = now
            trip.save(update_fields=["status", "ended_at", "updated_at"])
            audit.updated("transport", trip, before, action="transport_trip.cancelled")

            cls.record(trip, TripEventType.CANCELLED, actor, note="Trip cancelled")

    @staticmethod
    def assert_nobody_on_board(trip, lock: bool = False) -> None:
        riders = TransportTripRider.objects.filter(trip_id=trip.pk, status=TripRiderStatus.BOARDED)

        # Rows read and counted under the lock, not a locked count: PostgreSQL
        # refuses FOR UPDATE on an aggregate.
        on_board = len(riders.select_for_update().values_list("id", flat=True)) if lock else riders.count()

        if on_board > 0:
            raise TripRule.riders_on_board(on_board)

    @staticmethod
    def record(trip, event_type: str, actor: User, stop=None, student=None, note=None) -> None:
        now = timezone.now()

        TransportTripEvent.objects.create(
            school_id=trip.school_id, trip_id=trip.pk, type=event_type,
            stop_id=stop.pk if stop else None, stop_name=stop.name if stop else None,
            student_id=student.pk if student else None, student_name=student.name if student else None,
            recorded_by_id=actor.id, recorded_at=now, note=note, created_at=now, updated_at=now,
        )



SEND_PASSWORD_RESET = "password_reset_link"


class PasswordResetService:
    """Laravel's password broker, over the same table, so a link either
    backend sends is one either backend honours.

    The email itself goes on the queue with only the user's id in the job -
    the token is made when the job runs, and never sits in a queue row. That
    also keeps the endpoint equally quick whether or not the address has an
    account, which a send inside the request would not.
    """

    @staticmethod
    def request_link(email: str) -> None:
        user = User.objects.filter(email=email).only("id").first()

        if user is not None:
            queue.push(SEND_PASSWORD_RESET, {"user_id": user.id})

    @staticmethod
    def reset(email: str, token: str, password: str) -> bool:
        from django.conf import settings

        user = User.objects.filter(email=email).first()

        if user is None:
            return False

        row = PasswordResetToken.objects.filter(email=user.email).first()
        expires = settings.PASSWORD_RESET_EXPIRE_MINUTES

        if (
            row is None
            or row.created_at is None
            or row.created_at + dt.timedelta(minutes=expires) < timezone.now()
            or not hashing.check(token, row.token)
        ):
            return False

        with transaction.atomic():
            # Choosing a password is choosing a password, however the account
            # got here - an imported employee who uses the link is no longer
            # asked to change it again.
            user.password = hashing.make(password)
            user.must_change_password = False
            # Proving you own the address is as good as an administrator's
            # unlock: a locked-out person's way back in is this link.
            user.failed_login_attempts = 0
            user.locked_until = None
            user.updated_at = timezone.now()
            user.save(update_fields=["password", "must_change_password", "failed_login_attempts", "locked_until",
                                     "updated_at"])

            # Every session ends, and the link is spent.
            tokens.revoke_all(user)
            PasswordResetToken.objects.filter(email=user.email).delete()
            AuthService._record(user, "user.password_reset")

        return True


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

            profile = StaffProfile.objects.create(
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

            audit.created("staff", profile)

            return profile

    @staticmethod
    def update(profile: StaffProfile, data: dict) -> StaffProfile:
        before = audit.fields_of(profile)

        for field, value in data.items():
            setattr(profile, field, value)

        profile.updated_at = timezone.now()
        profile.save()
        audit.updated("staff", profile, before)

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
            audit.created("payments", payment)

            cls.send_receipt(payment)

        return payment

    @classmethod
    def update(cls, payment: Payment, data: dict) -> Payment:
        audited = audit.fields_of(payment)

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
            audit.updated("payments", payment, audited)

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

        period = Period.objects.create(
            school_id=school_id,
            period_number=data["period_number"],
            start_time=data["start_time"],
            end_time=data["end_time"],
            created_at=now,
            updated_at=now,
        )

        audit.created("timetable", period)

        return period

    @staticmethod
    def update(period: Period, data: dict) -> Period:
        before = audit.fields_of(period)

        for field, value in data.items():
            setattr(period, field, value)

        period.updated_at = timezone.now()
        period.save()
        audit.updated("timetable", period, before)

        return period

    @staticmethod
    def delete(period: Period) -> None:
        if TimetableEntry.objects.filter(period_id=period.id).exists():
            raise HasDependentRecords(
                "This period still has timetable entries scheduled against it. "
                "Remove them first."
            )

        audit.deleted("timetable", period)
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

        holiday = Holiday.objects.create(
            school_id=school_id,
            name=data["name"],
            type=data["type"],
            start_date=data["start_date"],
            end_date=data["end_date"],
            created_at=now,
            updated_at=now,
        )

        audit.created("holidays", holiday)

        return holiday

    @classmethod
    def update(cls, holiday: Holiday, data: dict) -> Holiday:
        before = audit.fields_of(holiday)

        start = data.get("start_date", holiday.start_date)
        end = data.get("end_date", holiday.end_date)

        cls._assert_no_overlap(holiday.school_id, start, end, ignoring=holiday.pk)

        for field, value in data.items():
            setattr(holiday, field, value)

        holiday.updated_at = timezone.now()
        holiday.save()
        audit.updated("holidays", holiday, before)

        return holiday

    @staticmethod
    def delete(holiday: Holiday) -> None:
        audit.deleted("holidays", holiday)
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

        school_class = SchoolClass.objects.create(
            school_id=school_id,
            academic_year_id=data["academic_year_id"],
            name=data["name"],
            level=data["level"],
            created_at=now,
            updated_at=now,
        )

        audit.created("academic", school_class)

        return school_class

    @staticmethod
    def update(school_class: SchoolClass, data: dict) -> SchoolClass:
        before = audit.fields_of(school_class)

        for field, value in data.items():
            setattr(school_class, field, value)

        school_class.updated_at = timezone.now()
        school_class.save()
        audit.updated("academic", school_class, before)

        return school_class

    @staticmethod
    def delete(school_class: SchoolClass) -> None:
        if ClassSection.objects.filter(school_class_id=school_class.id).exists():
            raise HasDependentRecords("This class still has sections under it. Remove them first.")

        audit.deleted("academic", school_class)
        school_class.delete()

    @staticmethod
    def add_section(school_class: SchoolClass, data: dict) -> ClassSection:
        now = timezone.now()

        section = ClassSection.objects.create(
            school_class_id=school_class.id,
            name=data["name"],
            room_number=data.get("room_number"),
            class_teacher_id=data.get("class_teacher_id"),
            created_at=now,
            updated_at=now,
        )

        audit.created("academic", section)

        return section

    @staticmethod
    def update_section(section: ClassSection, data: dict) -> ClassSection:
        before = audit.fields_of(section)

        for field, value in data.items():
            setattr(section, field, value)

        section.updated_at = timezone.now()
        section.save()
        audit.updated("academic", section, before)

        return section

    @staticmethod
    def delete_section(section: ClassSection) -> None:
        if Student.objects.filter(class_section_id=section.id).exists():
            raise HasDependentRecords(
                "This section still has students assigned to it. "
                "Reassign or remove them first."
            )

        audit.deleted("academic", section)
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

        department = Department.objects.create(
            school_id=school_id,
            name=data["name"],
            hod_user_id=data.get("hod_user_id"),
            created_at=now,
            updated_at=now,
        )

        audit.created("academic", department)

        return department

    @staticmethod
    def update(department: Department, data: dict) -> Department:
        before = audit.fields_of(department)

        for field, value in data.items():
            setattr(department, field, value)

        department.updated_at = timezone.now()
        department.save()
        audit.updated("academic", department, before)

        return department

    @staticmethod
    def delete(department: Department) -> None:
        if Subject.objects.filter(department_id=department.id).exists():
            raise HasDependentRecords(
                "This department still has subjects assigned to it. "
                "Reassign or remove them first."
            )

        audit.deleted("academic", department)
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

        subject = Subject.objects.create(
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

        audit.created("academic", subject)

        return subject

    @staticmethod
    def update(subject: Subject, data: dict) -> Subject:
        before = audit.fields_of(subject)

        for field, value in data.items():
            setattr(subject, field, value)

        subject.updated_at = timezone.now()
        subject.save()
        audit.updated("academic", subject, before)

        return subject

    @staticmethod
    def delete(subject: Subject) -> None:
        # No dependency check, matching Laravel. A subject is removed from the
        # catalogue; the timetable entries and syllabus topics that referenced
        # it are handled by the database's own foreign keys.
        audit.deleted("academic", subject)
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

            year = AcademicYear.objects.create(
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

            audit.created("academic", year)

            return year

    @staticmethod
    def update(year: AcademicYear, data: dict) -> AcademicYear:
        before = audit.fields_of(year)

        for field, value in data.items():
            setattr(year, field, value)

        year.updated_at = timezone.now()
        year.save()
        audit.updated("academic", year, before)

        return year

    @classmethod
    def set_current(cls, year: AcademicYear) -> AcademicYear:
        before = audit.fields_of(year)

        with transaction.atomic():
            cls._clear_current_for(year.school_id)

            year.is_current = True
            year.updated_at = timezone.now()
            year.save(update_fields=["is_current", "updated_at"])
            audit.updated("academic", year, before, action="academic_year.set_current")

        return year

    @staticmethod
    def delete(year: AcademicYear) -> None:
        if SchoolClass.objects.filter(academic_year_id=year.id).exists():
            raise HasDependentRecords(
                "This academic year still has classes set up under it. Remove them first."
            )

        audit.deleted("academic", year)
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
            # Only a bulk import sets this: the employee signs in with a
            # temporary password nobody chose and is made to replace it.
            must_change_password=data.get("must_change_password", False),
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

        audit.created("users", user)

        return user

    @staticmethod
    def update(user: User, data: dict) -> User:
        before = audit.fields_of(user)

        for field, value in data.items():
            # The model has no hashing cast the way Eloquent does, so the one
            # field that must never be stored as typed is hashed here.
            setattr(user, field, hashing.make(value) if field == "password" else value)

        user.updated_at = timezone.now()
        user.save()

        # A new password, a new role or a new sign-in address ends every
        # session: whoever held the old ones was signed in as somebody the
        # account no longer is.
        security_changed = "password" in data or user.role != before["role"] or user.email != before["email"]
        if security_changed:
            tokens.revoke_all(user)

        audit.updated("users", user, before, action="user.role_changed" if user.role != before["role"] else None)
        if "password" in data:
            # The password itself is never recorded - only that it was set.
            audit.record(action="user.password_set", module="users", entity_type="user", entity_id=user.id,
                         school_id=user.school_id, new={"sessions_ended": security_changed})

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
        before = audit.fields_of(user)
        user.status = status
        user.updated_at = timezone.now()
        user.save(update_fields=["status", "updated_at"])

        action = "user.activated" if status == UserStatus.ACTIVE else "user.deactivated"
        audit.updated("users", user, before, action=action)

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

        student = Student.objects.create(
            school_id=school_id,
            class_section_id=data.get("class_section_id"),
            admission_number=data["admission_number"],
            first_name=data["first_name"],
            last_name=data["last_name"],
            roll_number=data.get("roll_number"),
            guardian_name=data["guardian_name"],
            guardian_mobile=data.get("guardian_mobile"),
            guardian_email=data.get("guardian_email"),
            student_mobile=data.get("student_mobile"),
            student_email=data.get("student_email"),
            address=data.get("address"),
            status=StudentStatus.ACTIVE,
            created_at=now,
            updated_at=now,
        )

        audit.created("students", student)

        return student

    @staticmethod
    def update(student: Student, data: dict) -> Student:
        before = audit.fields_of(student)

        for field, value in data.items():
            setattr(student, field, value)

        student.updated_at = timezone.now()
        student.save()
        audit.updated("students", student, before)

        return student

    @classmethod
    def activate(cls, student: Student) -> Student:
        return cls.set_status(student, StudentStatus.ACTIVE)

    @classmethod
    def deactivate(cls, student: Student) -> Student:
        return cls.set_status(student, StudentStatus.INACTIVE)

    @staticmethod
    def set_status(student: Student, status: str) -> Student:
        before = audit.fields_of(student)

        student.status = status
        student.updated_at = timezone.now()
        student.save(update_fields=["status", "updated_at"])
        action = "student.activated" if status == StudentStatus.ACTIVE else "student.deactivated"
        audit.updated("students", student, before, action=action)

        return student


def as_date(value) -> dt.date:
    """A date from either a date or a `YYYY-MM-DD` string."""
    if isinstance(value, dt.date):
        return value

    return dt.date.fromisoformat(str(value)[:10])


def assert_not_too_late(school_id: int, module: str, date) -> None:
    """The school's limit on marking a register late (module settings,
    docs/settings.md): a date more than this many days before today, on the
    school's clock, is refused. Zero means today only."""
    limit = modules.setting(school_id, module, "max_backdate_days")
    today = SchoolClock.for_school(school_id).now().date()

    if as_date(date) < today - dt.timedelta(days=limit):
        raise SettingRefused(
            "Attendance can only be marked for today"
            + (f" or the last {limit} day{'s' if limit != 1 else ''}" if limit else "")
            + "."
        )


class ModuleSettingService:
    """Which modules a school has on, and each module's own settings
    (docs/settings.md). A row appears the first time somebody touches a
    module for a school; until then the defaults apply."""

    @staticmethod
    def update(school_id: int, module: str, data: dict, actor: User):
        row = ModuleSetting.objects.filter(school_id=school_id, module=module).first()
        now = timezone.now()
        creating = row is None

        if creating:
            row = ModuleSetting(school_id=school_id, module=module, settings=None, created_at=now)

        before = audit.fields_of(row)

        for switch in ("platform_enabled", "school_enabled"):
            if switch in data:
                setattr(row, switch, data[switch])

        if data.get("settings") is not None:
            row.settings = {**(row.settings or {}), **data["settings"]}

        row.updated_by_id = actor.id
        row.updated_at = now
        row.save()

        if creating:
            audit.created("settings", row, school_id=school_id)
        else:
            audit.updated("settings", row, before, school_id=school_id)

        return ModuleSetting.objects.select_related("updated_by").get(pk=row.pk)


class RolePermissionService:
    """The roles and permissions matrix (docs/settings.md). Only cells that
    differ from the defaults are stored, so resetting is deleting them."""

    @staticmethod
    def save(submitted: dict, actor: User) -> None:
        now = timezone.now()
        current = permissions.matrix()

        with transaction.atomic():
            for role, cells in submitted.items():
                for module, level in cells.items():
                    if current[role][module] == level:
                        continue

                    if level == permissions.DEFAULTS[role][module]:
                        RolePermission.objects.filter(role=role, module=module).delete()
                    else:
                        RolePermission.objects.update_or_create(
                            role=role, module=module,
                            defaults={"level": level, "updated_by_id": actor.id, "updated_at": now, "created_at": now},
                        )

                    audit.record(
                        action="permission.changed", module="settings", entity_type="role_permission",
                        entity_id=None, school_id=None,
                        old={"role": role, "module": module, "level": current[role][module]},
                        new={"role": role, "module": module, "level": level},
                    )

    @staticmethod
    def reset(actor: User) -> None:
        with transaction.atomic():
            changed = list(RolePermission.objects.values_list("role", "module", "level"))
            RolePermission.objects.all().delete()

            for role, module, level in changed:
                audit.record(
                    action="permission.changed", module="settings", entity_type="role_permission",
                    entity_id=None, school_id=None,
                    old={"role": role, "module": module, "level": level},
                    new={"role": role, "module": module, "level": permissions.DEFAULTS[role][module]},
                )
