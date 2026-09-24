"""The roles and permissions matrix (docs/settings.md).

One platform-wide table of role by module, each cell one of three levels:

- **none** - the role does not see the module;
- **view** - it reads what its scope allows;
- **manage** - it also writes, within the same scope.

The matrix decides *whether* a role may read or write a module. *Which
records* it reaches - a teacher's own classes, a head's own department, an
admin's own school or group - stays in the policies (school/policies.py),
because that is knowledge about the data, not about roles. Raising a role
to "manage" therefore widens what it may do, never whose records it does it
to.

The defaults below reproduce exactly what every policy allowed before the
matrix existed, so a platform that never edits it behaves as it always did.
Only cells that differ from a default are stored (`role_permissions`).
SUPER_ADMIN is not in the matrix: it is always full and cannot be edited.
GROUP_ADMIN follows SCHOOL_ADMIN, as it does everywhere else.
"""

from __future__ import annotations

from .enums import UserRole
from .models import RolePermission

NONE = "none"
VIEW = "view"
MANAGE = "manage"
LEVELS = (NONE, VIEW, MANAGE)

# The roles a Super Admin can edit, in the order the matrix shows them.
EDITABLE_ROLES = (
    UserRole.SCHOOL_ADMIN,
    UserRole.HOD,
    UserRole.TEACHER,
    UserRole.STAFF,
    UserRole.TRANSPORT_MANAGER,
    UserRole.ACCOUNTANT,
    UserRole.BUS_ATTENDANT,
)

# module -> (SCHOOL_ADMIN, HOD, TEACHER, STAFF, TRANSPORT_MANAGER, ACCOUNTANT,
# BUS_ATTENDANT),
# each what the policies granted before the matrix existed. Admin users and
# the audit log are administration rather than a module a role is granted,
# so they are not here: those policies answer for themselves.
_DEFAULT_ROWS = {
    "students":         (MANAGE, NONE,   VIEW,   NONE,   NONE,   NONE,   NONE),
    "staff":            (MANAGE, NONE,   NONE,   NONE,   NONE,   NONE,   NONE),
    "academics":        (MANAGE, VIEW,   VIEW,   VIEW,   VIEW,   VIEW,   NONE),
    "assessments":      (MANAGE, MANAGE, MANAGE, NONE,   NONE,   NONE,   NONE),
    "attendance":       (MANAGE, NONE,   MANAGE, NONE,   NONE,   NONE,   NONE),
    "staff_attendance": (MANAGE, MANAGE, NONE,   NONE,   NONE,   NONE,   NONE),
    "leave":            (MANAGE, MANAGE, MANAGE, MANAGE, MANAGE, MANAGE, MANAGE),
    "timetable":        (MANAGE, VIEW,   VIEW,   VIEW,   VIEW,   VIEW,   NONE),
    "teaching_reports": (MANAGE, MANAGE, MANAGE, NONE,   NONE,   NONE,   NONE),
    "syllabus":         (MANAGE, MANAGE, MANAGE, NONE,   NONE,   NONE,   NONE),
    "hod":              (VIEW,   VIEW,   NONE,   NONE,   NONE,   NONE,   NONE),
    # An attendant manages transport only for the routes they are assigned
    # to - the policies narrow it, as they narrow a teacher to their class.
    "transport":        (MANAGE, VIEW,   VIEW,   NONE,   MANAGE, NONE,   MANAGE),
    "communication":    (MANAGE, NONE,   NONE,   NONE,   NONE,   NONE,   NONE),
    "announcements":    (MANAGE, MANAGE, NONE,   NONE,   NONE,   NONE,   NONE),
    "payroll":          (MANAGE, NONE,   NONE,   NONE,   NONE,   MANAGE, NONE),
    "reports":          (VIEW,   VIEW,   NONE,   NONE,   VIEW,   VIEW,   NONE),
}

DEFAULTS: dict[str, dict[str, str]] = {
    role: {module: levels[index] for module, levels in _DEFAULT_ROWS.items()}
    for index, role in enumerate(EDITABLE_ROLES)
}

# Modules a level can be edited for, in the order the matrix shows them.
MODULES = tuple(_DEFAULT_ROWS)


def stored() -> dict[str, dict[str, str]]:
    """The cells that differ from the defaults, as saved."""
    matrix: dict[str, dict[str, str]] = {}

    for row in RolePermission.objects.all():
        matrix.setdefault(row.role, {})[row.module] = row.level

    return matrix


def matrix() -> dict[str, dict[str, str]]:
    """The whole matrix in force: defaults overlaid with what was saved."""
    saved = stored()

    return {
        role: {module: saved.get(role, {}).get(module, level) for module, level in defaults.items()}
        for role, defaults in DEFAULTS.items()
    }


def level_for(role: str, module: str, current: dict | None = None) -> str:
    """The level a role has on a module right now.

    Read per call rather than cached: a Super Admin who saves the matrix
    expects the next request to obey it, and the query is one small table.
    """
    if role == UserRole.SUPER_ADMIN:
        return MANAGE

    if role == UserRole.GROUP_ADMIN:
        role = UserRole.SCHOOL_ADMIN

    if module not in _DEFAULT_ROWS:
        # Platform business - schools, payments, mail settings - is not in
        # the matrix; those policies answer for themselves.
        return NONE

    current = matrix() if current is None else current

    return current.get(role, {}).get(module, NONE)


def may_view(actor, module: str) -> bool:
    return level_for(actor.role, module) in (VIEW, MANAGE)


def may_manage(actor, module: str) -> bool:
    return level_for(actor.role, module) == MANAGE


def for_user(actor) -> dict[str, str]:
    """Every module's level for one account - what /me tells the app."""
    current = matrix()

    return {module: level_for(actor.role, module, current) for module in MODULES}
