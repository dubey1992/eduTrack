"""The road a route follows, and when it is worked out (docs/maps.md, M2).

Computed once, when the stops change, and stored. A map that asked Google
for its own line would bill a call for every administrator who opened it,
and the line is the same every time until somebody moves a stop.

So: changing a stop marks the route `stale` and queues a job; the job calls
Google once and writes the answer. Between those two the map draws straight
lines between the stops and says the path is being worked out, which is
honest and still useful - a straight line through the right stops in the
right order tells somebody most of what they opened the map for.

**Where a route starts and ends.** At its own school. The stored path runs
the stops in order and then the school, which is the pickup run; the drop
run is the same roads with the school at the other end. One path rather than
two because the difference is a single leg and two would double what Google
is asked for a line that is drawn the same way.
"""

from __future__ import annotations

import json

from django.utils import timezone

from .gateways import google_maps
from .models import TransportRoute, TransportStop
from .queue import handler, push

COMPUTE_ROUTE_PATH = "compute_route_path"

# What `path_status` can be.
NONE = "none"
OK = "ok"
STALE = "stale"
FAILED = "failed"

# Two points make a path. One stop and a school is a path; one stop and no
# school is not.
MINIMUM_POINTS = 2


def points_for(route: TransportRoute) -> list[tuple[float, float]]:
    """The places the road has to join, in order.

    Stops with no coordinates are skipped rather than refused: a route is
    usually placed one stop at a time, and refusing to draw anything until
    every stop is placed would mean seeing nothing for most of the job.
    """
    stops = (
        TransportStop.objects.filter(route_id=route.pk, latitude__isnull=False, longitude__isnull=False)
        .order_by("sequence_number", "id")
        .values_list("latitude", "longitude")
    )

    points = [(float(latitude), float(longitude)) for latitude, longitude in stops]

    school = route.school

    if school.latitude is not None and school.longitude is not None:
        points.append((float(school.latitude), float(school.longitude)))

    return points


def mark_stale(route_id: int) -> None:
    """A stop moved, was added, renumbered or removed.

    Marked and queued rather than computed here: an administrator dragging
    a pin should not wait on Google, and dragging five pins should not be
    five calls. The job coalesces - whatever the stops are when it runs is
    what gets computed.
    """
    route = TransportRoute.objects.select_related("school").filter(pk=route_id).first()

    if route is None:
        return

    TransportRoute.objects.filter(pk=route_id).update(path_status=STALE, updated_at=timezone.now())

    # Nothing to ask about: a route with one placed stop and no school
    # location has no road to draw, and queuing would only fail.
    if len(points_for(route)) < MINIMUM_POINTS:
        TransportRoute.objects.filter(pk=route_id).update(path_status=NONE, path_failure_reason=None)
        return

    push(COMPUTE_ROUTE_PATH, {"route_id": route_id})


@handler(COMPUTE_ROUTE_PATH)
def compute_route_path(route_id: int) -> None:
    """Asks Google for the road, once, and writes what it said.

    Reads the stops now rather than trusting what was true when the job was
    queued - five drags queue five jobs, and the first to run should compute
    the route as it finally stands.
    """
    route = TransportRoute.objects.select_related("school").filter(pk=route_id).first()

    if route is None:
        return

    points = points_for(route)

    if len(points) < MINIMUM_POINTS:
        _store(route_id, status=NONE, reason=None)
        return

    try:
        found = google_maps.route(points)
    except google_maps.MapsUnavailable as error:
        # The map falls back to straight lines and offers to try again, so
        # the reason is kept in words an administrator can read.
        _store(route_id, status=FAILED, reason=str(error)[:255])
        return

    TransportRoute.objects.filter(pk=route_id).update(
        path_polyline=found.polyline,
        path_distance_m=found.distance_m,
        path_duration_s=found.duration_s,
        path_legs=json.dumps([{"distance_m": leg.distance_m, "duration_s": leg.duration_s} for leg in found.legs]),
        path_status=OK,
        path_failure_reason=None,
        path_computed_at=timezone.now(),
        updated_at=timezone.now(),
    )


def _store(route_id: int, *, status: str, reason: str | None) -> None:
    """Records an outcome that has no path in it.

    The old polyline is cleared: a line through stops that have since moved
    is worse than no line, because it looks current.
    """
    TransportRoute.objects.filter(pk=route_id).update(
        path_polyline=None,
        path_distance_m=None,
        path_duration_s=None,
        path_legs=None,
        path_status=status,
        path_failure_reason=reason,
        path_computed_at=timezone.now(),
        updated_at=timezone.now(),
    )


def legs_of(route: TransportRoute) -> list[dict]:
    """The stored legs, in order.

    Decoded here rather than by the field, because the column is text - see
    the model for why. Anything unreadable is no legs at all: an arrival
    estimate built on half a list would be confidently wrong, which is
    worse than saying nothing.
    """
    if not route.path_legs:
        return []

    try:
        legs = json.loads(route.path_legs)
    except ValueError:
        return []

    if not isinstance(legs, list):
        return []

    return [leg for leg in legs if isinstance(leg, dict)]
