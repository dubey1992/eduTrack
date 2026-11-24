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
    type: str  # "bool" | "int" | "text" | "choice"
    default: object
    help: str = ""
    min: int | None = None
    max: int | None = None
    # A "text" setting: its longest allowed length, whether the screen gives
    # it several lines, and an optional pattern a non-empty value must match
    # (with the sentence shown when it does not). Empty is always allowed.
    max_length: int | None = None
    multiline: bool = False
    pattern: str | None = None
    pattern_message: str = ""
    # A "choice" setting: the values it may take, each with what the screen
    # calls it, in the order the screen lists them.
    choices: tuple[tuple[str, str], ...] = ()


@dataclass(frozen=True)
class Module:
    key: str
    label: str
    description: str
    # False for the product's spine: always on, never a switch on screen.
    switchable: bool = True
    # False for a module a school only gets when it asks. Everything else
    # arrives on, because a school with no row should see the product it
    # bought - but a module that needs hardware on the wall is not something
    # to switch on for a school that has none.
    granted_by_default: bool = True
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
            Setting(
                "weak_below_percentage", "Weak subject, below", "int", 40, min=0, max=100,
                help="A subject average under this is flagged on a student's performance.",
            ),
            # The printed report card (docs/document-styles.md, decided
            # 2026-11-17). Read by report_card.py.
            Setting(
                "report_card_style", "Report card layout", "choice", "standard",
                choices=(("standard", "Standard"), ("classic", "Classic printed")),
                help="Classic printed: every term side by side with each test's marks, the totals, the result "
                     "and signature lines, as on a printed marksheet.",
            ),
            Setting(
                "result_rule", "Result on the report card", "choice", "every_subject",
                choices=(
                    ("every_subject", "Passed every subject"),
                    ("overall", "Passed overall"),
                    ("none", "Don't print a result"),
                ),
                help="Every subject: each subject reaches the pass mark (or, on a grade scale, no failing grade). "
                     "Overall: the whole year's total does.",
            ),
            Setting("result_pass_word", "Result wording when passed", "text", "QUALIFIED", max_length=30),
            Setting("result_fail_word", "Result wording when not passed", "text", "NOT QUALIFIED", max_length=30),
            Setting(
                "print_rank", "Print the class rank", "bool", False,
                help="Rank within the section by the year's percentage (or GPA). Equal scores share a rank.",
            ),
            Setting(
                "report_card_note", "A word to parents", "text", "", max_length=600, multiline=True,
                help="Printed on every classic report card. Leave empty to leave it off.",
            ),
            Setting(
                "report_card_instructions", "Instructions on the report card", "text", "", max_length=600,
                multiline=True, help="Printed above the grading key. Leave empty to leave it off.",
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
            # Read by staff_reminders.py (decided 2026-11-18): off for
            # schools already live, switched on for new ones at creation.
            Setting(
                "remind_register", "Remind class teachers whose register is not taken", "bool", False,
                help="In the app, once the first period has ended. Never by SMS.",
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
            # Checking in from the phone (docs/staff-check-in.md, decided
            # 2026-10-25). On by default; the school's map pin is the proof.
            Setting(
                "app_check_in", "Staff check in and out from the app", "bool", True,
                help="Staff mark their own arrival and departure from their phone, at school.",
            ),
            Setting(
                "check_in_radius_m", "Check-in distance from school (metres)", "int", 100,
                help="How close to the school's map pin a phone must be to check in or out.",
                min=25, max=1000,
            ),
            Setting(
                "remind_check_in", "Remind staff who have not checked in", "bool", False,
                help="In the app, 30 minutes into the first period. Never by SMS.",
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
    Module(
        "family_app", "Family App",
        "The School365ai Family app for parents: their children's day, the bus, fees and notices.",
        # Off until the platform grants it: a school starts by issuing letters
        # to parents, and nobody should get one before the school is ready
        # (docs/parent-student-app.md, F0).
        granted_by_default=False,
        settings=(
            Setting(
                "show_class_average", "Show parents the class average", "bool", False,
                help="Beside each published test, the average of everyone who sat it. Off by default: "
                     "a school decides whether its parents see how a class did.",
            ),
        ),
    ),
    Module(
        "biometric", "Biometric Attendance",
        "Fingerprint readers, the punch log, and the times they put on the staff register.",
        # Off until somebody asks for it: it needs readers on the wall, and a
        # school without them would find a screen that can only ever be empty
        # (docs/biometric.md).
        granted_by_default=False,
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
            # Decided 2026-11-02: a teacher checks in before reporting what
            # they taught that day. On by default; a school may switch it off.
            Setting(
                "needs_attendance", "Teachers must be marked present to file reports", "bool", True,
                help="A teacher files reports only for days they are marked present - checked in, "
                     "punched in, or marked by the office - and never for a day of leave.",
            ),
            Setting(
                "remind_reports_owed", "Remind teachers of reports still owed", "bool", False,
                help="In the app, once the last period has ended. Never by SMS.",
            ),
        ),
    ),
    Module("syllabus", "Syllabus", "Topic outlines and what has been covered."),
    Module("hod", "HOD Reports", "Department monitoring for heads of department."),
    Module(
        "transport", "Transport", "Vehicles, drivers, routes, stops and trips.",
        settings=(
            # Read by family_bus.py, as a recorded position comes in (F4).
            Setting(
                "near_stop_alert_m", "Tell parents when the bus is this close to their stop (metres)", "int", 500,
                help="Sent once per trip in the Family app, never by SMS. 0 turns it off.",
                min=0, max=5000,
            ),
            # Read by family_bus.py for the Bus tab's contacts (F4).
            Setting(
                "show_crew_phone_to_parents", "Show parents the bus attendant's mobile", "bool", False,
                help="Off: parents see the school office's number only.",
            ),
            # Read by the Driver app with the trip (M7, 1.3).
            Setting(
                "auto_reach_m", "Mark a stop Reached when the bus is this close (metres)", "int", 50,
                help="The Driver app marks it by itself; the Reached button still works. 0 turns it off.",
                min=0, max=200,
            ),
            # Read by TransportTripService.alert_at_stop (M7). Off by default:
            # no school's message bill changes until it chooses.
            Setting(
                "at_stop_alert", "Tell parents when the bus reaches their stop", "bool", False,
                help="Once per stop per trip, on the channels the school sends transport alerts on.",
            ),
        ),
    ),
    Module("communication", "Communication", "Alerts, messages and the message log."),
    Module("announcements", "Announcements", "Notices to the school, a class or a department."),
    Module(
        "payroll", "Payroll", "Salaries, monthly runs and payslips.",
        settings=(
            Setting(
                "email_payslips_on_finalize", "Email payslips when a run is finalized", "bool", True,
                help="Each employee is emailed their payslip the moment the month is finalized.",
            ),
            # Read by payroll/payslips.py (asked for 2026-11-21, as the fee
            # receipt and the report card have): which layout a payslip PDF
            # takes. Standard is the default, so no school's payslips change
            # until it chooses.
            Setting(
                "payslip_style", "Payslip layout", "choice", "standard",
                choices=(("standard", "Standard"), ("classic", "Classic printed")),
                help="Classic printed: a black-and-white salary slip with earnings and deductions side by side, "
                     "the net pay in words and signature lines, as on a printed salary register.",
            ),
        ),
    ),
    Module(
        "fees", "Fee Management",
        "Fee types, class and bus route fees, what each student owes, and receipts for what they pay.",
        # Off until the Super Admin grants it (docs/fees.md). On by default,
        # every school on the platform would find an empty Fees menu the
        # morning it shipped, with nothing set up behind it. Each setting
        # arrived with the slice that reads it, because a setting nothing
        # reads is a lie.
        granted_by_default=False,
        settings=(
            # Read by fees/receipts.py when a payment is recorded (F3).
            Setting(
                "allow_part_payment", "Allow part payments", "bool", True,
                help="Off: every installment a payment touches must be paid in full.",
            ),
            # Read by fees/fines.py, the hourly apply_late_fines job (F4).
            Setting(
                "late_fine_amount", "Late fine (whole currency units)", "int", 0, min=0, max=1000000,
                help="Added once to an installment unpaid this many days after it is due. 0 means no fines.",
            ),
            Setting("late_fine_grace_days", "Days of grace before the fine", "int", 7, min=0, max=90),
            # Read by fees/reminders.py, the hourly send_fee_reminders job (F5).
            Setting(
                "reminder_days_before", "Remind guardians this many days before a due date", "int", 3,
                min=0, max=30, help="0 turns these reminders off.",
            ),
            Setting(
                "remind_when_overdue", "Remind guardians once when an installment becomes overdue", "bool", True,
            ),
            # Read by family_fees.py: "How to pay" in the Family app (F3).
            # The app takes no payments (decision D4); it tells a parent how.
            Setting(
                "pay_counter_hours", "Fee counter hours", "text", "", max_length=200,
                help="When the office takes fees, e.g. \"Mon-Sat, 9 am to 1 pm\". Shown to parents in the Family app.",
            ),
            Setting(
                "pay_bank_details", "Bank details for fee transfers", "text", "", max_length=500, multiline=True,
                help="Account name, number, bank, branch and IFSC, as parents should write them. "
                     "Shown to parents in the Family app.",
            ),
            # Read by fees/receipt_pdf.py (docs/document-styles.md): which
            # layout a printed fee receipt takes. Standard is the default, so
            # no school's receipts change until it chooses.
            Setting(
                "receipt_style", "Fee receipt layout", "choice", "standard",
                choices=(("standard", "Standard"), ("classic", "Classic printed")),
                help="Classic printed: a black-and-white receipt with month-wise fee lines, the dues summary "
                     "and a signature line, as on a printed receipt book.",
            ),
            Setting(
                "pay_upi_id", "UPI ID for fees", "text", "", max_length=100,
                pattern=r"^[A-Za-z0-9._-]{2,256}@[A-Za-z][A-Za-z0-9.]{1,63}$",
                pattern_message="Enter a UPI ID like schoolname@okaxis.",
                help="Shown to parents in the Family app. Leave empty if the school takes no UPI payments.",
            ),
        ),
    ),
    Module(
        "reports", "Reports", "Attendance, leave, teaching, transport and payroll reports.",
        # Student early warning (docs/analytics.md, A3): per school, decided
        # 2026-10-29. The test-average line is the Assessments pass mark.
        settings=(
            Setting(
                "early_warning_attendance_below", "Early warning: attendance below (%)", "int", 75, min=1, max=100,
                help="A student under this over the last 30 school days is flagged.",
            ),
            Setting(
                "early_warning_drop_points", "Early warning: a drop of (points)", "int", 10, min=1, max=100,
                help="A fall this large in attendance or test average is flagged, even above the lines.",
            ),
        ),
    ),
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

    if row is None:
        return BY_KEY[module].granted_by_default

    return row.platform_enabled and row.school_enabled


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
