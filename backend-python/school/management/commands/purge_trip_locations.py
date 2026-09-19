"""Deletes bus positions older than the retention period (docs/maps.md).

    python manage.py purge_trip_locations            # older than 30 days
    python manage.py purge_trip_locations --days 7

Run daily from cron. Positions say where a named attendant was, minute by
minute; nobody needs that a month later, so it is not kept.
"""

from django.core.management.base import BaseCommand

from school.services import TripLocationService


class Command(BaseCommand):
    help = "Delete trip positions older than the retention period"

    def add_arguments(self, parser):
        parser.add_argument("--days", type=int, default=None, help="Keep this many days instead of 30")

    def handle(self, *args, **options):
        deleted = TripLocationService.purge(options["days"])

        self.stdout.write(f"deleted : {deleted}")
