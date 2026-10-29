"""Writes down each school's roll and what it is owed, for analytics
(docs/analytics.md, A1).

    python manage.py record_analytics_snapshots              # every active school
    python manage.py record_analytics_snapshots --school 12

These are the figures the database cannot count again for a past day: a
student who leaves keeps no leaving date, and a fee due keeps only what has
been paid so far. So they are recorded, once per school per day, and the
"students on roll" and "fees outstanding" charts are drawn from them.

Run hourly from cron, like the late fines: each school's day is its own, so
the snapshot is dated by the school's calendar, and the last run of a day is
the one that stands. Idempotent - a second run on the same day replaces that
day's figures rather than adding to them.
"""

from __future__ import annotations

from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from school.analytics import record_snapshot
from school.clock import SchoolClock
from school.enums import SchoolStatus
from school.models import School


class Command(BaseCommand):
    help = "Record today's roll and fees owed for each school, for the analytics charts."

    def add_arguments(self, parser) -> None:
        parser.add_argument("--school", type=int, default=None, help="Only this school.")

    def handle(self, *args, **options) -> None:
        if options["school"] is not None:
            if not School.objects.filter(pk=options["school"]).exists():
                raise CommandError(f"No school with id {options['school']}.")

            school_ids = [options["school"]]
        else:
            school_ids = list(
                School.objects.filter(status=SchoolStatus.ACTIVE).order_by("id").values_list("id", flat=True)
            )

        now = timezone.now()

        for school_id in school_ids:
            day = SchoolClock.for_school(school_id).now().date()
            record_snapshot(school_id, day, now)
            self.stdout.write(f"School {school_id}: recorded for {day.isoformat()}.")

        self.stdout.write(f"schools recorded : {len(school_ids)}")
