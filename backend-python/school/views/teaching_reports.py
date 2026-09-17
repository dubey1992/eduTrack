"""Daily teaching reports.

Port of DailyTeachingReportController. Four endpoints: file a report, list
them, the KPI row above the list, and review one.

The order checks happen in matters and follows Laravel's exactly. Filing
validates first, so a malformed report is a 422 whoever sent it; only then is
the period loaded and the policy asked whether it is the actor's to report
on. The summary is the other way round - the role gate comes before the date
is read - because there the date is read inside the controller rather than by
a form request.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..clock import SchoolClock
from ..models import DailyTeachingReport, TimetableEntry
from ..pagination import LaravelPagination
from ..policies import DailyTeachingReportPolicy, authorize
from ..requests import StoreDailyTeachingReportRequest, TeachingReportSummaryRequest
from ..resources import daily_teaching_report_resource
from ..services import DailyTeachingReportService


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method == "POST":
        return file_a_report(request)

    authorize(DailyTeachingReportPolicy.view_any(request.user))

    reports = DailyTeachingReportService.visible_to(
        request.user,
        {
            "school_id": request.query_params.get("school_id"),
            "teacher_id": request.query_params.get("teacher_id"),
            "report_date": request.query_params.get("report_date"),
        },
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(reports, request)

    return paginator.get_paginated_response(
        [daily_teaching_report_resource(row) for row in page]
    )


def file_a_report(request) -> Response:
    # "Not in the future" is measured on the school's calendar, not the
    # server's: a teacher in Kolkata filing at 7am is already on a date a UTC
    # server has not reached.
    today = SchoolClock.for_scope(request.user, request.data.get("school_id")).now().date()

    form = StoreDailyTeachingReportRequest(
        data=request.data, actor=request.user, context={"school_today": today}
    )
    form.is_valid(raise_exception=True)

    entry = get_object_or_404(TimetableEntry, pk=form.validated_data["timetable_entry_id"])

    authorize(DailyTeachingReportPolicy.create(request.user, entry))

    report = DailyTeachingReportService.create(entry, form.validated_data, request.user)

    return Response(daily_teaching_report_resource(report), status=status.HTTP_201_CREATED)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def summary(request) -> Response:
    authorize(DailyTeachingReportPolicy.view_any(request.user))

    form = TeachingReportSummaryRequest(data=request.query_params.dict())
    form.is_valid(raise_exception=True)

    return Response(
        DailyTeachingReportService.summary(
            request.user,
            {"school_id": request.query_params.get("school_id")},
            form.validated_data["date"],
        )
    )


@api_view(["PATCH"])
@permission_classes([IsAuthenticated])
def review(request, report_id: int) -> Response:
    report = get_object_or_404(
        DailyTeachingReport.objects.select_related("teacher"), pk=report_id
    )

    authorize(DailyTeachingReportPolicy.review(request.user, report))

    return Response(
        daily_teaching_report_resource(DailyTeachingReportService.review(report, request.user))
    )
