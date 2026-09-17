"""What time it is for one school.

Ported from backend/app/Support/SchoolClock.php. M8 needs only the part the
session user carries - a school's zone and the instant rendered in it - so
that is what is here; the date arithmetic the attendance and report modules
lean on comes across with those modules, not before.

The two rules it exists to keep are unchanged:

 - An instant (started_at, sent_at, created_at) is stored in UTC. It is a
   moment in time and does not belong to a timezone; only its *rendering*
   does.
 - A calendar date (attendance_date, a holiday) is whatever the date was *at
   the school*.

Platform-level views belong to no school - a Super Admin's cross-school
totals - and use platform() instead, which follows PLATFORM_TIMEZONE. That is
deliberately not Django's TIME_ZONE, which must stay UTC because it decides
how instants are stored.
"""

from __future__ import annotations

import datetime as dt

import zoneinfo

from django.conf import settings
from django.utils import timezone

from .fields import as_utc

from .enums import UserRole
from .models import School, User

KNOWN_ZONES = zoneinfo.available_timezones()

# DateFormats::TIME and DateFormats::DATE: "7:42 AM" and "09/17/2026".
TIME = "g:i A"
DATE = "m/d/Y"
DATE_TIME = "m/d/Y g:i A"


class SchoolClock:
    def __init__(self, zone_name: str) -> None:
        self._timezone = zone_name

    @classmethod
    def for_school(cls, school: School | int | None) -> "SchoolClock":
        """The clock for a school. A null school - a Super Admin, or a record
        with no school attached - falls back to the platform clock rather than
        guessing a zone.
        """
        if school is None:
            return cls.platform()

        if isinstance(school, School):
            zone_name = school.timezone
        else:
            zone_name = School.objects.filter(pk=school).values_list("timezone", flat=True).first()

        return cls(sanitize(zone_name))

    @classmethod
    def for_user(cls, user: User | None) -> "SchoolClock":
        """The clock for whichever school a user belongs to. A Super Admin
        belongs to none, so they get the platform clock.
        """
        if user is None:
            return cls.platform()

        # The loaded school where the caller already has it, so rendering a
        # list of users does not fire a query per row.
        if "school" in getattr(user, "_state").fields_cache:
            return cls.for_school(user.school)

        return cls.for_school(user.school_id)

    @classmethod
    def for_scope(cls, actor, school_id) -> "SchoolClock":
        """The clock a scoped listing should be read on.

        A school user always means their own school. A Super Admin means
        whichever school they have filtered to, or the platform's zone when
        they are looking across all of them - "today" across four countries
        cannot be any one school's today.
        """
        if actor.role != UserRole.SUPER_ADMIN:
            return cls.for_school(actor.school_id)

        if school_id is None or school_id == "":
            return cls.platform()

        return cls.for_school(int(school_id))

    @classmethod
    def platform(cls) -> "SchoolClock":
        return cls(sanitize(getattr(settings, "PLATFORM_TIMEZONE", "UTC")))

    def timezone(self) -> str:
        return self._timezone

    def now(self):
        """Now, as the school experiences it."""
        return timezone.now().astimezone(zoneinfo.ZoneInfo(self._timezone))

    def date(self) -> str:
        """The school's current calendar date as Y-m-d.

        The value that belongs in a date column, and the one to compare date
        columns against. Not the server's date: a school in Asia/Kolkata is
        already on tomorrow while a server in UTC is not.
        """
        return self.now().strftime("%Y-%m-%d")

    def format(self, instant, pattern: str) -> str | None:
        """An instant as the school's wall clock shows it, or None for None.

        `pattern` is one of the TIME/DATE shapes below - PHP's DateFormats,
        spelled out because strftime has no hour without a leading zero.
        """
        if instant is None:
            return None

        local = as_utc(instant).astimezone(zoneinfo.ZoneInfo(self._timezone))

        time = f"{local.hour % 12 or 12}:{local.minute:02d} {'AM' if local.hour < 12 else 'PM'}"

        if pattern == TIME:
            return time

        if pattern == DATE_TIME:
            return f"{local.strftime('%m/%d/%Y')} {time}"

        return local.strftime("%m/%d/%Y")

    def start_of_day_utc(self, day) -> dt.datetime:
        """The UTC instant a school-local calendar day begins."""
        midnight = dt.datetime.combine(day, dt.time(), tzinfo=zoneinfo.ZoneInfo(self._timezone))

        return midnight.astimezone(dt.timezone.utc)

    def end_of_day_utc(self, day) -> dt.datetime:
        """The UTC instant the *next* school-local day begins - an exclusive
        end. Across a daylight-saving change that is 23 or 25 hours away, not
        24, which is why it is not simply start + 1 day."""
        return self.start_of_day_utc(day + dt.timedelta(days=1))

    def today_range(self) -> tuple[dt.datetime, dt.datetime]:
        today = self.now().date()

        return self.start_of_day_utc(today), self.end_of_day_utc(today)

    def now_iso8601(self) -> str:
        """The instant in the form Laravel's toIso8601String() produces -
        `2026-09-16T14:05:00+05:30`, seconds and a colon in the offset.

        Python's own isoformat() gives microseconds when it has them, and the
        Flutter client parses a fixed shape, so the microseconds are dropped
        here rather than left to whether the clock happened to tick evenly.
        """
        return self.now().replace(microsecond=0).isoformat()


def sanitize(zone_name: str | None) -> str:
    """Guards against a zone that is empty or no longer valid - an IANA name
    can be retired between releases. Falling back to UTC keeps the request
    working instead of throwing on every date it touches.
    """
    if not zone_name:
        return "UTC"

    return zone_name if zone_name in KNOWN_ZONES else "UTC"
