"""Students: the roll, and everything a school does to it.

Port of StudentController. Every handler follows the same four steps as the
PHP - authorize, validate, call the service, render - and the authorize step
comes first even on reads, because a policy that runs after a query has
already read the row is a policy that has already leaked it.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..enums import StudentStatus
from ..models import Student
from ..pagination import LaravelPagination
from ..policies import StudentPolicy, authorize
from ..requests import StoreStudentRequest, UpdateStudentRequest
from ..resources import student_enrollment_resource, student_resource
from ..services import StudentEnrollmentService, StudentService

# What a student is rendered with - the same list Laravel's StudentController
# eager-loads. Named once so the list and the four single-record endpoints
# cannot drift into loading different things and answering with different
# shapes, which is a real risk here: whether a relation is loaded decides
# whether its key appears at all, not merely what it holds.
WITH = StudentService.WITH


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method == "POST":
        return store(request)

    return index(request)


def index(request) -> Response:
    authorize(StudentPolicy.view_any(request.user))

    students = StudentService.visible_to(
        request.user,
        {
            "school_id": request.query_params.get("school_id"),
            "class_section_id": request.query_params.get("class_section_id"),
            "status": request.query_params.get("status"),
            "search": request.query_params.get("search"),
        },
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(students, request)

    return paginator.get_paginated_response([student_resource(student) for student in page])


def store(request) -> Response:
    authorize(StudentPolicy.create(request.user))

    form = StoreStudentRequest(data=request.data, actor=request.user)
    form.is_valid(raise_exception=True)

    student = StudentService.create(form.validated_data, request.user)

    return Response(
        student_resource(reload(student.id)),
        status=status.HTTP_201_CREATED,
    )


@api_view(["GET", "PATCH"])
@permission_classes([IsAuthenticated])
def detail(request, student_id: int) -> Response:
    student = get_object_or_404(Student.objects.select_related(*WITH), pk=student_id)

    if request.method == "PATCH":
        return update(request, student)

    authorize(StudentPolicy.view(request.user, student))

    return Response(student_resource(student))


def update(request, student: Student) -> Response:
    authorize(StudentPolicy.update(request.user, student))

    form = UpdateStudentRequest(data=request.data, actor=request.user, student=student)
    form.is_valid(raise_exception=True)

    StudentService.update(student, form.validated_data)

    return Response(student_resource(reload(student.id)))


@api_view(["PATCH"])
@permission_classes([IsAuthenticated])
def activate(request, student_id: int) -> Response:
    return set_status(request, student_id, StudentStatus.ACTIVE)


@api_view(["PATCH"])
@permission_classes([IsAuthenticated])
def deactivate(request, student_id: int) -> Response:
    """Deactivating, never deleting.

    A student who has left keeps their attendance, their reports and their
    place in last year's register. Erasing the row would take those with it,
    which is why no endpoint in this API deletes a student at all.
    """
    return set_status(request, student_id, StudentStatus.INACTIVE)


def set_status(request, student_id: int, status_value: str) -> Response:
    student = get_object_or_404(Student.objects.select_related(*WITH), pk=student_id)

    authorize(StudentPolicy.set_status(request.user, student))

    StudentService.set_status(student, status_value)

    return Response(student_resource(reload(student.id)))


def reload(student_id: int) -> Student:
    """Reads the student back with its relations.

    A write returns the record as the client will store it, and the client
    stores `school_name` and `class_section_name` - which come from relations
    a freshly created or freshly patched instance has not loaded. Rendering
    without them would send null for two fields the same record answers with
    the moment it is fetched again.
    """
    return Student.objects.select_related(*WITH).get(pk=student_id)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def enrollments(request, student_id: int) -> Response:
    """A student's year-by-year history (docs/promotion.md).

    A plain list rather than a page: it holds one row per academic year the
    school has ever run, which is a handful, and a screen shows all of them
    at once.
    """
    student = get_object_or_404(Student.objects.select_related("school", "class_section"), pk=student_id)

    authorize(StudentPolicy.view(request.user, student))

    return Response(
        [student_enrollment_resource(row) for row in StudentEnrollmentService.history_for(student)]
    )
