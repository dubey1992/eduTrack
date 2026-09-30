"""One order for every date a person reads (docs/reports.md).

The helper's own behaviour, and a sweep that keeps the format from being
copied back out into the modules it came from. It was a literal in a dozen
places once, and drift is exactly what that invites: the communication log
spent a year comparing the server's 09/16/2026 against a screen writing
"16 Sep 2026", so "sent today" was never true.
"""

from __future__ import annotations

import datetime as dt
import pathlib
import re

from django.test import SimpleTestCase

from school import dates

SOURCE = pathlib.Path(__file__).resolve().parent.parent

# Where the format itself is allowed to be spelled out.
HOME = {"dates.py"}

# Reading a date is presentation; these are not. ISO on the wire, in a
# filename and in a query, and %A/%b for a weekday or a chart label.
WIRE = re.compile(r'strftime\(\s*["\'](%Y-%m-%d|%Y-%m|%Y-%m-%dT|%H:%M|%A|%b %d|%I:%M %p)')


class DateHelperTest(SimpleTestCase):
    def test_a_date_is_month_day_year(self):
        self.assertEqual("09/29/2026", dates.us(dt.date(2026, 9, 29)))

    def test_a_datetime_reads_the_same_way(self):
        self.assertEqual("09/29/2026", dates.us(dt.datetime(2026, 9, 29, 19, 42)))

    def test_nothing_reads_as_a_dash(self):
        self.assertEqual("-", dates.us(None))
        self.assertEqual("-", dates.us_time(None))
        self.assertEqual("-", dates.us_from_iso(None))
        self.assertEqual("-", dates.us_from_iso(""))

    def test_the_hour_loses_the_padding_strftime_adds(self):
        self.assertEqual("7:42 PM", dates.us_time(dt.datetime(2026, 9, 29, 19, 42)))
        self.assertEqual("12:05 AM", dates.us_time(dt.datetime(2026, 9, 29, 0, 5)))

    def test_an_iso_string_is_turned_round(self):
        self.assertEqual("09/29/2026", dates.us_from_iso("2026-09-29"))

    def test_text_that_is_not_a_date_is_handed_back_rather_than_swallowed(self):
        """Showing the raw value makes bad data visible; a dash hides it."""
        self.assertEqual("whenever", dates.us_from_iso("whenever"))

    def test_a_period_reads_as_one_phrase(self):
        self.assertEqual("09/01/2026 to 09/29/2026", dates.range_label(dt.date(2026, 9, 1), dt.date(2026, 9, 29)))
        self.assertEqual("09/01/2026 to 09/29/2026", dates.range_label_iso("2026-09-01", "2026-09-29"))


class DateFormatSweepTest(SimpleTestCase):
    def test_no_module_spells_the_display_format_out_for_itself(self):
        offenders = []

        for path in SOURCE.rglob("*.py"):
            if path.name in HOME or "tests" in path.parts or "migrations" in path.parts:
                continue

            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
                if "%m/%d/%Y" in line or "%d/%m/%Y" in line:
                    offenders.append(f"{path.relative_to(SOURCE)}:{number}")

        self.assertEqual([], offenders, "use school.dates so every date reads the same way")

    def test_every_other_strftime_is_a_wire_format_rather_than_a_date_to_read(self):
        """A date for a person goes through the helper; strftime is left for
        the ISO values, the times and the weekday names it is right for."""
        offenders = []

        for path in SOURCE.rglob("*.py"):
            if path.name in HOME or "tests" in path.parts or "migrations" in path.parts:
                continue

            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
                if "strftime(" in line and not WIRE.search(line):
                    offenders.append(f"{path.relative_to(SOURCE)}:{number}  {line.strip()}")

        self.assertEqual([], offenders, "an unexpected strftime - is it a date somebody reads?")
