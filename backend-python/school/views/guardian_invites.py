"""The school office's side of a parent's request for a second guardian
(docs/mobile-apps-review.md, M8, 8.5): the list, and approve or decline.

Who decides is whoever may edit the student - a School Admin by default - as
for adding a guardian by hand. The parent's side is in views/family.py.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework.decorators import api_view, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import guardian_invites
from ..models import GuardianInvite
from ..pagination import LaravelPagination
from ..policies import StudentPolicy, authorize, permitted
from ..scope import SchoolScope

STATUSES = (guardian_invites.PENDING, guardian_invites.APPROVED, guardian_invites.DECLINED)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    """The requests of the schools the caller may manage students in;
    pending by default, newest first."""
    authorize(permitted(request.user, "students", write=True))

    wanted = request.query_params.get("status", guardian_invites.PENDING)
    if wanted not in STATUSES:
        raise ValidationError({"status": ["Choose pending, approved or declined."]})

    rows = (
        SchoolScope.for_actor(request.user)
        .apply_to(GuardianInvite.objects.filter(status=wanted))
        .select_related("student__class_section__school_class", "requested_by", "decided_by")
        .order_by("-created_at", "-id")
    )
    paginator = LaravelPagination()
    page = paginator.paginate_queryset(rows, request)

    return paginator.get_paginated_response([guardian_invites.office_resource(row) for row in page])


def decided_invite(request, invite_id: int) -> GuardianInvite:
    invite = get_object_or_404(
        GuardianInvite.objects.select_related("student__class_section__school_class", "requested_by", "decided_by"),
        pk=invite_id,
    )
    authorize(StudentPolicy.update(request.user, invite.student))

    return invite


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def approve(request, invite_id: int) -> Response:
    invite = guardian_invites.approve(decided_invite(request, invite_id), request.user)

    return Response({"data": guardian_invites.office_resource(invite)})


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def decline(request, invite_id: int) -> Response:
    invite = guardian_invites.decline(decided_invite(request, invite_id), request.user)

    return Response({"data": guardian_invites.office_resource(invite)})
