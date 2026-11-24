"""Tells each family, once a day, about today's homework for their child
(docs/mobile-apps-review.md, M8, 8.1).

    python manage.py send_homework_digest
    python manage.py send_homework_digest --school 12

Run from cron every 15 minutes. It sends only after 6 PM on the school's own
clock, and each child's family gets it at most once a day
(family_homework.send_digest). The Family app only - never SMS.
"""

from __future__ import annotations

from django.core.management.base import BaseCommand

from school import family_homework


class Command(BaseCommand):
    help = "Tell families about today's homework, in the Family app."

    def add_arguments(self, parser) -> None:
        parser.add_argument("--school", type=int, default=None, help="Only this school.")

    def handle(self, *args, **options) -> None:
        told = family_homework.send_digest(school_id=options["school"])
        self.stdout.write(f"Homework digests sent: {told}")
