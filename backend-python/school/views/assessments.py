"""Class tests (docs/assessments.md).

CRUD over the record a teacher sets up before any mark exists. Marks, and
publishing, arrive in the slices after this one.

The authorization here is the part worth reading twice. Creating asks about
the **section and subject in the form**, not about a record that does not
exist yet, so a teacher cannot name a class they do not teach and have the
question asked too late. Editing and deleting ask the same question about
the stored record. In both cases the policy - not this view - decides.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..models import Assessment
from ..pagination import LaravelPagination
from ..policies import AssessmentPolicy, authorize
from ..requests import SaveMarksRequest, StoreAssessmentRequest, UpdateAssessmentRequest
from ..resources import assessment_resource, assessment_sheet_resource
from ..services import AssessmentMarkService, AssessmentService


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method == "POST":
        return store(request)

    return index(request)


def index(request) -> Response:
    authorize(AssessmentPolicy.view_any(request.user))

    found = AssessmentService.visible_to(
        request.user,
        {
            "school_id": request.query_params.get("school_id"),
            "academic_term_id": request.query_params.get("academic_term_id"),
            "class_section_id": request.query_params.get("class_section_id"),
            "subject_id": request.query_params.get("subject_id"),
            "status": request.query_params.get("status"),
            "type": request.query_params.get("type"),
        },
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)

    return paginator.get_paginated_response([assessment_resource(row) for row in page])


def store(request) -> Response:
    # The module and the matrix first, so somebody with no business here at
    # all is refused before the form tells them which ids exist.
    authorize(AssessmentPolicy.view_any(request.user))

    form = StoreAssessmentRequest(data=request.data, actor=request.user)
    form.is_valid(raise_exception=True)

    # Now the question that needs the form's answers: is this *their* class
    # and *their* subject.
    authorize(
        AssessmentPolicy.create(
            request.user,
            form.validated_data["school_id"],
            form.validated_data["class_section_id"],
            form.validated_data["subject_id"],
        )
    )

    assessment = AssessmentService.create(form.validated_data, request.user)

    return Response(assessment_resource(reload(assessment.id)), status=status.HTTP_201_CREATED)


@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def detail(request, assessment_id: int) -> Response:
    assessment = load(assessment_id)

    if request.method == "PATCH":
        return update(request, assessment)

    if request.method == "DELETE":
        return destroy(request, assessment)

    authorize(AssessmentPolicy.view(request.user, assessment))

    return Response(assessment_resource(assessment))


def update(request, assessment: Assessment) -> Response:
    authorize(AssessmentPolicy.update(request.user, assessment))

    form = UpdateAssessmentRequest(data=request.data, actor=request.user, assessment=assessment)
    form.is_valid(raise_exception=True)

    AssessmentService.update(assessment, form.validated_data)

    return Response(assessment_resource(reload(assessment.id)))


def destroy(request, assessment: Assessment) -> Response:
    authorize(AssessmentPolicy.delete(request.user, assessment))

    AssessmentService.delete(assessment)

    return Response(status=status.HTTP_204_NO_CONTENT)


def load(assessment_id: int) -> Assessment:
    return get_object_or_404(Assessment.objects.select_related(*AssessmentService.WITH), pk=assessment_id)


def reload(assessment_id: int) -> Assessment:
    return Assessment.objects.select_related(*AssessmentService.WITH).get(pk=assessment_id)


@api_view(["GET", "PUT"])
@permission_classes([IsAuthenticated])
def marks(request, assessment_id: int) -> Response:
    """The marks sheet for one test.

    Read by anyone who may see the test; written by whoever may manage it -
    the teacher the timetable gives that class and subject, their HOD, or an
    administrator. The whole sheet is sent in one PUT: a class of forty
    entered on a phone cannot afford forty round trips, and a half-saved
    sheet is worse than an unsaved one.
    """
    assessment = load(assessment_id)

    if request.method == "PUT":
        authorize(AssessmentPolicy.update(request.user, assessment))

        form = SaveMarksRequest(data=request.data, assessment=assessment)
        form.is_valid(raise_exception=True)

        saved = AssessmentMarkService.save(assessment, form.validated_data["marks"], request.user)

        return Response(assessment_sheet_resource(saved))

    authorize(AssessmentPolicy.view(request.user, assessment))

    return Response(assessment_sheet_resource(AssessmentMarkService.sheet(assessment)))
