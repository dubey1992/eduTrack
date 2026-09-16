"""Timestamps, against the schema Laravel actually built.

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
They hand the conversion a naive datetime directly, which is the case the test
database will never produce.
"""

import datetime as dt

from django.test import TestCase
from django.utils import timezone

from school import factories, tokens
from school.fields import UtcDateTimeField, as_utc
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
