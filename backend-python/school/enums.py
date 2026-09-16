"""The enums, as the API spells them.

Every one of these is a string the Flutter apps compare against - "SCHOOL_ADMIN",
"active" - so the stored value is contract, not an implementation detail. They
mirror App\Enums one for one; where a PHP enum carries a method, the method
comes with it rather than being re-derived at the call site.

`TextChoices` rather than a bare constant class so a serializer can validate
against `.choices` and get the same answer the database's own check would.
"""

from __future__ import annotations

from django.db import models


class UserRole(models.TextChoices):
    SUPER_ADMIN = "SUPER_ADMIN"
    # Attached to a parent school: reads every branch in its group, and writes
    # into whichever branch it names. Not a platform role - schools and
    # payments stay SUPER_ADMIN. See docs/branches.md.
    GROUP_ADMIN = "GROUP_ADMIN"
    # Attached to any one school. Where that school is part of a group, the
    # same group reach as a Group Admin - the head office looks down at its
    # branches and a branch looks up and across at its sisters. Where it is
    # standalone, which is most schools, exactly one school as always.
    SCHOOL_ADMIN = "SCHOOL_ADMIN"
    HOD = "HOD"
    TEACHER = "TEACHER"
    STAFF = "STAFF"
    TRANSPORT_MANAGER = "TRANSPORT_MANAGER"

    @classmethod
    def administers_school(cls, role: str) -> bool:
        """Administers schools' own affairs - their own school, and every
        branch in its group where there is one.

        Says nothing about *which* schools: that is SchoolScope's question, and
        asking it here instead is how the two would drift apart.

        Deliberately not "is an admin": onboarding a school and recording the
        payments it makes are platform actions and stay SUPER_ADMIN.
        """
        return role in (cls.SCHOOL_ADMIN, cls.GROUP_ADMIN)


class UserStatus(models.TextChoices):
    ACTIVE = "active"
    INACTIVE = "inactive"


class StudentStatus(models.TextChoices):
    ACTIVE = "active"
    INACTIVE = "inactive"


class SchoolStatus(models.TextChoices):
    ACTIVE = "active"
    INACTIVE = "inactive"


class HolidayType(models.TextChoices):
    NATIONAL = "national"
    RELIGIOUS = "religious"
    SCHOOL_EVENT = "school_event"
    VACATION = "vacation"
