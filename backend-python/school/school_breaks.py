"""Breaks in the school day: lunch, a short break, as many as a school rings.

A break sits between periods and is never one: it has its own table, so
nothing that counts periods - teaching reports, coverage, workload, the
teacher's day - can count it.

Two things make it easy to set up rather than fiddly:

- **What it would clash with is said by name**: "starts during Period 4
  (11:10-11:55)", not "overlap".
- **Making room.** A school whose periods run back to back has no gap for a
  lunch. Asked to, adding the break moves every later period (and break) of
  that day back by however long it takes, so nobody retypes ten bell times.
"""

from __future__ import annotations

import datetime as dt

from django.utils import timezone

from . import audit
from .models import Period, SchoolBreak



def minutes(at: dt.time) -> int:
    return at.hour * 60 + at.minute


def clock(total: int) -> dt.time:
    return dt.time(total // 60, total % 60)


def span(start: dt.time, end: dt.time) -> str:
    return f"{start.strftime('%H:%M')}-{end.strftime('%H:%M')}"


def periods_of(school_id: int, shape: str):
    return Period.objects.filter(school_id=school_id, day_shape=shape).order_by("start_time", "period_number")


def breaks_of(school_id: int, shape: str, ignoring: int | None = None):
    found = SchoolBreak.objects.filter(school_id=school_id, day_shape=shape).order_by("start_time", "id")

    return found.exclude(pk=ignoring) if ignoring is not None else found


def overlaps(start: dt.time, end: dt.time, other_start: dt.time, other_end: dt.time) -> bool:
    return start < other_end and other_start < end


def label_of(item) -> str:
    if isinstance(item, Period):
        return f"Period {item.period_number} ({span(item.start_time, item.end_time)})"

    return f"the {item.name} ({span(item.start_time, item.end_time)})"


def problem(school_id: int, shape: str, start: dt.time, end: dt.time, *, make_room: bool,
            ignoring: int | None = None) -> str | None:
    """Why a break cannot go here, or None if it can.

    Something running across the break's start can never be fixed by moving
    later things back - the break would start in the middle of it.
    """
    items = [*periods_of(school_id, shape), *breaks_of(school_id, shape, ignoring)]

    for item in items:
        if item.start_time < start < item.end_time:
            return f"It starts during {label_of(item)}. Start it when that ends, at {item.end_time.strftime('%H:%M')}."

    clashing = [item for item in items if overlaps(start, end, item.start_time, item.end_time)]

    if not clashing:
        return None

    if not make_room:
        return f"It overlaps {label_of(clashing[0])}. Choose \"Move later periods\" to make room for it."

    later = [item for item in items if item.start_time >= start]
    shift = minutes(end) - min(minutes(item.start_time) for item in later)
    last_end = max(minutes(item.end_time) for item in later)

    if last_end + shift > 23 * 60 + 59:
        return "There is no room to move the later periods back - the day would run past midnight."

    return None


def room_needed(school_id: int, shape: str, start: dt.time, end: dt.time, ignoring: int | None = None) -> int:
    """How many minutes the later periods and breaks must move back."""
    later = [
        item for item in (*periods_of(school_id, shape), *breaks_of(school_id, shape, ignoring))
        if item.start_time >= start
    ]

    if not later:
        return 0

    return max(0, minutes(end) - min(minutes(item.start_time) for item in later))


def make_room(school_id: int, shape: str, start: dt.time, end: dt.time, ignoring: int | None = None) -> int:
    """Moves every period and break from `start` on back far enough for a
    break to end at `end`. Returns the minutes moved. Each move is audited."""
    shift = room_needed(school_id, shape, start, end, ignoring)

    if shift == 0:
        return 0

    now = timezone.now()

    for item in (*periods_of(school_id, shape), *breaks_of(school_id, shape, ignoring)):
        if item.start_time < start:
            continue

        before = audit.fields_of(item)
        item.start_time = clock(minutes(item.start_time) + shift)
        item.end_time = clock(minutes(item.end_time) + shift)
        item.updated_at = now
        item.save(update_fields=["start_time", "end_time", "updated_at"])
        audit.updated("timetable", item, before)

    return shift


def clash_for_period(school_id: int, shape: str, start: dt.time, end: dt.time) -> str | None:
    """A period may not be set over a break."""
    for found in breaks_of(school_id, shape):
        if overlaps(start, end, found.start_time, found.end_time):
            return f"It overlaps {label_of(found)}. Move the break or choose other times."

    return None
