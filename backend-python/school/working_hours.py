"""How long somebody was at work.

Ported from App\Support\WorkingHours. Formats a check-in and check-out pair
as "7h 25m", or nothing when either side is missing - half a pair says nothing
about a day, and "0h 0m" would read as a day nobody worked rather than a day
nobody recorded.
"""

from __future__ import annotations

import datetime as dt


def format_span(check_in, check_out) -> str | None:
    if check_in is None or check_out is None:
        return None

    minutes = int((as_time(check_out) - as_time(check_in)).total_seconds() // 60)

    return f"{minutes // 60}h {minutes % 60}m"


def as_time(value) -> dt.timedelta:
    """A clock time as a span from midnight, so two of them can be subtracted."""
    if isinstance(value, dt.time):
        return dt.timedelta(hours=value.hour, minutes=value.minute)

    parts = str(value).split(":")

    return dt.timedelta(hours=int(parts[0]), minutes=int(parts[1]))


def clock(value) -> str | None:
    '''"08:05" - the form a timetable and a register show, never "08:05:00".'''
    if value is None:
        return None

    if isinstance(value, dt.time):
        return value.strftime("%H:%M")

    return str(value)[:5]
