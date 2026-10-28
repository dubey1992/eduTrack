"""Reminds guardians of fees falling due and fees just overdue (docs/fees.md, F5).

    python manage.py send_fee_reminders                 # every school with fees on
    python manage.py send_fee_reminders --school 12
    python manage.py send_fee_reminders --school 12 --dry-run

Run hourly from cron, like apply_late_fines: schools keep their own
timezones, so "today" begins at midnight in each school's zone, not the
server's. Idempotent - each guardian gets at most one reminder of each kind
per school-local day (fee_reminder_logs), so the other 23 runs of the day
send nothing.

The command only records the messages and queues them; the queue worker
(`work_queue`) talks to the SMS, WhatsApp and email providers, so a slow
provider never holds this up. `--dry-run` reports who would be reminded and
writes nothing.

A school is reminded only with the fees and Communication modules on, and
`reminder_days_before` above 0 or `remind_when_overdue` on (Settings ->
Modules -> Fee Management).
"""

from __future__ import annotations

from django.core.management.base import BaseCommand, CommandError

from school import dates
from school.fees.fines import schools_with_fines
from school.fees.reminders import FeeReminderService
from school.models import School


class Command(BaseCommand):
    help = "Remind guardians of fees due soon and fees that have just become overdue."

    def add_arguments(self, parser) -> None:
        parser.add_argument("--school", type=int, default=None, help="Only this school.")
        parser.add_argument("--dry-run", action="store_true", help="Say who would be reminded; send nothing.")

    def handle(self, *args, **options) -> None:
        dry_run = options["dry_run"]

        if options["school"] is not None:
            if not School.objects.filter(pk=options["school"]).exists():
                raise CommandError(f"No school with id {options['school']}.")

            school_ids = [options["school"]]
        else:
            # Every school with the fees module on - the same list the late
            # fines job works through.
            school_ids = schools_with_fines()

        if not school_ids:
            self.stdout.write("No school has fees switched on. Nothing to do.")
            return

        guardians = messages = 0

        for school_id in school_ids:
            run = FeeReminderService.send(school_id, dry_run=dry_run)

            if run.skipped:
                self.stdout.write(f"School {school_id}: nothing sent ({run.skipped}).")
                continue

            guardians += run.guardians
            messages += run.messages
            self.stdout.write(f"School {school_id}: {self.describe(run, dry_run)}")

        verb = "would be reminded" if dry_run else "reminded"
        self.stdout.write(f"guardians {verb} : {guardians}")

        if not dry_run:
            self.stdout.write(f"messages recorded : {messages}")

    @staticmethod
    def describe(run, dry_run: bool) -> str:
        parts = []

        if run.upcoming_date is not None:
            parts.append(f"{run.upcoming} upcoming (due {dates.us(run.upcoming_date)})")

        if run.overdue_date is not None:
            parts.append(f"{run.overdue} overdue (due {dates.us(run.overdue_date)})")

        line = f"today {dates.us(run.today)}, " + " and ".join(parts)
        line += f" - {run.students} students, {run.dues} dues"
        line += " (dry run, nothing sent)" if dry_run else f", {run.messages} messages recorded"

        if run.already_sent:
            line += f"; {run.already_sent} already reminded today"

        return line + "."
