"""Examinations and admit cards (docs/examinations.md).

Every endpoint asks ExaminationPolicy about the exam's own school - never a
school named in the request - and a record outside the caller's scope is a
404, so an id says nothing about whether it exists.

Cards are printed only from a published version (examinations/service.py).
A draft preview is for staff who manage the exam, and carries a DRAFT
banner.
"""

from __future__ import annotations

from django.http import Http404, HttpResponse
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..clock import DATE, SchoolClock
from ..errors import AdmitCardUnavailable
from ..examinations import card_pdf
from ..examinations.requests import ExamFields, ExceptionRequest, PapersRequest
from ..examinations.resources import candidate_resource, examination_resource
from ..examinations.service import (
    ExaminationService,
    candidates,
    card_state,
    class_of,
    latest_version,
    require_ready,
    snapshot_of,
    states_for,
)
from ..models import Examination, ExaminationException, ExaminationVersion, Student
from ..pagination import LaravelPagination
from ..policies import ExaminationPolicy, authorize
from ..scope import SchoolScope
from ..years import year_in_view

# The most cards one download prints. A section is a few dozen; more than
# this in one synchronous request would outlast the host's time limit.
MAX_CARDS = 80


def exam_for(request, exam_id: int) -> Examination:
    exam = get_object_or_404(Examination.objects.select_related("academic_year", "academic_term"), pk=exam_id)

    if not ExaminationPolicy.view(request.user, exam.school_id):
        raise Http404

    return exam


def managing(request, exam: Examination) -> None:
    authorize(ExaminationPolicy.manage(request.user, exam.school_id))


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    authorize(ExaminationPolicy.view_any(request.user))

    if request.method == "POST":
        form = ExamFields(request.data, actor=request.user)
        form.is_valid()
        year = form.validated_data["academic_year"]
        authorize(ExaminationPolicy.manage(request.user, year.school_id))
        exam = ExaminationService.create(form.validated_data, request.user)

        return Response(examination_resource(exam_for(request, exam.id), detail=True), status=status.HTTP_201_CREATED)

    exams = SchoolScope.for_actor(request.user).apply_to(
        Examination.objects.select_related("academic_year", "academic_term"), request.query_params.get("school_id")
    )
    year = year_in_view(request)

    if year is not None:
        exams = exams.filter(academic_year_id=year.id)

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(exams.order_by("-academic_year__start_date", "name", "id"), request)

    return paginator.get_paginated_response([examination_resource(exam) for exam in page])


@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def detail(request, exam_id: int) -> Response:
    exam = exam_for(request, exam_id)

    if request.method == "GET":
        return Response(examination_resource(exam, detail=True))

    managing(request, exam)

    if request.method == "DELETE":
        ExaminationService.delete(exam, request.user)
        return Response(status=status.HTTP_204_NO_CONTENT)

    form = ExamFields(request.data, actor=request.user, exam=exam)
    form.is_valid()
    ExaminationService.update(exam, form.validated_data, request.user)

    return Response(examination_resource(exam_for(request, exam.id), detail=True))


@api_view(["PUT"])
@permission_classes([IsAuthenticated])
def papers(request, exam_id: int) -> Response:
    exam = exam_for(request, exam_id)
    managing(request, exam)

    form = PapersRequest(request.data, exam=exam)
    form.is_valid()
    ExaminationService.set_papers(exam, form.validated_data["papers"], request.user)

    return Response(examination_resource(exam_for(request, exam.id), detail=True))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def publish(request, exam_id: int) -> Response:
    exam = exam_for(request, exam_id)
    managing(request, exam)
    ExaminationService.publish(exam, request.user)

    return Response(examination_resource(exam_for(request, exam.id), detail=True))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def candidate_list(request, exam_id: int) -> Response:
    """Who sits the exam, each with their card's state. ?state=ready|withheld|
    fee_hold|no_papers|not_published narrows it."""
    exam = exam_for(request, exam_id)
    params = request.query_params
    rows = list(candidates(
        exam, school_class_id=params.get("school_class_id") or None,
        class_section_id=params.get("class_section_id") or None, q=(params.get("q") or "").strip(),
    ))
    today = SchoolClock.for_school(exam.school_id).now().date()
    states = states_for(exam, rows, today)
    exceptions = {
        row.student_id: row for row in ExaminationException.objects.filter(examination_id=exam.id)
    }
    wanted = params.get("state")

    if wanted:
        rows = [row for row in rows if states[row.student_id].code == wanted]

    counts: dict[str, int] = {}

    for state in states.values():
        counts[state.code] = counts.get(state.code, 0) + 1

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(rows, request)
    response = paginator.get_paginated_response([
        candidate_resource(row, states[row.student_id], exception=exceptions.get(row.student_id)) for row in page
    ])
    response.data["counts"] = counts

    return response


