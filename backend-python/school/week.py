"""Which days a school actually runs (docs/holidays.md).

The product is multi-nation: each school carries its own currency and its own
timezone, and now its own week. A school in the Gulf runs Sunday to Thursday;
a six-day week is ordinary in much of India. Until this existed the week was
Monday to Friday in one line of application code, so those schools had
attendance refused on their own working days, allowed on their days off, and
every rate in every report computed against a week they do not keep.

Stored as seven characters, **Monday first** - the order of `date.weekday()`,
so the index is the weekday and there is no arithmetic to get wrong. A string
rather than a bitmask because two languages and the occasional human read this
column, and '1111100' is a week anybody can check.

Each character is a day: **'0' closed, '1' a full day, '2' a half day**. One
column rather than a second mask beside it, so a day marked "half" but not
"working" is a state that cannot be written rather than a rule somebody has
to remember (docs/holidays.md, H1).

**A half day is a full working day.** It is a shorter day, not a fraction of
one: the school ran, and a teacher who was there all morning worked a full
Saturday. Nothing that counts working days cares which shape they were - what
the shape decides is which periods the day has.

**Nothing else parses that column.** Everything asks a `WorkingWeek`.
"""

from __future__ import annotations

# Monday first, matching date.weekday(). Used for labels and for validating
# what a client sends; the storage order is this order.
DAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")

# What every school had before the column existed, and what a school gets
# when nobody chooses.
DEFAULT = "1111100"

CLOSED = "0"
FULL = "1"
HALF = "2"

# The shapes a day that runs can have. A period belongs to one of them.
FULL_DAY = "full"
HALF_DAY = "half"
SHAPES = (FULL_DAY, HALF_DAY)

_SHAPE_OF = {FULL: FULL_DAY, HALF: HALF_DAY}

LENGTH = len(DAYS)


class WorkingWeek:
    """The days one school runs, as a thing that can be asked about a date."""

    __slots__ = ("_days",)

    def __init__(self, stored: str | None) -> None:
        self._days = parse(stored)

    @property
    def stored(self) -> str:
        return "".join(self._days)

    @property
    def names(self) -> list[str]:
        """The working days by name, in week order - for an API answer and
        for the timetable's columns. A half day is a working day."""
        return [name for name, day in zip(DAYS, self._days) if day != CLOSED]

    @property
    def shapes(self) -> dict[str, str]:
        """Each working day by name, to the shape it keeps."""
        return {name: _SHAPE_OF[day] for name, day in zip(DAYS, self._days) if day != CLOSED}

    def runs_on(self, date) -> bool:
        """Whether this school opens on that date, holidays aside.

        Holidays are a separate question and a separate table; this one is
        only about the shape of the week. **A half day counts**: it is a
        shorter day, not a fraction of one.
        """
        return self._days[date.weekday()] != CLOSED

    def shape_on(self, date) -> str | None:
        """`full`, `half`, or None on a day this school does not run."""
        return _SHAPE_OF.get(self._days[date.weekday()])

    def shape_of(self, day_name: str) -> str | None:
        """The same, by the name the timetable uses."""
        return self.shapes.get(day_name)

    def __len__(self) -> int:
        return sum(1 for day in self._days if day != CLOSED)

    def __eq__(self, other) -> bool:
        return isinstance(other, WorkingWeek) and other._days == self._days

    def __repr__(self) -> str:
        return f"WorkingWeek({self.stored!r})"


def parse(stored: str | None) -> tuple[str, ...]:
    """The stored column, as seven day states.

    **Anything unreadable is the default week**, not an error and not a
    school that never opens. This is asked on every attendance mark and
    every report row; a column that somebody edited by hand into nonsense
    should degrade to the week the product assumed for its first year, not
    take the school offline.
    """
    if not is_valid(stored):
        stored = DEFAULT

    return tuple(stored)


def is_valid(stored: object) -> bool:
    """What a client is allowed to send: seven of 0, 1 and 2, with at least
    one day the school runs.

    A school that runs no days at all would refuse every mark on every date
    with a message about being closed, which is indistinguishable from the
    product being broken.
    """
    return (
        isinstance(stored, str)
        and len(stored) == LENGTH
        and not set(stored) - {CLOSED, FULL, HALF}
        and set(stored) != {CLOSED}
    )
