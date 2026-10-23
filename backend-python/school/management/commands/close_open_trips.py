"""Closes trips nobody ended, and tells the school (docs/driver-app.md).

    python manage.py close_open_trips

Run hourly from cron. Hourly rather than nightly because schools keep their
own timezones: midnight in Mumbai is not midnight in Dubai, and a job that
ran once a day in one of them would close the other's trips hours late - or
hours early, while a bus was still out.

A crew member who forgets to end a trip blocks the next morning's run: the
route already has one in progress, and only the office can clear it. The
driver finds that out in a yard at six, which is the worst moment and the
wrong person.
"""

from django.core.management.base import BaseCommand

from school.services import TransportTripService


class Command(BaseCommand):
    help = "Close trips still running after their own school's day has ended"

    def handle(self, *args, **options):
        outcome = TransportTripService.close_left_open()

        self.stdout.write(f"closed  : {outcome['closed']}")
        self.stdout.write(f"alerts  : {outcome['alerts']}")
