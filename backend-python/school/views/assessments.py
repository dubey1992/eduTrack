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

from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, parser_classes, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import csv_export
from ..imports import marks as marks_import
from ..models import Assessment, Student
from ..pagination import LaravelPagination
from ..policies import AssessmentPolicy, authorize
from ..requests import SaveMarksRequest, StoreAssessmentRequest, UpdateAssessmentRequest
from ..resources import assessment_resource, assessment_sheet_resource
from ..services import AssessmentMarkService, AssessmentPublishService, AssessmentService
from ..validation import required
from .imports import MAX_UPLOAD_BYTES


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


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def marks_template(request, assessment_id: int) -> HttpResponse:
    """The marks sheet as a spreadsheet, with the class already on it.

    Downloaded by whoever may mark it: filling in a column beats typing a
    roll of names back.
    """
    assessment = load(assessment_id)

    authorize(AssessmentPolicy.update(request.user, assessment))

    sheet = AssessmentMarkService.sheet(assessment)

    return csv_export.response(
        f"marks-{assessment.id}.csv", marks_import.HEADINGS, marks_import.roster_rows(sheet)
    )


@api_view(["POST"])
@permission_classes([IsAuthenticated])
@parser_classes([MultiPartParser, FormParser, JSONParser])
def marks_upload(request, assessment_id: int) -> Response:
    """The filled-in spreadsheet, sent back.

    Same permission as marking by hand, and the same rules: nothing is
    written unless every row passes, and a published test is closed.
    """
    assessment = load(assessment_id)

    authorize(AssessmentPolicy.update(request.user, assessment))

    upload = request.FILES.get("file")
    errors = {}

    if upload is None:
        errors["file"] = [required("file")]
    elif upload.size > MAX_UPLOAD_BYTES:
        errors["file"] = ["The file field must not be greater than 2048 kilobytes."]
    elif not str(upload.name).lower().endswith((".csv", ".txt")):
        errors["file"] = ["Upload a CSV file. In Excel, choose File - Save As - CSV."]

    if errors:
        raise ValidationError(errors)

    marks = marks_import.read(upload, assessment)
    saved = AssessmentMarkService.save(assessment, marks, request.user)

    return Response(assessment_sheet_resource(saved))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def publish(request, assessment_id: int) -> Response:
    """Freeze the grades and close the sheet.

    Whoever may mark it may publish it: a teacher publishes their own class's
    result, which is how a school works.
    """
    assessment = load(assessment_id)

    authorize(AssessmentPolicy.update(request.user, assessment))

    published = AssessmentPublishService.publish(assessment, request.user)

    return Response(assessment_resource(published))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def reopen(request, assessment_id: int) -> Response:
    """Take a published result back to a draft.

    Not the teacher who published it: a result that has been sent out is
    taken back by an administrator or by the subject's HOD, and the act is
    audited (docs/assessments.md).
    """
    assessment = load(assessment_id)

    authorize(AssessmentPolicy.reopen(request.user, assessment))

    reopened = AssessmentPublishService.reopen(assessment, request.user)

    return Response(assessment_resource(reopened))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
@parser_classes([MultiPartParser, FormParser, JSONParser])
def marks_preview(request, assessment_id: int) -> Response:
    """What the marks file would save, without saving it.

    The rows come back named, because a marks file is read as "did this land
    against the right children" rather than as a table of numbers.
    """
    assessment = load(assessment_id)

    authorize(AssessmentPolicy.update(request.user, assessment))

    upload = request.FILES.get("file")
    errors = {}

    if upload is None:
        errors["file"] = [required("file")]
    elif upload.size > MAX_UPLOAD_BYTES:
        errors["file"] = ["The file field must not be greater than 2048 kilobytes."]
    elif not str(upload.name).lower().endswith((".csv", ".txt")):
        errors["file"] = ["Upload a CSV file. In Excel, choose File - Save As - CSV."]

    if errors:
        raise ValidationError(errors)

    marks = marks_import.read(upload, assessment)
    names = dict(
        Student.objects.filter(pk__in=[entry["student_id"] for entry in marks]).values_list("id", "admission_number")
    )

    return Response(
        {
            "label": marks_import.LABEL,
            "row_count": len(marks),
            "rows": [
                {
                    "student_id": entry["student_id"],
                    "admission_number": names.get(entry["student_id"]),
                    "marks_obtained": None if entry["marks_obtained"] is None else f"{entry['marks_obtained']:.2f}",
                    "is_absent": entry["is_absent"],
                    "remarks": entry["remarks"],
                }
                for entry in marks
            ],
            "truncated": False,
        }
    )
