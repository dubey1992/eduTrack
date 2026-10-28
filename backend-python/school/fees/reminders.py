"""Automatic fee reminders: step F5 (docs/fees.md).

Two kinds, each judged on the school's own date (docs/timezones.md):

- **upcoming** - `reminder_days_before` days before a due date (0 turns
  these off): every due still owed that falls due on today + N;
- **overdue** - once, on the first day a due is overdue
  (`remind_when_overdue`): every due still owed that fell due yesterday.

"Still owed" is what the rest of Fees means by it: pending or part-paid with
something left to pay - a due a discount covers in full owes nothing and is
never mentioned - of a student who is active and has not left in that due's
year. Late fines count like any other due.

**One message per guardian per day per kind.** A school's dues are grouped
by guardian - the guardian's mobile with everything but the digits taken
out, else their email, else the student alone - so two brothers with one
mother's number get one text naming both, every due and the total, not
three. Each guardian reminded is written to `fee_reminder_logs` in the same
transaction as their messages; the unique key on (school, guardian, kind,
day) is what makes a second run the same day send nothing, even when two
runs overlap.

Sent through the Communication pipeline (school/notifications.py), as every
other alert is: the school's fee reminder wording, its switched-on channels
and providers, the message log, and the queue - the job only records rows
and queues them; the worker talks to the providers. With the Communication
module switched off nothing is sent and nothing is logged, here or in the
message log, exactly as for a switched-off alert.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import re
from dataclasses import dataclass, field
from decimal import Decimal

from django.db import IntegrityError, transaction
from django.db.models import Exists, F, OuterRef
from django.utils import timezone

from .. import audit, dates, modules, money, notifications
from ..clock import SchoolClock
from ..enums import EnrollmentStatus, MessageEvent, StudentStatus
from ..models import FeeReminderLog, StudentEnrollment, StudentFeeDue
from .dues import OPEN
from .ledger import balance_of

MODULE = "fees"
UPCOMING = "upcoming"
OVERDUE = "overdue"
KEY_MAX = 120
SUBJECT = "Fee reminder"


@dataclass
class Reminder:
    """One guardian's message: the students it names and their dues."""

    key: str
    dues: list = field(default_factory=list)

    @property
    def students(self) -> list:
        seen = {}
        for due in self.dues:
            seen.setdefault(due.student_id, due.student)

        return sorted(seen.values(), key=lambda student: (student.name.lower(), student.id))


@dataclass
class ReminderRun:
    """What one school's run did - or, on a dry run, would do - or why it did
    nothing."""

    school_id: int
    today: dt.date | None = None
    upcoming_date: dt.date | None = None
    overdue_date: dt.date | None = None
    upcoming: int = 0
    overdue: int = 0
    already_sent: int = 0
    students: int = 0
    dues: int = 0
    messages: int = 0
    skipped: str | None = None

    @property
    def guardians(self) -> int:
        return self.upcoming + self.overdue


def guardian_key(student) -> str:
    """Who a reminder goes to: siblings sharing a guardian's mobile (or, with
    none, email) share a key; a student with neither is on their own."""
    digits = re.sub(r"\D", "", student.guardian_mobile or "")

    if digits:
        return f"m:{digits}"[:KEY_MAX]

    email = (student.guardian_email or "").strip().lower()

    if email:
        key = f"e:{email}"
        # An address longer than the column is hashed rather than cut, so two
        # long addresses sharing a beginning never collide.
        return key if len(key) <= KEY_MAX else f"e#{hashlib.sha256(email.encode()).hexdigest()}"

    return f"s:{student.id}"


def owed_on(school_id: int, day: dt.date):
    """The school's dues still owed that fall due on `day`, of students still
    being charged - with the student and fee type, oldest first."""
    left = StudentEnrollment.objects.filter(
        student_id=OuterRef("student_id"), academic_year_id=OuterRef("academic_year_id"),
        status=EnrollmentStatus.LEFT,
    )

    return (
        StudentFeeDue.objects.filter(
            school_id=school_id,
            status__in=OPEN,
            due_date=day,
            amount__gt=F("discount_amount") + F("paid_amount"),
            student__status=StudentStatus.ACTIVE,
        )
        .exclude(Exists(left))
        .select_related("student", "fee_head")
        .order_by("student_id", "due_date", "id")
    )


def grouped(dues) -> list[Reminder]:
    """The dues by guardian, in a stable order."""
    reminders: dict[str, Reminder] = {}

    for due in dues:
        key = guardian_key(due.student)
        reminders.setdefault(key, Reminder(key)).dues.append(due)

    return [reminders[key] for key in sorted(reminders)]


def names(students) -> str:
    """"Aarav Shah", "Aarav Shah and Diya Shah", "A, B and C"."""
    shown = [student.name for student in students]

    return shown[0] if len(shown) == 1 else f"{', '.join(shown[:-1])} and {shown[-1]}"


