"""Bus trips, as the transport manager runs them from a phone.

Port of TransportTripController. Seven endpoints: the day's trips, one trip,
start, reach a stop, board / drop / mark a rider absent, end, and cancel.

The order of checks is Laravel's. Everything named in the path is found first
(404); a form validates before the controller body runs, so starting a trip
with a bad route is a 422 whoever asks; the policy then decides (403); and the
rules of running a trip come last (409). Two checks are plain validation
errors raised in the controller rather than by a form - a stop that is not on
the trip's route, a student who is not on the trip - so they arrive as 422s
keyed `stop` and `student`.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import serializers, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from django.db.models import Count

from ..clock import SchoolClock
from ..enums import TripDirection, TripStatus
from ..models import Student, TransportRoute, TransportStop, TransportTrip, TransportTripRider
from ..pagination import LaravelPagination
from ..policies import TransportTripPolicy, authorize
from ..requests import StartTripRequest, TripLocationsRequest, TripSyncRequest, UpdateTripRiderRequest
from ..resources import timestamp, transport_route_resource, transport_trip_resource
from ..services import TransportRouteService, TransportTripService, TripLocationService, TripSyncService


def detail_response(trip_id: int, **kwargs) -> Response:
    loaded = TransportTripService.detail(trip_id)

    return Response(
        transport_trip_resource(
            loaded["trip"], riders=loaded["riders"], events=loaded["events"], stops=loaded["stops"]
        ),
        **kwargs,
    )


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method == "POST":
        return start(request)

    authorize(TransportTripPolicy.view_any(request.user))

    found = TransportTripService.visible_to(
        request.user, {key: request.query_params.get(key) for key in ("school_id", "route_id", "date", "status")}
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)

    return paginator.get_paginated_response(
        [transport_trip_resource(trip, riders_count=trip.riders_count) for trip in page]
    )


def start(request) -> Response:
    form = StartTripRequest(data=request.data, actor=request.user)
    form.is_valid(raise_exception=True)

    route = get_object_or_404(TransportRoute.objects.select_related("vehicle", "driver"), pk=form.validated_data["route_id"])

    authorize(TransportTripPolicy.create(request.user, route))

    trip_id = TransportTripService.start(route, form.validated_data["direction"], request.user)

    return detail_response(trip_id, status=status.HTTP_201_CREATED)


def found_trip(trip_id: int):
    return get_object_or_404(TransportTrip.objects.select_related("route", "vehicle"), pk=trip_id)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def detail(request, trip_id: int) -> Response:
    trip = found_trip(trip_id)

    authorize(TransportTripPolicy.view(request.user, trip))

    return detail_response(trip.pk)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def reach_stop(request, trip_id: int, stop_id: int) -> Response:
    trip = found_trip(trip_id)
    stop = get_object_or_404(TransportStop, pk=stop_id)

    authorize(TransportTripPolicy.manage(request.user, trip))

    if stop.route_id != trip.route_id:
        raise serializers.ValidationError({"stop": ["The selected stop is not on this trip's route."]})

    TransportTripService.reach_stop(trip, stop, request.user)

    return detail_response(trip.pk)


@api_view(["PATCH"])
@permission_classes([IsAuthenticated])
def rider(request, trip_id: int, student_id: int) -> Response:
    trip = found_trip(trip_id)
    student = get_object_or_404(Student, pk=student_id)

    authorize(TransportTripPolicy.manage(request.user, trip))

    form = UpdateTripRiderRequest(data=request.data)
    form.is_valid(raise_exception=True)

    if not TransportTripRider.objects.filter(trip_id=trip.pk, student_id=student.pk).exists():
        raise serializers.ValidationError({"student": ["This student is not on this trip."]})

    TransportTripService.update_rider(trip, student, form.validated_data["status"], request.user)

    return detail_response(trip.pk)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def end(request, trip_id: int) -> Response:
    trip = found_trip(trip_id)

    authorize(TransportTripPolicy.manage(request.user, trip))

    TransportTripService.end(trip, request.user)

    return detail_response(trip.pk)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def cancel(request, trip_id: int) -> Response:
    trip = found_trip(trip_id)

    authorize(TransportTripPolicy.manage(request.user, trip))

    TransportTripService.cancel(trip, request.user)

    return detail_response(trip.pk)


# -- the attendant's phone: marks made offline, positions, My Routes --------
#
# docs/maps.md, "The Bus Attendant" and "Offline".


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def sync(request, trip_id: int) -> Response:
    """A batch of marks from the phone, in the order they were made. Every
    mark gets its own answer; the trip comes back as it now stands."""
    trip = found_trip(trip_id)

    authorize(TransportTripPolicy.manage(request.user, trip))

    form = TripSyncRequest(data=request.data)
    form.is_valid(raise_exception=True)

    results = TripSyncService.sync(trip, form.validated_data["operations"], request.user)
    loaded = TransportTripService.detail(trip.pk)

    return Response({
        "results": results,
        "trip": transport_trip_resource(loaded["trip"], riders=loaded["riders"], events=loaded["events"], stops=loaded["stops"]),
    })


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def locations(request, trip_id: int) -> Response:
    trip = found_trip(trip_id)

    authorize(TransportTripPolicy.manage(request.user, trip))

    form = TripLocationsRequest(data=request.data)
    form.is_valid(raise_exception=True)

    return Response(TripLocationService.record(trip, form.validated_data["points"], request.user))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def live(request, trip_id: int) -> Response:
    trip = found_trip(trip_id)

    authorize(TransportTripPolicy.view(request.user, trip))

    answer = TripLocationService.live(trip)

    if answer["position"] is not None:
        answer["position"]["recorded_at"] = timestamp(answer["position"]["recorded_at"])

    return Response(answer)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def my_routes(request) -> Response:
    """The routes this attendant runs, each with today's pickup and drop trip
    if they have started - what the My Trip screen opens on."""
    actor = request.user

    authorize(TransportTripPolicy.my_routes(actor))

    today = SchoolClock.for_user(actor).now().date()
    routes = (
        TransportRouteService.with_counts(TransportRoute.objects.filter(attendant_user_id=actor.id))
        .order_by("name", "id")
    )
    trips = {
        (trip.route_id, trip.direction): trip
        for trip in TransportTrip.objects.select_related(*TransportTripService.LIST)
        .annotate(riders_count=Count("transporttriprider"))
        .filter(route__attendant_user_id=actor.id, trip_date=today)
        .exclude(status=TripStatus.CANCELLED)
    }

    return Response({
        "date": today.isoformat(),
        "routes": [
            {
                **transport_route_resource(route),
                "today": {
                    direction: (
                        None if (route.pk, direction) not in trips
                        else transport_trip_resource(trips[(route.pk, direction)], riders_count=trips[(route.pk, direction)].riders_count)
                    )
                    for direction in (TripDirection.PICKUP, TripDirection.DROP)
                },
            }
            for route in routes
        ],
    })
