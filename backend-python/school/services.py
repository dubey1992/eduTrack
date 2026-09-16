"""The business rules, away from the HTTP.

app/Services, ported. Controllers stay thin - request, validation, service,
response (CLAUDE.md rule 8) - so anything here is a rule about the product
rather than about the web, and can be tested without one.
"""

from __future__ import annotations

from django.db.models import Q
from django.utils import timezone

from . import hashing, tokens
from .enums import StudentStatus, UserRole
from .errors import AccountInactive, Unauthenticated
from .models import PersonalAccessToken, Student, User
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

        # Exactly Laravel's `orderBy('first_name')`, tiebreaker and all - which
        # is to say without one. Two students called Aarav come back in
        # whatever order the database felt like, and a page boundary between
        # them can show one twice and the other not at all.
        #
        # Left alone deliberately. Adding `, id` here would fix a real bug and
        # would also mean the Python backend ordering a list differently from
        # the PHP one, which is the kind of difference this migration exists
        # not to introduce. It belongs in its own change, on both backends.
        return students.order_by("first_name")

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
