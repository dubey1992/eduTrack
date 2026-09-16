"""Work the API defers, and the worker that drains it.

Hosting is cPanel (docs/python-migration.md, M0): cron and no broker. So this
is a database queue drained by a management command a cron calls, which is the
same shape Laravel runs today (`QUEUE_CONNECTION=database` plus
`queue:work --stop-when-empty`). Not a limitation being worked around - the
requirement.

Two rules make it safe to run from cron, where two invocations can overlap if
one run takes longer than the gap between them:

- **A job is reserved before it runs**, in a single statement that only
  succeeds if nobody else has reserved it. Two workers racing for the same row
  means one of them gets it and the other moves on, rather than both sending
  the same receipt.
- **A job that throws is retried with a backoff**, and after enough attempts
  is left reserved with its error on the row. It stops costing a worker on
  every pass, and it is visible in the table rather than only in a log.

Handlers are registered by name. The payload carries ids, never records: a job
that carried a copy of a payment would act on what was true when it was queued
rather than what is true when it runs.
"""

from __future__ import annotations

import logging
import traceback
from datetime import timedelta

from django.db import transaction
from django.utils import timezone

from .models import QueuedJob

logger = logging.getLogger(__name__)

# Enough for a mail server having a bad morning, not so many that a job which
# can never succeed is retried forever.
MAX_ATTEMPTS = 5

# How long to wait after each failure: a minute, then four, then nine. Squared
# rather than doubled - gentler early, which is where a transient failure
# usually is.
def backoff(attempts: int) -> timedelta:
    return timedelta(minutes=attempts * attempts)


HANDLERS: dict[str, callable] = {}


def handler(name: str):
    """Registers a handler under the name jobs are queued with."""

    def register(function):
        HANDLERS[name] = function

        return function

    return register


def push(name: str, payload: dict, queue: str = "default", delay: timedelta | None = None) -> QueuedJob:
    """Queues a job. Returns the row, so a caller can assert on it.

    Deliberately not "dispatch after the response": the row is written inside
    whatever transaction the caller is in, so a job is queued if and only if
    the work that asked for it was committed.
    """
    if name not in HANDLERS:
        raise KeyError(f"No handler registered for the job {name!r}")

    now = timezone.now()

    return QueuedJob.objects.create(
        queue=queue,
        name=name,
        payload=payload,
        attempts=0,
        available_at=now + (delay or timedelta()),
        created_at=now,
        updated_at=now,
    )


def reserve(queue: str = "default") -> QueuedJob | None:
    """Claims the next due job, or None.

    The UPDATE is the lock. Filtering on `reserved_at=None` inside the same
    statement that sets it means two workers cannot both win: the second one
    updates zero rows and looks again.
    """
    now = timezone.now()

    while True:
        candidate = (
            QueuedJob.objects.filter(
                queue=queue, reserved_at__isnull=True, available_at__lte=now
            )
            .order_by("available_at", "id")
            .values_list("id", flat=True)
            .first()
        )

        if candidate is None:
            return None

        claimed = QueuedJob.objects.filter(pk=candidate, reserved_at__isnull=True).update(
            reserved_at=now, updated_at=now
        )

        if claimed:
            return QueuedJob.objects.get(pk=candidate)

        # Somebody else took it between the read and the update. Look again
        # rather than giving up - there may be more work behind it.


def run(job: QueuedJob) -> bool:
    """Runs one reserved job. True if it succeeded.

    A handler that throws is not allowed to take the worker down with it: the
    next job in the queue has nothing to do with this one's bad day.
    """
    function = HANDLERS.get(job.name)

    if function is None:
        # A job queued by a version that knew a handler this one does not.
        # Left in place rather than deleted: the deploy that removed the
        # handler may be the mistake.
        fail(job, f"No handler registered for the job {job.name!r}", retry=False)

        return False

    try:
        with transaction.atomic():
            function(**job.payload)
    except Exception:
        fail(job, traceback.format_exc())

        return False

    job.delete()

    return True


def fail(job: QueuedJob, error: str, retry: bool = True) -> None:
    attempts = job.attempts + 1
    now = timezone.now()

    if retry and attempts < MAX_ATTEMPTS:
        QueuedJob.objects.filter(pk=job.pk).update(
            attempts=attempts,
            last_error=error[-2000:],
            reserved_at=None,
            available_at=now + backoff(attempts),
            updated_at=now,
        )

        logger.warning("Job %s failed, attempt %s of %s", job.name, attempts, MAX_ATTEMPTS)

        return

    # Out of attempts. Left reserved so no worker picks it up again, with the
    # error on the row where somebody looking at the queue will see it.
    QueuedJob.objects.filter(pk=job.pk).update(
        attempts=attempts, last_error=error[-2000:], reserved_at=now, updated_at=now
    )

    logger.error("Job %s gave up after %s attempts", job.name, attempts)


def work(queue: str = "default", limit: int | None = None) -> dict:
    """Drains the queue and returns what happened.

    Stops when there is nothing due, which is what makes it safe to run from
    cron: the process ends rather than sitting in a loop the host would kill.
    """
    done = failed = 0

    while limit is None or done + failed < limit:
        job = reserve(queue)

        if job is None:
            break

        if run(job):
            done += 1
        else:
            failed += 1

    return {"done": done, "failed": failed}
