"""Who may do what.

The Python half of app/Policies. Named `policies` rather than `permissions`
because these are ports of specific Laravel policies and reading the two side
by side is how they get reviewed - the migration plan calls this the dangerous
part, since every mistake here is one school reading another's records.

A policy answers a question and returns a bool. Raising the 403 is the view's
job, through `authorize()`, so the same policy can be asked without an
exception when a caller only wants to know.

Every rule below has an ALLOW test and a DENY test in tests/test_policies.py
(CLAUDE.md rule 11).
"""

from __future__ import annotations

from rest_framework.exceptions import PermissionDenied

from .enums import UserRole
from .models import Student, User
from .scope import SchoolScope

ADMIN_ROLES = (UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN)


def authorize(allowed: bool) -> None:
    """Turns a policy's answer into the 403 the client expects."""
    if not allowed:
        raise PermissionDenied()


class SchoolPolicy:
    """Schools are platform-level records - only SUPER_ADMIN manages them.

    A SCHOOL_ADMIN may view any school in their own group (the school details
    screen and the branch pickers need it) but never one outside it, and never
    edits the school record itself.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        # An admin who answers for several branches lists them so they can
        # pick one. Asked of the scope rather than the role, because a School
        # Admin has branches to pick from only when their school is in a
        # group; a standalone one has nothing to choose and is refused.
        return actor.role == UserRole.SUPER_ADMIN or SchoolScope.for_actor(actor).covers_a_group()

    @staticmethod
    def view(actor: User, school) -> bool:
        return actor.role == UserRole.SUPER_ADMIN or SchoolScope.for_actor(actor).allows(school.id)

    @staticmethod
    def create(actor: User) -> bool:
        return actor.role == UserRole.SUPER_ADMIN

    @staticmethod
    def update(actor: User, school=None) -> bool:
        return actor.role == UserRole.SUPER_ADMIN

    @staticmethod
    def set_status(actor: User, school=None) -> bool:
        return actor.role == UserRole.SUPER_ADMIN


class SchoolOwnedPolicy:
    """The shape most school-owned records share.

    Admins manage their own school's records; everybody else may read them.
    Departments, subjects, classes, periods and holidays all answer exactly
    this, and writing it five times is how one of them quietly ends up
    different from the other four.

    Subclasses exist so a call site names the thing it is asking about, and so
    a record that later needs its own rule has somewhere to put it.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return True

    @staticmethod
    def view(actor: User, record) -> bool:
        return actor.role == UserRole.SUPER_ADMIN or SchoolScope.for_actor(actor).allows(
            record.school_id
        )

    @staticmethod
    def create(actor: User) -> bool:
        return actor.role in ADMIN_ROLES

    @classmethod
    def update(cls, actor: User, record) -> bool:
        return cls._manages(actor, record)

    @classmethod
    def delete(cls, actor: User, record) -> bool:
        return cls._manages(actor, record)

    @staticmethod
    def _manages(actor: User, record) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return UserRole.administers_school(actor.role) and SchoolScope.for_actor(actor).allows(
            record.school_id
        )


class DepartmentPolicy(SchoolOwnedPolicy):
    """Departments, plus the department report the HOD screens need.

    The report is the one place this diverges: an admin sees any department of
    their school, an HOD only the ones they actually head.
    """

    @staticmethod
    def view_any_report(actor: User) -> bool:
        return actor.role in ADMIN_ROLES or actor.role == UserRole.HOD

    @staticmethod
    def view_report(actor: User, department) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        if not SchoolScope.for_actor(actor).allows(department.school_id):
            return False

        if UserRole.administers_school(actor.role):
            return True

        if actor.role == UserRole.HOD:
            return department.hod_user_id == actor.id

        return False


class SubjectPolicy(SchoolOwnedPolicy):
    pass


class StaffProfilePolicy:
    """Employment records.

    Admins only, even to read: a teacher does not browse their colleagues'
    joining dates and addresses. That is the one way this differs from the
    school-owned shape, which lets every role read.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return actor.role in ADMIN_ROLES

    @classmethod
    def view(cls, actor: User, profile) -> bool:
        return cls._manages(actor, profile)

    @staticmethod
    def create(actor: User) -> bool:
        return actor.role in ADMIN_ROLES

    @classmethod
    def update(cls, actor: User, profile) -> bool:
        return cls._manages(actor, profile)

    @staticmethod
    def _manages(actor: User, profile) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return UserRole.administers_school(actor.role) and SchoolScope.for_actor(actor).allows(
            profile.school_id
        )


class PaymentPolicy:
    """Platform business, and nobody else's.

    Onboarding a school and recording what it paid are things the platform
    does, not things a school does - so this is the one module where a School
    Admin has no access at all, not even to their own school's rows.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return actor.role == UserRole.SUPER_ADMIN

    @staticmethod
    def view(actor: User, payment=None) -> bool:
        return actor.role == UserRole.SUPER_ADMIN

    @staticmethod
    def create(actor: User) -> bool:
        return actor.role == UserRole.SUPER_ADMIN

    @staticmethod
    def update(actor: User, payment=None) -> bool:
        return actor.role == UserRole.SUPER_ADMIN


class SchoolClassPolicy(SchoolOwnedPolicy):
    pass


class HolidayPolicy(SchoolOwnedPolicy):
    pass


