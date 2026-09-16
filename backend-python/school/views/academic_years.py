"""Academic years.

Port of AcademicYearController. Two things here are not ordinary CRUD:

- **Exactly one year is current per school.** Setting one clears the rest, in
  a transaction, through its own endpoint rather than as a field edit - a year
  becoming current makes another stop being current, which is not something a
  PATCH of a name should do quietly.
- **Deleting is refused while classes hang off it**, with the reason. This is
  the only module in M9 that deletes anything at all.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..models import AcademicYear
from ..pagination import LaravelPagination
from ..policies import AcademicYearPolicy, authorize
from ..requests import StoreAcademicYearRequest, UpdateAcademicYearRequest
from ..resources import academic_year_resource
from ..services import AcademicYearService


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method == "POST":
        return store(request)

    return index(request)


def index(request) -> Response:
    authorize(AcademicYearPolicy.view_any(request.user))

    years = AcademicYearService.visible_to(
        request.user, {"school_id": request.query_params.get("school_id")}
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(years, request)

    return paginator.get_paginated_response([academic_year_resource(year) for year in page])


def store(request) -> Response:
    authorize(AcademicYearPolicy.create(request.user))

    form = StoreAcademicYearRequest(data=request.data, actor=request.user)
    form.is_valid(raise_exception=True)

    year = AcademicYearService.create(form.validated_data, request.user)

    return Response(academic_year_resource(reload(year.id)), status=status.HTTP_201_CREATED)


@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def detail(request, year_id: int) -> Response:
    year = get_object_or_404(AcademicYear.objects.select_related("school"), pk=year_id)

    if request.method == "PATCH":
        return update(request, year)

    if request.method == "DELETE":
        return destroy(request, year)

    authorize(AcademicYearPolicy.view(request.user, year))

    return Response(academic_year_resource(year))


def update(request, year: AcademicYear) -> Response:
    authorize(AcademicYearPolicy.update(request.user, year))

    form = UpdateAcademicYearRequest(data=request.data, actor=request.user, year=year)
    form.is_valid(raise_exception=True)

    AcademicYearService.update(year, form.validated_data)

    return Response(academic_year_resource(reload(year.id)))


def destroy(request, year: AcademicYear) -> Response:
    authorize(AcademicYearPolicy.delete(request.user, year))

    AcademicYearService.delete(year)

    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(["PATCH"])
@permission_classes([IsAuthenticated])
def set_current(request, year_id: int) -> Response:
    year = get_object_or_404(AcademicYear.objects.select_related("school"), pk=year_id)

    authorize(AcademicYearPolicy.set_current(request.user, year))

    AcademicYearService.set_current(year)

    return Response(academic_year_resource(reload(year.id)))


def reload(year_id: int) -> AcademicYear:
    return AcademicYear.objects.select_related("school").get(pk=year_id)
