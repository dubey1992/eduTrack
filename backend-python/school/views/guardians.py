"""A student's guardians, and their Family app sign-in, for the school office
(docs/parent-student-app.md, F0). Whoever may edit the student looks after
their guardians.

- GET    students/{student}/guardians - the student's guardians, primary first.
- POST   students/{student}/guardians - link one (an existing guardian when
  the mobile number matches - the same parent as a sibling's).
- PATCH  students/{student}/guardians/{link} - edit the person and the link.
- DELETE students/{student}/guardians/{link} - unlink.
- GET    students/{student}/guardians/{link}/family-access - their sign-in:
  whether there is an account, a code waiting, a lock, their phones.
- POST   students/{student}/guardians/{link}/family-access/setup-code - a new
  one-time code for the parent's letter, shown once.
- POST   students/{student}/guardians/{link}/family-access/letter - the same
  fresh code, printed on the letter the parent takes home (a PDF).
- DELETE students/{student}/guardians/{link}/family-access/devices/{device} -
  a lost phone.
"""

from __future__ import annotations

from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import family_letter
from ..family_accounts import FamilyAuthService, GuardianService
from ..family_requests import GuardianRequest, SetupCodeRequest
from ..family_resources import family_access_resource, guardian_link_resource
from ..models import FamilyDevice, GuardianStudent, Student
from ..policies import StudentPolicy, authorize
from ..resources import timestamp


def editable_student(request, student_id: int) -> Student:
    student = get_object_or_404(Student, pk=student_id)
    authorize(StudentPolicy.update(request.user, student))

    return student


def link_of(student: Student, link_id: int) -> GuardianStudent:
    return get_object_or_404(GuardianStudent.objects.select_related("guardian", "guardian__user", "student"),
                             pk=link_id, student_id=student.id)


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request, student_id: int) -> Response:
    student = editable_student(request, student_id)

    if request.method == "POST":
        form = GuardianRequest(data=request.data)
        form.is_valid(raise_exception=True)
        link = GuardianService.add(student, form.validated_data, request.user)

        return Response({"data": guardian_link_resource(link)}, status=status.HTTP_201_CREATED)

    return Response({"data": [guardian_link_resource(link) for link in GuardianService.links_of(student)]})


@api_view(["PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def item(request, student_id: int, link_id: int) -> Response:
    student = editable_student(request, student_id)
    link = link_of(student, link_id)

    if request.method == "DELETE":
        GuardianService.unlink(link, request.user)
        return Response(status=status.HTTP_204_NO_CONTENT)

    form = GuardianRequest(data=request.data, partial=True)
    form.is_valid(raise_exception=True)
    link = GuardianService.update(link, form.validated_data, request.user)

    return Response({"data": guardian_link_resource(link)})


def access_response(guardian) -> Response:
    guardian.refresh_from_db()

    return Response({"data": family_access_resource(guardian, GuardianService.credential_of(guardian),
                                                    GuardianService.devices_of(guardian))})


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def access(request, student_id: int, link_id: int) -> Response:
    return access_response(link_of(editable_student(request, student_id), link_id).guardian)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def setup_code(request, student_id: int, link_id: int) -> Response:
    guardian = link_of(editable_student(request, student_id), link_id).guardian

    form = SetupCodeRequest(data=request.data)
    form.is_valid(raise_exception=True)
    code, expires = GuardianService.issue_setup_code(guardian, request.user, form.validated_data["consent"])

    return Response(
        {"data": {"setup_code": code, "expires_at": timestamp(expires), "login_mobile": guardian.login_mobile}},
        status=status.HTTP_201_CREATED,
    )


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def letter(request, student_id: int, link_id: int) -> HttpResponse:
    guardian = link_of(editable_student(request, student_id), link_id).guardian

    form = SetupCodeRequest(data=request.data)
    form.is_valid(raise_exception=True)
    code, expires = GuardianService.issue_setup_code(guardian, request.user, form.validated_data["consent"])
    guardian.refresh_from_db()
    children = FamilyAuthService.children_of(guardian.user)

    response = HttpResponse(family_letter.render(guardian, children, code, expires), content_type="application/pdf")
    response["Content-Disposition"] = f'attachment; filename="{family_letter.file_name(guardian)}"'

    return response


@api_view(["DELETE"])
@permission_classes([IsAuthenticated])
def device(request, student_id: int, link_id: int, device_id: int) -> Response:
    guardian = link_of(editable_student(request, student_id), link_id).guardian
    found = get_object_or_404(FamilyDevice, pk=device_id, user_id=guardian.user_id)

    GuardianService.revoke_device(guardian, found)

    return access_response(guardian)
