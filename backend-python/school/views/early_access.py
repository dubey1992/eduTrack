"""Early access: the marketing page's signup form, and the Super Admin's queue.

Port of EarlyAccessController. Signing up is public - it is how a school with
no account asks for one - and throttled for that reason. Everything else is
the Super Admin's.

One path serves both the public write and the panel's read, so the view
checks who is asking itself rather than leaning on one permission class: an
anonymous signup is welcome, an anonymous read of the queue is a 401.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.exceptions import NotAuthenticated
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..enums import UserRole
from ..models import EarlyAccessRequest
from ..pagination import LaravelPagination
from ..policies import authorize
from ..requests import ReviewEarlyAccessRequest, StoreEarlyAccessRequest
from ..resources import early_access_resource
from ..services import EarlyAccessService
from ..throttling import EarlyAccessThrottle


def is_super_admin(user) -> bool:
    return user is not None and user.role == UserRole.SUPER_ADMIN


@api_view(["GET", "POST"])
@permission_classes([])
@throttle_classes([EarlyAccessThrottle])
def collection(request) -> Response:
    if request.method == "POST":
        form = StoreEarlyAccessRequest(data=request.data)
        form.is_valid(raise_exception=True)

        EarlyAccessService.record(form.validated_data)

        # The same answer whether this was a new request or a correction to
        # one already open.
        return Response(
            {"message": "Thanks - we have your details and will be in touch soon."},
            status=status.HTTP_201_CREATED,
        )

    if request.user is None:
        raise NotAuthenticated()

    authorize(is_super_admin(request.user))

    found = EarlyAccessService.visible_to({
        "status": request.query_params.get("status"),
        "q": (request.query_params.get("q") or "").strip() or None,
    })

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)

    return paginator.get_paginated_response([early_access_resource(row) for row in page])


@api_view(["GET", "PATCH"])
@permission_classes([IsAuthenticated])
def detail(request, request_id: int) -> Response:
    found = get_object_or_404(
        EarlyAccessRequest.objects.select_related("converted_school", "reviewed_by"), pk=request_id
    )

    authorize(is_super_admin(request.user))

    if request.method == "PATCH":
        form = ReviewEarlyAccessRequest(data=request.data)
        form.is_valid(raise_exception=True)

        found = EarlyAccessService.review(found, form.validated_data, request.user)

    return Response(early_access_resource(found))
