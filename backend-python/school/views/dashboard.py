"""The landing screen.

Port of DashboardController. No authorization gate: every signed-in user has
a dashboard, and what it holds is decided by their role in DashboardService
rather than by anything they send. The school_id filter only moves a Super
Admin, or an admin within their own group - see SchoolScope.
"""

from __future__ import annotations

from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..years import year_in_view
from ..dashboard import DashboardService


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def index(request) -> Response:
    # The top bar's year (decided 2026-11-05) moves the Results card only:
    # everything else on the dashboard is about today.
    return Response(
        DashboardService.for_user(request.user, request.query_params.get("school_id"), year_in_view(request))
    )
