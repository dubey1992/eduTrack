"""Columns Laravel built, read by models Django would have built differently.

These exist because of a bug the M8 gate found that every other test in this
suite was structurally incapable of catching, and the shape of that blind spot
is worth keeping written down.

Laravel's columns are `timestamp without time zone` holding UTC instants. The
Django test database is built *from the models*, where Django creates
`timestamp with time zone` - so in a test the value comes back already aware
and everything works. Against the real database it comes back **naive**, and
`.astimezone()` on a naive datetime assumes the machine's local zone. On a
laptop in Asia/Kolkata every instant the API returned was five and a half
hours early.

So these tests do not go near the database for the thing they are asserting.
They hand the conversion a value shaped the way the *real* column produces it,
which is the case the test database never will.

It has happened twice now - once with timestamps, once with JSON - so the
pattern is worth naming: **any time Django's default column type differs from
Laravel's, the test suite is blind to it and `manage.py check_models` is not.**
"""

import datetime as dt

from django.test import TestCase
from django.utils import timezone

from school import factories, tokens
from school.fields import LaravelJSONField, UtcDateTimeField, as_utc
from school.queue import handler as queue_handler
from school.resources import timestamp

# 10:45:17 on the sixteenth, exactly as it sits in the column - no offset, no
# marker, nothing to say what it means except the project's convention that it
# means UTC.
AS_STORED = dt.datetime(2026, 9, 16, 10, 45, 17)


class ANaiveValueMeansUtc(TestCase):
    def test_a_naive_datetime_is_stamped_not_shifted(self):
        self.assertEqual(
            dt.datetime(2026, 9, 16, 10, 45, 17, tzinfo=dt.timezone.utc),
            as_utc(AS_STORED),
        )

    def test_an_aware_datetime_is_converted_rather_than_restamped(self):
        kolkata = dt.timezone(dt.timedelta(hours=5, minutes=30))
        aware = dt.datetime(2026, 9, 16, 16, 15, 17, tzinfo=kolkata)

        self.assertEqual(
            dt.datetime(2026, 9, 16, 10, 45, 17, tzinfo=dt.timezone.utc),
            as_utc(aware),
        )

    def test_it_is_safe_to_apply_twice(self):
        self.assertEqual(as_utc(AS_STORED), as_utc(as_utc(AS_STORED)))

    def test_nothing_stays_nothing(self):
        self.assertIsNone(as_utc(None))

    def test_the_field_stamps_what_the_driver_hands_back(self):
        # from_db_value is the only thing standing between a naive column and
        # every timestamp in the API being wrong.
        field = UtcDateTimeField()

        self.assertEqual(
            dt.datetime(2026, 9, 16, 10, 45, 17, tzinfo=dt.timezone.utc),
            field.from_db_value(AS_STORED, None, None),
        )


class TheWireFormat(TestCase):
    def test_a_stored_instant_renders_as_laravel_renders_it(self):
        # The exact string Laravel produced for this row, compared against.
        # This is the assertion that was failing in production while every
        # other test passed.
        self.assertEqual("2026-09-16T10:45:17.000000Z", timestamp(AS_STORED))

    def test_an_aware_instant_renders_the_same(self):
        self.assertEqual(
            "2026-09-16T10:45:17.000000Z",
            timestamp(AS_STORED.replace(tzinfo=dt.timezone.utc)),
        )

    def test_it_always_has_six_fractional_digits_and_a_z(self):
        # Eloquent's shape, which the Flutter client parses. Python's own
        # isoformat() drops the fraction when it happens to be zero.
        rendered = timestamp(dt.datetime(2026, 1, 2, 3, 4, 5, tzinfo=dt.timezone.utc))

        self.assertEqual("2026-01-02T03:04:05.000000Z", rendered)

    def test_nothing_stays_nothing(self):
        self.assertIsNone(timestamp(None))


class ComparingInstants(TestCase):
    def test_an_expiry_read_as_naive_does_not_raise(self):
        # Comparing a naive datetime to an aware one raises TypeError. Against
        # the real schema `expires_at` was naive, so this line would have
        # crashed on the first token anybody set an expiry on - and no test
        # would have shown it, because the test database's column is aware.
        user = factories.UserFactory()
        token = tokens.find(tokens.issue(user))

        token.expires_at = AS_STORED

        self.assertIsInstance(tokens.has_expired(token), bool)

    def test_an_expiry_in_the_past_is_expired_and_one_ahead_is_not(self):
        user = factories.UserFactory()
        token = tokens.find(tokens.issue(user))

        token.expires_at = timezone.now() - dt.timedelta(minutes=1)
        self.assertTrue(tokens.has_expired(token))

        token.expires_at = timezone.now() + dt.timedelta(minutes=1)
        self.assertFalse(tokens.has_expired(token))


class AJsonColumnMayAlreadyBeDecoded(TestCase):
    """The same trap as the naive datetimes above, in a different column type.

    Laravel's `$table->json()` makes a **`json`** column on PostgreSQL.
    Django's JSONField assumes **`jsonb`**: with psycopg3 it registers a loader
    so `jsonb` arrives as a raw string it decodes itself, and that
    registration does not cover `json`. A `json` column therefore arrives
    already decoded, and Django hands a dict to `json.loads`.

    Invisible in the suite, because the test database is built from the models
    and Django creates `jsonb`. `check_models` found it against the real one.
    """

    def test_a_value_already_decoded_is_passed_through(self):
        field = LaravelJSONField()

        self.assertEqual({"payment_id": 7}, field.from_db_value({"payment_id": 7}, None, None))
        self.assertEqual([1, 2], field.from_db_value([1, 2], None, None))

    def test_a_raw_string_is_still_decoded(self):
        # A `jsonb` column, or any backend that hands back text. Both column
        # types have to work, because the model does not know which it has.
        field = LaravelJSONField()

        self.assertEqual({"a": 1}, field.from_db_value('{"a": 1}', None, None))

    def test_nothing_stays_nothing(self):
        self.assertIsNone(LaravelJSONField().from_db_value(None, None, None))

    def test_a_queued_job_round_trips_its_payload(self):
        # The one place this is used today. A payload that came back as a
        # string would break every handler, which takes keyword arguments.
        from school import queue
        from school.models import QueuedJob

        queue.push("test_roundtrip", {"payment_id": 7, "nested": {"a": [1, 2]}})

        stored = QueuedJob.objects.get(name="test_roundtrip")

        self.assertEqual({"payment_id": 7, "nested": {"a": [1, 2]}}, stored.payload)


@queue_handler("test_roundtrip")
def _a_job(**kwargs):
    """Registered so push() accepts the name above; never run."""
