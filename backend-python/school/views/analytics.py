"""Analytics, A1 (docs/analytics.md): a measure over time, for one school.

Who may chart a measure is exactly who may read the report it comes from -
the same matrix row, the same roles, the same module switch - so a chart
never shows a figure its reader could not already print.
"""

from __future__ import annotations

from rest_framework import serializers
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import analytics, early_warning, modules, permissions
from ..enums import UserRole
from ..errors import ModuleDisabled
from ..models import ClassSection, Department
from ..pagination import LaravelPagination
from ..policies import FeePolicy, authorize, permitted
from ..requests import AnalyticsSeriesRequest, EarlyWarningRequest
from ..scope import SchoolScope
from .reports import filters_for


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def measures(request):
    """What this person may chart, for the picker."""
    actor = request.user

    return Response({
        "data": [
            {"key": measure.key, "label": measure.label, "unit": measure.unit, "snapshot": measure.snapshot}
            for measure in analytics.MEASURES.values()
            if may_chart(actor, measure)
        ],
    })


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def series(request):
    actor = request.user
    form = AnalyticsSeriesRequest(data=request.query_params.dict(), actor=actor)
    form.is_valid(raise_exception=True)
    validated = form.validated_data
    measure = validated["measure"]

    authorize(permitted(actor, "reports") and (measure.roles is None or actor.role in measure.roles))

    if measure.module is not None:
        authorize(permissions.may_view(actor, measure.module))

    school_id = _school_for(actor, form, "Pick a school to chart.")

    if measure.module == "fees":
        authorize(FeePolicy.view(actor, school_id))

    everything = filters_for(actor, validated)
    filters = {key: everything[key] for key in (*measure.filters, "department_ids") if key in everything}

    return Response(analytics.series(school_id, measure, validated["interval"], validated["from"], validated["to"], filters))


def may_chart(actor, measure: analytics.Measure) -> bool:
    if not permitted(actor, "reports") or (measure.roles is not None and actor.role not in measure.roles):
        return False

    if measure.module is not None:
        switched_on = actor.school_id is None or modules.is_enabled(actor.school_id, measure.module)
        if not switched_on or not permissions.may_view(actor, measure.module):
            return False

    return True


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def early_warning_list(request):
    """The flagged students (docs/analytics.md, A3), highest risk first.

    An admin sees the whole school and every signal. A class teacher sees
    their own classes, every signal. A head of department sees the test
    signals from their own departments' subjects. Anyone else is refused;
    a teacher with no class sees an empty list, not an error.
    """
    actor = request.user
    form = EarlyWarningRequest(data=request.query_params.dict(), actor=actor)
    form.is_valid(raise_exception=True)
    validated = form.validated_data

    if actor.role in analytics.ADMINS:
        authorize(permitted(actor, "reports"))
        school_id = _school_for(actor, form, "Pick a school to see its students.")
        scope = early_warning.Scope(full_section_ids=None)
    elif actor.role in (UserRole.HOD, UserRole.TEACHER):
        school_id = actor.school_id
        scope = early_warning.Scope(
            full_section_ids=list(
                ClassSection.objects.filter(class_teacher_id=actor.id, school_class__school_id=school_id)
                .values_list("id", flat=True)
            ),
            department_ids=list(
                Department.objects.filter(school_id=school_id, hod_user_id=actor.id).values_list("id", flat=True)
            )
            if actor.role == UserRole.HOD
            else [],
        )
    else:
        authorize(False)

    # The thresholds are the Reports module's settings; a school that has
    # switched Reports off has no early warning either.
    if not modules.is_enabled(school_id, "reports"):
        raise ModuleDisabled(modules.get("reports").label)

    result = early_warning.flagged(school_id, scope, validated["class_section_id"])
    rows = result["rows"]
    counts = {
        early_warning.HIGH: sum(1 for row in rows if row["level"] == early_warning.HIGH),
        early_warning.AT_RISK: sum(1 for row in rows if row["level"] == early_warning.AT_RISK),
    }

    if validated["level"]:
        rows = [row for row in rows if row["level"] == validated["level"]]

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(rows, request)
    response = paginator.get_paginated_response(page)
    response.data["summary"] = {
        "as_of": result["as_of"],
        "thresholds": result["thresholds"],
        "windows": result["windows"],
        "counts": counts,
    }

    return response


def _school_for(actor, form, missing: str) -> int:
    """The school a request is about. As in the reports: a school outside
    the actor's reach is ignored, and someone who may see only their own
    school gets it whatever they ask for."""
    scope = SchoolScope.for_actor(actor)
    # Validation has already made it a number or nothing.
    raw = form.initial_data.get("school_id")
    requested = int(raw) if raw is not None else None
    requested = requested or None
    school_id = scope.writable_school_id(requested if scope.allows(requested) else None)

    if school_id is None:
        # Someone spanning schools, naming none. One school at a time.
        raise serializers.ValidationError({"school_id": [missing]})

    return school_id
