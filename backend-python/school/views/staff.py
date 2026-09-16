"""Teachers and other staff.

Port of StaffController. The Add Employee screen is one form and creates two
rows in one transaction - the login and the employment record - because half
an employee is not a state the product has a screen for: a login with no
profile is invisible to Attendance and Leave, and a profile with no login is
somebody on a roster who cannot sign in.

Admins only, even to read. A teacher does not browse their colleagues' joining
dates and addresses, which is the one way this differs from the other
school-owned modules.

There is no delete. Somebody who has left is deactivated through the Users
endpoints, which keeps their attendance, their leave and their name on last
year's timetable.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..models import StaffProfile
from ..pagination import LaravelPagination
from ..policies import StaffProfilePolicy, authorize
from ..requests import StoreStaffRequest, UpdateStaffProfileRequest
from ..resources import staff_profile_resource
from ..services import StaffProfileService


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method == "POST":
        return store(request)

    authorize(StaffProfilePolicy.view_any(request.user))

    found = StaffProfileService.visible_to(
        request.user,
        {
            "school_id": request.query_params.get("school_id"),
            "department_id": request.query_params.get("department_id"),
            "role": request.query_params.get("role"),
            "status": request.query_params.get("status"),
            "search": request.query_params.get("search"),
        },
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)

    # One query for the whole page's assigned classes, not one per employee.
    taught = StaffProfileService.classes_taught_by(row.user_id for row in page)

    return paginator.get_paginated_response(
        [staff_profile_resource(row, taught.get(row.user_id, [])) for row in page]
    )


def store(request) -> Response:
    authorize(StaffProfilePolicy.create(request.user))

    form = StoreStaffRequest(data=request.data, actor=request.user)
    form.is_valid(raise_exception=True)

    profile = StaffProfileService.create_employee(
        form.user_data(), form.profile_data(), request.user
    )

    return Response(rendered(profile.id), status=status.HTTP_201_CREATED)


@api_view(["GET", "PATCH"])
@permission_classes([IsAuthenticated])
def detail(request, profile_id: int) -> Response:
    profile = get_object_or_404(
        StaffProfile.objects.select_related(*StaffProfileService.WITH), pk=profile_id
    )

    if request.method == "PATCH":
        authorize(StaffProfilePolicy.update(request.user, profile))

        form = UpdateStaffProfileRequest(data=request.data, actor=request.user, profile=profile)
        form.is_valid(raise_exception=True)

        StaffProfileService.update(profile, form.validated_data)

        return Response(rendered(profile.id))

    authorize(StaffProfilePolicy.view(request.user, profile))

    return Response(rendered(profile.id))


def rendered(profile_id: int) -> dict:
    profile = StaffProfile.objects.select_related(*StaffProfileService.WITH).get(pk=profile_id)
    taught = StaffProfileService.classes_taught_by([profile.user_id])

    return staff_profile_resource(profile, taught.get(profile.user_id, []))
