"""Syllabus tracking.

Ports of SyllabusTopicController and SyllabusProgressController. Six
endpoints: a subject's outline (list, add, edit, remove a topic), and one
class section's checklist against it (read, tick or untick a topic).

**Two reads check the subject's school here, and Laravel did not.** Both take
a `subject_id` in the query string, and `exists` only proves a subject is
real: the outline list handed any school another school's topics, and the
checklist did the same when the foreign subject was paired with one of the
actor's own sections. Fixed on both backends in the same change. A subject
outside the actor's schools is a 404, not a 403 - the id came from a query
string, and a stranger should not learn it exists. The timetable grid gives
the same answer for the same reason.

The order of checks otherwise follows Laravel's exactly, because it decides
which of 403, 404 and 422 a caller sees: a form request validates before the
controller runs, a request validated inside the controller does not, and an
update's form request authorizes before it validates.
"""

from __future__ import annotations

from django.http import Http404
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..models import ClassSection, Subject, SyllabusTopic
from ..policies import SyllabusTopicPolicy, authorize
from ..requests import (
    StoreSyllabusTopicRequest,
    SyllabusChecklistRequest,
    SyllabusTopicListRequest,
    ToggleSyllabusProgressRequest,
    UpdateSyllabusTopicRequest,
)
from ..resources import syllabus_topic_resource
from ..scope import SchoolScope
from ..services import SyllabusProgressService, SyllabusTopicService


def assert_reachable(actor, subject) -> None:
    """The subject has to be one of the actor's schools' - see the module
    docstring for why this is a 404."""
    if not SchoolScope.for_actor(actor).allows(subject.school_id):
        raise Http404


# -- the outline ------------------------------------------------------------


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def topics(request) -> Response:
    if request.method == "POST":
        return add_topic(request)

    authorize(SyllabusTopicPolicy.view_any(request.user))

    form = SyllabusTopicListRequest(data=request.query_params.dict())
    form.is_valid(raise_exception=True)

    subject = get_object_or_404(Subject, pk=form.validated_data["subject_id"])

    assert_reachable(request.user, subject)

    # A bare list: an outline is a few dozen topics, read whole.
    return Response(
        [syllabus_topic_resource(topic) for topic in SyllabusTopicService.for_subject(subject.id)]
    )


def add_topic(request) -> Response:
    form = StoreSyllabusTopicRequest(data=request.data, actor=request.user)
    form.is_valid(raise_exception=True)

    subject = get_object_or_404(
        Subject.objects.select_related("department"), pk=form.validated_data["subject_id"]
    )

    authorize(SyllabusTopicPolicy.create(request.user, subject))

    topic = SyllabusTopicService.create(subject, form.validated_data)

    return Response(syllabus_topic_resource(topic), status=status.HTTP_201_CREATED)


@api_view(["PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def topic(request, topic_id: int) -> Response:
    found = get_object_or_404(
        SyllabusTopic.objects.select_related("subject__department"), pk=topic_id
    )

    if request.method == "DELETE":
        authorize(SyllabusTopicPolicy.delete(request.user, found))

        SyllabusTopicService.delete(found)

        return Response(status=status.HTTP_204_NO_CONTENT)

    # Authorized before validated: Laravel's update form request answers
    # the ability first, so a stranger's malformed edit is a 403, not a 422.
    authorize(SyllabusTopicPolicy.update(request.user, found))

    form = UpdateSyllabusTopicRequest(data=request.data, topic=found)
    form.is_valid(raise_exception=True)

    return Response(
        syllabus_topic_resource(SyllabusTopicService.update(found, form.validated_data))
    )


# -- one section's checklist ------------------------------------------------


@api_view(["GET", "PATCH"])
@permission_classes([IsAuthenticated])
def progress(request) -> Response:
    if request.method == "PATCH":
        return tick(request)

    form = SyllabusChecklistRequest(data=request.query_params.dict())
    form.is_valid(raise_exception=True)

    section = get_object_or_404(
        ClassSection.objects.select_related("school_class"), pk=form.validated_data["class_section_id"]
    )
    subject = get_object_or_404(Subject, pk=form.validated_data["subject_id"])

    authorize(SyllabusTopicPolicy.view_checklist(request.user, section))

    # The policy looked at the section; the subject arrived separately.
    assert_reachable(request.user, subject)

    return Response(SyllabusProgressService.checklist(subject, section))


def tick(request) -> Response:
    form = ToggleSyllabusProgressRequest(data=request.data)
    form.is_valid(raise_exception=True)

    found = get_object_or_404(
        SyllabusTopic.objects.select_related("subject__department"),
        pk=form.validated_data["syllabus_topic_id"],
    )
    section = get_object_or_404(
        ClassSection.objects.select_related("school_class"), pk=form.validated_data["class_section_id"]
    )

    authorize(SyllabusTopicPolicy.mark(request.user, found, section))

    SyllabusProgressService.toggle(found, section, form.validated_data["completed"], request.user)

    return Response(SyllabusProgressService.checklist(found.subject, section))
