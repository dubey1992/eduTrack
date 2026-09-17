"""Transport master data: vehicles, drivers, routes and their stops, and which
student rides which route.

Ports of VehicleController, DriverController, TransportRouteController and
StudentTransportController - 21 endpoints of the same few shapes.

Every write here goes through a form request whose `authorize()` runs before
its rules, so a caller who may not make the change gets a 403 whatever they
sent. A record named in the path is found first, so one that does not exist is
a 404 before either.

Vehicles and drivers are separate tables with identical rules, so their views
share one pair of functions rather than being written out twice.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..models import Driver, Student, TransportRoute, TransportStop, Vehicle
from ..pagination import LaravelPagination
from ..policies import StudentPolicy, TransportMasterPolicy, TransportRoutePolicy, authorize
from ..requests import (
    AssignStudentTransportRequest,
    StoreDriverRequest,
    StoreTransportRouteRequest,
    StoreTransportStopRequest,
    StoreVehicleRequest,
    UpdateDriverRequest,
    UpdateTransportRouteRequest,
    UpdateTransportStopRequest,
    UpdateVehicleRequest,
)
from ..resources import (
    driver_resource,
    route_student_resource,
    student_resource,
    transport_route_resource,
    transport_stop_resource,
    vehicle_resource,
)
from ..services import DriverService, StudentTransportService, TransportRouteService, VehicleService
from .students import reload

FLEET = {
    "vehicle": (Vehicle, VehicleService, vehicle_resource, StoreVehicleRequest, UpdateVehicleRequest),
    "driver": (Driver, DriverService, driver_resource, StoreDriverRequest, UpdateDriverRequest),
}


def fleet_collection(request, kind: str) -> Response:
    model, service, resource, store_form, _ = FLEET[kind]

    if request.method == "POST":
        authorize(TransportMasterPolicy.create(request.user))

        form = store_form(data=request.data, actor=request.user)
        form.is_valid(raise_exception=True)

        return Response(resource(service.create(form.validated_data), None), status=status.HTTP_201_CREATED)

    authorize(TransportMasterPolicy.view_any(request.user))

    found = service.visible_to(request.user, {
        "school_id": request.query_params.get("school_id"),
        "status": request.query_params.get("status"),
    })

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)
    routes = service.routes_of(page)

    return paginator.get_paginated_response([resource(row, routes.get(row.pk)) for row in page])


def fleet_detail(request, kind: str, record_id: int) -> Response:
    model, service, resource, _, update_form = FLEET[kind]
    record = get_object_or_404(model.objects.select_related("school"), pk=record_id)

    if request.method == "DELETE":
        authorize(TransportMasterPolicy.manage(request.user, record))
        service.delete(record)

        return Response(status=status.HTTP_204_NO_CONTENT)

    if request.method == "PATCH":
        authorize(TransportMasterPolicy.manage(request.user, record))

        form = update_form(data=request.data, **{kind: record})
        form.is_valid(raise_exception=True)
        record = service.update(record, form.validated_data)
    else:
        authorize(TransportMasterPolicy.view(request.user, record))

    return Response(resource(record, service.route_of(record)))


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def vehicles(request) -> Response:
    return fleet_collection(request, "vehicle")


@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def vehicle(request, record_id: int) -> Response:
    return fleet_detail(request, "vehicle", record_id)


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def drivers(request) -> Response:
    return fleet_collection(request, "driver")


@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def driver(request, record_id: int) -> Response:
    return fleet_detail(request, "driver", record_id)


# -- routes -----------------------------------------------------------------


def route_detail_response(route_id: int, **kwargs) -> Response:
    route, stops = TransportRouteService.detail(route_id)

    return Response(transport_route_resource(route, stops), **kwargs)


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def routes(request) -> Response:
    if request.method == "POST":
        authorize(TransportRoutePolicy.create(request.user))

        form = StoreTransportRouteRequest(data=request.data, actor=request.user)
        form.is_valid(raise_exception=True)

        created = TransportRouteService.create(form.validated_data)

        return route_detail_response(created.pk, status=status.HTTP_201_CREATED)

    authorize(TransportRoutePolicy.view_any(request.user))

    found = TransportRouteService.visible_to(request.user, {
        "school_id": request.query_params.get("school_id"),
        "status": request.query_params.get("status"),
    })

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)

    # The list leaves each route's stops out; only the detail carries them.
    return paginator.get_paginated_response([transport_route_resource(row) for row in page])


@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def route(request, route_id: int) -> Response:
    found = get_object_or_404(TransportRoute, pk=route_id)

    if request.method == "DELETE":
        authorize(TransportRoutePolicy.manage(request.user, found))
        TransportRouteService.delete(found)

        return Response(status=status.HTTP_204_NO_CONTENT)

    if request.method == "PATCH":
        authorize(TransportRoutePolicy.manage(request.user, found))

        form = UpdateTransportRouteRequest(data=request.data, route=found)
        form.is_valid(raise_exception=True)
        TransportRouteService.update(found, form.validated_data)
    else:
        authorize(TransportRoutePolicy.view(request.user, found))

    return route_detail_response(found.pk)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def route_students(request, route_id: int) -> Response:
    found = get_object_or_404(TransportRoute, pk=route_id)

    authorize(TransportRoutePolicy.view_students(request.user, found))

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(StudentTransportService.students_on(found), request)

    return paginator.get_paginated_response([route_student_resource(row) for row in page])


# -- stops ------------------------------------------------------------------


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def add_stop(request, route_id: int) -> Response:
    found = get_object_or_404(TransportRoute, pk=route_id)

    authorize(TransportRoutePolicy.manage(request.user, found))

    form = StoreTransportStopRequest(data=request.data, route=found)
    form.is_valid(raise_exception=True)

    stop = TransportRouteService.add_stop(found, form.validated_data)

    return Response(transport_stop_resource(stop, stop.students_count), status=status.HTTP_201_CREATED)


@api_view(["PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def stop(request, stop_id: int) -> Response:
    found = get_object_or_404(TransportStop.objects.select_related("route"), pk=stop_id)

    # Changing a stop is changing its route.
    authorize(TransportRoutePolicy.manage(request.user, found.route))

    if request.method == "DELETE":
        TransportRouteService.delete_stop(found)

        return Response(status=status.HTTP_204_NO_CONTENT)

    form = UpdateTransportStopRequest(data=request.data, stop=found)
    form.is_valid(raise_exception=True)

    updated = TransportRouteService.update_stop(found, form.validated_data)

    return Response(transport_stop_resource(updated, updated.students_count))


# -- which student rides which route ----------------------------------------


@api_view(["PUT", "DELETE"])
@permission_classes([IsAuthenticated])
def student_transport(request, student_id: int) -> Response:
    student = get_object_or_404(Student, pk=student_id)

    authorize(StudentPolicy.update(request.user, student))

    if request.method == "DELETE":
        StudentTransportService.unassign(student)

        return Response(student_resource(reload(student.pk)))

    form = AssignStudentTransportRequest(data=request.data, student=student)
    form.is_valid(raise_exception=True)

    found_route = get_object_or_404(TransportRoute.objects.select_related("vehicle"), pk=form.validated_data["route_id"])
    found_stop = get_object_or_404(TransportStop, pk=form.validated_data["transport_stop_id"])

    StudentTransportService.assign(student, found_route, found_stop)

    return Response(student_resource(reload(student.pk)))
