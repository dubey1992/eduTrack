"""The job queue.

Hosting is cPanel: cron and no broker. That makes two things worth testing
hard, because both are about what happens when cron fires again before the
last run finished.

**Reserving is a race, and it has to be won by exactly one worker.** Two
processes sending the same receipt is the failure this prevents.

**A job that throws must not take the worker down**, and must come back later
rather than immediately - a mail server having a bad morning should not be
retried five times in five seconds.
"""

from datetime import timedelta

from django.test import TestCase
from django.utils import timezone

from school import queue
from school.models import QueuedJob

RAN = []


@queue.handler("test_job")
def a_job(value: str = "") -> None:
    RAN.append(value)


@queue.handler("test_failure")
def a_failing_job() -> None:
    raise RuntimeError("the mail server is having a bad morning")


class QueueTest(TestCase):
    def setUp(self):
        RAN.clear()


class Queueing(QueueTest):
    def test_a_job_is_written_with_its_payload(self):
        job = queue.push("test_job", {"value": "hello"})

        self.assertEqual("test_job", job.name)
        self.assertEqual({"value": "hello"}, job.payload)
        self.assertEqual(0, job.attempts)
        self.assertIsNone(job.reserved_at)

    def test_a_job_nobody_can_run_is_refused_at_the_point_of_queueing(self):
        # Better to fail in the request that queued it than to leave a row
        # the worker will refuse forever.
        with self.assertRaises(KeyError):
            queue.push("no_such_job", {})

    def test_a_delayed_job_is_not_due_yet(self):
        queue.push("test_job", {"value": "later"}, delay=timedelta(minutes=5))

        self.assertIsNone(queue.reserve())


class Reserving(QueueTest):
    def test_only_one_worker_can_claim_a_job(self):
        # The whole point. Two crons overlapping must not send one receipt
        # twice.
        queue.push("test_job", {"value": "once"})

        first = queue.reserve()
        second = queue.reserve()

        self.assertIsNotNone(first)
        self.assertIsNone(second, "the second worker found nothing left to take")

    def test_a_reserved_job_is_marked_so_in_the_table(self):
        queue.push("test_job", {"value": "x"})

        job = queue.reserve()

        self.assertIsNotNone(QueuedJob.objects.get(pk=job.pk).reserved_at)

    def test_the_oldest_due_job_goes_first(self):
        queue.push("test_job", {"value": "second"}, delay=timedelta(seconds=-10))
        queue.push("test_job", {"value": "first"}, delay=timedelta(seconds=-60))

        self.assertEqual("first", queue.reserve().payload["value"])


class Running(QueueTest):
    def test_a_finished_job_leaves_no_row_behind(self):
        queue.push("test_job", {"value": "done"})

        result = queue.work()

        self.assertEqual({"done": 1, "failed": 0}, result)
        self.assertEqual(["done"], RAN)
        self.assertEqual(0, QueuedJob.objects.count())

    def test_the_queue_drains_and_then_stops(self):
        # Stopping is what makes it safe to run from cron: the process ends
        # rather than sitting in a loop the host would kill.
        for index in range(3):
            queue.push("test_job", {"value": str(index)})

        result = queue.work()

        self.assertEqual({"done": 3, "failed": 0}, result)
        self.assertEqual(["0", "1", "2"], RAN)

    def test_a_limit_stops_early(self):
        for index in range(5):
            queue.push("test_job", {"value": str(index)})

        result = queue.work(limit=2)

        self.assertEqual({"done": 2, "failed": 0}, result)
        self.assertEqual(3, QueuedJob.objects.count())


class Failing(QueueTest):
    def test_one_bad_job_does_not_stop_the_next(self):
        queue.push("test_failure", {})
        queue.push("test_job", {"value": "still ran"})

        result = queue.work()

        self.assertEqual({"done": 1, "failed": 1}, result)
        self.assertEqual(["still ran"], RAN)

    def test_a_failure_is_retried_later_rather_than_at_once(self):
        queue.push("test_failure", {})

        queue.work()

        job = QueuedJob.objects.get(name="test_failure")
        self.assertEqual(1, job.attempts)
        self.assertIsNone(job.reserved_at, "released, so a later run can take it")
        self.assertGreater(job.available_at, timezone.now(), "and not before the backoff")
        self.assertIn("bad morning", job.last_error)

    def test_the_backoff_grows(self):
        self.assertLess(queue.backoff(1), queue.backoff(2))
        self.assertLess(queue.backoff(2), queue.backoff(3))

    def test_it_gives_up_eventually_and_says_why(self):
        job = queue.push("test_failure", {})

        for _ in range(queue.MAX_ATTEMPTS):
            # Make it due again, as the backoff eventually would.
            QueuedJob.objects.filter(pk=job.pk).update(available_at=timezone.now())
            queue.work()

        exhausted = QueuedJob.objects.get(pk=job.pk)

        self.assertEqual(queue.MAX_ATTEMPTS, exhausted.attempts)
        self.assertIsNotNone(
            exhausted.reserved_at, "left reserved so no worker picks it up again"
        )
        self.assertIn("bad morning", exhausted.last_error)

        # And it no longer costs a worker anything.
        self.assertEqual({"done": 0, "failed": 0}, queue.work())

    def test_a_job_whose_handler_has_gone_is_left_alone(self):
        # Queued by a version that knew a handler this one does not. The
        # deploy that removed the handler may be the mistake, so the row stays.
        job = QueuedJob.objects.create(
            queue="default",
            name="a_handler_that_was_removed",
            payload={},
            attempts=0,
            available_at=timezone.now(),
            created_at=timezone.now(),
            updated_at=timezone.now(),
        )

        result = queue.work()

        self.assertEqual({"done": 0, "failed": 1}, result)

        left = QueuedJob.objects.get(pk=job.pk)
        self.assertIn("No handler registered", left.last_error)
        self.assertIsNotNone(left.reserved_at, "not retried - the handler is not coming back")


class SeparateQueues(QueueTest):
    def test_a_worker_only_drains_the_queue_it_was_asked_for(self):
        # Named queues exist so a slow bulk job can never sit in front of a
        # receipt.
        queue.push("test_job", {"value": "bulk"}, queue="bulk")
        queue.push("test_job", {"value": "default"})

        result = queue.work()

        self.assertEqual({"done": 1, "failed": 0}, result)
        self.assertEqual(["default"], RAN)
        self.assertEqual(1, QueuedJob.objects.filter(queue="bulk").count())
