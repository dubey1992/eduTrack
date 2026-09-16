"""The business rules, away from the HTTP.

app/Services, ported. Controllers stay thin - request, validation, service,
response (CLAUDE.md rule 8) - so anything here is a rule about the product
rather than about the web, and can be tested without one.
"""

from __future__ import annotations

from django.db import transaction
from django.db.models import Count, Q
from django.utils import timezone

from . import hashing, tokens
from .clock import SchoolClock
from .enums import SchoolStatus, StudentStatus, UserRole, UserStatus
from .errors import AccountInactive, HasDependentRecords, Unauthenticated
from .models import (
    AcademicYear,
    EarlyAccessRequest,
    PersonalAccessToken,
    School,
    SchoolClass,
    StaffProfile,
    Student,
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
