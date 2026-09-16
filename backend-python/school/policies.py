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
