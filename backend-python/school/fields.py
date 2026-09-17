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


class LaravelJSONField(models.JSONField):
    """A JSONField that reads a `json` column as well as a `jsonb` one.

    The same shape of bug as the timestamps above, found the same way and
    worth the same warning.

    Laravel's `$table->json()` creates a **`json`** column on PostgreSQL.
    Django's JSONField assumes **`jsonb`**: with psycopg3 it registers a
    loader so `jsonb` arrives as a raw string, which Django then decodes
    itself. That registration does not cover `json`, so a `json` column
    arrives already decoded into a dict - and Django's `json.loads` is handed
    a dict and raises `TypeError: the JSON object must be str, bytes or
    bytearray, not dict`.

    Invisible in the test suite, because the test database is built from these
    models and Django creates `jsonb` there. It only appears against a schema
    Laravel built, which is what `manage.py check_models` is for - and is what
    caught it.

    Reading a value that has already been decoded is the whole fix. Changing
    the column to `jsonb` would also work and was rejected: it is the better
    column type, but it would make PostgreSQL and MySQL disagree about a
    type, and `schema:diff` proving those two identical is load-bearing for
    the whole migration.
    """

    def from_db_value(self, value, expression, connection):
        # Already a Python value - psycopg decoded a `json` column for us.
        if value is None or isinstance(value, (dict, list, int, float, bool)):
            return value

        return super().from_db_value(value, expression, connection)


@models.CharField.register_lookup
@models.TextField.register_lookup
class ILike(models.Lookup):
    """`column ILIKE value`, with the value's own % and _ left alone.

    Laravel's whereLike(..., caseSensitive: false) on PostgreSQL is exactly
    this, and it does not escape the term - so searching the message log for
    "%" matches everything. Django's icontains escapes both wildcards and
    would match a literal percent sign instead. Use as
    `field__ilike="%term%"`.
    """

    lookup_name = "ilike"

    def as_sql(self, compiler, connection):
        lhs, lhs_params = self.process_lhs(compiler, connection)
        rhs, rhs_params = self.process_rhs(compiler, connection)

        return f"{lhs}::text ILIKE {rhs}", [*lhs_params, *rhs_params]
