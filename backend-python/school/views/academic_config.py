"""Departments and subjects.

Ports of DepartmentController and SubjectController. Two modules in one file
because they are the same five endpoints twice over, differing only in the
record they are about - splitting them would produce two files whose diff
against each other is the interesting part.

The rule they share and that matters: **a department may only be headed, and a
subject only led, by somebody who teaches at that school.** Naming a teacher
from another school is an invalid selection rather than a forbidden one - the
client never had a legitimate way to offer it - so it fails validation on the
field rather than with a 403.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..models import Department, Subject
from ..pagination import LaravelPagination
from ..policies import DepartmentPolicy, SubjectPolicy, authorize
from ..requests import (
    StoreDepartmentRequest,
    StoreSubjectRequest,
    UpdateDepartmentRequest,
    UpdateSubjectRequest,
)
from ..resources import department_resource, subject_resource
from ..services import DepartmentService, SubjectService

# -- departments ------------------------------------------------------------


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def departments(request) -> Response:
    if request.method == "POST":
        authorize(DepartmentPolicy.create(request.user))

        form = StoreDepartmentRequest(data=request.data, actor=request.user)
        form.is_valid(raise_exception=True)

        department = DepartmentService.create(form.validated_data, request.user)

        return Response(
            department_resource(reload(Department, DepartmentService, department.id)),
            status=status.HTTP_201_CREATED,
        )

    authorize(DepartmentPolicy.view_any(request.user))

    found = DepartmentService.visible_to(
        request.user, {"school_id": request.query_params.get("school_id")}
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)

    return paginator.get_paginated_response([department_resource(row) for row in page])


@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def department(request, department_id: int) -> Response:
    record = get_object_or_404(
        Department.objects.select_related(*DepartmentService.WITH), pk=department_id
    )

    if request.method == "PATCH":
        authorize(DepartmentPolicy.update(request.user, record))

        form = UpdateDepartmentRequest(data=request.data, actor=request.user, department=record)
        form.is_valid(raise_exception=True)

        DepartmentService.update(record, form.validated_data)

        return Response(department_resource(reload(Department, DepartmentService, record.id)))

    if request.method == "DELETE":
        authorize(DepartmentPolicy.delete(request.user, record))

        DepartmentService.delete(record)

        return Response(status=status.HTTP_204_NO_CONTENT)

    authorize(DepartmentPolicy.view(request.user, record))

    return Response(department_resource(record))


# -- subjects ---------------------------------------------------------------


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def subjects(request) -> Response:
    if request.method == "POST":
        authorize(SubjectPolicy.create(request.user))

        form = StoreSubjectRequest(data=request.data, actor=request.user)
        form.is_valid(raise_exception=True)

        created = SubjectService.create(form.validated_data, request.user)

        return Response(
            subject_resource(reload(Subject, SubjectService, created.id)),
            status=status.HTTP_201_CREATED,
        )

    authorize(SubjectPolicy.view_any(request.user))

    found = SubjectService.visible_to(
        request.user,
        {
            "school_id": request.query_params.get("school_id"),
            "department_id": request.query_params.get("department_id"),
        },
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)

    return paginator.get_paginated_response([subject_resource(row) for row in page])


@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def subject(request, subject_id: int) -> Response:
    record = get_object_or_404(Subject.objects.select_related(*SubjectService.WITH), pk=subject_id)

    if request.method == "PATCH":
        authorize(SubjectPolicy.update(request.user, record))

        form = UpdateSubjectRequest(data=request.data, actor=request.user, subject=record)
        form.is_valid(raise_exception=True)

        SubjectService.update(record, form.validated_data)

        return Response(subject_resource(reload(Subject, SubjectService, record.id)))

    if request.method == "DELETE":
        authorize(SubjectPolicy.delete(request.user, record))

        SubjectService.delete(record)

        return Response(status=status.HTTP_204_NO_CONTENT)

    authorize(SubjectPolicy.view(request.user, record))

    return Response(subject_resource(record))


def reload(model, service, record_id: int):
    """Reads a record back with its relations loaded.

    A write answers the same shape a read does, which matters more here than
    it looks: whether a relation is loaded decides whether `school_name` and
    `department_name` appear at all, not merely what they hold.
    """
    return model.objects.select_related(*service.WITH).get(pk=record_id)
