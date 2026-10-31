"""A new school's setup guide, and the departments it can add in one step
(docs/onboarding.md, slice O4).

The guide is a School Admin's: it describes their own school, from the data
the school already has. Nobody else has a school to set up in this sense - a
Super or Group Admin sets schools up through the screens themselves.
"""

from __future__ import annotations

from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import audit, setup_guide
from ..enums import UserRole
from ..models import School
from ..policies import DepartmentPolicy, authorize
from ..requests import QuickDepartmentSetupRequest
from ..services import DepartmentService


def own_school(request) -> School:
    user = request.user
    authorize(user.role == UserRole.SCHOOL_ADMIN and user.school_id is not None)

    return School.objects.get(pk=user.school_id)


def guide(school: School) -> dict:
    steps = setup_guide.steps_for(school.id)

    return {
        "school_id": school.id,
        "school_name": school.name,
        "closed": school.setup_guide_closed_at is not None,
        "done": sum(1 for step in steps if step["done"]),
        "total": len(steps),
        "steps": steps,
        "extras": [{"title": title, "path": path, "detail": detail} for title, path, detail in setup_guide.EXTRAS],
    }


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def show(request) -> Response:
    return Response(guide(own_school(request)))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def close(request) -> Response:
    """Finished or hidden: off the dashboard for every admin of the school."""
    return Response(guide(set_closed(own_school(request), closed=True)))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def reopen(request) -> Response:
    """Back on the dashboard."""
    return Response(guide(set_closed(own_school(request), closed=False)))


def set_closed(school: School, closed: bool) -> School:
    if (school.setup_guide_closed_at is not None) == closed:
        return school

    before = audit.fields_of(school)
    school.setup_guide_closed_at = timezone.now() if closed else None
    school.updated_at = timezone.now()
    school.save(update_fields=["setup_guide_closed_at", "updated_at"])
    audit.updated("schools", school, before)

    return school


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def quick_departments(request) -> Response:
    """Common departments in one step. GET says what is offered and ticked;
    POST adds the ones chosen, skipping any the school already has."""
    authorize(DepartmentPolicy.create(request.user))

    if request.method == "GET":
        return Response(
            {"departments": [{"name": name, "selected": ticked} for name, ticked in setup_guide.DEPARTMENT_PRESETS]}
        )

    form = QuickDepartmentSetupRequest(data=request.data, actor=request.user)
    form.is_valid(raise_exception=True)

    return Response(
        DepartmentService.quick_setup(form.validated_data, request.user), status=status.HTTP_201_CREATED
    )
