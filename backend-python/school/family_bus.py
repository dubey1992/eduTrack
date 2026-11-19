"""The school bus as a parent sees it in the Family app
(docs/parent-student-app.md, F4).

- `bus_of`  - the Bus tab: the child's route, stop and vehicle, who to call,
  and today's trips with the child's own part of each (when the bus left,
  reached their stop, when they boarded and were dropped).
- `live_of` - where the bus is, **only while the child's own trip is
  running** and they have not yet got off (decision D9): the position, the
  route's road, their stop, and how far and how long until it gets there.
  Any other time it is None, and the app says the bus is not on the road
  for them.
- `alert_near_stops` - called as the crew's phone reports positions: tells
  each parent once per trip, in the app only, that the bus is within the
  school's distance of their child's stop.

Nothing here names another child, another family or the crew's personal
numbers unless the school has switched that on.
"""

from __future__ import annotations

from django.db.models import Q

from . import geo, modules
from .clock import SchoolClock
from .enums import MessageChannel, MessageEvent, TripDirection, TripEventType, TripRiderStatus, TripStatus, UserRole
from .models import (
    Message,
    Student,
    StudentTransportAssignment,
    TransportRoute,
    TransportStop,
    TransportTrip,
    TransportTripEvent,
    TransportTripRider,
)
from .services import TripLocationService

MODULE = "transport"


def assignment_of(student: Student):
    return (
        StudentTransportAssignment.objects.select_related(
            "route__vehicle", "route__attendant_user", "transport_stop", "route__school"
        )
        .filter(student_id=student.id)
        .first()
    )


def point(latitude, longitude) -> dict | None:
    if latitude is None or longitude is None:
        return None
    return {"latitude": str(latitude), "longitude": str(longitude)}


def in_words(metres: float) -> str:
    """"350 m", "1.2 km" - how a distance reads in a message."""
    return f"{round(metres / 50) * 50:.0f} m" if metres < 1000 else f"{metres / 1000:.1f} km"


def bus_of(student: Student) -> dict | None:
    """The Bus tab; None for a child the school does not carry."""
    assignment = assignment_of(student)
    if assignment is None:
        return None

    route = assignment.route
    stop = assignment.transport_stop
    clock = SchoolClock.for_school(student.school_id)
    now = clock.now()
    zone = now.tzinfo
    today = now.date()

    def at(instant):
        return instant.astimezone(zone).strftime("%H:%M") if instant else None

    trips = list(TransportTrip.objects.filter(route_id=route.id, trip_date=today).order_by("started_at", "id"))
    riders = {r.trip_id: r for r in TransportTripRider.objects.filter(student_id=student.id, trip__in=trips)}
    reached = {
        event.trip_id: event.recorded_at
        for event in TransportTripEvent.objects.filter(
            trip__in=trips, type=TripEventType.STOP_REACHED, stop_id=stop.id if stop else None
        ).order_by("recorded_at")
    } if stop else {}

    timelines = _timelines(trips, student, stop, at)
    show_crew = bool(modules.setting(student.school_id, MODULE, "show_crew_phone_to_parents"))
    attendant = route.attendant_user

    return {
        "route": {"id": route.id, "name": route.name},
        "vehicle": (
            {"name": route.vehicle.name, "registration_number": route.vehicle.registration_number}
            if route.vehicle_id else None
        ),
        "stop": {
            "name": stop.name,
            "pickup_time": stop.pickup_time.strftime("%H:%M") if stop.pickup_time else None,
            "drop_time": stop.drop_time.strftime("%H:%M") if stop.drop_time else None,
            "location": point(stop.latitude, stop.longitude),
        } if stop else None,
        "contacts": {
            "office_phone": route.school.phone or None,
            # The attendant's own number only when the school says so.
            "attendant": (
                {"name": attendant.name, "mobile": attendant.mobile}
                if show_crew and attendant is not None and attendant.mobile else None
            ),
        },
        "trips": [
            {
                "id": trip.id,
                "direction": trip.direction,
                "status": trip.status,
                "started_at": at(trip.started_at),
                "ended_at": at(trip.ended_at),
                "reached_stop_at": at(reached.get(trip.id)),
                "rider_status": riders[trip.id].status if trip.id in riders else None,
                "boarded_at": at(riders[trip.id].boarded_at) if trip.id in riders else None,
                "dropped_at": at(riders[trip.id].dropped_at) if trip.id in riders else None,
                "is_live": live_trip(trip, riders.get(trip.id)),
                "timeline": timelines.get(trip.id, []),
            }
            for trip in trips
        ],
    }


