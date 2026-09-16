"""The timezones a school can be set to.

Reference data, not tenant data: the IANA list, so the picker can never offer
a zone the backend would reject. The list is bounded (a few hundred entries)
and identical for every user, so it comes back whole rather than paginated -
`q` narrows it for a search box.

Port of TimezoneController, and the list comes from `school/zones.py` rather
than from Python's own `zoneinfo`. Those two disagree: Python includes 179
backward-compatibility aliases that PHP does not, and offering one here would
let a school be set to a name Laravel then refuses to read - falling back to
UTC and moving that school's whole calendar. The picker must never offer a
zone the other backend would reject.
"""

from __future__ import annotations

import zoneinfo
from datetime import datetime, timezone as dt_timezone

from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..zones import ZONES


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def index(request) -> Response:
    term = str(request.query_params.get("q", "")).strip().lower()
    now = datetime.now(dt_timezone.utc)

    zones = []

    for name in ZONES:
        if term and term not in name.lower():
            continue

        offset = now.astimezone(zoneinfo.ZoneInfo(name)).utcoffset()
        minutes = int(offset.total_seconds() // 60)

        zones.append(
            {
                "name": name,
                "region": name.split("/")[0] if "/" in name else "Other",
                "offset_minutes": minutes,
                "label": f"{name} ({offset_label(minutes)})",
            }
        )

    # Sorted west to east and then by name, which is the order a timezone
    # picker is read in.
    zones.sort(key=lambda zone: (zone["offset_minutes"], zone["name"]))

    return Response({"data": zones})


def offset_label(minutes: int) -> str:
    """"GMT+05:30" - the form people recognise from a timezone picker."""
    sign = "-" if minutes < 0 else "+"
    minutes = abs(minutes)

    return f"GMT{sign}{minutes // 60:02d}:{minutes % 60:02d}"
