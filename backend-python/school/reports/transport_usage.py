"""How each bus route actually ran over a range.

Port of App\\Services\\Reports\\TransportUsageReport: trips completed, days
the route never left, and what happened to the children on it. "Days not run"
is measured against the school's working days, so a route is not marked as
having missed a holiday nobody expected it to run on.
"""

from __future__ import annotations

from django.db.models import Count

from ..enums import TripRiderStatus, TripStatus
from ..models import TransportRoute, TransportTrip, TransportTripRider
from .range import ReportRange


class TransportUsageReport:
    def build(self, report_range: ReportRange, filters: dict) -> dict:
        trips = self._trips_by_route(report_range)
        days_run_by_route = self._days_run_by_route(report_range)
        riders = self._riders_by_route(report_range)
        days = report_range.working_day_count()

        routes = (
            TransportRoute.objects.filter(school_id=report_range.school_id)
            .select_related("vehicle", "driver")
            # A route's name is unique within its school, so this cannot tie.
            .order_by("name")
        )

        rows = []
        for route in routes:
            route_trips = trips.get(route.id, [])
            counts = riders.get(route.id, {})

            def trips_with(status, route_trips=route_trips):
                return sum(trip["total"] for trip in route_trips if trip["status"] == status)

            days_run = days_run_by_route.get(route.id, 0)

            rows.append({
                "route_id": route.id,
                "route": route.name,
                "vehicle": route.vehicle.name if route.vehicle else None,
                "driver": route.driver.name if route.driver else None,
                "working_days": days,
                "days_run": days_run,
                # Working days on which this route never started a trip at all.
                "days_not_run": max(0, days - days_run),
                "trips_completed": trips_with(TripStatus.COMPLETED),
                "trips_cancelled": trips_with(TripStatus.CANCELLED),
                "trips_in_progress": trips_with(TripStatus.IN_PROGRESS),
                "riders_boarded": counts.get(TripRiderStatus.BOARDED, 0),
                "riders_dropped": counts.get(TripRiderStatus.DROPPED, 0),
                "riders_absent": counts.get(TripRiderStatus.ABSENT, 0),
            })

        return {
            "range": report_range.to_dict(),
            "rows": rows,
            "totals": {
                "routes": len(rows),
                "working_days": days,
                "trips_completed": sum(row["trips_completed"] for row in rows),
                "trips_cancelled": sum(row["trips_cancelled"] for row in rows),
                "riders_boarded": sum(row["riders_boarded"] for row in rows),
                "riders_absent": sum(row["riders_absent"] for row in rows),
            },
        }

    def headings(self) -> list[str]:
        return [
            "Route", "Vehicle", "Driver", "Working days", "Days run", "Days not run",
            "Trips completed", "Trips cancelled", "Boarded", "Dropped", "Absent",
        ]

    def csv_rows(self, report: dict) -> list[list]:
        return [
            [
                row["route"], row["vehicle"], row["driver"], row["working_days"], row["days_run"],
                row["days_not_run"], row["trips_completed"], row["trips_cancelled"], row["riders_boarded"],
                row["riders_dropped"], row["riders_absent"],
            ]
            for row in report["rows"]
        ]

    def combine_totals(self, branch_totals: list[dict]) -> dict:
        def total(key):
            return sum(int(totals[key]) for totals in branch_totals)

        return {
            "branches": len(branch_totals),
            "routes": total("routes"),
            "trips_completed": total("trips_completed"),
            "trips_cancelled": total("trips_cancelled"),
            "riders_boarded": total("riders_boarded"),
            "riders_absent": total("riders_absent"),
        }

    @staticmethod
    def _trips_by_route(report_range: ReportRange) -> dict[int, list[dict]]:
        """Trip counts per route and status."""
        trips: dict[int, list[dict]] = {}

        grouped = (
            TransportTrip.objects.filter(
                school_id=report_range.school_id,
                trip_date__range=(report_range.start, report_range.end),
            )
            .values("route_id", "status")
            .annotate(total=Count("id"))
        )

        for row in grouped:
            trips.setdefault(row["route_id"], []).append(row)

        return trips

    @staticmethod
    def _days_run_by_route(report_range: ReportRange) -> dict[int, int]:
        """The working days on which each route set off: distinct dates with
        a trip that was started, whether or not it has finished.

        A cancelled trip never ran, so a route cancelled every morning reads as
        not having run. A trip on a weekend or holiday is not a working day
        run - counting it would let days run exceed the days it is measured
        against.
        """
        return dict(
            TransportTrip.objects.filter(
                school_id=report_range.school_id,
                trip_date__range=(report_range.start, report_range.end),
                trip_date__in=report_range.working_dates,
                status__in=(TripStatus.IN_PROGRESS, TripStatus.COMPLETED),
            )
            .values("route_id")
            .annotate(days=Count("trip_date", distinct=True))
            .values_list("route_id", "days")
        )

    @staticmethod
    def _riders_by_route(report_range: ReportRange) -> dict[int, dict[str, int]]:
        riders: dict[int, dict[str, int]] = {}

        grouped = (
            TransportTripRider.objects.filter(
                trip__school_id=report_range.school_id,
                trip__trip_date__range=(report_range.start, report_range.end),
            )
            .values("trip__route_id", "status")
            .annotate(total=Count("id"))
        )

        for row in grouped:
            riders.setdefault(row["trip__route_id"], {})[row["status"]] = row["total"]

        return riders
