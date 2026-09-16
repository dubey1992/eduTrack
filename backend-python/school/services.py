"""The business rules, away from the HTTP.

app/Services, ported. Controllers stay thin - request, validation, service,
response (CLAUDE.md rule 8) - so anything here is a rule about the product
rather than about the web, and can be tested without one.
"""

from __future__ import annotations

from django.db import transaction
from django.db.models import Count, F, Q, Sum
from django.utils import timezone

from . import hashing, jobs, money, queue, tokens
from .clock import SchoolClock
from .enums import PaymentStatus, SchoolStatus, StudentStatus, UserRole, UserStatus
from .errors import AccountInactive, HasDependentRecords, HolidayOverlap, Unauthenticated
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
