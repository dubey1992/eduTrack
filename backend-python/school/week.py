"""Which days a school actually runs (docs/holidays.md).

The product is multi-nation: each school carries its own currency and its own
timezone, and now its own week. A school in the Gulf runs Sunday to Thursday;
a six-day week is ordinary in much of India. Until this existed the week was
Monday to Friday in one line of application code, so those schools had
attendance refused on their own working days, allowed on their days off, and
every rate in every report computed against a week they do not keep.

Stored as seven characters of '1' and '0', **Monday first** - the order of
`date.weekday()`, so the index is the weekday and there is no arithmetic to
get wrong. A string rather than a bitmask because two languages and the
occasional human read this column, and '1111100' is a week anybody can check.

**Nothing else parses that column.** Everything asks a `WorkingWeek`.
"""

from __future__ import annotations

# Monday first, matching date.weekday(). Used for labels and for validating
# what a client sends; the storage order is this order.
DAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")

# What every school had before the column existed, and what a school gets
# when nobody chooses.
DEFAULT = "1111100"

LENGTH = len(DAYS)


class WorkingWeek:
    """The days one school runs, as a thing that can be asked about a date."""

    __slots__ = ("_days",)

    def __init__(self, stored: str | None) -> None:
        self._days = parse(stored)

    @property
    def stored(self) -> str:
        return "".join("1" if day else "0" for day in self._days)

    @property
    def names(self) -> list[str]:
        """The working days by name, in week order - for an API answer and
        for the timetable's columns."""
        return [name for name, working in zip(DAYS, self._days) if working]

    def runs_on(self, date) -> bool:
        """Whether this school opens on that date, holidays aside.

        Holidays are a separate question and a separate table; this one is
        only about the shape of the week.
        """
        return self._days[date.weekday()]

    def __len__(self) -> int:
        return sum(self._days)

    def __eq__(self, other) -> bool:
        return isinstance(other, WorkingWeek) and other._days == self._days

    def __repr__(self) -> str:
        return f"WorkingWeek({self.stored!r})"


def parse(stored: str | None) -> tuple[bool, ...]:
    """The stored column, as seven booleans.

    **Anything unreadable is the default week**, not an error and not a
    school that never opens. This is asked on every attendance mark and
    every report row; a column that somebody edited by hand into nonsense
    should degrade to the week the product assumed for its first year, not
    take the school offline.
    """
    if not isinstance(stored, str) or len(stored) != LENGTH or set(stored) - {"0", "1"} or "1" not in stored:
        stored = DEFAULT

    return tuple(character == "1" for character in stored)


def is_valid(stored: object) -> bool:
    """What a client is allowed to send: seven of 0 and 1, at least one day.

    A school that runs no days at all would refuse every mark on every date
    with a message about being closed, which is indistinguishable from the
    product being broken.
    """
    return (
        isinstance(stored, str)
        and len(stored) == LENGTH
        and not set(stored) - {"0", "1"}
        and "1" in stored
    )
