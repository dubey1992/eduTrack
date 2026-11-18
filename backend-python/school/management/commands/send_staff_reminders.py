"""Reminds staff of the day's register, check-in and teaching reports
(docs/mobile-apps-review.md, 5.1).

    python manage.py send_staff_reminders
    python manage.py send_staff_reminders --school 12

Run from cron every 15 minutes: each reminder is due at a moment of the
school's own day (the first period's end, 30 minutes into it, the last
period's end), so a quarter-hour run sends it within 15 minutes of then.
Idempotent - each person gets each reminder at most once a school day
(staff_reminders.already_reminded). Each school switches each reminder on in
Settings -> Modules; they are off for schools that were already live.

The inbox rows are written here; the push copies go through the queue
worker (`work_queue`).
"""

from __future__ import annotations

from django.core.management.base import BaseCommand

from school import staff_reminders


class Command(BaseCommand):
    help = "Remind staff of registers not taken, check-ins missed and teaching reports still owed."

    def add_arguments(self, parser) -> None:
        parser.add_argument("--school", type=int, default=None, help="Only this school.")

    def handle(self, *args, **options) -> None:
        sent = staff_reminders.send(school_id=options["school"])
        self.stdout.write(f"Staff reminders sent: {sent}")