@api_view(["PUT"])
@permission_classes([IsAuthenticated])
def exception(request, exam_id: int) -> Response:
    exam = exam_for(request, exam_id)
    managing(request, exam)

    form = ExceptionRequest(request.data, exam=exam)
    form.is_valid()
    data = form.validated_data
    ExaminationService.set_exception(exam, data["student"], data["kind"], data["reason"], request.user)

    today = SchoolClock.for_school(exam.school_id).now().date()
    state = card_state(exam, data["student"], today)

    return Response({"student_id": data["student"].id, "state": state.code})


def version_for(exam: Examination, raw) -> ExaminationVersion:
    if raw in (None, ""):
        version = latest_version(exam)
    else:
        version = ExaminationVersion.objects.filter(
            examination_id=exam.id, version=int(raw) if str(raw).isdigit() else -1
        ).first()

    if version is None:
        raise AdmitCardUnavailable("This exam has not been published yet.")

    return version


def cards_for(exam: Examination, version: ExaminationVersion, students: list) -> list:
    issued = SchoolClock.for_school(exam.school_id).format(version.published_at, DATE)

    return [
        card_pdf.Card(student=student, snapshot=version.snapshot, class_id=class_id, version=version.version,
                      issued_on=issued)
        for student, class_id in students
    ]


def pdf(document: bytes, name: str, **headers) -> HttpResponse:
    response = HttpResponse(document, content_type="application/pdf")
    response["Content-Disposition"] = f'attachment; filename="{name}"'

    for key, value in headers.items():
        response[key] = str(value)

    return response


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def student_card(request, exam_id: int, student_id: int):
    """One student's card. ?version=n reprints an earlier issue; ?draft=1
    previews the unpublished sheet (exam managers only)."""
    exam = exam_for(request, exam_id)
    student = get_object_or_404(Student.objects.select_related("class_section__school_class"), pk=student_id,
                                 school_id=exam.school_id)
    class_id = class_of(student, exam.academic_year_id)

    if request.query_params.get("draft") in ("1", "true"):
        managing(request, exam)
        snapshot = snapshot_of(exam)

        if class_id is None or str(class_id) not in snapshot["classes"]:
            raise AdmitCardUnavailable("This student's class has no paper in the date sheet yet.")

        card = card_pdf.Card(student=student, snapshot=snapshot, class_id=class_id, version=None, issued_on=None)
    else:
        today = SchoolClock.for_school(exam.school_id).now().date()
        require_ready(card_state(exam, student, today))
        version = version_for(exam, request.query_params.get("version"))

        if str(class_id) not in version.snapshot["classes"]:
            raise AdmitCardUnavailable("This student's class had no paper in that version.")

        card = cards_for(exam, version, [(student, class_id)])[0]

    document = card_pdf.render([card], school=exam.school, year_id=exam.academic_year_id)

    return pdf(document, card_pdf.file_name(exam.name, student.admission_number or student.id))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def class_cards(request, exam_id: int):
    """Every ready card of one section (or one class), one per sheet, in roll
    order. Cards that are not ready are left out and counted in the
    X-Cards-Skipped header, which the screen reports."""
    exam = exam_for(request, exam_id)
    section_id = request.query_params.get("class_section_id") or None
    class_id = request.query_params.get("school_class_id") or None

    if not section_id and not class_id:
        from rest_framework import serializers

        raise serializers.ValidationError({"class_section_id": ["Choose a class or a section to print."]})

    version = version_for(exam, None)
    rows = list(candidates(exam, school_class_id=class_id, class_section_id=section_id))
    today = SchoolClock.for_school(exam.school_id).now().date()
    states = states_for(exam, rows, today)
    ready = [row for row in rows if states[row.student_id].ready]

    if not ready:
        raise AdmitCardUnavailable("No card in this selection is ready to print.")

    if len(ready) > MAX_CARDS:
        raise AdmitCardUnavailable(f"Print at most {MAX_CARDS} cards at a time - choose one section.")

    cards = cards_for(exam, version, [(row.student, row.school_class_id) for row in ready])
    document = card_pdf.render(cards, school=exam.school, year_id=exam.academic_year_id)
    who = ready[0].class_section.name if section_id and ready[0].class_section_id else ready[0].school_class.name

    return pdf(
        document, card_pdf.file_name(exam.name, f"{ready[0].school_class.name}-{who}"),
        **{"X-Cards-Printed": len(ready), "X-Cards-Skipped": len(rows) - len(ready),
           "Access-Control-Expose-Headers": "X-Cards-Printed, X-Cards-Skipped, Content-Disposition"},
    )
