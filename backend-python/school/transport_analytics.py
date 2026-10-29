"""Transport analytics, A6 (docs/analytics.md, decided 2026-10-29).

Each route, month by month:

- **Service** - the days a trip ran against the school's working days, and
  trips completed and cancelled. Working days come from the same calendar
  as every rate in the product, so a holiday is not a day a bus missed.
- **Riders** - riders on the trips' lists, how many boarded, how many were
  marked absent (no-shows).
- **On time** - each stop the bus reached against that stop's scheduled
  pickup or drop time: **more than 10 minutes after it is late**; early is
  never late. Measured in the school's own time, since a stop's schedule is
  a time on the school's clock.
- **Trip length** - how long the completed trips took.

And over the whole range, the stops most often late - the ones a transport
manager goes and looks at.

A route whose trips have no stop times, or a stop with no scheduled time,
says nothing about lateness rather than counting as on time.
"""

from __future__ import annotations

import datetime as dt
import zoneinfo

from django.db.models import Count, Q

from .analytics import MONTH, periods
from .clock import SchoolClock
from .enums import TransportStatus, TripDirection, TripEventType, TripRiderStatus, TripStatus
from .models import TransportRoute, TransportTrip, TransportTripEvent, TransportTripRider
from .services import HolidayService

LATE_AFTER_MINUTES = 10

# The stops listed as most often late, worst first.
WORST_STOPS = 10


def transport(school_id: int, start: dt.date, end: dt.date) -> dict:
    clock = SchoolClock.for_school(school_id)
    today = clock.now().date()
    zone = zoneinfo.ZoneInfo(clock.timezone())
    months = periods(start, min(end, today), MONTH)
    first, last = months[0][0], months[-1][1]

    trips = list(
        TransportTrip.objects.filter(school_id=school_id, trip_date__range=(first, last)).values(
            "id", "route_id", "trip_date", "status", "direction", "started_at", "ended_at"
        )
    )
    riders = _riders_by_trip([trip["id"] for trip in trips])
    arrivals = _arrivals([trip["id"] for trip in trips], zone)

    routes = {
        route.id: route.name
        for route in TransportRoute.objects.filter(
            Q(school_id=school_id, status=TransportStatus.ACTIVE) | Q(id__in={trip["route_id"] for trip in trips})
        ).order_by("name", "id")
    }

    lines = []
    for route_id, name in routes.items():
        route_trips = [trip for trip in trips if trip["route_id"] == route_id]
        lines.append({
            "route_id": route_id,
            "route": name,
            "months": [
                _month(
                    school_id,
                    month_start,
                    month_end,
                    [trip for trip in route_trips if month_start <= trip["trip_date"] <= month_end],
                    riders,
                    arrivals,
                )
                for month_start, month_end in months
            ],
        })

    return {
        "as_of": today.isoformat(),
        "late_after_minutes": LATE_AFTER_MINUTES,
        "months": [{"from": a.isoformat(), "to": b.isoformat()} for a, b in months],
        "routes": lines,
        "late_stops": _late_stops(trips, arrivals, routes),
    }


def _month(school_id, start, end, trips, riders, arrivals) -> dict:
    working = len(HolidayService.working_dates(school_id, start, end))
    completed = [trip for trip in trips if trip["status"] == TripStatus.COMPLETED]

    on_list = boarded = absent = 0
    for trip in trips:
        counts = riders.get(trip["id"], {})
        on_list += sum(counts.values())
        boarded += counts.get(TripRiderStatus.BOARDED, 0) + counts.get(TripRiderStatus.DROPPED, 0)
        absent += counts.get(TripRiderStatus.ABSENT, 0)

    timed = [arrival for trip in trips for arrival in arrivals.get(trip["id"], []) if arrival["late_by"] is not None]
    late = [arrival for arrival in timed if arrival["late_by"] > LATE_AFTER_MINUTES]

    lengths = [
        (trip["ended_at"] - trip["started_at"]).total_seconds() / 60
        for trip in completed
        if trip["ended_at"] and trip["started_at"]
    ]

    return {
        "from": start.isoformat(),
        "to": end.isoformat(),
        "service": {
            "working_days": working,
            "days_run": len({trip["trip_date"] for trip in completed}),
            "trips_completed": len(completed),
            "trips_cancelled": sum(1 for trip in trips if trip["status"] == TripStatus.CANCELLED),
        },
        "riders": {
            "on_list": on_list,
            "boarded": boarded,
            "absent": absent,
            "boarded_rate": _rate(boarded, on_list),
        },
        "on_time": {
            "arrivals": len(timed),
            "late": len(late),
            "on_time_rate": _rate(len(timed) - len(late), len(timed)),
            "average_minutes_late": round(sum(a["late_by"] for a in late) / len(late), 1) if late else None,
        },
        "length": {
            "trips": len(lengths),
            "average_minutes": round(sum(lengths) / len(lengths), 1) if lengths else None,
            "longest_minutes": round(max(lengths), 1) if lengths else None,
        },
    }