class PeriodPolicy(SchoolOwnedPolicy):
    pass


class ClassSectionPolicy:
    """A section has no school of its own - it reaches one through its class.

    So this cannot inherit SchoolOwnedPolicy, which reads `record.school_id`.
    Written out rather than bent to fit, because a policy that silently read a
    missing attribute as None would allow everything for a scope that permits
    None, and that is the worst possible failure here.
    """

    @staticmethod
    def create(actor: User) -> bool:
        return actor.role in ADMIN_ROLES

    @classmethod
    def update(cls, actor: User, section) -> bool:
        return cls._manages(actor, section)

    @classmethod
    def delete(cls, actor: User, section) -> bool:
        return cls._manages(actor, section)

    @classmethod
    def view_attendance(cls, actor: User, section) -> bool:
        """Admins, and the teacher who actually has the class.

        Attendance is M10's work; the ability lives here because it is a
        question about a section and this is where those are answered.
        """
        return cls._manages(actor, section) or cls._is_class_teacher(actor, section)

    @classmethod
    def mark_attendance(cls, actor: User, section) -> bool:
        return cls.view_attendance(actor, section)

    @staticmethod
    def _manages(actor: User, section) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return UserRole.administers_school(actor.role) and SchoolScope.for_actor(actor).allows(
            section.school_class.school_id
        )

    @staticmethod
    def _is_class_teacher(actor: User, section) -> bool:
        return actor.role == UserRole.TEACHER and actor.id == section.class_teacher_id


class AcademicYearPolicy(SchoolOwnedPolicy):
    """The shared shape, plus the one action that is not a field edit.

    Making a year current makes another year stop being current, so it has its
    own ability rather than riding on `update` - the permission and the
    side effect belong together.
    """

    @classmethod
    def set_current(cls, actor: User, year) -> bool:
        return cls._manages(actor, year)


class UserPolicy:
    """Who may manage which accounts.

    SUPER_ADMIN manages every user, across every school. An admin manages
    non-admin accounts in their own school freely, and admin-tier accounts on
    a strict hierarchy: the head - a School Admin who is not themselves a Sub
    Admin - manages the Sub Admins in their own school, but never another
    head, and never themselves.

    `is_sub_admin` is two tiers of one role rather than a role of its own, so
    every other policy treats them identically. A School Admin a Super Admin
    onboarded can create further admin accounts for their school; a Sub Admin
    has the same permissions everywhere else but can create no admin account
    at all.

    Operational staff (HOD/TEACHER/STAFF/TRANSPORT_MANAGER) are onboarded
    through Teachers & Staff instead, which creates the login and the
    employment record together. One created here would have no StaffProfile
    and be invisible to Attendance and Leave, so that path is deliberately not
    offered.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return actor.role in ADMIN_ROLES

    @classmethod
    def view(cls, actor: User, target: User) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return cls._same_school(actor, target)

    @staticmethod
    def create(actor: User) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return UserRole.administers_school(actor.role) and not actor.is_sub_admin

    @classmethod
    def update(cls, actor: User, target: User) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return cls._manages(actor, target)

    @classmethod
    def set_status(cls, actor: User, target: User) -> bool:
        # Nobody deactivates their own account through this endpoint, whatever
        # their role - it is the one mistake that locks you out of fixing it.
        if actor.id == target.id:
            return False

        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return cls._manages(actor, target)

    @classmethod
    def _manages(cls, actor: User, target: User) -> bool:
        if not cls._same_school(actor, target):
            return False

        # Admin-tier targets follow the hierarchy; everybody else is managed
        # freely within the school.
        if not UserRole.administers_school(target.role):
            return True

        return not actor.is_sub_admin and target.is_sub_admin

    @staticmethod
    def _same_school(actor: User, target: User) -> bool:
        return UserRole.administers_school(actor.role) and SchoolScope.for_actor(actor).allows(
            target.school_id
        )


class StudentPolicy:
    """SUPER_ADMIN, GROUP_ADMIN and SCHOOL_ADMIN manage every student in
    scope. TEACHER gets read-only access, and only to students in a class
    section they are the class teacher of - the "a Teacher assigned to 8A must
    not access 9A" rule from CLAUDE.md. HOD/STAFF/TRANSPORT_MANAGER have no
    student access.
    """

    @staticmethod
    def view_any(actor: User) -> bool:
        return actor.role in ADMIN_ROLES or actor.role == UserRole.TEACHER

    @staticmethod
    def view(actor: User, student: Student) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        if UserRole.administers_school(actor.role):
            return SchoolScope.for_actor(actor).allows(student.school_id)

        if actor.role == UserRole.TEACHER:
            section = student.class_section

            return section is not None and section.class_teacher_id == actor.id

        return False

    @staticmethod
    def create(actor: User) -> bool:
        return actor.role in ADMIN_ROLES

    @classmethod
    def update(cls, actor: User, student: Student) -> bool:
        return cls._manages(actor, student)

    @classmethod
    def set_status(cls, actor: User, student: Student) -> bool:
        return cls._manages(actor, student)

    @staticmethod
    def _manages(actor: User, student: Student) -> bool:
        if actor.role == UserRole.SUPER_ADMIN:
            return True

        return UserRole.administers_school(actor.role) and SchoolScope.for_actor(actor).allows(
            student.school_id
        )
