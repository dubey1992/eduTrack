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

import zoneinfo

from django.conf import settings
from django.utils import timezone

from .models import School, User

KNOWN_ZONES = zoneinfo.available_timezones()


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
    def platform(cls) -> "SchoolClock":
        return cls(sanitize(getattr(settings, "PLATFORM_TIMEZONE", "UTC")))

    def timezone(self) -> str:
        return self._timezone

    def now(self):
        """Now, as the school experiences it."""
        return timezone.now().astimezone(zoneinfo.ZoneInfo(self._timezone))

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
