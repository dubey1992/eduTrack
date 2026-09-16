"""Reading the timestamps Laravel wrote.

One field, and it exists because of a bug the M8 gate found - the sort that
passes every test and is wrong in production.

Laravel's migrations create timestamps as `timestamp without time zone`, and
the project stores instants in UTC in them (APP_TIMEZONE is pinned to UTC; see
docs/timezones.md). A naive column is a perfectly good place to keep a UTC
instant as long as everybody agrees that is what it means.

Django does not agree by default. It expects `timestamp with time zone`, so
against the real schema psycopg hands back a **naive** datetime - and the
moment anything calls `.astimezone()` on that, Python assumes it is in the
machine's local zone and shifts it. On a developer's laptop in Asia/Kolkata
every stored instant came back five and a half hours early.

The reason it passed every Django test: the test database is built *from these
models*, where Django creates the column as `timestamp with time zone`, so the
value comes back already aware and the bug cannot appear. It only shows up
against a schema Laravel built - which is the exact gap `manage.py
check_models` exists for, and the exact reason the gate is driven through the
real app against the real database rather than through the test suite alone.

So: attach UTC on the way in, once, at the field. Every model, every module,
without anybody having to remember.
"""

from __future__ import annotations

import datetime as dt

from django.db import models

UTC = dt.timezone.utc


def as_utc(value: dt.datetime | None) -> dt.datetime | None:
    """A datetime read from the database, as an instant.

    Naive means UTC here - that is the storage convention, not a guess. An
    already-aware value is converted rather than stamped, so this is safe to
    call twice and safe to call on a column that is `timestamptz` after all
    (the test database's are).
    """
    if value is None:
        return None

    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)

    return value.astimezone(UTC)


class UtcDateTimeField(models.DateTimeField):
    """A DateTimeField that knows a naive column holds UTC."""

    def from_db_value(self, value, expression, connection):
        return as_utc(value)
