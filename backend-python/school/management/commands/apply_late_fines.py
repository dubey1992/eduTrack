"""Adds the late fine to every installment still owed past its grace period
(docs/fees.md, F4).

    python manage.py apply_late_fines             # every school with fines on
    python manage.py apply_late_fines --school 12

Run hourly from cron. Hourly rather than nightly because schools keep their
own timezones: the day an installment becomes overdue starts at midnight in
the school's zone, not the server's. Idempotent - an installment is fined
once, ever, so a run that finds nothing new changes nothing.

A school is fined only with the fees module on and `late_fine_amount` above
0 (Settings -> Modules -> Fee Management).
"""

from __future__ import annotations

from django.core.management.base import BaseCommand, CommandError

from school.fees.fines import LateFineService, schools_with_fines
from school.models import School


class Command(BaseCommand):
    help = "Add one late fine to each installment still unpaid past the school's grace period."

    def add_arguments(self, parser) -> None:
        parser.add_argument("--school", type=int, default=None, help="Only this school.")

    def handle(self, *args, **options) -> None:
        if options["school"] is not None:
            if not School.objects.filter(pk=options["school"]).exists():
                raise CommandError(f"No school with id {options['school']}.")

            school_ids = [options["school"]]
        else:
            school_ids = schools_with_fines()

        if not school_ids:
            self.stdout.write("No school has fees switched on. Nothing to do.")
            return

        total = 0

        for school_id in school_ids:
            run = LateFineService.apply(school_id)

            if run.skipped:
                self.stdout.write(f"School {school_id}: nothing fined ({run.skipped}).")
                continue

            total += run.fines
            self.stdout.write(
                f"School {school_id}: {run.fines} fines of {run.amount} added for {run.students} students."
            )

        self.stdout.write(f"fines added : {total}")