# What a parent sees of a trip (docs/mobile-apps-review.md, 4.3): the bus
# leaving, reaching their stop, their child on or off - each with the time
# and who marked it - and the trip ending. Nothing about other children.
_TRIP_WIDE = (TripEventType.STARTED, TripEventType.COMPLETED, TripEventType.CANCELLED)
_THE_CHILD = (TripEventType.BOARDED, TripEventType.DROPPED, TripEventType.ABSENT)

_ROLE_WORDS = {
    UserRole.DRIVER: "driver",
    UserRole.BUS_ATTENDANT: "attendant",
    UserRole.TRANSPORT_MANAGER: "transport office",
}


def _timelines(trips, student: Student, stop, at) -> dict[int, list[dict]]:
    if not trips:
        return {}

    concerns = Q(type__in=_TRIP_WIDE) | Q(type__in=_THE_CHILD, student_id=student.id)
    if stop is not None:
        concerns |= Q(type=TripEventType.STOP_REACHED, stop_id=stop.id)

    timelines: dict[int, list[dict]] = {}
    events = (
        TransportTripEvent.objects.select_related("recorded_by")
        .filter(concerns, trip__in=trips)
        .order_by("recorded_at", "id")
    )
    for event in events:
        by = event.recorded_by
        timelines.setdefault(event.trip_id, []).append({
            "type": event.type,
            "at": at(event.recorded_at),
            "stop_name": event.stop_name,
            "by": by.name if by else None,
            "by_role": _ROLE_WORDS.get(by.role, "school") if by else None,
        })
    return timelines


def live_trip(trip: TransportTrip, rider: TransportTripRider | None) -> bool:
    """Whether a parent may watch this trip: it is running, the child is on
    its list, and they have not yet been dropped or marked absent."""
    return (
        trip.status == TripStatus.IN_PROGRESS
        and rider is not None
        and rider.status not in (TripRiderStatus.DROPPED, TripRiderStatus.ABSENT)
    )


def live_of(student: Student) -> dict | None:
    """Where the bus is, while the child's own trip runs; None otherwise."""
    assignment = assignment_of(student)
    if assignment is None:
        return None

    today = SchoolClock.for_school(student.school_id).now().date()
    candidates = TransportTrip.objects.filter(
        route_id=assignment.route_id, trip_date=today, status=TripStatus.IN_PROGRESS
    ).order_by("-started_at", "-id")

    for trip in candidates:
        rider = TransportTripRider.objects.filter(trip_id=trip.id, student_id=student.id).first()
        if live_trip(trip, rider):
            return live_view(trip, assignment)

    return None


