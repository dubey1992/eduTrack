"""Staff leave.

Port of StaffLeaveController. Five endpoints: apply, list, the stat cards
above the list, approve and reject.

Two of the checks a reader might expect to find here live elsewhere on
purpose. *Who* a reviewer may decide for is the policy's question, asked
against the leave row itself rather than against a school id, because an HOD's
reach is a department. And *what* a list contains is the service's, because
"my own leave", "my department's" and "my school's" are the same endpoint seen
by different people - a role gate here would only duplicate that badly.

The odd one out is the missing profile. Applying is allowed by role, but an
account with no employment record has nothing to apply against. That is a
missing row rather than a refusal, so it answers with a sentence naming the
fix instead of a 403 that leaves somebody arguing with the wrong person.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..errors import StaffProfileRequired
from ..models import StaffLeave
from ..pagination import LaravelPagination
from ..policies import StaffLeavePolicy, authorize
from ..requests import ApplyStaffLeaveRequest, ReviewStaffLeaveRequest
from ..resources import staff_leave_resource
from ..services import StaffLeaveService


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method == "POST":
        return apply_for_leave(request)

    authorize(StaffLeavePolicy.view_any(request.user))

    leaves = StaffLeaveService.visible_to(
        request.user,
        {
            "school_id": request.query_params.get("school_id"),
            "staff_profile_id": request.query_params.get("staff_profile_id"),
            "department_id": request.query_params.get("department_id"),
            "status": request.query_params.get("status"),
        },
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(leaves, request)

    return paginator.get_paginated_response([staff_leave_resource(row) for row in page])


def apply_for_leave(request) -> Response:
    # Validation, then the role, then the profile - the order a Laravel form
    # request produces, where the rules run before the controller body ever
    # starts. A bad field is a 422 whoever sent it.
    form = ApplyStaffLeaveRequest(data=request.data, actor=request.user)
    form.is_valid(raise_exception=True)

    authorize(StaffLeavePolicy.apply(request.user))

    profile = request.user.staff_profile

    if profile is None:
        raise StaffProfileRequired(
            "Your account is not yet linked to a staff profile. Ask your school admin "
            "to add you under Teachers & Staff before applying for leave."
        )

    leave = StaffLeaveService.apply(profile, form.validated_data, request.user)

    return Response(staff_leave_resource(leave), status=status.HTTP_201_CREATED)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def summary(request) -> Response:
    authorize(StaffLeavePolicy.view_any(request.user))

    return Response(
        StaffLeaveService.summary(
            request.user, {"school_id": request.query_params.get("school_id")}
        )
    )


@api_view(["PATCH"])
@permission_classes([IsAuthenticated])
def approve(request, leave_id: int) -> Response:
    return decide(request, leave_id, StaffLeaveService.approve)


@api_view(["PATCH"])
@permission_classes([IsAuthenticated])
def reject(request, leave_id: int) -> Response:
    return decide(request, leave_id, StaffLeaveService.reject)


def decide(request, leave_id: int, decision) -> Response:
    """Approve and reject differ only in which way they go.

    Both find the row first and let the policy see it, because who may decide
    depends on whose leave it is - an HOD's own request is not theirs to
    approve, and neither is another department's.
    """
    leave = get_object_or_404(
        StaffLeave.objects.select_related("staff_profile__department"), pk=leave_id
    )

    form = ReviewStaffLeaveRequest(data=request.data, actor=request.user)
    form.is_valid(raise_exception=True)

    authorize(StaffLeavePolicy.review(request.user, leave))

    reviewed = decision(leave, request.user, form.validated_data.get("remarks"))

    return Response(staff_leave_resource(reviewed))
