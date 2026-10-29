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

from .. import analytics, modules, permissions
from ..policies import FeePolicy, authorize, permitted
from ..requests import AnalyticsSeriesRequest
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

    # As in the reports: a school outside the actor's reach is ignored, and
    # one who may see only their own school charts it whatever they ask for.
    scope = SchoolScope.for_actor(actor)
    # Validation has already made it a number or nothing.
    raw = form.initial_data.get("school_id")
    requested = int(raw) if raw is not None else None
    requested = requested or None
    school_id = scope.writable_school_id(requested if scope.allows(requested) else None)

    if school_id is None:
        # A Group Admin naming no branch. A1 charts one school at a time.
        raise serializers.ValidationError({"school_id": ["Pick a school to chart."]})

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