def live_view(trip: TransportTrip, assignment) -> dict:
    stop = assignment.transport_stop
    route = assignment.route
    live = TripLocationService.live(trip)
    position = live["position"]

    reached = set(
        TransportTripEvent.objects.filter(trip_id=trip.id, type=TripEventType.STOP_REACHED)
        .values_list("stop_id", flat=True)
    )
    yours_reached = stop is not None and stop.id in reached
    stops_before = None
    if stop is not None and not yours_reached:
        stops_before = (
            TransportStop.objects.filter(route_id=route.id, sequence_number__lt=stop.sequence_number)
            .exclude(pk__in=reached)
            .count()
        )

    distance = None
    if position is not None and stop is not None and stop.latitude is not None and not yours_reached:
        distance = round(geo.distance_m(position["latitude"], position["longitude"], stop.latitude, stop.longitude))

    next_stop = live["next_stop"]
    # The estimate is the next stop's: it is the child's only when that stop is theirs.
    eta = next_stop.get("eta_seconds") if next_stop and stop and next_stop["id"] == stop.id else None

    return {
        "trip_id": trip.id,
        "direction": trip.direction,
        "position": None if position is None else {
            "latitude": position["latitude"],
            "longitude": position["longitude"],
            "heading": position["heading"],
            "age_seconds": position["age_seconds"],
            "is_stale": position["is_stale"],
        },
        "route_path": route.path_polyline or None,
        "your_stop": {
            "name": stop.name,
            "location": point(stop.latitude, stop.longitude),
            "reached": yours_reached,
            "stops_before": stops_before,
            "distance_m": distance,
            "eta_seconds": eta,
        } if stop else None,
        "next_stop": next_stop["name"] if next_stop else None,
    }


# -- "The bus is near your stop" -------------------------------------------------


def alert_near_stops(trip: TransportTrip) -> int:
    """Tells each waiting child's parents, once per trip and in the Family
    app only, that the bus is within the school's distance of their stop.
    Returns how many children's parents were told.

    Who is waiting: on a pickup, a child not yet boarded or marked absent;
    on a drop, a child on board. A stop the bus has already reached is
    past. Never raises - the crew's position upload must not fail for this.
    """
    try:
        return _alert_near_stops(trip)
    except Exception:  # noqa: BLE001 - reported, never the upload's problem
        import logging

        logging.getLogger(__name__).exception("Near-stop alerts failed for trip %s.", trip.pk)
        return 0


def _alert_near_stops(trip: TransportTrip) -> int:
    from .notifications import copy_to_family_app

    if trip.status != TripStatus.IN_PROGRESS or not modules.is_enabled(trip.school_id, "family_app"):
        return 0

    threshold = modules.setting(trip.school_id, MODULE, "near_stop_alert_m")
    if not threshold:
        return 0

    latest = TripLocationService.live(trip)["position"]
    if latest is None or latest["is_stale"]:
        return 0

    waiting = TripRiderStatus.PENDING if trip.direction == TripDirection.PICKUP else TripRiderStatus.BOARDED
    reached = set(
        TransportTripEvent.objects.filter(trip_id=trip.id, type=TripEventType.STOP_REACHED)
        .values_list("stop_id", flat=True)
    )
    riders = (
        TransportTripRider.objects.select_related("student", "stop")
        .filter(trip_id=trip.id, status=waiting, stop__isnull=False, stop__latitude__isnull=False)
        .exclude(stop_id__in=reached)
    )
    already = set(
        Message.objects.filter(
            event=MessageEvent.TRANSPORT_NEAR_STOP, channel=MessageChannel.IN_APP,
            created_at__gte=trip.started_at, student_id__in=[r.student_id for r in riders],
        ).values_list("student_id", flat=True)
    )
    route = TransportRoute.objects.select_related("vehicle", "school").get(pk=trip.route_id)
    clock = SchoolClock.for_school(trip.school_id)
    told = 0

    for rider in riders:
        if rider.student_id in already:
            continue

        metres = geo.distance_m(latest["latitude"], latest["longitude"], rider.stop.latitude, rider.stop.longitude)
        if metres > threshold:
            continue

        tokens = {
            "student_name": rider.student.name,
            "guardian_name": rider.student.guardian_name,
            "stop_name": rider.stop.name,
            "route_name": route.name,
            "vehicle_name": route.vehicle.name if route.vehicle_id else route.name,
            "distance": in_words(metres),
            "direction": trip.direction,
            "time": clock.now().strftime("%I:%M %p").lstrip("0"),
            "school_name": route.school.name,
        }
        if copy_to_family_app(MessageEvent.TRANSPORT_NEAR_STOP, rider.student, tokens, subject="The bus is nearly here"):
            told += 1

    return told

