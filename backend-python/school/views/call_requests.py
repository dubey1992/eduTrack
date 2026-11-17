"""Parents' "please call me", as the school sees them (docs/parent-student-app.md,
F5). The parent's side is in views/family.py.

- GET  call-requests[?status=open|called] - open first, newest first: a
  teacher's own; every request at the school for its admins.
- POST call-requests/{id}/called - {outcome_note?}: called; the parent sees it.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import call_requests
from ..enums import UserRole
from ..models import CallRequest
from ..pagination import LaravelPagination
from ..policies import authorize
from ..scope import SchoolScope

HANDLERS = (UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN, UserRole.TEACHER, UserRole.HOD)


def requests_query():
    return CallRequest.objects.select_related("student", "requested_by", "teacher_user", "called_by")


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    actor = request.user
    authorize(actor.role in HANDLERS)

    if actor.role in (UserRole.TEACHER, UserRole.HOD):
        rows = requests_query().filter(teacher_user_id=actor.id)
    else:
        rows = SchoolScope.for_actor(actor).apply_to(requests_query())

    wanted = request.query_params.get("status")
    if wanted in (call_requests.OPEN, call_requests.CALLED):
        rows = rows.filter(status=wanted)

    rows = rows.order_by("-status", "-created_at", "-id")
    paginator = LaravelPagination()
    page = paginator.paginate_queryset(rows, request)

    return paginator.get_paginated_response([call_requests.staff_request_resource(r) for r in page])


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def called(request, request_id: int) -> Response:
    found = get_object_or_404(requests_query(), pk=request_id)
    authorize(call_requests.may_handle(request.user, found))

    done = call_requests.mark_called(found, request.user, request.data.get("outcome_note"))
    return Response(call_requests.staff_request_resource(done))
