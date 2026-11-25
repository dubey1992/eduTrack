"""Reminds families and teachers of tomorrow's parent-teacher meetings
(docs/mobile-apps-review.md, M12, 8.4).

    python manage.py send_ptm_reminders
    python manage.py send_ptm_reminders --school 12

Run from cron every 15 minutes. It sends only after 5 PM on the school's own
clock, the evening before, and each family and teacher is told once
(ptm.send_reminders). The Family app and the staff inbox - never SMS.
"""

from __future__ import annotations

from django.core.management.base import BaseCommand

from school import ptm


class Command(BaseCommand):
    help = "Remind families and teachers of tomorrow's parent-teacher meetings."

    def add_arguments(self, parser) -> None:
        parser.add_argument("--school", type=int, default=None, help="Only this school.")

    def handle(self, *args, **options) -> None:
        told = ptm.send_reminders(school_id=options["school"])
        self.stdout.write(f"Meeting reminders sent: {told}")
