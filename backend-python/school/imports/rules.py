"""Laravel's validator, as it treats one row of a spreadsheet.

The importers used to spell their checks out by hand, which was fine for
students. Four more importers make the few behaviours of Laravel's validator
that decide *which* messages a row gets worth writing down once:

- **Rules run in order, and every failing one is reported** - except that
  `unique` and `exists` are skipped once the field has already failed. An
  address that is not an address is never also "not found".
- **A blank cell runs only `required`.** Every other rule leaves an empty
  value alone.
- **`min` and `max` compare numbers only when the value is numeric.** For
  "abc" they compare its length, which is why a word in a number column earns
  "must be an integer" and nothing more.
- **Names and addresses match however they are capitalised** - see
  `matching`. Laravel's MatchesIgnoringCase.
- **A date in the form people write it** - 09/14/2026 or 9/14/2026 - and the
  message names only the first format, as Laravel's does.

Each message is Laravel's own sentence, so a row reads the same whichever
backend checked it.
"""

from __future__ import annotations

import datetime as dt
import re

from django.db.models.functions import Lower

from ..validation import (
    PHP_INTEGER,
    already_taken,
    at_least,
    at_most,
    attribute,
    bad_format,
    does_not_exist,
    must_be_an_integer,
    not_an_email,
    required,
    too_long,
)

PHP_NUMERIC = re.compile(r"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$")
EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
INTERNATIONAL_PHONE = re.compile(r"^\+[1-9][0-9 ]{6,17}$")
# PHP's date_format:m/d/Y,n/j/Y - both parts zero-padded, or neither.
PADDED_DATE = re.compile(r"^\d{2}/\d{2}/\d{4}$")
BARE_DATE = re.compile(r"^[1-9]\d?/[1-9]\d?/\d{4}$")


class Row:
    """One row's messages, gathered field by field in rule order."""

    def __init__(self, data: dict) -> None:
        self.data = data
        self.messages: list[str] = []
        self._failed: set[str] = set()

    def value(self, field: str):
        return self.data.get(field)

    def fail(self, field: str, message: str) -> None:
        self.messages.append(message)
        self._failed.add(field)

    def failed(self, field: str) -> bool:
        return field in self._failed

    # -- the rules ----------------------------------------------------------

    def text(self, field: str, max_length: int, is_required: bool = True) -> bool:
        """`required|string|max:n`, or `nullable|string|max:n`. True when there
        is a value to go on checking."""
        value = self.value(field)

        if value is None:
            if is_required:
                self.fail(field, required(field))

            return False

        if len(value) > max_length:
            self.fail(field, too_long(field, max_length))

        return True

    def present(self, field: str, is_required: bool = True) -> bool:
        value = self.value(field)

        if value is None:
            if is_required:
                self.fail(field, required(field))

            return False

        return True

    def email(self, field: str) -> None:
        if not EMAIL.match(self.value(field)):
            self.fail(field, not_an_email(field))

    def phone(self, field: str) -> None:
        if not INTERNATIONAL_PHONE.match(self.value(field)):
            self.fail(field, bad_format(field))

    def integer_between(self, field: str, low: int, high: int) -> None:
        value = self.value(field)

        if not PHP_INTEGER.match(value):
            self.fail(field, must_be_an_integer(field))

        # A numeric value is compared as a number; anything else by its length.
        size = float(value) if PHP_NUMERIC.match(value) else len(value)

        if size < low:
            self.fail(field, at_least(field, low))

        if size > high:
            self.fail(field, at_most(field, high))

    def input_date(self, field: str) -> None:
        if to_iso(self.value(field)) is None:
            self.fail(field, f"The {attribute(field)} field must match the format m/d/Y.")

    def unique(self, field: str, queryset) -> None:
        if not self.failed(field) and queryset.exists():
            self.fail(field, already_taken(field))

    def exists(self, field: str, queryset) -> None:
        if not self.failed(field) and not queryset.exists():
            self.fail(field, does_not_exist(field))


def matching(queryset, column: str, value: str):
    """The rows whose `column` is `value` ignoring case: LOWER(column) = value.

    A department typed "science" is the Science department, and an address is
    stored lowercase, so the checks have to compare the way the importers look
    things up - PostgreSQL's `=` does not.
    """
    return queryset.alias(matched=Lower(column)).filter(matched=value.strip().lower())


def to_iso(value: str | None) -> str | None:
    """09/14/2026 or 9/14/2026 as the ISO date a date column stores, or None.

    Strict the way PHP's date_format is: "09/5/2026" matches neither format,
    and a date that would roll over - the 40th of a month - is not a date.
    """
    if value is None or not (PADDED_DATE.match(value) or BARE_DATE.match(value)):
        return None

    month, day, year = (int(part) for part in value.split("/"))

    try:
        return dt.date(year, month, day).isoformat()
    except ValueError:
        return None
