"""How a date is written wherever a person reads one.

US order - 09/29/2026 - in every message, on every receipt and payslip, in
every report heading, and on every screen (see the Flutter side's
core/utils/date_format.dart). A date that reads one way in an SMS and
another on the PDF it refers to is a date nobody can check.

This is presentation only. Anything going over the wire, into a filename or
into a query stays ISO, and must: `%m/%d/%Y` in a URL would simply be
rejected, and ISO is also the only order that sorts correctly.

It lives in one place because it did not used to. The format was a literal
copied into a dozen modules, and twice a copy drifted - the communication
log spent a year comparing the server's 09/16/2026 against a screen's
"16 Sep 2026", so "sent today" was never true.
"""

from __future__ import annotations

import datetime as dt

# The one order. Nothing else formats a date for a person to read.
DATE = "%m/%d/%Y"

# A time of day, on the 12-hour clock people here use.
TIME = "%I:%M %p"


def us(value: dt.date | dt.datetime | None) -> str:
    """09/29/2026, or a dash where there is no date."""
    return "-" if value is None else value.strftime(DATE)


def us_time(value: dt.datetime | None) -> str:
    """7:42 PM, without the leading zero a strftime pads onto the hour."""
    return "-" if value is None else value.strftime(TIME).lstrip("0")


def us_from_iso(value: str | None) -> str:
    """The same, from an ISO string the client sent or a column holds.

    Unparseable text is handed back as it came: showing a raw value beats
    showing nothing, and it makes the bad data visible instead of hiding it
    behind a dash.
    """
    if not value:
        return "-"

    try:
        return us(dt.date.fromisoformat(value))
    except ValueError:
        return value


def range_label(start, end) -> str:
    """"09/01/2026 to 09/29/2026" - the period across the top of a report."""
    return f"{us(start)} to {us(end)}"


def range_label_iso(start: str | None, end: str | None) -> str:
    """The same, from the ISO pair a built report carries.

    A report's own `range` stays ISO because the client parses it and the
    download filenames sort by it; only the heading a person reads is
    turned round.
    """
    return f"{us_from_iso(start)} to {us_from_iso(end)}"
