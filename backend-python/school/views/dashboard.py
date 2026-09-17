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

from ..dashboard import DashboardService


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def index(request) -> Response:
    return Response(DashboardService.for_user(request.user, request.query_params.get("school_id")))
