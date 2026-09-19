"""Distances on the earth, for checks that need no map provider.

The great-circle (haversine) distance is exact enough for what it is used
for here - "is this stop within 100 km of its school", "how far is the bus
from its next stop" - and needs nothing but arithmetic, so it works whether
or not a map provider is configured.
"""

from __future__ import annotations

import math
from decimal import Decimal

EARTH_RADIUS_M = 6_371_000


def distance_m(lat1, lng1, lat2, lng2) -> float:
    """Metres between two points given in degrees."""
    lat1, lng1, lat2, lng2 = (math.radians(float(Decimal(str(value)))) for value in (lat1, lng1, lat2, lng2))

    a = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lng2 - lng1) / 2) ** 2

    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))
