"""Drains the job queue once and exits.

    python manage.py work_queue

Run from cron. Exiting rather than looping is the point: shared hosting kills
a long-running process, and a worker that has been killed mid-job is a worker
whose jobs are all reserved and none finished.

    * * * * * cd /path/to/backend-python && .venv/bin/python manage.py work_queue

Two runs overlapping is safe - see school/queue.py, where reserving a job is a
single conditional UPDATE - so the cron interval can be as short as the host
allows without anybody having to reason about it.
"""

from django.core.management.base import BaseCommand

from school import queue

# Importing the module that registers the handlers. Without this the worker
# would find rows it has no handler for and refuse them - the one failure mode
# that looks like a corrupt queue and is really a missing import.
from school import jobs  # noqa: F401


class Command(BaseCommand):
    help = "Run queued jobs until the queue is empty, then exit"

    def add_arguments(self, parser):
        parser.add_argument("--queue", default="default")
        parser.add_argument(
            "--limit",
            type=int,
            default=None,
            help="Stop after this many jobs, however many are left",
        )

    def handle(self, *args, **options):
        result = queue.work(queue=options["queue"], limit=options["limit"])

        self.stdout.write(f"done   : {result['done']}")

        if result["failed"]:
            self.stdout.write(self.style.WARNING(f"failed : {result['failed']}"))
        else:
            self.stdout.write("failed : 0")
