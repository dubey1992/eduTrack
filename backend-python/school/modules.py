"""The product's modules: which can be switched off per school, and what each
one's own settings are (docs/settings.md).

A module here is what a school sees as one thing in the sidebar: attendance,
transport, payroll. Some are the product's spine and are always on - students,
staff, the academic set-up, admin users, the audit trail. The rest a school
can do without, so each has two switches: the platform grants it (Super
Admin) and the school keeps it on (School Admin). A module is on only when
both say so, and a school with no row has everything on with its defaults,
so nothing changes until somebody edits something.

Settings are declared, not free-form: each module lists the fields it
understands with a type, a range and a default, and the API refuses
anything else. Every setting listed here is read by a service somewhere -
a setting nothing reads would be a lie on a screen.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .models import ModuleSetting


@dataclass(frozen=True)
class Setting:
    key: str
    label: str
    type: str  # "bool" | "int"
    default: object
    help: str = ""
    min: int | None = None
    max: int | None = None


@dataclass(frozen=True)
class Module:
    key: str
    label: str
    description: str
    # False for the product's spine: always on, never a switch on screen.
    switchable: bool = True
    settings: tuple[Setting, ...] = field(default_factory=tuple)

    def defaults(self) -> dict:
        return {setting.key: setting.default for setting in self.settings}


MODULES: tuple[Module, ...] = (
    Module("students", "Students", "Student records and guardians.", switchable=False),
    Module("staff", "Teachers & Staff", "Employment records and logins.", switchable=False),
    Module(
        "academics", "Academic Set-up",
        "Academic years, holidays, departments, subjects, classes and periods.", switchable=False,
    ),
    Module("users", "Admin Users", "School administrator accounts.", switchable=False),
    Module("audit", "Audit Log", "Who changed what, and when.", switchable=False),
    Module(
        "assessments", "Class Tests & Assessments",
        "Class tests, the marks sheet and published results.",
        settings=(
            Setting(
                "pass_percentage", "Pass mark, as a percentage", "int", 33, min=0, max=100,
                help="Used when a test does not set its own pass mark.",
            ),
        ),
    ),
    Module(
        "attendance", "Student Attendance", "Daily registers and guardian alerts.",
        settings=(
            Setting(
                "max_backdate_days", "Days a register may be marked late", "int", 30,
                help="How many days back a register may still be submitted or corrected. 0 means today only.",
                min=0, max=365,
            ),
        ),
    ),
    Module(
        "staff_attendance", "Staff Attendance", "The staff register.",
        settings=(
            Setting(
                "max_backdate_days", "Days a register may be marked late", "int", 30,
                help="How many days back the staff register may still be submitted or corrected.",
                min=0, max=365,
            ),
        ),
    ),
    Module(
        "leave", "Staff Leave", "Applying for leave and deciding it.",
        settings=(
            Setting(
                "min_notice_days", "Minimum notice (days)", "int", 0,
                help="Leave must start at least this many days after it is applied for. 0 allows leave from today.",
                min=0, max=90,
            ),
        ),
    ),
    Module("timetable", "Timetable", "Periods and the weekly grid."),
    Module(
        "teaching_reports", "Teaching Reports", "Daily reports on what was taught, and their review.",
        settings=(
            Setting(
                "filing_window_days", "Days allowed to file a report", "int", 0,
                help="A report may be filed this many days after the period. 0 means no limit.",
                min=0, max=90,
            ),
        ),
    ),
    Module("syllabus", "Syllabus", "Topic outlines and what has been covered."),
    Module("hod", "HOD Reports", "Department monitoring for heads of department."),
    Module("transport", "Transport", "Vehicles, drivers, routes, stops and trips."),
    Module("communication", "Communication", "Alerts, messages and the message log."),
    Module("announcements", "Announcements", "Notices to the school, a class or a department."),
    Module(
        "payroll", "Payroll", "Salaries, monthly runs and payslips.",
        settings=(
            Setting(
                "email_payslips_on_finalize", "Email payslips when a run is finalized", "bool", True,
                help="Each employee is emailed their payslip the moment the month is finalized.",
            ),
        ),
    ),
    Module("reports", "Reports", "Attendance, leave, teaching, transport and payroll reports."),
)

BY_KEY = {module.key: module for module in MODULES}
KEYS = tuple(module.key for module in MODULES)
SWITCHABLE = tuple(module.key for module in MODULES if module.switchable)


def get(key: str) -> Module:
    return BY_KEY[key]


def rows_for(school_id: int) -> dict[str, ModuleSetting]:
    """Whatever the school has saved, by module. Absent means defaults."""
    return {row.module: row for row in ModuleSetting.objects.filter(school_id=school_id)}


def is_enabled(school_id, module: str, rows: dict | None = None) -> bool:
    """Whether a module is on for a school. A module that cannot be switched
    is always on; so is everything for an actor with no school - a Super
    Admin looking at the platform rather than at a school."""
    if module not in BY_KEY or not BY_KEY[module].switchable or school_id is None:
        return True

    if rows is None:
        row = ModuleSetting.objects.filter(school_id=school_id, module=module).first()
    else:
        row = rows.get(module)

    return row is None or (row.platform_enabled and row.school_enabled)


def enabled_map(school_id) -> dict[str, bool]:
    """Every module and whether it is on - what /me tells the app."""
    rows = rows_for(school_id) if school_id is not None else {}

    return {module.key: is_enabled(school_id, module.key, rows) for module in MODULES}


def settings_for(school_id, module: str) -> dict:
    """The module's settings for a school: the defaults, overlaid with
    whatever the school saved. A key the school saved that the module no
    longer declares is dropped rather than shown."""
    declared = get(module)
    values = declared.defaults()

    if school_id is None:
        return values

    row = ModuleSetting.objects.filter(school_id=school_id, module=module).first()

    if row is not None and row.settings:
        values.update({key: value for key, value in row.settings.items() if key in values})

    return values


def setting(school_id, module: str, key: str):
    """One setting's value for a school - what a service reads."""
    return settings_for(school_id, module)[key]