def _riders_by_trip(trip_ids) -> dict[int, dict[str, int]]:
    counts: dict[int, dict[str, int]] = {}
    for row in (
        TransportTripRider.objects.filter(trip_id__in=trip_ids).values("trip_id", "status").annotate(n=Count("id")).order_by()
    ):
        counts.setdefault(row["trip_id"], {})[row["status"]] = row["n"]

    return counts


def _arrivals(trip_ids, zone) -> dict[int, list[dict]]:
    """Each stop reached, with how many minutes after its scheduled time -
    negative when early, None when the stop has no scheduled time for the
    trip's direction."""
    found: dict[int, list[dict]] = {}
    events = (
        TransportTripEvent.objects.filter(trip_id__in=trip_ids, type=TripEventType.STOP_REACHED)
        .select_related("stop", "trip")
        .order_by("recorded_at", "id")
    )

    for event in events:
        stop = event.stop
        scheduled = None
        if stop is not None:
            scheduled = stop.pickup_time if event.trip.direction == TripDirection.PICKUP else stop.drop_time

        late_by = None
        if scheduled is not None:
            local = event.recorded_at.astimezone(zone)
            due = dt.datetime.combine(local.date(), scheduled, tzinfo=zone)
            late_by = round((local - due).total_seconds() / 60, 1)

        found.setdefault(event.trip_id, []).append({
            "stop_id": event.stop_id,
            "stop": event.stop_name or (stop.name if stop else None),
            "late_by": late_by,
        })

    return found


def _late_stops(trips, arrivals, routes) -> list[dict]:
    """Over the whole range: each stop's timed arrivals, how many were late,
    and by how much on average. Worst first; stops never late are left out."""
    by_stop: dict[int, dict] = {}
    route_of = {trip["id"]: trip["route_id"] for trip in trips}

    for trip_id, reached in arrivals.items():
        for arrival in reached:
            if arrival["late_by"] is None or arrival["stop_id"] is None:
                continue
            entry = by_stop.setdefault(arrival["stop_id"], {
                "stop_id": arrival["stop_id"],
                "stop": arrival["stop"],
                "route": routes.get(route_of.get(trip_id)),
                "arrivals": 0,
                "late": 0,
                "minutes_late": 0.0,
            })
            entry["arrivals"] += 1
            if arrival["late_by"] > LATE_AFTER_MINUTES:
                entry["late"] += 1
                entry["minutes_late"] += arrival["late_by"]

    rows = []
    for entry in by_stop.values():
        if not entry["late"]:
            continue
        rows.append({
            "stop_id": entry["stop_id"],
            "stop": entry["stop"],
            "route": entry["route"],
            "arrivals": entry["arrivals"],
            "late": entry["late"],
            "late_rate": _rate(entry["late"], entry["arrivals"]),
            "average_minutes_late": round(entry["minutes_late"] / entry["late"], 1),
        })

    rows.sort(key=lambda row: (-row["late_rate"], -row["average_minutes_late"], row["stop"] or ""))

    return rows[:WORST_STOPS]


def _rate(part: int, whole: int) -> float | None:
    return None if whole == 0 else round(part / whole * 100, 1)
