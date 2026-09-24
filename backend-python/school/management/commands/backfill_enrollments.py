"""Gives students admitted before the history table existed their row in the
current academic year (docs/promotion.md).

Run once per environment before the first promotion, and harmlessly as often
as you like after that: a student who already has a row for the year is
updated in place, never duplicated.

    python manage.py backfill_enrollments
    python manage.py backfill_enrollments --school 12

A student is skipped, and counted as skipped, when there is nothing to
record: no section yet, or a school with no current year set. Neither is an
error - the row appears the moment the fact does.
"""

from __future__ import annotations

from django.core.management.base import BaseCommand

from school.models import School
from school.services import StudentEnrollmentService


class Command(BaseCommand):
    help = "Write the current year's enrollment row for students that have none."

    def add_arguments(self, parser) -> None:
        parser.add_argument(
            "--school",
            type=int,
            default=None,
            help="Only this school. The default is every school on the platform.",
        )

    def handle(self, *args, **options) -> None:
        school_id = options["school"]

        if school_id is not None and not School.objects.filter(pk=school_id).exists():
            self.stderr.write(f"No school with id {school_id}.")
            return

        counted = StudentEnrollmentService.backfill(school_id)

        where = f"school {school_id}" if school_id is not None else "every school"
        self.stdout.write(
            f"{where}: {counted['written']} enrolment rows written or confirmed, "
            f"{counted['skipped']} students skipped (no section, or no current year)."
        )
