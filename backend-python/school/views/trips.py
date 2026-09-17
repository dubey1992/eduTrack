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

from ..models import Student, TransportRoute, TransportStop, TransportTrip, TransportTripRider
from ..pagination import LaravelPagination
from ..policies import TransportTripPolicy, authorize
from ..requests import StartTripRequest, UpdateTripRiderRequest
from ..resources import transport_trip_resource
from ..services import TransportTripService


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
