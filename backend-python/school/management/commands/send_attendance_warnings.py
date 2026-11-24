"""Tells families when their child's attendance falls below the school's
early-warning line (docs/mobile-apps-review.md, M8, 5.4).

    python manage.py send_attendance_warnings
    python manage.py send_attendance_warnings --school 12

Run from cron every 15 minutes with the homework digest. It works only after
6 PM on the school's clock, tells each family once per drop below the line
(attendance_warnings.check), and never by SMS.
"""

from __future__ import annotations

from django.core.management.base import BaseCommand

from school import attendance_warnings


class Command(BaseCommand):
    help = "Warn families, in the Family app, when attendance falls below the school's line."

    def add_arguments(self, parser) -> None:
        parser.add_argument("--school", type=int, default=None, help="Only this school.")

    def handle(self, *args, **options) -> None:
        warned = attendance_warnings.check(school_id=options["school"])
        self.stdout.write(f"Attendance warnings sent: {warned}")
