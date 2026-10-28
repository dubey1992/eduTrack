"""Brings every student's fee dues in line with the published fees, for one
school (docs/fees.md, F2).

For repairs, and for the first production run after F2 ships: fees
published before the dues table existed charged nobody, and this charges
them. Idempotent - a second run changes nothing.

    python manage.py sync_fee_dues --school 12
    python manage.py sync_fee_dues --school 12 --year 34

Without --year it covers every academic year of the school that has a
published fee. Every student enrolled in a year is reconciled for that year,
in batches, each batch its own transaction. "Today" is the school's date, so
dues already due stay owed exactly as they would in the app.
"""

from __future__ import annotations

from django.core.management.base import BaseCommand, CommandError

from school.enums import FeeStructureStatus
from school.fees.dues import FeeDueService, PublishedFees, SyncResult
from school.models import AcademicYear, FeeStructure, School, StudentEnrollment

BATCH = 200


class Command(BaseCommand):
    help = "Charge, re-price and cancel students' fee dues from the published fees of one school."

    def add_arguments(self, parser) -> None:
        parser.add_argument("--school", type=int, required=True, help="The school to reconcile.")
        parser.add_argument(
            "--year", type=int, default=None,
            help="Only this academic year. The default is every year of the school with a published fee.",
        )

    def handle(self, *args, **options) -> None:
        school_id = options["school"]

        if not School.objects.filter(pk=school_id).exists():
            raise CommandError(f"No school with id {school_id}.")

        years = AcademicYear.objects.filter(school_id=school_id).order_by("start_date")

        if options["year"] is not None:
            years = years.filter(pk=options["year"])

            if not years.exists():
                raise CommandError(f"School {school_id} has no academic year with id {options['year']}.")
        else:
            published = FeeStructure.objects.filter(school_id=school_id, status=FeeStructureStatus.PUBLISHED)
            years = years.filter(pk__in=published.values("academic_year_id"))

        total = SyncResult()
        years = list(years)

        if not years:
            self.stdout.write(f"School {school_id}: no academic year with a published fee. Nothing to do.")
            return

        for year in years:
            ids = list(
                StudentEnrollment.objects.filter(academic_year_id=year.id)
                .order_by("student_id")
                .values_list("student_id", flat=True)
            )
            fees = PublishedFees(year)
            result = SyncResult()

            for start in range(0, len(ids), BATCH):
                result.add(FeeDueService.sync_many(ids[start:start + BATCH], year, fees))

            # One audit row per year that changed - a repair is an action too.
            FeeDueService.audit(result, entity_type="academic_year", entity_id=year.id, school_id=school_id,
                                actor=None)
            total.add(result)
            self.stdout.write(f"{year.name} (id {year.id}): {len(ids)} students enrolled; {self.describe(result)}")

        self.stdout.write(f"School {school_id}: {self.describe(total)}")

    @staticmethod
    def describe(result: SyncResult) -> str:
        counts = result.counts()

        return (
            f"{counts['created']} dues created, {counts['revived']} revived, {counts['cancelled']} cancelled, "
            f"{counts['updated']} updated."
        )
