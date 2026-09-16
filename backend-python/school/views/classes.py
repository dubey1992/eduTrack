"""Classes, their sections, the school day's periods, and the holiday calendar.

Ports of SchoolClassController, PeriodController and HolidayController - the
last of M9's academic configuration.

Three things here are not ordinary CRUD:

- **A class carries its sections.** They are fetched for the whole page in one
  query rather than one per class, because a school with thirty classes would
  otherwise cost thirty-one.
- **Periods are not paginated.** A school has eight or nine, and a paging
  control on a list that short is furniture nobody uses.
- **A holiday reports what it broke.** Declaring one after the fact is a
  legitimate correction; doing it silently is not, because the attendance
  already marked on those days stops counting towards every working-day
  figure in the product.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..models import ClassSection, Holiday, Period, SchoolClass
from ..pagination import LaravelPagination
from ..policies import (
    ClassSectionPolicy,
    HolidayPolicy,
    PeriodPolicy,
    SchoolClassPolicy,
    authorize,
)
from ..requests import (
    StoreClassSectionRequest,
    StoreHolidayRequest,
    StorePeriodRequest,
    StoreSchoolClassRequest,
    UpdateClassSectionRequest,
    UpdateHolidayRequest,
    UpdatePeriodRequest,
    UpdateSchoolClassRequest,
)
from ..resources import (
    class_section_resource,
    holiday_resource,
    period_resource,
    school_class_resource,
)
from ..services import HolidayService, PeriodService, SchoolClassService

# -- classes ----------------------------------------------------------------


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def classes(request) -> Response:
    if request.method == "POST":
        authorize(SchoolClassPolicy.create(request.user))

        form = StoreSchoolClassRequest(data=request.data, actor=request.user)
        form.is_valid(raise_exception=True)

        created = SchoolClassService.create(form.validated_data, request.user)

        return Response(with_sections(created.id), status=status.HTTP_201_CREATED)

    authorize(SchoolClassPolicy.view_any(request.user))

    found = SchoolClassService.visible_to(
        request.user,
        {
            "school_id": request.query_params.get("school_id"),
            "academic_year_id": request.query_params.get("academic_year_id"),
        },
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)

    # One query for the whole page's sections, not one per class.
    sections = SchoolClassService.sections_of(row.id for row in page)

    return paginator.get_paginated_response(
        [school_class_resource(row, sections.get(row.id, [])) for row in page]
    )


@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def school_class(request, class_id: int) -> Response:
    record = get_object_or_404(
        SchoolClass.objects.select_related(*SchoolClassService.WITH), pk=class_id
    )

    if request.method == "PATCH":
        authorize(SchoolClassPolicy.update(request.user, record))

        form = UpdateSchoolClassRequest(
            data=request.data, actor=request.user, school_class=record
        )
        form.is_valid(raise_exception=True)

        SchoolClassService.update(record, form.validated_data)

        return Response(with_sections(record.id))

    if request.method == "DELETE":
        authorize(SchoolClassPolicy.delete(request.user, record))

        SchoolClassService.delete(record)

        return Response(status=status.HTTP_204_NO_CONTENT)

    authorize(SchoolClassPolicy.view(request.user, record))

    return Response(with_sections(record.id))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def add_section(request, class_id: int) -> Response:
    record = get_object_or_404(SchoolClass, pk=class_id)

    # Asked of the class, because a section does not exist yet to ask about.
    authorize(SchoolClassPolicy.update(request.user, record))

    form = StoreClassSectionRequest(data=request.data, school_class=record)
    form.is_valid(raise_exception=True)

    section = SchoolClassService.add_section(record, form.validated_data)

    return Response(reload_section(section.id), status=status.HTTP_201_CREATED)


@api_view(["PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def section(request, section_id: int) -> Response:
    record = get_object_or_404(
        ClassSection.objects.select_related("school_class", "class_teacher"), pk=section_id
    )

    if request.method == "DELETE":
        authorize(ClassSectionPolicy.delete(request.user, record))

        SchoolClassService.delete_section(record)

        return Response(status=status.HTTP_204_NO_CONTENT)

    authorize(ClassSectionPolicy.update(request.user, record))

    form = UpdateClassSectionRequest(data=request.data, section=record)
    form.is_valid(raise_exception=True)

    SchoolClassService.update_section(record, form.validated_data)

    return Response(reload_section(record.id))


def with_sections(class_id: int) -> dict:
    record = SchoolClass.objects.select_related(*SchoolClassService.WITH).get(pk=class_id)

    return school_class_resource(record, SchoolClassService.sections_of([class_id]).get(class_id, []))


def reload_section(section_id: int) -> dict:
    return class_section_resource(
        ClassSection.objects.select_related("class_teacher").get(pk=section_id)
    )


# -- periods ----------------------------------------------------------------


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def periods(request) -> Response:
    if request.method == "POST":
        authorize(PeriodPolicy.create(request.user))

        form = StorePeriodRequest(data=request.data, actor=request.user)
        form.is_valid(raise_exception=True)

        created = PeriodService.create(form.validated_data, request.user)

        return Response(period_resource(created), status=status.HTTP_201_CREATED)

    authorize(PeriodPolicy.view_any(request.user))

    found = PeriodService.visible_to(
        request.user, {"school_id": request.query_params.get("school_id")}
    )

    # A bare array, not {"data": [...]}.
    #
    # Laravel calls JsonResource::withoutWrapping(), so a single resource and
    # a non-paginated collection are both flat; only the paginator adds
    # data/links/meta. The Flutter client relies on it here - period_api.dart
    # does `response.data as List`, which would throw on an object.
    #
    # Caught by diffing the two backends. Every test on this side passed with
    # the wrapper, because the tests were written against the wrapper.
    return Response([period_resource(row) for row in found])


@api_view(["PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def period(request, period_id: int) -> Response:
    record = get_object_or_404(Period, pk=period_id)

    if request.method == "DELETE":
        authorize(PeriodPolicy.delete(request.user, record))

        PeriodService.delete(record)

        return Response(status=status.HTTP_204_NO_CONTENT)

    authorize(PeriodPolicy.update(request.user, record))

    form = UpdatePeriodRequest(data=request.data, actor=request.user, period=record)
    form.is_valid(raise_exception=True)

    PeriodService.update(record, form.validated_data)

    return Response(period_resource(Period.objects.get(pk=record.id)))


# -- holidays ---------------------------------------------------------------


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def holidays(request) -> Response:
    if request.method == "POST":
        authorize(HolidayPolicy.create(request.user))

        form = StoreHolidayRequest(data=request.data, actor=request.user)
        form.is_valid(raise_exception=True)

        created = HolidayService.create(form.validated_data, request.user)

        return Response(
            holiday_resource(reload_holiday(created.id), HolidayService.affected_records(created)),
            status=status.HTTP_201_CREATED,
        )

    authorize(HolidayPolicy.view_any(request.user))

    found = HolidayService.visible_to(
        request.user,
        {
            "school_id": request.query_params.get("school_id"),
            "date_from": request.query_params.get("date_from"),
            "date_to": request.query_params.get("date_to"),
        },
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)

    return paginator.get_paginated_response([holiday_resource(row) for row in page])


@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def holiday(request, holiday_id: int) -> Response:
    record = get_object_or_404(Holiday.objects.select_related("school"), pk=holiday_id)

    if request.method == "PATCH":
        authorize(HolidayPolicy.update(request.user, record))

        form = UpdateHolidayRequest(data=request.data, actor=request.user, holiday=record)
        form.is_valid(raise_exception=True)

        HolidayService.update(record, form.validated_data)

        return Response(
            holiday_resource(reload_holiday(record.id), HolidayService.affected_records(record))
        )

    if request.method == "DELETE":
        authorize(HolidayPolicy.delete(request.user, record))

        HolidayService.delete(record)

        return Response(status=status.HTTP_204_NO_CONTENT)

    authorize(HolidayPolicy.view(request.user, record))

    return Response(holiday_resource(record))


def reload_holiday(holiday_id: int) -> Holiday:
    return Holiday.objects.select_related("school").get(pk=holiday_id)