def totals(dues) -> str:
    """What is owed, per currency, never added across two."""
    sums: dict[str, Decimal] = {}

    for due in dues:
        sums[due.currency_code] = sums.get(due.currency_code, Decimal("0.00")) + balance_of(due)

    return " + ".join(money.formatted(amount, code) for code, amount in sorted(sums.items()))


def details(reminder: Reminder, kind: str) -> str:
    """The `{fee_details}` token: each student, each due and what is left on
    it. "Now overdue." first on an overdue reminder, whose due date has
    passed."""
    parts = []

    for student in reminder.students:
        lines = ", ".join(
            f"{due.label} {money.formatted(balance_of(due), due.currency_code)}"
            for due in reminder.dues
            if due.student_id == student.id
        )
        parts.append(f"{student.name}: {lines}.")

    text = " ".join(parts)

    return f"Now overdue. {text}" if kind == OVERDUE else text


def tokens_for(reminder: Reminder, kind: str, day: dt.date) -> dict:
    return {
        "student_name": names(reminder.students),
        "amount": totals(reminder.dues),
        "due_date": dates.us(day),
        "fee_details": details(reminder, kind),
    }


class FeeReminderService:
    @classmethod
    def send(cls, school_id: int, dry_run: bool = False) -> ReminderRun:
        """One school's reminders for its today. Idempotent per day."""
        run = ReminderRun(school_id=school_id)

        if not modules.is_enabled(school_id, MODULE):
            run.skipped = "fees module off"
            return run

        if not modules.is_enabled(school_id, "communication"):
            # Nothing sent and nothing logged, like a switched-off alert.
            run.skipped = "communication module off"
            return run

        settings = modules.settings_for(school_id, MODULE)
        days_before = int(settings["reminder_days_before"])
        when_overdue = bool(settings["remind_when_overdue"])

        if days_before <= 0 and not when_overdue:
            run.skipped = "reminders switched off"
            return run

        run.today = SchoolClock.for_school(school_id).now().date()
        kinds = []

        if days_before > 0:
            run.upcoming_date = run.today + dt.timedelta(days=days_before)
            kinds.append((UPCOMING, run.upcoming_date))

        if when_overdue:
            run.overdue_date = run.today - dt.timedelta(days=1)
            kinds.append((OVERDUE, run.overdue_date))

        students: set[int] = set()

        for kind, day in kinds:
            reminders = grouped(owed_on(school_id, day))
            done = set(
                FeeReminderLog.objects.filter(
                    school_id=school_id, kind=kind, reminder_date=run.today,
                    guardian_key__in=[reminder.key for reminder in reminders],
                ).values_list("guardian_key", flat=True)
            )

            for reminder in reminders:
                if reminder.key in done:
                    run.already_sent += 1
                    continue

                sent = 0 if dry_run else cls._remind(school_id, reminder, kind, day, run.today)

                if sent is None:
                    # Another run got there first.
                    run.already_sent += 1
                    continue

                run.messages += sent
                setattr(run, kind, getattr(run, kind) + 1)
                run.dues += len(reminder.dues)
                students |= {student.id for student in reminder.students}

        run.students = len(students)

        if run.guardians and not dry_run:
            # One row per school per run that reminded anybody.
            audit.record(
                actor=None, action="fee_reminders.sent", module=MODULE, entity_type="school",
                entity_id=school_id, school_id=school_id,
                new={
                    "date": run.today.isoformat(),
                    "upcoming": run.upcoming, "upcoming_due_date": iso(run.upcoming_date),
                    "overdue": run.overdue, "overdue_due_date": iso(run.overdue_date),
                    "students": run.students, "dues": run.dues, "messages": run.messages,
                },
            )

        return run

    @staticmethod
    def _remind(school_id: int, reminder: Reminder, kind: str, day: dt.date, today: dt.date) -> int | None:
        """Logs the reminder and records its messages, together - or returns
        None when the log says this guardian was reminded already."""
        students = reminder.students
        lead = students[0]

        with transaction.atomic():
            try:
                with transaction.atomic():
                    FeeReminderLog.objects.create(
                        school_id=school_id,
                        guardian_key=reminder.key,
                        kind=kind,
                        reminder_date=today,
                        student_ids=",".join(str(student.id) for student in students),
                        dues_count=len(reminder.dues),
                        created_at=timezone.now(),
                    )
            except IntegrityError:
                return None

            # The guardian is reached on the lead student's contact details -
            # the same number (or address) every sibling in the group shares.
            messages = notifications.notify_guardian(
                MessageEvent.FEE_REMINDER, lead, tokens_for(reminder, kind, day), subject=SUBJECT
            )

        return len(messages)


def iso(day: dt.date | None) -> str | None:
    return None if day is None else day.isoformat()
